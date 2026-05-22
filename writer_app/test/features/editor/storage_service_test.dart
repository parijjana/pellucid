// @trace FEAT-20260516-120000-0001
// Description: Unit tests for StorageService.
// TestID: TEST-20260516-120000-0001

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';

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
  });
}
