// Slice 10 / backlog item 6: where does "New project" spend its time?
// The sequence mirrors settings_screen.dart and mac_menu_bar_wrapper.dart:
// save stats -> flush sync of the OLD project -> create -> load.
// Network latency is simulated by a fake sync provider (default 800 ms).

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sync/models/logical_file.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}

class SlowSyncProvider extends Mock implements SyncProvider {
  SlowSyncProvider(this.latency);
  final Duration latency;
  int calls = 0;
  bool finished = false;

  @override
  SyncStatus get status => SyncStatus.success;

  @override
  Future<void> syncCurrentFile({
    required String projectName,
    required LogicalFile fileName,
    required String content,
  }) async {
    calls++;
    await Future.delayed(latency);
    finished = true;
  }
}

void main() {
  const latency = Duration(milliseconds: 800);
  late MockSettingsDatabase db;
  late StorageService storage;
  late SettingsProvider settings;
  late EditorProvider editor;
  late SlowSyncProvider sync;

  setUp(() async {
    db = MockSettingsDatabase();
    when(() => db.getMirroredProjects()).thenAnswer((_) async => <String>{});
    when(() => db.updateSetting(any(), any())).thenAnswer((_) async {});
    storage = StorageService(fileSystem: MemoryFileSystem());
    settings = SettingsProvider(settingsDatabase: db, storageService: storage);
    editor = EditorProvider(storageService: storage, settingsDatabase: db);
    sync = SlowSyncProvider(latency);
    await settings.setMasterDirectory('/master');
    await settings.createProject('Old');
    await editor.loadProject(settings.currentProjectPath);
    editor.updateContent('unsynced words'); // no provider: stays unsynced
  });

  tearDown(() => settings.dispose());

  test('MEASURE: per-step cost of creating a project while the old one has unsynced edits', () async {
    final sw = Stopwatch();
    final steps = <String, int>{};
    Future<void> time(String name, Future<void> Function() f) async {
      sw..reset()..start();
      await f();
      steps[name] = sw.elapsedMilliseconds;
    }

    // Old flow (pre-fix): flush is awaited. Re-dirty via the public API.
    editor.updateContent('more', syncProvider: sync, projectName: 'Old');
    await time('flushSync (awaited, fake network ${latency.inMilliseconds} ms)',
        () => editor.flushSync(syncProvider: sync, projectName: 'Old'));
    await time('createProject (fs + db)', () => settings.createProject('New'));
    await time('loadProject (fs)', () => editor.loadProject(settings.currentProjectPath));
    // ignore: avoid_print
    steps.forEach((k, v) => print('STEP $k: $v ms'));
    expect(steps['createProject (fs + db)']!, lessThan(latency.inMilliseconds));
  });

  test('creating a project does not await the network', () async {
    editor.updateContent('edit', syncProvider: sync, projectName: 'Old');
    final sw = Stopwatch()..start();
    editor.flushSyncInBackground(syncProvider: sync, projectName: 'Old');
    expect(await settings.createProject('New'), isTrue);
    await editor.loadProject(settings.currentProjectPath);
    sw.stop();

    expect(sync.calls, 1, reason: 'old project still gets uploaded');
    expect(sync.finished, isFalse, reason: 'create returned before the upload ended');
    expect(sw.elapsedMilliseconds, lessThan(latency.inMilliseconds ~/ 2));
    await Future.delayed(latency + const Duration(milliseconds: 100));
    expect(sync.finished, isTrue);
  });

  test('background sync of the old project does not mark the new project clean', () async {
    editor.updateContent('edit', syncProvider: sync, projectName: 'Old');
    editor.flushSyncInBackground(syncProvider: sync, projectName: 'Old');
    await settings.createProject('New');
    await editor.loadProject(settings.currentProjectPath);
    editor.updateContent('new project edit', syncProvider: sync, projectName: 'New');
    expect(editor.hasUnsyncedChanges, isTrue);
    await Future.delayed(latency + const Duration(milliseconds: 100));
    expect(editor.hasUnsyncedChanges, isTrue);
  });
}
