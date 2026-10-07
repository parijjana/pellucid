import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';

class MockEditorProvider extends Mock implements EditorProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockSettingsProvider extends Mock implements SettingsProvider {}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockHistoryProvider extends Mock implements HistoryProvider {}
class MockNotesProvider extends Mock implements NotesProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('window_manager');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  late MockEditorProvider mockEditor;
  late MockThemeProvider mockTheme;
  late MockSettingsProvider mockSettings;
  late MockSyncProvider mockSync;
  late MockHistoryProvider mockHistory;
  late MockNotesProvider mockNotes;
  late SearchProvider searchProvider;
  late ShortcutsProvider shortcutsProvider;

  Future<void> pumpEditor(WidgetTester tester, String content) async {
    when(() => mockEditor.content).thenReturn(content);
    when(() => mockEditor.documentLoadFailed).thenReturn(false);
    when(() => mockEditor.isMirrorProject).thenReturn(false);
    when(() => mockEditor.zoomLevel).thenReturn(1.0);
    when(() => mockEditor.pageWidth).thenReturn(800.0);
    when(() => mockEditor.horizontalPosition).thenReturn(0.5);
    when(() => mockEditor.updateContent(any(),
            syncProvider: any(named: 'syncProvider'),
            projectName: any(named: 'projectName'),
            syncInterval: any(named: 'syncInterval')))
        .thenAnswer((_) async {});

    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets.first);

    when(() => mockSettings.currentProjectName).thenReturn('Test Project');
    when(() => mockSettings.currentProjectPath).thenReturn('/test/project');
    when(() => mockSettings.masterDirectoryPath).thenReturn('/test/master');
    when(() => mockSettings.clockEnabled).thenReturn(false);
    when(() => mockSettings.currentSessionEnabled).thenReturn(false);
    when(() => mockSettings.targetSessionEnabled).thenReturn(false);
    when(() => mockSettings.focusTimerEnabled).thenReturn(false);
    when(() => mockSettings.isAlarmTriggered).thenReturn(false);
    when(() => mockSettings.batteryGuardEnabled).thenReturn(false);
    when(() => mockSettings.showBatteryPercentage).thenReturn(false);
    when(() => mockSettings.batteryAlertThreshold).thenReturn(20);
    when(() => mockSettings.syncIntervalMinutes).thenReturn(30);
    when(() => mockSettings.typewriterEnabled).thenReturn(false);
    when(() => mockSettings.paragraphFocusEnabled).thenReturn(false);
    when(() => mockSettings.codexLinkingEnabled).thenReturn(false);
    when(() => mockSettings.tocWordCountsEnabled).thenReturn(true);
    when(() => mockSettings.spellCheckEnabled).thenReturn(true);

    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());
    when(() => mockHistory.setEditorFocus(any())).thenReturn(null);
    when(() => mockHistory.saveStatsNow()).thenAnswer((_) async {});

    when(() => mockNotes.cards).thenReturn([]);
    when(() => mockNotes.categories).thenReturn(['general', 'people', 'places', 'events']);

    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
          ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
          ChangeNotifierProvider<ShortcutsProvider>.value(value: shortcutsProvider),
          ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    mockEditor = MockEditorProvider();
    mockTheme = MockThemeProvider();
    mockSettings = MockSettingsProvider();
    mockSync = MockSyncProvider();
    mockHistory = MockHistoryProvider();
    mockNotes = MockNotesProvider();
    searchProvider = SearchProvider();
    shortcutsProvider = ShortcutsProvider();
  });


  List<TextSpan> leaves(WidgetTester tester) {
    final editable = tester.state<EditableTextState>(find.byType(EditableText).first).renderEditable.text!;
    final out = <TextSpan>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.text != null) out.add(s);
        s.children?.forEach(walk);
      }
    }
    walk(editable);
    return out;
  }

  Future<void> findText(WidgetTester tester, String q) async {
    searchProvider.toggleSearch(isOpen: true);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('search_query_field')), q);
    await tester.pump();
  }

  Color? bg(TextSpan s) => s.style?.backgroundColor;

  testWidgets('every match is tinted and the current one is distinct', (tester) async {
    await pumpEditor(tester, '# cat title\nA **cat** and a cat.');
    await findText(tester, 'cat');
    final hits = leaves(tester).where((s) => s.text == 'cat').toList();
    expect(hits.length, 3);
    expect(hits.every((s) => bg(s) != null), isTrue);
    expect(bg(hits[0]), MarkdownEditingController.currentMatchColor(WriterTheme.presets.first));
    expect(bg(hits[1]), MarkdownEditingController.matchColor(WriterTheme.presets.first));
    expect(bg(hits[2]), MarkdownEditingController.matchColor(WriterTheme.presets.first));
    // Non-matching text is untouched.
    expect(leaves(tester).where((s) => s.text == 'cat').length, 3);
  });

  testWidgets('Next and Previous move the current match', (tester) async {
    await pumpEditor(tester, 'cat and cat and cat');
    await findText(tester, 'cat');
    final current = MarkdownEditingController.currentMatchColor(WriterTheme.presets.first);
    int currentIndex() =>
        leaves(tester).where((s) => s.text == 'cat').toList().indexWhere((s) => bg(s) == current);
    expect(currentIndex(), 0);
    searchProvider.nextMatch();
    await tester.pump();
    expect(currentIndex(), 1);
    searchProvider.previousMatch();
    searchProvider.previousMatch();
    await tester.pump();
    expect(currentIndex(), 2);
  });

  testWidgets('closing Find clears the highlights', (tester) async {
    await pumpEditor(tester, 'cat and cat');
    await findText(tester, 'cat');
    expect(leaves(tester).any((s) => bg(s) != null), isTrue);
    searchProvider.toggleSearch(isOpen: false);
    await tester.pump();
    expect(leaves(tester).any((s) => bg(s) != null), isFalse);
  });

  testWidgets('moving to a far match scrolls it into view', (tester) async {
    final doc = '${List.filled(120, 'filler line of text').join('\n')}\nneedle here';
    await pumpEditor(tester, doc);
    final scrollable = tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
    final outer = scrollable.firstWhere((s) => s.position.maxScrollExtent > 0);
    expect(outer.position.pixels, 0);
    await findText(tester, 'needle');
    await tester.pumpAndSettle();
    expect(outer.position.pixels, greaterThan(500));
  });

  testWidgets('status bar shows "N of M words" while text is selected', (tester) async {
    await pumpEditor(tester, 'one two three four');
    final controller = tester.widget<TextField>(find.byType(TextField).first).controller!;
    expect(find.text('4 words'), findsWidgets);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pump();
    expect(find.text('2 of 4 words'), findsWidgets);
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(find.text('4 words'), findsWidgets);
    expect(find.textContaining(' of 4 words'), findsNothing);
  });

  group('MarkdownEditingController highlighting', () {
    List<TextSpan> flat(MarkdownEditingController c, BuildContext ctx) {
      final out = <TextSpan>[];
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null) out.add(s);
          s.children?.forEach(walk);
        }
      }
      walk(c.buildTextSpan(context: ctx, style: const TextStyle(), withComposing: false));
      return out;
    }

    testWidgets('match colours are visible on every theme', (tester) async {
      for (final t in WriterTheme.presets) {
        for (final c in [MarkdownEditingController.matchColor(t), MarkdownEditingController.currentMatchColor(t)]) {
          final page = t.backgroundColor;
          final over = Color.alphaBlend(c, page);
          double d(Color a, Color b) =>
              (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
          expect(d(over, page), greaterThan(0.35), reason: '${t.name} highlight too faint');
        }
        expect(MarkdownEditingController.currentMatchColor(t),
            isNot(MarkdownEditingController.matchColor(t)));
      }
    });

    testWidgets('search tint combines with spell-check underline', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      final c = MarkdownEditingController(text: 'a catt here', theme: WriterTheme.presets.first);
      c.searchQuery = 'catt';
      c.setMisspellings(const [TextRange(start: 2, end: 6)]);
      final hit = flat(c, ctx).firstWhere((s) => s.text == 'catt');
      expect(hit.style!.backgroundColor, isNotNull);
      expect(hit.style!.decoration, TextDecoration.underline);
      c.searchQuery = '';
      final cleared = flat(c, ctx).firstWhere((s) => s.text == 'catt');
      expect(cleared.style!.backgroundColor, isNull);
      expect(cleared.style!.decoration, TextDecoration.underline);
      c.dispose();
    });
  });
}
