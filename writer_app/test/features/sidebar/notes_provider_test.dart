// @trace FEAT-20260516-114400-0002
// Description: Unit tests for NotesProvider (TDD).
// TestID: TEST-20260516-114400-0002

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';

class MockStorageService extends Mock implements StorageService {}

void main() {
  late NotesProvider notesProvider;
  late MockStorageService mockStorageService;

  setUp(() {
    mockStorageService = MockStorageService();
    notesProvider = NotesProvider(storageService: mockStorageService);
    when(() => mockStorageService.readCategories(any()))
        .thenAnswer((_) async => ['general', 'people', 'places', 'events']);
    when(() => mockStorageService.saveCategories(any(), any()))
        .thenAnswer((_) async {});
  });

  group('NotesProvider', () {
    test('initial values should be empty', () {
      expect(notesProvider.cards, isEmpty);
    });

    test('addCard should add a card and save', () async {
      when(() => mockStorageService.readNotes(any()))
          .thenAnswer((_) async => []);
      when(() => mockStorageService.saveNotes(any(), any()))
          .thenAnswer((_) async {});
      
      // Need a project path for save to trigger
      await notesProvider.loadProject('test_path');
      
      notesProvider.addCard();
      
      expect(notesProvider.cards.length, 1);
      expect(notesProvider.cards.first.title, 'New Note');
      verify(() => mockStorageService.saveNotes('test_path', any())).called(1);
    });

    test('deleteCard should remove card and connections', () async {
      when(() => mockStorageService.readNotes(any()))
          .thenAnswer((_) async => []);
      when(() => mockStorageService.saveNotes(any(), any()))
          .thenAnswer((_) async {});
      
      await notesProvider.loadProject('test_path');
      
      notesProvider.addCard(); // id1
      final id1 = notesProvider.cards.first.id;
      
      notesProvider.deleteCard(id1);
      
      expect(notesProvider.cards, isEmpty);
      verify(() => mockStorageService.saveNotes('test_path', any())).called(2);
    });
  });
}
