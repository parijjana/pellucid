// @trace FEAT-20260516-120000-0001
// Description: Unit tests for EditorProvider (TDD).
// TestID: TEST-20260516-120000-0002

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';

class MockStorageService extends Mock implements StorageService {}
class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  late EditorProvider editorProvider;
  late MockStorageService mockStorageService;
  late MockSettingsDatabase mockSettingsDatabase;

  setUp(() {
    mockStorageService = MockStorageService();
    mockSettingsDatabase = MockSettingsDatabase();
    
    // This will fail to compile initially because EditorProvider 
    // doesn't accept settingsDatabase in constructor yet.
    editorProvider = EditorProvider(
      storageService: mockStorageService,
      settingsDatabase: mockSettingsDatabase,
    );
  });

  group('EditorProvider', () {
    test('initial values should be correct', () {
      expect(editorProvider.content, StorageService.userManualContent);
      expect(editorProvider.zoomLevel, 1.0);
    });

    test('updateContent should update content and notify listeners', () {
      bool notified = false;
      editorProvider.addListener(() => notified = true);
      
      editorProvider.updateContent('New Content');
      
      expect(editorProvider.content, 'New Content');
      expect(notified, true);
    });

    test('setZoomLevel should clamp and update setting', () async {
      when(() => mockSettingsDatabase.updateSetting(any(), any()))
          .thenAnswer((_) async {});

      editorProvider.setZoomLevel(3.0);
      expect(editorProvider.zoomLevel, 2.0); // Clamped

      verify(() => mockSettingsDatabase.updateSetting('zoom_level', 2.0)).called(1);
    });
  });
}
