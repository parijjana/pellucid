import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:pellucid/features/search/widgets/search_popup.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';

class MockEditorProvider extends Mock implements EditorProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockNotesProvider extends Mock implements NotesProvider {}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockSettingsProvider extends Mock implements SettingsProvider {}

void main() {
  group('SearchProvider Unit Tests', () {
    test('initial state is closed and empty query', () {
      final provider = SearchProvider();
      expect(provider.isSearchOpen, isFalse);
      expect(provider.query, isEmpty);
    });

    test('toggleSearch changes state and resets query on close', () {
      final provider = SearchProvider();
      
      provider.toggleSearch(isOpen: true);
      expect(provider.isSearchOpen, isTrue);

      provider.setQuery('test');
      expect(provider.query, 'test');

      provider.toggleSearch(isOpen: false);
      expect(provider.isSearchOpen, isFalse);
      expect(provider.query, isEmpty);
    });

    test('setQuery updates query', () {
      final provider = SearchProvider();
      provider.setQuery('hello');
      expect(provider.query, 'hello');
    });

    test('clear resets query', () {
      final provider = SearchProvider();
      provider.setQuery('hello');
      provider.clear();
      expect(provider.query, isEmpty);
    });
  });

  group('SearchPopup Widget Tests', () {
    late MockEditorProvider mockEditor;
    late MockThemeProvider mockTheme;
    late MockNotesProvider mockNotes;
    late SearchProvider searchProvider;

    setUp(() {
      mockEditor = MockEditorProvider();
      mockTheme = MockThemeProvider();
      mockNotes = MockNotesProvider();
      searchProvider = SearchProvider();

      when(() => mockEditor.content).thenReturn('Once upon a time in a fantasy world.');
      when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets[0]);
      when(() => mockNotes.cards).thenReturn([
        NoteCard(title: 'Character info', content: 'Alice is a wizard.'),
        NoteCard(title: 'World-building notes', content: 'Fantasy realm of Eldoria.'),
      ]);
    });

    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
          ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SearchPopup(),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('renders search popup elements', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('autofocuses text field', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(); // allow post frame callbacks to run

      final FocusScopeNode focusScope = FocusScope.of(tester.element(find.byType(TextField)));
      expect(focusScope.focusedChild, isNotNull);
    });

    testWidgets('updates query on text entry and displays match count', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'wizard');
      await tester.pump();

      expect(searchProvider.query, 'wizard');
      // "wizard" appears once in NoteCard content. Total: 1 match
      expect(find.text('1 match'), findsOneWidget);
    });

    testWidgets('clears text on close/clear button tap', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'wizard');
      await tester.pump();
      expect(searchProvider.query, 'wizard');

      // Click clear button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(searchProvider.query, isEmpty);
      expect(find.text('wizard'), findsNothing);
    });

    testWidgets('closes search on ESC key press', (WidgetTester tester) async {
      searchProvider.toggleSearch(isOpen: true);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(searchProvider.isSearchOpen, isFalse);
    });
  });
}
