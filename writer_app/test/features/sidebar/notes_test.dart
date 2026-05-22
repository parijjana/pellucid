// @trace FEAT-20260522-0001
// Description: Unit and Widget tests for Notes Category management, Bidirectional Linking, and Sizing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/sidebar/widgets/note_editor_dialog.dart';
import 'package:pellucid/features/sidebar/widgets/note_mini_card.dart';
import 'package:pellucid/features/sidebar/screens/notes_sidebar.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/sidebar/widgets/note_editor_attribution_list.dart';
import 'package:provider/provider.dart';

class MockStorageService extends Mock implements StorageService {}
class MockSettingsProvider extends Mock implements SettingsProvider {}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockEditorProvider extends Mock implements EditorProvider {}

void main() {
  setUpAll(() {
    registerFallbackValue(NoteCard(title: '', content: ''));
    registerFallbackValue(MockSyncProvider());
  });

  group('NoteCard JSON Deserialization Fallback', () {
    test('should parse category from old int values correctly', () {
      final json1 = {'id': '1', 'title': 'T1', 'content': 'C1', 'category': 0}; // people
      final json2 = {'id': '2', 'title': 'T2', 'content': 'C2', 'category': 1}; // places
      final json3 = {'id': '3', 'title': 'T3', 'content': 'C3', 'category': 2}; // events
      final json4 = {'id': '4', 'title': 'T4', 'content': 'C4', 'category': 99}; // general

      expect(NoteCard.fromJson(json1).category, 'people');
      expect(NoteCard.fromJson(json2).category, 'places');
      expect(NoteCard.fromJson(json3).category, 'events');
      expect(NoteCard.fromJson(json4).category, 'general');
    });

    test('should handle missing fields gracefully', () {
      final json = {
        'id': '1',
        'title': 'T1',
        'content': 'C1',
      };
      final card = NoteCard.fromJson(json);
      expect(card.category, 'general');
      expect(card.connections, isEmpty);
      expect(card.isAttribution, isFalse);
      expect(card.sourceUrl, isNull);
    });
  });

  group('NotesProvider Bidirectional Linking & Categories', () {
    late NotesProvider notesProvider;
    late MockStorageService mockStorageService;

    setUp(() {
      mockStorageService = MockStorageService();
      notesProvider = NotesProvider(storageService: mockStorageService);
      when(() => mockStorageService.readCategories(any()))
          .thenAnswer((_) async => ['general', 'people', 'places', 'events']);
      when(() => mockStorageService.saveCategories(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockStorageService.readNotes(any()))
          .thenAnswer((_) async => []);
      when(() => mockStorageService.saveNotes(any(), any()))
          .thenAnswer((_) async {});
    });

    test('connectCards should link bidirectionally', () async {
      await notesProvider.loadProject('test_path');
      notesProvider.addCard(); // Card 1
      notesProvider.addCard(); // Card 2
      
      final id1 = notesProvider.cards[0].id;
      final id2 = notesProvider.cards[1].id;

      notesProvider.connectCards(id1, id2);

      expect(notesProvider.cards[0].connections, contains(id2));
      expect(notesProvider.cards[1].connections, contains(id1));
    });

    test('disconnectCards should unlink bidirectionally', () async {
      await notesProvider.loadProject('test_path');
      notesProvider.addCard(); // Card 1
      notesProvider.addCard(); // Card 2
      
      final id1 = notesProvider.cards[0].id;
      final id2 = notesProvider.cards[1].id;

      notesProvider.connectCards(id1, id2);
      expect(notesProvider.cards[0].connections, contains(id2));

      notesProvider.disconnectCards(id1, id2);
      expect(notesProvider.cards[0].connections, isEmpty);
      expect(notesProvider.cards[1].connections, isEmpty);
    });

    test('addCategory should add custom category and call saveCategories', () async {
      await notesProvider.loadProject('test_path');
      await notesProvider.addCategory('custom_cat');

      expect(notesProvider.categories, contains('custom_cat'));
      verify(() => mockStorageService.saveCategories('test_path', any())).called(1);
    });
  });

  group('NotesProvider Attribution Features', () {
    late NotesProvider notesProvider;
    late MockStorageService mockStorageService;

    setUp(() {
      mockStorageService = MockStorageService();
      notesProvider = NotesProvider(storageService: mockStorageService);
      when(() => mockStorageService.readCategories(any()))
          .thenAnswer((_) async => ['general', 'people', 'places', 'events']);
      when(() => mockStorageService.saveCategories(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockStorageService.readNotes(any()))
          .thenAnswer((_) async => []);
      when(() => mockStorageService.saveNotes(any(), any()))
          .thenAnswer((_) async {});
    });

    test('addAttributionCard should enforce single attribution card constraint', () async {
      await notesProvider.loadProject('test_path');
      notesProvider.addAttributionCard();
      expect(notesProvider.cards.where((c) => c.isAttribution).length, 1);

      // Try adding another one, should not add
      notesProvider.addAttributionCard();
      expect(notesProvider.cards.where((c) => c.isAttribution).length, 1);
    });

    test('updateCard should store attribution items and type correctly', () async {
      await notesProvider.loadProject('test_path');
      notesProvider.addAttributionCard();
      final attrCardId = notesProvider.cards.firstWhere((c) => c.isAttribution).id;

      final items = [
        AttributionItem(text: 'Item 1'),
        AttributionItem(text: 'Item 2', connections: ['some_note_id']),
      ];

      notesProvider.updateCard(
        attrCardId,
        attributionItems: items,
        attributionType: 'number',
      );

      final updatedCard = notesProvider.cards.firstWhere((c) => c.id == attrCardId);
      expect(updatedCard.attributionType, 'number');
      expect(updatedCard.attributionItems!.length, 2);
      expect(updatedCard.attributionItems![1].connections, contains('some_note_id'));
    });
  });

  group('NoteEditorDialog Widget Tests', () {
    late NotesProvider notesProvider;
    late MockStorageService mockStorageService;
    late MockSettingsProvider mockSettings;
    late MockSyncProvider mockSync;
    late MockThemeProvider mockTheme;
    late MockEditorProvider mockEditor;

    setUp(() {
      mockStorageService = MockStorageService();
      notesProvider = NotesProvider(storageService: mockStorageService);
      mockSettings = MockSettingsProvider();
      mockSync = MockSyncProvider();
      mockTheme = MockThemeProvider();
      mockEditor = MockEditorProvider();

      when(() => mockStorageService.readCategories(any()))
          .thenAnswer((_) async => ['general', 'people', 'places', 'events']);
      when(() => mockStorageService.saveCategories(any(), any()))
          .thenAnswer((_) async {});
      when(() => mockStorageService.readNotes(any()))
          .thenAnswer((_) async => []);
      when(() => mockStorageService.saveNotes(any(), any()))
          .thenAnswer((_) async {});

      when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets[0]);
      when(() => mockSync.isLoggedIn).thenReturn(false);
      when(() => mockSync.status).thenReturn(SyncStatus.idle);
      when(() => mockSync.lastSynced).thenReturn(null);
      when(() => mockSettings.currentProjectName).thenReturn('TestProject');
      when(() => mockEditor.syncAttributions(any(), syncProvider: any(named: 'syncProvider'), projectName: any(named: 'projectName'))).thenAnswer((_) {});
    });

    testWidgets('Should render NoteEditorDialog in popup mode with 70% width and 50% height constraints', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(() => mockSettings.lastNotesFullscreenState).thenReturn(false);

      await notesProvider.loadProject('test_path');
      notesProvider.addCard();
      final noteId = notesProvider.cards.first.id;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditorDialog(noteId: noteId),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final containerFinder = find.byType(AnimatedContainer);
      expect(containerFinder, findsOneWidget);

      final size = tester.getSize(containerFinder);
      expect(size.width, closeTo(700, 0.01));
      expect(size.height, closeTo(300, 0.01));
      
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    });

    testWidgets('Toggling fullscreen updates size to 100% and stores state', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(() => mockSettings.lastNotesFullscreenState).thenReturn(false);
      when(() => mockSettings.setLastNotesFullscreenState(any())).thenAnswer((_) async {});

      await notesProvider.loadProject('test_path');
      notesProvider.addCard();
      final noteId = notesProvider.cards.first.id;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditorDialog(noteId: noteId),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      var size = tester.getSize(find.byType(AnimatedContainer));
      expect(size.width, closeTo(700, 0.01));

      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pumpAndSettle();

      size = tester.getSize(find.byType(AnimatedContainer));
      expect(size.width, closeTo(1000, 0.01));
      expect(size.height, closeTo(600, 0.01));

      verify(() => mockSettings.setLastNotesFullscreenState(true)).called(1);
    });

    testWidgets('Fullscreen mode reveals power features and supports navigation history stack', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(() => mockSettings.lastNotesFullscreenState).thenReturn(true);

      await notesProvider.loadProject('test_path');
      
      notesProvider.addCard(); // Note 1
      notesProvider.addCard(); // Note 2
      
      final noteId1 = notesProvider.cards[0].id;
      final noteId2 = notesProvider.cards[1].id;

      notesProvider.updateCard(noteId1, title: 'Note One');
      notesProvider.updateCard(noteId2, title: 'Note Two');

      notesProvider.connectCards(noteId1, noteId2);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditorDialog(noteId: noteId1),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Note One'), findsOneWidget);
      expect(find.text('#Note Two'), findsOneWidget);

      await tester.tap(find.text('#Note Two'));
      await tester.pumpAndSettle();

      expect(find.text('Note Two'), findsOneWidget);

      final backButton = find.byIcon(Icons.arrow_back);
      expect(backButton, findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.text('Note One'), findsOneWidget);
    });

    testWidgets('Custom category creator should add category and update dropdown', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(() => mockSettings.lastNotesFullscreenState).thenReturn(true);

      await notesProvider.loadProject('test_path');
      notesProvider.addCard();
      final noteId = notesProvider.cards.first.id;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditorDialog(noteId: noteId),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final categoryFieldFinder = find.widgetWithText(TextField, 'New category name...');
      expect(categoryFieldFinder, findsOneWidget);

      await tester.enterText(categoryFieldFinder, 'Lore');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(notesProvider.categories, contains('lore'));
    });

    testWidgets('Attribution switch toggle displays source URL input and hyperlink', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(() => mockSettings.lastNotesFullscreenState).thenReturn(true);

      await notesProvider.loadProject('test_path');
      notesProvider.addCard();
      final noteId = notesProvider.cards.first.id;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditorDialog(noteId: noteId),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final urlFieldFinder = find.widgetWithText(TextField, 'Source URL (e.g. https://...)');
      expect(urlFieldFinder, findsOneWidget);
      await tester.enterText(urlFieldFinder, 'https://example.com');
      await tester.pumpAndSettle();

      expect(find.text('https://example.com'), findsOneWidget);
    });

    testWidgets('NotesSidebar renders borderless Attributions text button and handles tap', (WidgetTester tester) async {
      when(() => mockSettings.lastNotesFullscreenState).thenReturn(false);
      await notesProvider.loadProject('test_path');
      // No attribution card created yet

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotesSidebar(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the new borderless button text "Attributions" is shown
      expect(find.text('Attributions'), findsOneWidget);
      // The old "Add Attribution Note" should not exist
      expect(find.text('Add Attribution Note'), findsNothing);

      // Tap on the Attributions button
      await tester.tap(find.text('Attributions'));
      await tester.pumpAndSettle();

      // Verify it called addAttributionCard and opened the editor dialog
      expect(notesProvider.cards.any((c) => c.isAttribution), isTrue);
      expect(find.byType(NoteEditorDialog), findsOneWidget);
    });

    testWidgets('NotesSidebar renders borderless Attributions text button and opens existing attribution card without recreating it', (WidgetTester tester) async {
      when(() => mockSettings.lastNotesFullscreenState).thenReturn(false);
      await notesProvider.loadProject('test_path');
      // Create attribution card beforehand
      notesProvider.addAttributionCard(syncProvider: mockSync);
      final initialCardCount = notesProvider.cards.length;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotesSidebar(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the borderless button text "Attributions" is shown and NoteMiniCard is NOT shown for it
      expect(find.text('Attributions'), findsOneWidget);
      expect(find.byType(NoteMiniCard), findsNothing);

      // Tap on the Attributions button
      await tester.tap(find.text('Attributions'));
      await tester.pumpAndSettle();

      // Verify no new card was added, and the NoteEditorDialog is opened
      expect(notesProvider.cards.length, equals(initialCardCount));
      expect(find.byType(NoteEditorDialog), findsOneWidget);
    });

    testWidgets('LinkHighlightingTextEditingController highlights valid urls and ignores spaces', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final theme = WriterTheme.presets[0];
              final controller = LinkHighlightingTextEditingController(
                text: 'Hello www.google.com and www.google .com text',
                theme: theme,
              );

              final textSpan = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              expect(textSpan.children, isNotNull);
              expect(textSpan.children!.length, equals(5));

              expect((textSpan.children![0] as TextSpan).text, 'Hello ');
              expect((textSpan.children![0] as TextSpan).style, isNull);

              expect((textSpan.children![1] as TextSpan).text, 'www.google.com');
              expect((textSpan.children![1] as TextSpan).style!.decoration, TextDecoration.underline);

              expect((textSpan.children![2] as TextSpan).text, ' and ');
              expect((textSpan.children![2] as TextSpan).style, isNull);

              expect((textSpan.children![3] as TextSpan).text, 'www.google');
              expect((textSpan.children![3] as TextSpan).style!.decoration, TextDecoration.underline);

              expect((textSpan.children![4] as TextSpan).text, ' .com text');
              expect((textSpan.children![4] as TextSpan).style, isNull);

              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('Attributions list editor handles keyboard navigation (Enter, Shift+Enter, Backspace)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(() => mockSettings.lastNotesFullscreenState).thenReturn(false);

      await notesProvider.loadProject('test_path');
      notesProvider.addAttributionCard(syncProvider: mockSync);
      final noteId = notesProvider.cards.firstWhere((c) => c.isAttribution).id;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
            ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
            ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
            ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditorDialog(noteId: noteId),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially, there should be 1 empty list item text field (plus the Title text field)
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsNWidgets(2));

      final itemField = textFieldFinder.at(1);
      await tester.enterText(itemField, 'First item');
      await tester.pump();

      // Press Enter key to add a new item
      await tester.showKeyboard(itemField);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Should now have 3 TextFields (Title + 2 items)
      expect(find.byType(TextField), findsNWidgets(3));

      // Clear the second item's text
      await tester.enterText(find.byType(TextField).at(2), '');
      await tester.pump();

      // Press Backspace in the empty second item to delete it
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      // Should be back to 2 TextFields (Title + 1 item)
      expect(find.byType(TextField), findsNWidgets(2));

      // Focus the first item again
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();

      // Press Shift+Enter to add a newline
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      // Still should have 2 TextFields (no new item created on Shift+Enter)
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });
}
