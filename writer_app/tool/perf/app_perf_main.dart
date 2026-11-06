// Whole-app performance harness (PERF_PASS_1.1.0). Measurement only; not part
// of the app. Runs the REAL app (WriterApp + the same providers as
// lib/main.dart) and drives it from inside the process.
//
//   env: PERF_MODE=prep|session   PERF_MASTER=<dir>  PERF_PROJECT=<name>
//        PERF_T0=<ms epoch taken by the launcher just before exec>
//        PERF_OUT=<jsonl file>    PERF_RUN=comma list (default: all)
//        PERF_IDLE_SECS=60
//
// Text input is injected through the real platform text-input channel path:
// a BinaryMessenger proxy sniffs TextInput.setClient/setEditingState (to track
// the client id and the platform-side editing model) and keystrokes are fed in
// as TextInputClient.updateEditingState messages, exactly what the macOS
// embedder sends. The OS key-event -> NSTextInputClient hop is NOT exercised.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:pellucid/main.dart' show WriterApp;
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';
import 'package:pellucid/features/editor/utils/toc_parser.dart';
import 'package:pellucid/features/editor/widgets/editor_selection_actions.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/editor/word_count.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/core/platform_context.dart';

final _env = Platform.environment;
final String _mode = _env['PERF_MODE'] ?? 'session';
final int _t0 = int.tryParse(_env['PERF_T0'] ?? '') ?? DateTime.now().millisecondsSinceEpoch;
final String _outPath = _env['PERF_OUT'] ?? '/tmp/pellucid-perf-out.jsonl';
final Set<String> _runSet = (_env['PERF_RUN'] ?? 'all').split(',').toSet();
final int _idleSecs = int.tryParse(_env['PERF_IDLE_SECS'] ?? '') ?? 60;
bool _want(String s) => _runSet.contains('all') || _runSet.contains(s);

int _since() => DateTime.now().millisecondsSinceEpoch - _t0;

void _emit(Map<String, Object?> m) {
  m['project'] = _env['PERF_PROJECT'];
  m['run'] = _env['PERF_RUNID'];
  File(_outPath).writeAsStringSync('${jsonEncode(m)}\n', mode: FileMode.append);
}

// ---------------------------------------------------------------- binding

class _Sniff extends BinaryMessenger {
  _Sniff(this.inner);
  final BinaryMessenger inner;
  static int? clientId;
  static String mText = '';
  static int mBase = 0, mExt = 0;
  static int setEditingStates = 0;

  @override
  Future<void> handlePlatformMessage(String channel, ByteData? data, ui.PlatformMessageResponseCallback? callback) =>
      inner.handlePlatformMessage(channel, data, callback);

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == 'flutter/textinput' && message != null) {
      try {
        final call = const JSONMethodCodec().decodeMethodCall(message);
        if (call.method == 'TextInput.setClient') {
          clientId = (call.arguments as List)[0] as int;
        } else if (call.method == 'TextInput.clearClient') {
          clientId = null;
        } else if (call.method == 'TextInput.setEditingState') {
          final m = call.arguments as Map;
          mText = m['text'] as String;
          mBase = m['selectionBase'] as int;
          mExt = m['selectionExtent'] as int;
          setEditingStates++;
        }
      } catch (_) {}
    }
    return inner.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) => inner.setMessageHandler(channel, handler);
}

class _PerfBinding extends BindingBase
    with GestureBinding, SchedulerBinding, ServicesBinding, PaintingBinding, SemanticsBinding, RendererBinding, WidgetsBinding {
  @override
  BinaryMessenger createBinaryMessenger() => _Sniff(super.createBinaryMessenger());
  static _PerfBinding ensureInitialized() {
    _inst ??= _PerfBinding();
    return _inst!;
  }

  static _PerfBinding? _inst;
}

// ---------------------------------------------------------------- timing

class _Frame {
  _Frame(this.buildStart, this.buildUs, this.rasterUs, this.rasterFinish, this.totalUs);
  final int buildStart, buildUs, rasterUs, rasterFinish, totalUs;
}

final List<_Frame> _frames = [];

void _installTimings() {
  SchedulerBinding.instance.addTimingsCallback((list) {
    for (final t in list) {
      _frames.add(_Frame(
        t.timestampInMicroseconds(ui.FramePhase.buildStart),
        t.buildDuration.inMicroseconds,
        t.rasterDuration.inMicroseconds,
        t.timestampInMicroseconds(ui.FramePhase.rasterFinish),
        t.totalSpan.inMicroseconds,
      ));
    }
  });
}

int _now() => dev.Timeline.now;

double _pct(List<num> sorted, double q) => sorted.isEmpty ? -1 : sorted[((sorted.length - 1) * q).round()].toDouble();
List<double> _sorted(Iterable<num> v) => (v.map((e) => e.toDouble()).toList()..sort());
Map<String, double> _stats(Iterable<num> v) {
  final s = _sorted(v);
  return {
    'n': s.length.toDouble(),
    'p50': _pct(s, .5),
    'p90': _pct(s, .9),
    'p99': _pct(s, .99),
    'max': s.isEmpty ? -1 : s.last,
  };
}

Future<void> _frame() => SchedulerBinding.instance.endOfFrame;
Future<void> _settle([int ms = 400]) async {
  for (int i = 0; i < 3; i++) {
    await _frame();
  }
  await Future<void>.delayed(Duration(milliseconds: ms));
}

/// Event-loop heartbeat: how late a 4 ms timer fires = how long the UI isolate was blocked.
class _Beat {
  final List<double> late = [];
  Timer? _t;
  int _last = 0;
  void start() {
    late.clear();
    _last = _now();
    _t = Timer.periodic(const Duration(milliseconds: 4), (_) {
      final n = _now();
      late.add((n - _last - 4000) / 1000.0);
      _last = n;
    });
  }

  double stop() {
    _t?.cancel();
    return late.isEmpty ? 0 : late.reduce((a, b) => a > b ? a : b);
  }
}

// ---------------------------------------------------------------- tree helpers

Element? _findEl(bool Function(Element) test) {
  Element? hit;
  void visit(Element e) {
    if (hit != null) return;
    if (test(e)) {
      hit = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return hit;
}

BuildContext get _ctx => _findEl((e) => e.widget is EditorScreen)!;

ScrollPosition? _mainScroll() {
  ScrollPosition? best;
  void visit(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final s = e.state as ScrollableState;
      final p = s.position;
      if (p.hasContentDimensions &&
          (s.axisDirection == AxisDirection.down || s.axisDirection == AxisDirection.up) &&
          (best == null || p.maxScrollExtent > best!.maxScrollExtent)) {
        best = p;
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return best;
}

FocusNode? _editorFocus() {
  FocusNode? n;
  void visit(Element e) {
    if (n != null) return;
    if (e.widget is EditableText) {
      n = (e.widget as EditableText).focusNode;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return n;
}

MarkdownEditingController get _doc => ActiveEditor.controller as MarkdownEditingController;
bool get _isWindowed => windowedEditorFor(_doc) != null;
T _p<T extends ChangeNotifier>() => Provider.of<T>(_ctx, listen: false);

// ---------------------------------------------------------------- input

Future<void> _ensureFocus() async {
  for (int i = 0; i < 40 && _Sniff.clientId == null; i++) {
    _editorFocus()?.requestFocus();
    await _frame();
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  if (_Sniff.clientId == null) throw StateError('no text input client');
}

/// Feed [ch] at the platform model's caret. Returns synchronous handler time (us).
Future<int> _key(String ch) async {
  final text = _Sniff.mText;
  final at = _Sniff.mExt.clamp(0, text.length);
  final nt = text.replaceRange(at, at, ch);
  final data = const JSONMethodCodec().encodeMethodCall(MethodCall('TextInputClient.updateEditingState', [
    _Sniff.clientId,
    {
      'text': nt,
      'selectionBase': at + ch.length,
      'selectionExtent': at + ch.length,
      'selectionAffinity': 'TextAffinity.downstream',
      'selectionIsDirectional': false,
      'composingBase': -1,
      'composingExtent': -1,
    }
  ]));
  _Sniff.mText = nt;
  _Sniff.mBase = _Sniff.mExt = at + ch.length;
  final t = _now();
  final c = Completer<void>();
  (ServicesBinding.instance.defaultBinaryMessenger as _Sniff)
      .inner
      .handlePlatformMessage('flutter/textinput', data, (_) => c.complete());
  await c.future;
  return _now() - t;
}

const _typed = 'the quick brown fox jumps over the lazy dog ';

/// e2e latency (input -> raster finish) per key, plus handler-only and build/raster.
Future<Map<String, Object?>> _typePaced(int n, {int gapMs = 90}) async {
  _frames.clear();
  final starts = <int>[];
  final handler = <int>[];
  final toFrameEnd = <int>[];
  for (int i = 0; i < n; i++) {
    final ch = _typed[i % _typed.length];
    final t0 = _now();
    starts.add(t0);
    handler.add(await _key(ch));
    await _frame();
    toFrameEnd.add(_now() - t0);
    await Future<void>.delayed(Duration(milliseconds: gapMs));
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final e2e = <double>[];
  for (final t0 in starts) {
    final f = _frames.where((f) => f.buildStart >= t0 - 500).firstOrNull;
    if (f != null) e2e.add((f.rasterFinish - t0) / 1000.0);
  }
  return {
    'e2e_ms': _stats(e2e),
    'handler_ms': _stats(handler.map((e) => e / 1000.0)),
    'toFrameEnd_ms': _stats(toFrameEnd.map((e) => e / 1000.0)),
    'build_ms': _stats(_frames.map((f) => f.buildUs / 1000.0)),
    'raster_ms': _stats(_frames.map((f) => f.rasterUs / 1000.0)),
    'frames': _frames.length,
  };
}

/// Real-rate typing: keys at a fixed cadence regardless of how the UI is
/// doing. Reports timer lateness (event-loop stalls) and dropped characters.
Future<Map<String, Object?>> _typeRate(int n, int cps, int caretAt) async {
  final doc = _doc;
  final before = doc.text;
  final interval = 1000000 ~/ cps;
  final expected = StringBuffer();
  for (int i = 0; i < n; i++) {
    expected.write(_typed[i % _typed.length]);
  }
  _frames.clear();
  final late = <double>[];
  final handler = <double>[];
  final start = _now();
  for (int i = 0; i < n; i++) {
    final target = start + i * interval;
    final wait = target - _now();
    if (wait > 0) await Future<void>.delayed(Duration(microseconds: wait));
    late.add((_now() - target) / 1000.0);
    handler.add(await _key(_typed[i % _typed.length]) / 1000.0);
  }
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final after = doc.text;
  final want = before.replaceRange(caretAt, caretAt, expected.toString());
  final gained = after.length - before.length;
  return {
    'cps': cps,
    'n': n,
    'inserted': gained,
    'dropped': n - gained,
    'exact_match': after == want,
    'late_ms': _stats(late),
    'handler_ms': _stats(handler),
    'frame_total_ms': _stats(_frames.map((f) => f.totalUs / 1000.0)),
    'wall_ms': (_now() - start) / 1000.0,
  };
}

// ---------------------------------------------------------------- scenarios

bool _isWindowedExpected(String t) => t.length >= kWindowedEditorMinWords * 6;

Future<void> _waitDocVisible(String expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final c = ActiveEditor.controller;
    if (c != null && c.text.length == expected.length) {
      if (windowedEditorFor(c) == null && _isWindowedExpected(expected)) {
        // windowed editor not yet built
      } else {
        break;
      }
    }
    await _frame();
  }
  await _frame();
  await _frame();
}

Future<int> _rss() async => ProcessInfo.currentRss;

double _cpuSecs() {
  final r = Process.runSync('ps', ['-o', 'time=', '-p', '$pid']);
  final s = (r.stdout as String).trim();
  double v = 0;
  for (final p in s.split(':')) {
    v = v * 60 + double.parse(p);
  }
  return v;
}

Future<void> _launchScenario(EditorProvider editor, Map<String, int> marks) async {
  final content = editor.content;
  await _waitDocVisible(content);
  marks['docVisible'] = _since();
  final windowed = _isWindowed;
  final tFocus = _since();
  await _ensureFocus();
  final tFocused = _since();
  final before = _doc.text.length;
  final h = await _key('x');
  await _frame();
  final accepted = _doc.text.length == before + 1;
  marks['focusReady'] = tFocused;
  marks['firstKeyDone'] = _since();
  _emit({
    's': 'launch',
    'words': countWords(content),
    'chars': content.length,
    'editor': windowed ? 'windowed' : 'single',
    'marks_ms': marks,
    'focus_ms': tFocused - tFocus,
    'firstKeyHandler_ms': h / 1000.0,
    'firstKeyAccepted': accepted,
    'rss_mb': (await _rss()) / 1048576,
  });
  _doc.text = content;
}

Future<void> _typingScenarios() async {
  final doc = _doc;
  final text = doc.text;
  int snap(int o) {
    o = o.clamp(0, text.length);
    final sp = text.indexOf(' ', o);
    return sp < 0 ? text.length : sp;
  }

  final spots = {'start': snap(250), 'middle': snap(text.length ~/ 2), 'end': text.length};
  final win = _isWindowed;
  for (final e in spots.entries) {
    doc.selection = TextSelection.collapsed(offset: e.value);
    await _settle(600);
    await _ensureFocus();
    final r = await _typePaced(60);
    _emit({'s': 'typing', 'where': e.key, 'editor': win ? 'windowed' : 'single', ...r});
  }
  for (final cps in [10, 25]) {
    final at = _doc.text.indexOf(' ', _doc.text.length ~/ 2);
    doc.selection = TextSelection.collapsed(offset: at);
    await _settle(600);
    await _ensureFocus();
    final r = await _typeRate(cps == 10 ? 100 : 150, cps, at);
    _emit({'s': 'typingRate', 'where': 'middle', 'editor': win ? 'windowed' : 'single', ...r});
  }
}

void _sendKey(LogicalKeyboardKey l, PhysicalKeyboardKey p) {
  final km = ServicesBinding.instance.keyEventManager;
  km.handleKeyData(ui.KeyData(
      timeStamp: Duration.zero, type: ui.KeyEventType.down, physical: p.usbHidUsage, logical: l.keyId, character: null, synthesized: false));
  km.handleKeyData(ui.KeyData(
      timeStamp: Duration.zero, type: ui.KeyEventType.up, physical: p.usbHidUsage, logical: l.keyId, character: null, synthesized: false));
}

Future<void> _scrollScenarios() async {
  final win = _isWindowed;
  final doc = _doc;
  doc.selection = const TextSelection.collapsed(offset: 0);
  await _settle(500);
  final pos = _mainScroll();
  if (pos == null) {
    _emit({'s': 'scroll', 'error': 'no scrollable'});
    return;
  }
  final out = <String, Object?>{'s': 'scroll', 'editor': win ? 'windowed' : 'single', 'maxExtent': pos.maxScrollExtent};
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final center = Offset(view.physicalSize.width / view.devicePixelRatio / 2, view.physicalSize.height / view.devicePixelRatio / 2);
  GestureBinding.instance.handlePointerEvent(PointerAddedEvent(position: center, kind: PointerDeviceKind.mouse, device: 77));
  await _frame();
  final resp = <double>[];
  bool firstMoved = false;
  _frames.clear();
  final beat = _Beat()..start();
  for (int i = 0; i < 30; i++) {
    final before = _mainScroll()!.pixels;
    final t0 = _now();
    GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(position: center, device: 77, kind: PointerDeviceKind.mouse, scrollDelta: const Offset(0, 240)));
    final moved = _mainScroll()!.pixels != before;
    await _frame();
    final f = _frames.where((f) => f.buildStart >= t0 - 500).firstOrNull;
    resp.add(((f?.rasterFinish ?? _now()) - t0) / 1000.0);
    if (i == 0) firstMoved = moved;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  out['wheel_resp_ms'] = _stats(resp);
  out['wheel_first_resp_ms'] = resp.first;
  out['wheel_firstMoved'] = firstMoved;
  out['wheel_maxBlock_ms'] = beat.stop();
  final max = _mainScroll()!.maxScrollExtent;
  _frames.clear();
  var t0 = _now();
  _mainScroll()!.jumpTo(max * 0.9);
  await _frame();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final farF = _frames.where((f) => f.buildStart >= t0 - 500).firstOrNull;
  out['farJump_ms'] = ((farF?.rasterFinish ?? _now()) - t0) / 1000.0;
  out['farJump_frameBuild_ms'] = (farF?.buildUs ?? 0) / 1000.0;
  _mainScroll()!.jumpTo(0);
  await _settle(400);
  _frames.clear();
  final beat2 = _Beat()..start();
  final dragMs = <double>[];
  for (int i = 0; i <= 40; i++) {
    final frac = i <= 20 ? i / 20 * 0.9 : (0.9 - (i - 20) / 20 * 0.8);
    final t = _now();
    _mainScroll()!.jumpTo(max * frac);
    await _frame();
    dragMs.add((_now() - t) / 1000.0);
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  out['drag_step_ms'] = _stats(dragMs);
  out['drag_frame_total_ms'] = _stats(_frames.map((f) => f.totalUs / 1000.0));
  out['drag_maxBlock_ms'] = beat2.stop();
  _mainScroll()!.jumpTo(0);
  doc.selection = const TextSelection.collapsed(offset: 0);
  await _settle(500);
  await _ensureFocus();
  final pg = <double>[];
  int moved = 0;
  _frames.clear();
  for (int i = 0; i < 20; i++) {
    final before = _mainScroll()!.pixels;
    final selBefore = doc.selection.extentOffset;
    final t0k = _now();
    _sendKey(LogicalKeyboardKey.pageDown, PhysicalKeyboardKey.pageDown);
    await _frame();
    await _frame();
    final f = _frames.where((f) => f.buildStart >= t0k - 500).firstOrNull;
    pg.add(((f?.rasterFinish ?? _now()) - t0k) / 1000.0);
    if (_mainScroll()!.pixels != before || doc.selection.extentOffset != selBefore) moved++;
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  out['pgdn_resp_ms'] = _stats(pg);
  out['pgdn_moved_of_20'] = moved;
  _emit(out);
}

String _editorTextNow() => _p<EditorProvider>().content;

Future<void> _featureScenarios() async {
  final win = _isWindowed;
  final doc = _doc;
  final text = doc.text;
  final out = <String, Object?>{'s': 'features', 'editor': win ? 'windowed' : 'single'};
  final search = _p<SearchProvider>();
  final shortcuts = _p<ShortcutsProvider>();
  final settings = _p<SettingsProvider>();

  doc.selection = const TextSelection.collapsed(offset: 0);
  _mainScroll()?.jumpTo(0);
  await _settle(500);
  _editorFocus()?.unfocus();
  await _settle(200);
  String phrase = '';
  for (int o = (text.length * .9).toInt(); o < text.length - 60; o += 50) {
    final sp = text.indexOf(' ', o);
    if (sp < 0 || sp + 25 > text.length) break;
    final cand = text.substring(sp + 1, sp + 25);
    if (!cand.contains('\n') && text.indexOf(cand) == text.lastIndexOf(cand)) {
      phrase = cand;
      break;
    }
  }
  out['find_target_off'] = phrase.isEmpty ? -1 : text.indexOf(phrase);
  if (phrase.isNotEmpty) {
    search.toggleSearch(isOpen: true);
    await _settle(200);
    _frames.clear();
    final beat = _Beat()..start();
    final sw = Stopwatch()..start();
    final t0 = _now();
    search.setQuery(phrase);
    search.updateMatchOffsets(_editorTextNow());
    out['find_sync_ms'] = sw.elapsedMicroseconds / 1000.0;
    await _frame();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final p = _mainScroll();
    out['find_scrolled'] = (p?.pixels ?? 0) > 100;
    out['find_scrollPx'] = p?.pixels ?? 0;
    out['find_maxBlock_ms'] = beat.stop();
    out['find_frameTotal_ms'] = _stats(_frames.map((f) => f.totalUs / 1000.0));
    final first = _frames.where((f) => f.buildStart >= t0 - 500).firstOrNull;
    out['find_firstFrame_ms'] = ((first?.rasterFinish ?? t0) - t0) / 1000.0;
    final sw2 = Stopwatch()..start();
    search.updateMatchOffsets(text);
    out['find_updateMatchOffsets_ms'] = sw2.elapsedMicroseconds / 1000.0;
    search.setQuery('');
    search.toggleSearch(isOpen: false);
    await _settle(200);
  }

  doc.selection = const TextSelection.collapsed(offset: 0);
  _mainScroll()?.jumpTo(0);
  await _settle(500);
  _frames.clear();
  var t = _now();
  shortcuts.toggleLeftSidebar();
  await _frame();
  await Future<void>.delayed(const Duration(milliseconds: 600));
  out['tocOpen_firstFrame_ms'] = ((_frames.firstOrNull?.rasterFinish ?? t) - t) / 1000.0;
  out['tocOpen_frameTotal_ms'] = _stats(_frames.map((f) => f.totalUs / 1000.0));
  final nav = _findEl((e) => e.widget.runtimeType.toString() == 'EditorNavigationSidebar');
  final headers = parseTocHeaders(text);
  out['toc_headers'] = headers.length;
  if (nav != null && headers.isNotEmpty) {
    final w = nav.widget as dynamic;
    final h = headers[(headers.length * .85).toInt()];
    _frames.clear();
    final beat = _Beat()..start();
    t = _now();
    final sw = Stopwatch()..start();
    w.onHeaderTap(h.line);
    out['toc_sync_ms'] = sw.elapsedMicroseconds / 1000.0;
    await _frame();
    final fr = _frames.where((f) => f.buildStart >= t - 500).firstOrNull;
    out['toc_firstFrame_ms'] = ((fr?.rasterFinish ?? _now()) - t) / 1000.0;
    double last = -1;
    int settleT = _now();
    for (int i = 0; i < 80; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final px = _mainScroll()?.pixels ?? 0;
      if ((px - last).abs() < 0.5 && px > 100) break;
      last = px;
      settleT = _now();
    }
    out['toc_settled_ms'] = (settleT - t) / 1000.0;
    out['toc_scrollPx'] = _mainScroll()?.pixels ?? 0;
    out['toc_maxBlock_ms'] = beat.stop();
    out['toc_frameTotal_ms'] = _stats(_frames.map((f) => f.totalUs / 1000.0));
  } else {
    out['toc_error'] = 'no nav or headers';
  }
  shortcuts.toggleLeftSidebar();
  await _settle(500);

  t = _now();
  _frames.clear();
  final beatC = _Beat()..start();
  shortcuts.toggleRightSidebar();
  await _frame();
  await Future<void>.delayed(const Duration(milliseconds: 600));
  out['codexOpen_firstFrame_ms'] = ((_frames.firstOrNull?.rasterFinish ?? t) - t) / 1000.0;
  out['codexOpen_frameTotal_ms'] = _stats(_frames.map((f) => f.totalUs / 1000.0));
  out['codexOpen_maxBlock_ms'] = beatC.stop();
  shortcuts.toggleRightSidebar();
  await _settle(500);

  settings.toggleTypewriter(true);
  await _settle(300);
  final sp = doc.text.indexOf(' ', doc.text.length ~/ 2);
  doc.selection = TextSelection.collapsed(offset: sp);
  await _settle(800);
  await _ensureFocus();
  final tw = await _typePaced(40);
  out['typewriter_e2e_ms'] = tw['e2e_ms'];
  out['typewriter_handler_ms'] = tw['handler_ms'];
  out['typewriter_raster_ms'] = tw['raster_ms'];
  out['typewriter_build_ms'] = tw['build_ms'];
  settings.toggleTypewriter(false);
  await _settle(300);
  _emit(out);
}

Future<void> _microScenario() async {
  final text = _doc.text;
  final out = <String, Object?>{'s': 'micro', 'chars': text.length};
  double time(void Function() f, [int reps = 5]) {
    f();
    final sw = Stopwatch()..start();
    for (int i = 0; i < reps; i++) {
      f();
    }
    return sw.elapsedMicroseconds / reps / 1000.0;
  }

  out['countWords_ms'] = time(() => countWords(text));
  out['parseTocHeaders_ms'] = time(() => parseTocHeaders(text));
  out['split_nl_ms'] = time(() => text.split('\n'));
  final copy = String.fromCharCodes(text.codeUnits);
  out['string_equals_ms'] = time(() => text == copy);
  out['replaceRange_ms'] = time(() => text.replaceRange(text.length ~/ 2, text.length ~/ 2, 'x'));
  _emit(out);
}

Future<void> _idleScenarios() async {
  final win = _isWindowed;
  await _settle(1500);
  final rss0 = await _rss();
  _frames.clear();
  final c0 = _cpuSecs();
  final w0 = Stopwatch()..start();
  await Future<void>.delayed(Duration(seconds: _idleSecs));
  final cpuVisible = (_cpuSecs() - c0) / (w0.elapsedMilliseconds / 1000.0) * 100;
  final framesVisible = _frames.length;
  _emit({
    's': 'idle',
    'state': 'visible',
    'editor': win ? 'windowed' : 'single',
    'cpu_pct': cpuVisible,
    'frames': framesVisible,
    'rss_mb': (await _rss()) / 1048576,
    'rss_start_mb': rss0 / 1048576,
    'secs': _idleSecs
  });
  await windowManager.hide();
  await Future<void>.delayed(const Duration(seconds: 3));
  _frames.clear();
  final c1 = _cpuSecs();
  final w1 = Stopwatch()..start();
  await Future<void>.delayed(Duration(seconds: _idleSecs));
  final cpuHidden = (_cpuSecs() - c1) / (w1.elapsedMilliseconds / 1000.0) * 100;
  _emit({
    's': 'idle',
    'state': 'hidden',
    'editor': win ? 'windowed' : 'single',
    'cpu_pct': cpuHidden,
    'frames': _frames.length,
    'rss_mb': (await _rss()) / 1048576,
    'secs': _idleSecs
  });
  await windowManager.show();
  await _settle(500);
}

Future<void> _projectScenarios(List<String> names) async {
  final settings = _p<SettingsProvider>();
  final editor = _p<EditorProvider>();
  final notes = _p<NotesProvider>();
  final history = _p<HistoryProvider>();
  final sync = _p<SyncProvider>();

  Future<Map<String, Object?>> switchTo(String name) async {
    final beat = _Beat()..start();
    _frames.clear();
    final t0 = _now();
    await history.saveStatsNow();
    final tA = _now();
    await editor.flushSync(syncProvider: sync, projectName: settings.currentProjectName);
    final tB = _now();
    await settings.setCurrentProject(name);
    final path = settings.currentProjectPath;
    await editor.loadProject(path);
    final tC = _now();
    await notes.loadProject(path, projectName: name);
    await history.loadProjectStats(path);
    await settings.refreshProjects();
    final tD = _now();
    final content = editor.content;
    await _waitDocVisible(content);
    final t1 = _now();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return {
      'total_ms': (t1 - t0) / 1000.0,
      'saveStats_ms': (tA - t0) / 1000.0,
      'flushSync_ms': (tB - tA) / 1000.0,
      'loadProject_ms': (tC - tB) / 1000.0,
      'notes_stats_refresh_ms': (tD - tC) / 1000.0,
      'toVisible_ms': (t1 - tD) / 1000.0,
      'maxBlock_ms': beat.stop(),
      'chars': content.length,
      'editor': _isWindowed ? 'windowed' : 'single',
    };
  }

  final cur = settings.currentProjectName!;
  for (final n in names) {
    for (int i = 0; i < 3; i++) {
      final r = await switchTo(n);
      _emit({'s': 'projectSwitch', 'to': n, 'rep': i, ...r});
      await switchTo(cur);
    }
  }
  for (int i = 0; i < 3; i++) {
    final name = 'NewProj${DateTime.now().millisecondsSinceEpoch % 100000}_$i';
    final beat = _Beat()..start();
    final t0 = _now();
    await history.saveStatsNow();
    final tA = _now();
    editor.flushSyncInBackground(syncProvider: sync, projectName: settings.currentProjectName);
    final tB = _now();
    final ok = await settings.createProject(name);
    final tC = _now();
    final path = settings.currentProjectPath;
    await editor.loadProject(path);
    await notes.loadProject(path, projectName: name);
    await history.loadProjectStats(path);
    final tD = _now();
    await _waitDocVisible(editor.content);
    final t1 = _now();
    _emit({
      's': 'newProject',
      'rep': i,
      'ok': ok,
      'total_ms': (t1 - t0) / 1000.0,
      'saveStats_ms': (tA - t0) / 1000.0,
      'flushBg_ms': (tB - tA) / 1000.0,
      'create_ms': (tC - tB) / 1000.0,
      'load_ms': (tD - tC) / 1000.0,
      'toVisible_ms': (t1 - tD) / 1000.0,
      'maxBlock_ms': beat.stop(),
    });
    await switchTo(cur);
  }
}

Future<void> _pasteScenario(String fullText) async {
  final settings = _p<SettingsProvider>();
  final editor = _p<EditorProvider>();
  final notes = _p<NotesProvider>();
  final history = _p<HistoryProvider>();
  await settings.setCurrentProject('Empty');
  final path = settings.currentProjectPath;
  await editor.loadProject(path);
  await notes.loadProject(path, projectName: 'Empty');
  await history.loadProjectStats(path);
  await _waitDocVisible(editor.content);
  await _settle(500);
  await _ensureFocus();
  await Clipboard.setData(ClipboardData(text: fullText));
  await _settle(200);
  final beat = _Beat()..start();
  _frames.clear();
  final t0 = _now();
  final ctx = _editorFocus()!.context!;
  Actions.maybeInvoke(ctx, const PasteTextIntent(SelectionChangedCause.keyboard));
  int tText = -1;
  for (int i = 0; i < 5000; i++) {
    if (_doc.text.length >= fullText.length * 0.99) {
      tText = _now();
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  await _frame();
  final tFrame = _now();
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final blocked = beat.stop();
  final fr = _frames.where((f) => f.buildStart >= t0 - 500).toList();
  _emit({
    's': 'paste',
    'editor': _isWindowed ? 'windowed' : 'single',
    'chars': fullText.length,
    'pasted': _doc.text.length,
    'textArrived_ms': tText < 0 ? -1 : (tText - t0) / 1000.0,
    'toFrameEnd_ms': (tFrame - t0) / 1000.0,
    'firstRasterFinish_ms': fr.isEmpty ? -1 : (fr.first.rasterFinish - t0) / 1000.0,
    'maxBlock_ms': blocked,
    'frameTotal_ms': _stats(fr.map((f) => f.totalUs / 1000.0)),
    'frames': fr.length,
  });
}

// ---------------------------------------------------------------- main

Future<void> main() async {
  _PerfBinding.ensureInitialized();
  final tMain = _since();
  _installTimings();
  final marks = <String, int>{'main': tMain};

  final editorProvider = EditorProvider();
  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  final syncProvider = SyncProvider();
  final historyProvider = HistoryProvider(syncProvider: syncProvider);
  final notesProvider = NotesProvider();
  final searchProvider = SearchProvider();
  final sprintController = SprintController();
  editorProvider.isMirrorProjectPath = (projectPath) => settingsProvider.isMirroredProject(projectPath.split('/').last);

  await themeProvider.loadSettings();
  await editorProvider.loadSettings();
  await settingsProvider.loadSettings();

  if (_mode == 'prep') {
    final master = _env['PERF_MASTER']!;
    if (settingsProvider.masterDirectoryPath != master) {
      await settingsProvider.setMasterDirectory(master);
    }
    await settingsProvider.refreshProjects();
    await settingsProvider.setCurrentProject(_env['PERF_PROJECT']);
    _emit({
      's': 'prep',
      'master': settingsProvider.masterDirectoryPath,
      'current': settingsProvider.currentProjectName,
      'projects': settingsProvider.availableProjects.length
    });
    exit(0);
  }

  await editorProvider.loadProject(settingsProvider.currentProjectPath);
  await notesProvider.loadProject(settingsProvider.currentProjectPath);
  await historyProvider.loadProjectStats(settingsProvider.currentProjectPath);
  marks['providersLoaded'] = _since();

  await windowManager.ensureInitialized();
  const WindowOptions windowOptions = WindowOptions(
    size: Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: editorProvider),
        ChangeNotifierProvider.value(value: notesProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: historyProvider),
        ChangeNotifierProvider.value(value: syncProvider),
        ChangeNotifierProvider.value(value: searchProvider),
        ChangeNotifierProvider.value(value: sprintController),
        ChangeNotifierProvider(create: (_) => ShortcutsProvider()),
        ChangeNotifierProvider(create: (_) => PointerTypeNotifier()),
      ],
      child: const WriterApp(),
    ),
  );
  marks['runApp'] = _since();
  WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) => marks['firstFrameRasterized'] = _since());

  try {
    await _launchScenario(editorProvider, marks);
    final fullText = editorProvider.content;
    final names = settingsProvider.availableProjects
        .map((p) => p.name)
        .where((n) => n != settingsProvider.currentProjectName && n.startsWith('S_'))
        .toList()
      ..sort();
    if (_want('micro')) await _microScenario();
    if (_want('typing')) await _typingScenarios();
    if (_want('scroll')) await _scrollScenarios();
    if (_want('features')) await _featureScenarios();
    if (_want('idle')) await _idleScenarios();
    if (_want('project')) await _projectScenarios(names.take(3).toList());
    if (_want('paste')) await _pasteScenario(fullText);
  } catch (e, st) {
    _emit({'s': 'error', 'error': '$e', 'stack': '$st'.split('\n').take(8).join(' | ')});
  }
  _emit({'s': 'done'});
  exit(0);
}
