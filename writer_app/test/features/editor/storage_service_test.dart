import 'dart:io' as io;
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

    test('USER_MANUAL.md in repository root must match StorageService.userManualContent', () {
      final file = io.File('../USER_MANUAL.md');
      expect(file.existsSync(), isTrue, reason: 'USER_MANUAL.md does not exist at repo root');
      final content = file.readAsStringSync().replaceAll('\r\n', '\n');
      final compiledContent = StorageService.userManualContent.replaceAll('\r\n', '\n');
      expect(compiledContent, content, reason: 'The compiled userManualContent does not match USER_MANUAL.md');
    });
  });
}

