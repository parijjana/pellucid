import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/list_marker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/main.dart';
import 'package:pellucid/features/editor/widgets/typewriter_pause.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';

class MockEditorProvider extends Mock implements EditorProvider {}

class MockThemeProvider extends Mock implements ThemeProvider {}

class MockSettingsProvider extends Mock implements SettingsProvider {
  @override
  EditorFont get editorFont => EditorFont.defaultFont;
  @override
  bool get spellCheckEnabled => true;
  @override
  bool get grammarHintsEnabled => false;
  @override
  bool get smartPunctuationEnabled => false;
  @override
  BulletStyle get bulletStyle => BulletStyle.defaultStyle;
  @override
  bool get autoContinueListsEnabled => true;
  @override
  bool get attributionDuplicateHighlightEnabled => true;
}

class MockSyncProvider extends Mock implements SyncProvider {}

class MockHistoryProvider extends Mock implements HistoryProvider {}

class MockNotesProvider extends Mock implements NotesProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('window_manager');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall c) async => null);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final doc = List.generate(
    120,
    (i) => 'Line number $i of the manuscript',
  ).join('\n');

  Future<(TextEditingController, ScrollController)> pump(
    WidgetTester tester,
  ) async {
    final editor = MockEditorProvider();
    final theme = MockThemeProvider();
    final settings = MockSettingsProvider();
    final sync = MockSyncProvider();
    final history = MockHistoryProvider();
    final notes = MockNotesProvider();
    when(() => editor.content).thenReturn(doc);
    when(() => editor.documentLoadFailed).thenReturn(false);
    when(() => editor.isMirrorProject).thenReturn(false);
    when(() => editor.zoomLevel).thenReturn(1.0);
    when(() => editor.pageWidth).thenReturn(800.0);
    when(() => editor.horizontalPosition).thenReturn(0.5);
    when(() => theme.currentTheme).thenReturn(WriterTheme.presets[0]);
    when(() => settings.currentProjectName).thenReturn('Test Project');
    when(() => settings.currentProjectPath).thenReturn('/test_project');
    when(() => settings.masterDirectoryPath).thenReturn('/test_master');
    when(() => settings.availableProjects).thenReturn([]);
    when(() => settings.clockEnabled).thenReturn(false);
    when(() => settings.currentSessionEnabled).thenReturn(false);
    when(() => settings.targetSessionEnabled).thenReturn(false);
    when(() => settings.focusTimerEnabled).thenReturn(false);
    when(() => settings.isAlarmTriggered).thenReturn(false);
    when(() => settings.batteryGuardEnabled).thenReturn(false);
    when(() => settings.showBatteryPercentage).thenReturn(false);
    when(() => settings.batteryAlertThreshold).thenReturn(20);
    when(() => settings.lastNotesFullscreenState).thenReturn(false);
    when(
      () => settings.setLastNotesFullscreenState(any()),
    ).thenAnswer((_) async {});
    when(() => settings.refreshProjects()).thenAnswer((_) async {});
    when(() => settings.markProjectMirrored(any())).thenAnswer((_) async {});
    when(() => settings.syncIntervalMinutes).thenReturn(30);
    when(() => settings.typewriterEnabled).thenReturn(true);
    when(() => settings.paragraphFocusEnabled).thenReturn(false);
    when(() => settings.codexLinkingEnabled).thenReturn(false);
    when(() => settings.tocWordCountsEnabled).thenReturn(true);
    when(() => settings.dailyWordGoal).thenReturn(0);
    when(() => settings.hasDailyWordGoal).thenReturn(false);
    when(() => sync.status).thenReturn(SyncStatus.idle);
    when(() => sync.isLoggedIn).thenReturn(false);
    when(() => sync.lastSynced).thenReturn(null);
    when(() => history.history).thenReturn([]);
    when(() => history.currentProjectStats).thenReturn(ProjectStats());
    when(() => history.saveStatsNow()).thenAnswer((_) async {});
    when(() => history.loadProjectStats(any())).thenAnswer((_) async {});
    when(() => notes.cards).thenReturn([]);
    when(
      () => notes.categories,
    ).thenReturn(['general', 'people', 'places', 'events']);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: editor),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
          ChangeNotifierProvider<HistoryProvider>.value(value: history),
          ChangeNotifierProvider<NotesProvider>.value(value: notes),
          ChangeNotifierProvider<SearchProvider>(
            create: (_) => SearchProvider(),
          ),
          ChangeNotifierProvider<ShortcutsProvider>.value(
            value: ShortcutsProvider(),
          ),
          ChangeNotifierProvider<SprintController>(
            create: (_) => SprintController(),
          ),
        ],
        child: const WriterApp(),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    field.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    return (field.controller!, scroll);
  }

  int offsetOfLine(int n) =>
      doc.split('\n').take(n).fold<int>(0, (a, l) => a + l.length + 1);

  testWidgets(
    'mouse selection across lines does not scroll; a key then re-centres once',
    (tester) async {
      final (controller, scroll) = await pump(tester);

      // Typewriter on: moving the caret far down re-centres.
      controller.selection = TextSelection.collapsed(offset: offsetOfLine(40));
      await tester.pumpAndSettle();
      final before = scroll.offset;
      expect(before, greaterThan(0));

      // Press the mouse in the text, then "drag" the selection down many lines.
      final gesture = await tester.startGesture(
        const Offset(600, 400),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      controller.selection = TextSelection(
        baseOffset: offsetOfLine(40),
        extentOffset: offsetOfLine(44),
      );
      await tester.pumpAndSettle();
      controller.selection = TextSelection(
        baseOffset: offsetOfLine(40),
        extentOffset: offsetOfLine(47),
      );
      await tester.pumpAndSettle();
      expect(
        scroll.offset,
        before,
        reason: 'page must not jump while the mouse selects',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, before);

      // A caret-moving key resumes typewriter scroll and re-centres.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(scroll.offset, isNot(before));
    },
  );

  testWidgets('Shift+arrow selection after a keystroke keeps typewriter on', (
    tester,
  ) async {
    final (controller, scroll) = await pump(tester);
    controller.selection = TextSelection.collapsed(offset: offsetOfLine(5));
    await tester.pumpAndSettle();
    final before = scroll.offset;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    controller.selection = TextSelection(
      baseOffset: offsetOfLine(5),
      extentOffset: offsetOfLine(60),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(scroll.offset, greaterThan(before));
  });

  test(
    'TypewriterPause.resumes: keys that edit or move resume, modifiers do not',
    () {
      KeyEvent down(LogicalKeyboardKey k) => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: k,
        timeStamp: Duration.zero,
      );
      bool r(LogicalKeyboardKey k, {bool cm = false, bool alt = false}) =>
          TypewriterPause.resumes(down(k), ctrlOrMeta: cm, alt: alt);
      expect(r(LogicalKeyboardKey.keyA), isTrue);
      expect(r(LogicalKeyboardKey.backspace), isTrue);
      expect(r(LogicalKeyboardKey.arrowLeft), isTrue);
      expect(r(LogicalKeyboardKey.arrowLeft, cm: true), isTrue);
      expect(r(LogicalKeyboardKey.home), isTrue);
      expect(r(LogicalKeyboardKey.pageDown), isTrue);
      expect(r(LogicalKeyboardKey.keyV, cm: true), isTrue);
      expect(r(LogicalKeyboardKey.keyC, cm: true), isFalse);
      expect(r(LogicalKeyboardKey.keyK, alt: true), isFalse);
      expect(r(LogicalKeyboardKey.shiftLeft), isFalse);
      expect(r(LogicalKeyboardKey.metaLeft), isFalse);
      expect(
        TypewriterPause.resumes(
          KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            timeStamp: Duration.zero,
          ),
          ctrlOrMeta: false,
          alt: false,
        ),
        isFalse,
      );
    },
  );
}
