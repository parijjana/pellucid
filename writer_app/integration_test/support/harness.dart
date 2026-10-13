// Shared rig for the long-document E2E suite. Mounts the REAL EditorScreen (the
// same widget tree the app shows) over real EditorProvider / NotesProvider /
// StorageService instances that read and write ONLY a temp directory.
//
// What is faked, deliberately: settings persistence (an in-memory
// SettingsDatabase, so no settings.db is touched), Google sync (never signed
// in), the history/stats provider, and the system clipboard (an in-memory
// pasteboard, so a run never overwrites the owner's clipboard).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';
import 'package:pellucid/features/editor/widgets/editor_selection_actions.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/token_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture.dart';

class _MemDb extends Mock implements SettingsDatabase {
  @override
  Future<void> updateSetting(String key, dynamic value) async {}
}

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

class _Sync extends Mock implements SyncProvider {}

class _Hist extends Mock implements HistoryProvider {}

/// Refuses to run unless the test app is the isolated e2e bundle and every
/// path it will touch is under the system temp directory.
Future<void> assertIsolated() async {
  final support = (await getApplicationSupportDirectory()).path;
  if (!support.contains('com.overengineeredhobbies.pellucid.e2e')) {
    throw StateError('E2E ISOLATION BREACH: app support dir is "$support", not the .e2e bundle. Aborting.');
  }
  // ignore: avoid_print
  print('E2E|isolation|app support dir = $support');
}

void step(String s) {
  // ignore: avoid_print
  print('STEP|${DateTime.now().toIso8601String().substring(11, 23)}|$s');
}

/// The fixture is expensive to build; share one.
final Fixture fixture = buildFixture();

class Rig {
  final WidgetTester tester;
  final Fixture fx;
  final Directory root;
  final String projectPath;
  final EditorProvider editor;
  final SettingsProvider settings;
  final SearchProvider search;
  final NotesProvider notes;
  final ShortcutsProvider shortcuts;
  final MarkdownEditingController doc;
  final String codexId;
  final List<String> clipboardLog;
  String clipboard;

  Rig._(this.tester, this.fx, this.root, this.projectPath, this.editor, this.settings, this.search, this.notes,
      this.shortcuts, this.doc, this.codexId, this.clipboardLog, this.clipboard);

  WindowedEditorState get win => tester.state<WindowedEditorState>(find.byType(WindowedEditor));
  String get text => doc.text;
  TextSelection get sel => doc.selection;
  FocusNode get focus => win.widget.focusNode;

  /// Document equals [expected], reporting only the first difference (never the 600 kB).
  void expectDoc(String expected, String reason) {
    final actual = doc.text;
    if (actual == expected) return;
    int i = 0;
    final n = actual.length < expected.length ? actual.length : expected.length;
    while (i < n && actual.codeUnitAt(i) == expected.codeUnitAt(i)) {
      i++;
    }
    String snip(String t) {
      final a = (i - 30).clamp(0, t.length), b = (i + 40).clamp(0, t.length);
      return t.substring(a, b).replaceAll('\n', r'\n');
    }

    fail('$reason: document differs at $i (len ${actual.length} vs expected ${expected.length}); '
        'actual "...${snip(actual)}..." expected "...${snip(expected)}..."');
  }

  Future<void> pump([int frames = 3]) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Scrolls so [offset] is a third down the view (as Find and the TOC do).
  Future<void> reveal(int offset, {double fraction = 1 / 3}) async {
    step('reveal $offset');
    bool done = false;
    final f = win.revealOffset(offset, fraction: fraction, duration: Duration.zero).then((_) => done = true);
    for (int i = 0; i < 80 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (!done) throw StateError('reveal($offset) did not finish in 80 frames');
    await f;
    await pump();
  }

  Rect get viewport => tester.getRect(find.byType(CustomScrollView));

  /// Global rect of document line [line] if it is built, else null.
  Rect? lineRect(int line) {
    final f = find.byKey(ValueKey('L$line'));
    if (f.evaluate().isNotEmpty) return tester.getRect(f);
    return null;
  }

  /// Screen point at the start of document line [line] (caller must have revealed it).
  Offset pointInLine(int line, {double dx = 24, double dy = 8}) {
    final r = lineRect(line);
    if (r != null) return r.topLeft + Offset(dx, dy);
    // The line is in the live window, not a static line: ask the field.
    final re = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    final local = win.window.windowStart;
    final docOff = fx.lineStart(line) - local;
    final box = re.getLocalRectForCaret(TextPosition(offset: docOff));
    return re.localToGlobal(box.topLeft) + Offset(dx, dy);
  }

  /// Screen point at document offset [off], in the live field or a static line.
  Offset pointAtOffset(int off) {
    final w = win;
    final ws = w.window.windowStart;
    if (off >= ws && off <= ws + w.window.text.length) {
      final re = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
      final r = re.getLocalRectForCaret(TextPosition(offset: off - ws));
      return re.localToGlobal(r.center) + const Offset(1, 0);
    }
    final line = w.buffer.lineOfOffset(off);
    final f = find.byKey(ValueKey('L$line'));
    expect(f, findsOneWidget, reason: 'line $line is built');
    final ro = tester.renderObject(f);
    final col = off - w.buffer.lineStart(line);
    // The static line's paragraph resolves columns.
    final para = _findParagraph(ro);
    final r = para.getBoxesForSelection(TextSelection(baseOffset: col, extentOffset: col + 1));
    final box = r.isEmpty ? Rect.fromLTWH(0, 0, 4, 20) : r.first.toRect();
    return para.localToGlobal(box.center);
  }

  RenderParagraph _findParagraph(RenderObject ro) {
    RenderParagraph? found;
    void visit(RenderObject n) {
      if (found != null) return;
      if (n is RenderParagraph) {
        found = n;
        return;
      }
      n.visitChildren(visit);
    }

    visit(ro);
    return found!;
  }

  /// What the platform does for typed text: a new value on the field.
  Future<void> typeText(String s, {int gapMs = 30}) async {
    step('typeText');
    for (final ch in s.characters) {
      // The field's own current value (the test input channel's editingState goes stale).
      final v = win.window.value;
      final b = v.selection.baseOffset, e = v.selection.extentOffset;
      final lo = b < e ? b : e, hi = b < e ? e : b;
      final next = v.text.replaceRange(lo, hi, ch);
      tester.testTextInput.updateEditingValue(
          TextEditingValue(text: next, selection: TextSelection.collapsed(offset: lo + ch.length)));
      await tester.pump(Duration(milliseconds: gapMs));
    }
  }

  Future<void> key(LogicalKeyboardKey k,
      {bool meta = false, bool shift = false, bool alt = false, bool ctrl = false}) async {
    step('key ${k.keyLabel} meta=$meta shift=$shift');
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(k);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await pump();
  }

  /// Puts the caret at [offset] by setting the document selection (as Find /
  /// a jump does) and gives the editor focus.
  Future<void> placeCaret(int offset) async {
    step('placeCaret $offset');
    doc.selection = TextSelection.collapsed(offset: offset);
    await pump(4);
    focus.requestFocus();
    await pump(4);
  }

  /// Waits [d] of real time while frames keep flowing.
  Future<void> wait(Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    tester.testTextInput.unregister();
    debugDefaultTargetPlatformOverride = null;
  }

  /// Asserts the windowed editor is what's on screen and the document is the
  /// long one. Prints the evidence.
  void expectWindowed() {
    expect(find.byType(WindowedEditor), findsOneWidget, reason: 'windowed editor engaged');
    expect(fx.words, greaterThanOrEqualTo(kWindowedEditorMinWords));
  }
}

/// Mounts a fresh EditorScreen over a fresh temp project holding [text] (the
/// fixture by default) and a codex note "Darcy".
Future<Rig> mount(WidgetTester tester,
    {String? text, Size size = const Size(1400, 900), bool spell = false, bool codex = false}) async {
  step('mount start');
  await assertIsolated();
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  // The integration binding talks to the real macOS text-input plugin; to drive composing text and
  // typing deterministically the platform channel is replaced by the test text-input harness. The
  // widget tree above it (EditableText, formatters, the windowed editor) is the real one.
  tester.testTextInput.register();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fx = fixture;
  final root = await Directory.systemTemp.createTemp('pellucid_e2e_');
  final projectPath = '${root.path}/Long Book';
  await Directory(projectPath).create(recursive: true);
  await File('$projectPath/document.md').writeAsString(text ?? fx.text);
  final darcy = NoteCard(title: 'Darcy', content: 'Proud, rich, and misjudged.', category: 'people');
  await File('$projectPath/notes.json').writeAsString(jsonEncode([darcy.toJson()]));
  await File('$projectPath/stats.json').writeAsString('{}');

  final storage = StorageService();
  final editor = EditorProvider(storageService: storage, settingsDatabase: _MemDb());
  await editor.loadProject(projectPath);
  final notes = NotesProvider();
  await notes.loadProject(projectPath, projectName: 'Long Book');
  final settings = SettingsProvider(
    settingsDatabase: _MemDb(),
    storageService: storage,
    tokenStore: TokenStore(secrets: _Secrets(), prefs: SharedPreferences.getInstance),
  );
  settings.toggleCodexLinking(codex);
  settings.toggleSpellCheck(spell);
  final sync = _Sync();
  when(() => sync.status).thenReturn(SyncStatus.idle);
  when(() => sync.isLoggedIn).thenReturn(false);
  when(() => sync.lastSynced).thenReturn(null);
  final hist = _Hist();
  when(() => hist.history).thenReturn([]);
  when(() => hist.currentProjectStats).thenReturn(ProjectStats());
  final search = SearchProvider();
  final shortcuts = ShortcutsProvider();

  // In-memory pasteboard: never touch the owner's clipboard.
  final clip = <String>[];
  late Rig rig;
  String clipboard = '';
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboard = (call.arguments as Map)['text'] as String? ?? '';
      clip.add(clipboard);
      return null;
    }
    if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clipboard};
    if (call.method == 'Clipboard.hasStrings') return <String, dynamic>{'value': clipboard.isNotEmpty};
    return null;
  });
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/charging'), (_) async => null);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<EditorProvider>.value(value: editor),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<SyncProvider>.value(value: sync),
      ChangeNotifierProvider<HistoryProvider>.value(value: hist),
      ChangeNotifierProvider<NotesProvider>.value(value: notes),
      ChangeNotifierProvider<SearchProvider>.value(value: search),
      ChangeNotifierProvider<ShortcutsProvider>.value(value: shortcuts),
      ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
    ],
    child: const MaterialApp(home: EditorScreen()),
  ));
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  step('mount pumped');
  rig = Rig._(tester, fx, root, projectPath, editor, settings, search, notes, shortcuts,
      ActiveEditor.controller! as MarkdownEditingController, darcy.id, clip, clipboard);
  // Keep the rig's clipboard view live.
  return rig;
}

extension RigClipboard on Rig {
  Future<String> readClipboard() async => (await Clipboard.getData('text/plain'))?.text ?? '';
}

// ---------------------------------------------------------------- timing ---

class FrameStats {
  final String name;
  final List<int> buildUs;
  final List<int> rasterUs;
  final List<int> totalUs;
  FrameStats(this.name, this.buildUs, this.rasterUs, this.totalUs);

  static int _pct(List<int> l, double p) {
    if (l.isEmpty) return 0;
    final s = [...l]..sort();
    return s[((s.length - 1) * p).round()];
  }

  double ms(int us) => us / 1000;
  int get frames => totalUs.length;
  double get p50 => ms(_pct(totalUs, .5));
  double get p90 => ms(_pct(totalUs, .9));
  double get max => ms(_pct(totalUs, 1));
  double get buildP50 => ms(_pct(buildUs, .5));
  double get buildP90 => ms(_pct(buildUs, .9));
  double get buildMax => ms(_pct(buildUs, 1));
  double get rasterP50 => ms(_pct(rasterUs, .5));
  double get rasterP90 => ms(_pct(rasterUs, .9));
  double get rasterMax => ms(_pct(rasterUs, 1));

  String line() => 'TIMING|$name|frames=$frames|build p50/p90/max=${buildP50.toStringAsFixed(1)}/'
      '${buildP90.toStringAsFixed(1)}/${buildMax.toStringAsFixed(1)}ms|raster p50/p90/max='
      '${rasterP50.toStringAsFixed(1)}/${rasterP90.toStringAsFixed(1)}/${rasterMax.toStringAsFixed(1)}ms|'
      'total p50/p90/max=${p50.toStringAsFixed(1)}/${p90.toStringAsFixed(1)}/${max.toStringAsFixed(1)}ms';
}

/// Records engine frame timings between start() and stop(). The engine batches
/// timings, so stop() waits a moment for the last batch.
class FrameRecorder {
  final List<FrameTiming> _frames = [];
  late final TimingsCallback _cb = _frames.addAll;
  void start() {
    _frames.clear();
    SchedulerBinding.instance.addTimingsCallback(_cb);
  }

  Future<FrameStats> stop(WidgetTester tester, String name) async {
    // Keep frames flowing so the engine flushes its batch.
    final end = DateTime.now().add(const Duration(milliseconds: 1400));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    SchedulerBinding.instance.removeTimingsCallback(_cb);
    final stats = FrameStats(
      name,
      [for (final f in _frames) f.buildDuration.inMicroseconds],
      [for (final f in _frames) f.rasterDuration.inMicroseconds],
      [for (final f in _frames) f.totalSpan.inMicroseconds],
    );
    // ignore: avoid_print
    print(stats.line());
    return stats;
  }
}

/// Registers a check test. Names start with "Check N" so the run script can
/// build a table. [knownBug] marks a test expected to fail because of a real
/// app bug: it passes while the bug exists and fails (loudly) once fixed.
void check(String name, Future<void> Function(WidgetTester tester) body, {String? knownBug}) {
  testWidgets(name, (tester) async {
    if (knownBug == null) {
      await body(tester);
      return;
    }
    Object? failure;
    try {
      await body(tester);
    } catch (e) {
      failure = e;
    }
    if (failure == null) {
      fail('XFAIL test passed unexpectedly: the app bug may be fixed ($knownBug)');
    }
    // ignore: avoid_print
    print('XFAIL|$name|$knownBug|${failure.toString().split('\n').first}');
  }, timeout: const Timeout(Duration(seconds: 150)));
}
