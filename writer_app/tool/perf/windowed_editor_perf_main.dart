// Windowed editor typing benchmark (slice 3b, backlog item 23). Not part of the app.
//
//   flutter build macos --profile -t tool/perf/windowed_editor_perf_main.dart
//   build/macos/Build/Products/Profile/Pellucid.app/Contents/MacOS/Pellucid | grep EVID
//
// Runs each configuration in turn: today's single EditableText, then the
// windowed editor (alone, and with the editor screen's per-keystroke
// listeners: whole-document word count and TOC parse), at 100k and 500k words
// and on markup-heavy text. Prints one EVID| line per configuration with
// frame build/raster/total times, then exits.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/utils/toc_parser.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/editor/word_count.dart';

import '../../test/features/editor/large_document_fixture.dart';

class _Config {
  final String name;
  final bool windowed;
  final int words;
  final int markupEvery;
  final bool screenListeners;
  const _Config(this.name, {required this.windowed, this.words = 100000, this.markupEvery = 400, this.screenListeners = false});
}

const _configs = [
  _Config('single', windowed: false),
  _Config('windowed', windowed: true),
  _Config('windowed+screen', windowed: true, screenListeners: true),
  _Config('windowed', windowed: true, words: 500000),
  _Config('windowed markup-heavy', windowed: true, markupEvery: 40),
];

const _style = TextStyle(fontSize: 16, height: 1.8, fontFamily: 'Georgia', color: Colors.black);

void main() => runApp(const MaterialApp(home: Scaffold(body: _Runner())));

class _Runner extends StatefulWidget {
  const _Runner();
  @override
  State<_Runner> createState() => _RunnerState();
}

class _RunnerState extends State<_Runner> {
  _Config? _cfg;
  MarkdownEditingController? _doc;
  final _key = GlobalKey<WindowedEditorState>();
  final _focus = FocusNode();
  final List<FrameTiming> _timings = [];
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((t) {
      if (_recording) _timings.addAll(t);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _frame() => SchedulerBinding.instance.endOfFrame;

  Future<List<FrameTiming>> _record(Future<void> Function() body) async {
    _timings.clear();
    _recording = true;
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _recording = false;
    return List.of(_timings);
  }

  String _stats(String name, List<FrameTiming> t) {
    if (t.isEmpty) return '|$name n=0';
    List<int> us(Duration Function(FrameTiming) f) => t.map((x) => f(x).inMicroseconds).toList()..sort();
    final b = us((x) => x.buildDuration), r = us((x) => x.rasterDuration), tot = us((x) => x.totalSpan);
    String p(List<int> l, double q) => (l[((l.length - 1) * q).round()] / 1000).toStringAsFixed(1);
    return '|$name n=${t.length} build p50=${p(b, .5)} p90=${p(b, .9)} raster p50=${p(r, .5)} '
        'total p50=${p(tot, .5)} p90=${p(tot, .9)} max=${p(tot, 1)}ms';
  }

  void _type(int i) {
    final s = _key.currentState;
    final TextEditingController c = s?.window ?? _doc!;
    final at = c.selection.extentOffset;
    c.value = TextEditingValue(text: c.text.replaceRange(at, at, 'x'), selection: TextSelection.collapsed(offset: at + 1));
  }

  Future<void> _runAll() async {
    for (final cfg in _configs) {
      final text = generateManuscript(cfg.words, markupEvery: cfg.markupEvery);
      final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
        ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
      if (cfg.screenListeners) {
        // What editor_screen.dart does on every text change today.
        doc.addListener(() {
          countWords(doc.text);
          parseTocHeaders(doc.text);
        });
      }
      setState(() {
        _cfg = cfg;
        _doc = doc;
      });
      await _frame();
      await Future<void>.delayed(const Duration(seconds: 1));
      var line = 'EVID|profile|${cfg.name} words=${cfg.words} markupEvery=${cfg.markupEvery}|chars=${text.length}';
      line += _stats('key', await _record(() async {
        for (int k = 0; k < 30; k++) {
          _type(k);
          await _frame();
        }
      }));
      final s = _key.currentState;
      if (s != null) {
        line += _stats('jump', await _record(() async {
          for (int k = 0; k < 10; k++) {
            doc.selection = TextSelection.collapsed(offset: doc.text.length * (k + 1) ~/ 12);
            await _frame();
            await _frame();
          }
        }));
        line += _stats('scrollSmooth', await _record(() async {
          for (int k = 0; k < 120; k++) {
            s.scroll.jumpTo(s.scroll.offset + 30);
            await _frame();
          }
        }));
        line += _stats('scrollFar', await _record(() async {
          for (int k = 0; k < 20; k++) {
            s.scroll.jumpTo((k.isEven ? 1 : -1) * 4000.0 * (k + 1));
            await _frame();
          }
        }));
        line += '|windowMoves=${s.windowMoves}';
      }
      stdout.writeln(line);
      setState(() {
        _cfg = null;
        _doc = null;
      });
      await _frame();
    }
    stdout.writeln('EVID|done');
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg, doc = _doc;
    if (cfg == null || doc == null) return const SizedBox();
    if (!cfg.windowed) {
      return SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: 700,
            child: EditableText(
              controller: doc,
              focusNode: _focus,
              maxLines: null,
              style: _style,
              cursorColor: Colors.black,
              backgroundCursorColor: Colors.grey,
            ),
          ),
        ),
      );
    }
    return WindowedEditor(
      key: _key,
      controller: doc,
      focusNode: _focus,
      theme: doc.theme,
      style: _style,
      pageWidth: 820,
      horizontalPosition: 0.5,
      cursorColor: Colors.black,
      onChanged: (_) {},
    );
  }
}
