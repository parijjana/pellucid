// New-project speed: the owner saw a huge delay after pressing Create.
// Cause: HistoryProvider.saveStatsNow awaited a Drive upload (twice: once
// explicitly and once inside loadProjectStats), and createProject re-read every
// project's stats. Real file IO in a temp dir; slow Drive simulated.

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sync/models/logical_file.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';

class MockDb extends Mock implements SettingsDatabase {}

class SlowDrive extends Mock implements SyncProvider {
  SlowDrive(this.latency);
  final Duration latency;
  int statsUploads = 0;
  int statsFinished = 0;

  @override
  bool get isLoggedIn => true;
  @override
  SyncStatus get status => SyncStatus.success;

  @override
  Future<void> syncStats({required String projectName, required String statsJson}) async {
    statsUploads++;
    await Future.delayed(latency);
    statsFinished++;
  }

  @override
  Future<String?> getLatestContent({required String projectName, required LogicalFile fileName}) async => null;
}

class CountingStorage extends StorageService {
  final reads = <String>[];
  @override
  Future<ProjectStats> readProjectStats(String projectPath) {
    reads.add(projectPath);
    return super.readProjectStats(projectPath);
  }

  @override
  Future<List<String>> listProjects(String masterPath) {
    reads.add('LIST');
    return super.listProjects(masterPath);
  }
}

void main() {
  const latency = Duration(milliseconds: 600);
  late io.Directory tmp;
  late CountingStorage storage;
  late MockDb db;
  late SettingsProvider settings;
  late HistoryProvider history;
  late EditorProvider editor;
  late SlowDrive drive;

  setUp(() async {
    tmp = await io.Directory.systemTemp.createTemp('pellucid_np_');
    for (var i = 0; i < 10; i++) {
      await io.Directory('${tmp.path}/P$i').create();
      await io.File('${tmp.path}/P$i/document.md').writeAsString(i == 0 ? List.filled(127000, 'word').join(' ') : 'hello');
    }
    db = MockDb();
    when(() => db.getMirroredProjects()).thenAnswer((_) async => <String>{});
    when(() => db.updateSetting(any(), any())).thenAnswer((_) async {});
    when(() => db.getHistory()).thenAnswer((_) async => []);
    when(() => db.upsertHistory(any(), any(), any(), any())).thenAnswer((_) async {});
    storage = CountingStorage();
    drive = SlowDrive(latency);
    settings = SettingsProvider(settingsDatabase: db, storageService: storage);
    history = HistoryProvider(settingsDatabase: db, storageService: storage, syncProvider: drive);
    editor = EditorProvider(storageService: storage, settingsDatabase: db);
    await settings.setMasterDirectory(tmp.path);
    await settings.setCurrentProject('P0');
    await editor.loadProject(settings.currentProjectPath);
    await history.loadProjectStats(settings.currentProjectPath);
    await pumpEventQueue();
    drive.statsUploads = 0;
    drive.statsFinished = 0;
    storage.reads.clear();
  });

  tearDown(() async {
    settings.dispose();
    history.dispose();
    await tmp.delete(recursive: true);
  });

  Future<void> createFlow(String name) async {
    await history.saveStatsNow(remoteInBackground: true);
    expect(await settings.createProject(name), isTrue);
    final path = settings.currentProjectPath;
    await editor.loadProject(path);
    await history.loadProjectStats(path);
  }

  test('create does not wait on the Drive stats upload and still uploads it', () async {
    final sw = Stopwatch()..start();
    await createFlow('Fresh');
    sw.stop();
    // ignore: avoid_print
    print('STEP create flow with ${latency.inMilliseconds} ms Drive: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(latency.inMilliseconds ~/ 2));
    expect(drive.statsUploads, greaterThanOrEqualTo(1), reason: 'old project stats still go to Drive');
    expect(drive.statsFinished, 0);
    await Future.delayed(latency * 2);
    expect(drive.statsFinished, drive.statsUploads);
  });

  test('project list is updated incrementally, not rescanned', () async {
    await settings.refreshProjects();
    final before = settings.availableProjects.length;
    expect(before, greaterThanOrEqualTo(10));
    storage.reads.clear();
    await settings.createProject('Fresh');
    expect(settings.availableProjects.map((p) => p.name), contains('Fresh'));
    expect(settings.availableProjects.length, before + 1);
    expect(storage.reads, isNot(contains('LIST')));
    expect(storage.reads.length, 1, reason: 'only the new project is read');
    expect(settings.currentProjectName, 'Fresh');
    expect(io.File('${tmp.path}/Fresh/document.md').existsSync(), isTrue);
    expect(io.File('${tmp.path}/Fresh/notes.json').existsSync(), isTrue);
  });

  test('current project is saved before the switch (stats on disk, text kept)', () async {
    editor.updateContent('unsaved words in P0');
    history.updateWordCount(4242);
    await createFlow('Fresh');
    final stats = await StorageService().readProjectStats('${tmp.path}/P0');
    expect(stats.totalWordCount, 4242);
    expect(io.File('${tmp.path}/P0/document.md').readAsStringSync(), 'unsaved words in P0');
    expect(settings.currentProjectName, 'Fresh');
    expect(editor.content, '');
  });
}
