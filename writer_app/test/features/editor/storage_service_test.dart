import 'dart:io' as io;
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/local_snapshot_store.dart';

void main() {
  late MemoryFileSystem fs;
  late StorageService storageService;

  setUp(() {
    fs = MemoryFileSystem();
    storageService = StorageService(fileSystem: fs);
  });

  group('StorageService', () {
    const testPath = '/test_project';

    test('should return empty string if file does not exist', () async {
      final content = await storageService.readDocument(testPath);
      expect(content, '');
    });

    test('should save and read document', () async {
      const testContent = 'Hello, world!';
      await storageService.saveDocument(testPath, testContent);
      
      final content = await storageService.readDocument(testPath);
      expect(content, testContent);
    });

    test('should overwrite existing document', () async {
      await storageService.saveDocument(testPath, 'First content');
      await storageService.saveDocument(testPath, 'Second content');
      
      final content = await storageService.readDocument(testPath);
      expect(content, 'Second content');
    });

    test('USER_MANUAL.md in repository root must match StorageService.userManualContent', () {
      final file = io.File('../USER_MANUAL.md');
      expect(file.existsSync(), isTrue, reason: 'USER_MANUAL.md does not exist at repo root');
      final content = file.readAsStringSync().replaceAll('\r\n', '\n');
      final compiledContent = StorageService.userManualContent.replaceAll('\r\n', '\n');
      expect(compiledContent, content, reason: 'The compiled userManualContent does not match USER_MANUAL.md');
    });

    group('Local Snapshot Safety Net', () {
      late List<DateTime> clock;
      DateTime nextClockValue() => clock.removeAt(0);

      StorageService buildService() {
        return StorageService(fileSystem: fs, snapshotStore: LocalSnapshotStore(fs, clock: nextClockValue));
      }

      test('save/list/read round trip', () async {
        clock = [DateTime(2026, 7, 4, 15, 30, 0)];
        final service = buildService();

        await service.saveLocalSnapshot(testPath, 'v1');

        final list = await service.listLocalSnapshots(testPath);
        expect(list.length, 1);
        expect(list.first.timestamp, DateTime(2026, 7, 4, 15, 30, 0));

        final content = await service.readLocalSnapshot(list.first.filePath);
        expect(content, 'v1');
      });

      test('listLocalSnapshots returns newest-first', () async {
        clock = [
          DateTime(2026, 7, 4, 10, 0, 0),
          DateTime(2026, 7, 4, 11, 0, 0),
          DateTime(2026, 7, 4, 12, 0, 0),
        ];
        final service = buildService();

        await service.saveLocalSnapshot(testPath, 'v1');
        await service.saveLocalSnapshot(testPath, 'v2');
        await service.saveLocalSnapshot(testPath, 'v3');

        final list = await service.listLocalSnapshots(testPath);
        expect(list.map((r) => r.timestamp).toList(), [
          DateTime(2026, 7, 4, 12, 0, 0),
          DateTime(2026, 7, 4, 11, 0, 0),
          DateTime(2026, 7, 4, 10, 0, 0),
        ]);
      });

      test('skips saving when content is byte-identical to the latest snapshot', () async {
        clock = [DateTime(2026, 7, 4, 9, 0, 0), DateTime(2026, 7, 4, 9, 5, 0)];
        final service = buildService();

        await service.saveLocalSnapshot(testPath, 'same content');
        await service.saveLocalSnapshot(testPath, 'same content');

        final list = await service.listLocalSnapshots(testPath);
        expect(list.length, 1);
      });

      test('skips saving when content is empty', () async {
        final service = buildService();
        await service.saveLocalSnapshot(testPath, '');
        final list = await service.listLocalSnapshots(testPath);
        expect(list, isEmpty);
      });

      test('returns empty list when .history folder does not exist', () async {
        final service = buildService();
        final list = await service.listLocalSnapshots('/never_snapshotted');
        expect(list, isEmpty);
      });

      test('prunes oldest snapshots beyond the 50-snapshot cap', () async {
        final base = DateTime(2026, 1, 1, 0, 0, 0);
        clock = List.generate(51, (i) => base.add(Duration(seconds: i)));
        final service = buildService();

        for (int i = 0; i < 51; i++) {
          await service.saveLocalSnapshot(testPath, 'content-$i');
        }

        final list = await service.listLocalSnapshots(testPath);
        expect(list.length, 50);
        expect(list.first.timestamp, base.add(const Duration(seconds: 50)));
        expect(list.last.timestamp, base.add(const Duration(seconds: 1)));
      });
    });
  });
}

