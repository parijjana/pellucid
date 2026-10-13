import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/long_document/windowed_paper_area.dart';
import 'package:pellucid/features/editor/list_marker.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

class MockEditorProvider extends Mock implements EditorProvider {}
class MockThemeProvider extends Mock implements ThemeProvider {}
class MockSettingsProvider extends Mock implements SettingsProvider {
  @override
  bool get spellCheckEnabled => true;
}
class MockSyncProvider extends Mock implements SyncProvider {}
class MockHistoryProvider extends Mock implements HistoryProvider {}
class MockNotesProvider extends Mock implements NotesProvider {}
class MockWindowManager extends Mock implements WindowManager {}

void main() {
  late MockEditorProvider mockEditor;
  late MockThemeProvider mockTheme;
  late MockSettingsProvider mockSettings;
  late MockSyncProvider mockSync;
  late MockHistoryProvider mockHistory;
  late MockNotesProvider mockNotes;

  setUp(() {
    mockEditor = MockEditorProvider();
    mockTheme = MockThemeProvider();
    mockSettings = MockSettingsProvider();
    mockSync = MockSyncProvider();
    mockHistory = MockHistoryProvider();
    mockNotes = MockNotesProvider();

    when(() => mockEditor.content).thenReturn('# Hello World');

    when(() => mockEditor.documentLoadFailed).thenReturn(false);

    when(() => mockEditor.isMirrorProject).thenReturn(false);
    when(() => mockEditor.zoomLevel).thenReturn(1.0);
    when(() => mockEditor.pageWidth).thenReturn(800.0);
    when(() => mockEditor.horizontalPosition).thenReturn(0.5);
    
    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets[0]);
    
    when(() => mockSettings.currentProjectName).thenReturn('Test Project');
    when(() => mockSettings.clockEnabled).thenReturn(false);
    when(() => mockSettings.currentSessionEnabled).thenReturn(false);
    when(() => mockSettings.targetSessionEnabled).thenReturn(false);
    when(() => mockSettings.focusTimerEnabled).thenReturn(false);
    when(() => mockSettings.isAlarmTriggered).thenReturn(false);
    when(() => mockSettings.batteryGuardEnabled).thenReturn(false);
    when(() => mockSettings.batteryAlertThreshold).thenReturn(20);
    when(() => mockSettings.typewriterEnabled).thenReturn(false);
    when(() => mockSettings.paragraphFocusEnabled).thenReturn(false);
    when(() => mockSettings.codexLinkingEnabled).thenReturn(false);
    when(() => mockSettings.tocWordCountsEnabled).thenReturn(true);

    when(() => mockSync.status).thenReturn(SyncStatus.idle);
    when(() => mockSync.isLoggedIn).thenReturn(false);
    when(() => mockSync.lastSynced).thenReturn(null);

    when(() => mockHistory.history).thenReturn([]);
    when(() => mockHistory.currentProjectStats).thenReturn(ProjectStats());

    when(() => mockNotes.cards).thenReturn([]);
  });


  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
          ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
          ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ChangeNotifierProvider<SyncProvider>.value(value: mockSync),
          ChangeNotifierProvider<HistoryProvider>.value(value: mockHistory),
          ChangeNotifierProvider<NotesProvider>.value(value: mockNotes),
          ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
          ChangeNotifierProvider<ShortcutsProvider>(create: (_) => ShortcutsProvider()),
          ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
        ],
        child: const MaterialApp(home: EditorScreen()),
      );

  final zoomCalls = <double>[];

  setUpAll(() => registerFallbackValue(1.0));

  setUp(() {
    zoomCalls.clear();
    when(() => mockSettings.bulletStyle).thenReturn(BulletStyle.defaultStyle);
    when(() => mockSettings.editorFont).thenReturn(EditorFont.values.first);
    when(() => mockSettings.grammarHintsEnabled).thenReturn(false);
    when(() => mockSettings.smartPunctuationEnabled).thenReturn(false);
    when(() => mockSettings.autoContinueListsEnabled).thenReturn(false);
    when(() => mockSettings.attributionDuplicateHighlightEnabled).thenReturn(false);
    when(() => mockEditor.content)
        .thenReturn(List.generate(200, (i) => 'Line $i of text').join('\n\n'));
    when(() => mockEditor.setZoomLevel(any())).thenAnswer((inv) {
      zoomCalls.add(EditorProvider.snapZoom(inv.positionalArguments.first as double));
    });
  });

  Future<void> desktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pump();
  }

  Future<TestPointer> pinch(WidgetTester tester, double scale,
      {Offset pan = Offset.zero}) async {
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(const Offset(700, 450)));
    await tester.sendEventToBinding(
        pointer.panZoomUpdate(const Offset(700, 450), scale: scale, pan: pan));
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();
    return pointer;
  }

  group('trackpad pinch zoom on desktop layout', () {
    testWidgets('pinch out raises zoom to a 5% step', (tester) async {
      await desktop(tester);
      await pinch(tester, 1.12);
      expect(zoomCalls, isNotEmpty);
      expect(zoomCalls.last, closeTo(1.10, 1e-9));
      expect(zoomCalls.last, greaterThan(1.0));
    });

    testWidgets('pinch in lowers zoom', (tester) async {
      await desktop(tester);
      await pinch(tester, 0.8);
      expect(zoomCalls.last, closeTo(0.80, 1e-9));
    });

    testWidgets('pan without scale leaves zoom alone and still scrolls',
        (tester) async {
      await desktop(tester);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
      final before = scrollable.position.pixels;
      await pinch(tester, 1.0, pan: const Offset(0, -200));
      expect(zoomCalls, isEmpty);
      expect(scrollable.position.pixels, greaterThan(before));
    });

    testWidgets('narrow desktop window (still non-compact) pinches too',
        (tester) async {
      // The compact (touch) branch cannot be forced from flutter test because
      // isTouchPlatform reads Platform.*; its scale handlers now share
      // _applyPinchScale with this path, which this test exercises.
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pump();
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(const Offset(250, 400)));
      await tester.sendEventToBinding(
          pointer.panZoomUpdate(const Offset(250, 400), scale: 1.3));
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pump();
      expect(zoomCalls.last, closeTo(1.30, 1e-9));
    });

    testWidgets('pinch works while the windowed long-document editor is shown',
        (tester) async {
      debugForceWindowedEditor = true;
      addTearDown(() => debugForceWindowedEditor = false);
      when(() => mockEditor.content).thenReturn(
          List.generate(20000, (i) => 'Line $i of some text here').join('\n\n'));
      await desktop(tester);
      expect(find.byType(WindowedEditor), findsOneWidget);
      await pinch(tester, 1.12);
      expect(zoomCalls.last, closeTo(1.10, 1e-9));
    });
  });
}
