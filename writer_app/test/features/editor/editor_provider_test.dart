// @trace FEAT-20260516-120000-0001
// Description: Unit tests for EditorProvider (TDD).
// TestID: TEST-20260516-120000-0002

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';

class MockStorageService extends Mock implements StorageService {}
class MockSettingsDatabase extends Mock implements SettingsDatabase {}
class MockSyncProvider extends Mock implements SyncProvider {}

void main() {
  late EditorProvider editorProvider;
  late MockStorageService mockStorageService;
  late MockSettingsDatabase mockSettingsDatabase;
  late MockSyncProvider mockSyncProvider;

  setUp(() {
    mockStorageService = MockStorageService();
    mockSettingsDatabase = MockSettingsDatabase();
    mockSyncProvider = MockSyncProvider();
    
    editorProvider = EditorProvider(
      storageService: mockStorageService,
      settingsDatabase: mockSettingsDatabase,
    );

    when(() => mockStorageService.readDocument(any()))
        .thenAnswer((_) async => 'Mock project content');

    when(() => mockSyncProvider.status).thenReturn(SyncStatus.success);
    when(() => mockSyncProvider.syncCurrentFile(
      projectName: any(named: 'projectName'),
      fileName: any(named: 'fileName'),
      content: any(named: 'content'),
    )).thenAnswer((_) async {});
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

    test('local auto-save should trigger 2 seconds after updateContent', () async {
      when(() => mockStorageService.saveDocument(any(), any()))
          .thenAnswer((_) async {});

      await editorProvider.loadProject('/test/project/path');
      editorProvider.updateContent('New local content');

      // Immediate check should be empty
      verifyNever(() => mockStorageService.saveDocument(any(), any()));

      // Wait 2.1 seconds for the local debounce timer to fire
      await Future.delayed(const Duration(milliseconds: 2100));

      verify(() => mockStorageService.saveDocument('/test/project/path', 'New local content')).called(1);
    });

    test('cloud sync should debounce on idle', () async {
      editorProvider.syncDebounceDuration = const Duration(milliseconds: 50);
      editorProvider.syncThrottleDuration = const Duration(milliseconds: 200);

      await editorProvider.loadProject('/test/project/path');
      editorProvider.updateContent(
        'Idle debounce content',
        syncProvider: mockSyncProvider,
        projectName: 'TestProject',
      );

      // Verify no immediate sync
      verifyNever(() => mockSyncProvider.syncCurrentFile(
        projectName: any(named: 'projectName'),
        fileName: any(named: 'fileName'),
        content: any(named: 'content'),
      ));

      // Wait 60 milliseconds
      await Future.delayed(const Duration(milliseconds: 60));

      verify(() => mockSyncProvider.syncCurrentFile(
        projectName: 'TestProject',
        fileName: 'manuscript.md',
        content: 'Idle debounce content',
      )).called(1);
    });

    test('cloud sync should throttle on continuous typing', () async {
      editorProvider.syncDebounceDuration = const Duration(milliseconds: 100);
      editorProvider.syncThrottleDuration = const Duration(milliseconds: 40);

      await editorProvider.loadProject('/test/project/path');

      // Continuous typing: update at t=0, t=15, t=30
      editorProvider.updateContent('Content 1', syncProvider: mockSyncProvider, projectName: 'TestProject');
      await Future.delayed(const Duration(milliseconds: 15));
      editorProvider.updateContent('Content 2', syncProvider: mockSyncProvider, projectName: 'TestProject');
      await Future.delayed(const Duration(milliseconds: 15));
      editorProvider.updateContent('Content 3', syncProvider: mockSyncProvider, projectName: 'TestProject');

      // At this point (t=30ms), debounce would be at t=130ms.
      // But throttle should fire at t=40ms.
      await Future.delayed(const Duration(milliseconds: 15)); // t=45ms total

      verify(() => mockSyncProvider.syncCurrentFile(
        projectName: 'TestProject',
        fileName: 'manuscript.md',
        content: 'Content 3',
      )).called(1);
    });

    test('flushSync should trigger immediate cloud sync and cancel active timers', () async {
      editorProvider.syncDebounceDuration = const Duration(milliseconds: 200);
      editorProvider.syncThrottleDuration = const Duration(milliseconds: 200);

      await editorProvider.loadProject('/test/project/path');
      editorProvider.updateContent('Flush content', syncProvider: mockSyncProvider, projectName: 'TestProject');

      // Verify no immediate sync
      verifyNever(() => mockSyncProvider.syncCurrentFile(
        projectName: any(named: 'projectName'),
        fileName: any(named: 'fileName'),
        content: any(named: 'content'),
      ));

      // Call flushSync
      await editorProvider.flushSync(syncProvider: mockSyncProvider, projectName: 'TestProject');

      // Verify immediate sync
      verify(() => mockSyncProvider.syncCurrentFile(
        projectName: 'TestProject',
        fileName: 'manuscript.md',
        content: 'Flush content',
      )).called(1);

      // Reset mock verify counts
      clearInteractions(mockSyncProvider);

      // Wait 250 milliseconds and ensure no more syncs occur (timers cancelled)
      await Future.delayed(const Duration(milliseconds: 250));
      verifyNever(() => mockSyncProvider.syncCurrentFile(
        projectName: any(named: 'projectName'),
        fileName: any(named: 'fileName'),
        content: any(named: 'content'),
      ));
    });

    group('syncAttributions', () {
      test('syncAttributions with null card should remove the # Attributions section', () {
        editorProvider.updateContent('Introduction\n\n# Attributions\n\n* Some attribution\n\n# Chapter 2\n\nContent');
        editorProvider.syncAttributions(null);
        expect(editorProvider.content, 'Introduction\n\n# Chapter 2\n\nContent');
      });

      test('syncAttributions should insert or update # Attributions section correctly', () {
        editorProvider.updateContent('Introduction\n\n# Chapter 2\n\nContent');
        
        final card = NoteCard(
          title: 'Attributions',
          content: '',
          isAttribution: true,
          attributionItems: [
            AttributionItem(text: 'Item 1'),
            AttributionItem(text: 'Item 2'),
          ],
          attributionType: 'bullet',
        );

        editorProvider.syncAttributions(card);
        expect(editorProvider.content, 'Introduction\n\n# Chapter 2\n\nContent\n\n# Attributions\n\n* Item 1\n* Item 2\n');

        final updatedCard = card.copyWith(
          attributionItems: [
            AttributionItem(text: 'Item A'),
            AttributionItem(text: 'Item B'),
          ],
          attributionType: 'number',
        );

        editorProvider.syncAttributions(updatedCard);
        expect(editorProvider.content, 'Introduction\n\n# Chapter 2\n\nContent\n\n# Attributions\n\n1. Item A\n2. Item B\n');
      });
    });
  });
}
