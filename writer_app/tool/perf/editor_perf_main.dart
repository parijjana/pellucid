// Editor typing benchmark (backlog item 23). Not part of the app.
//
//   flutter run --profile -d macos -t tool/perf/editor_perf_main.dart \
//     --dart-define=WORDS=100000 --dart-define=MARKUP_EVERY=400
//
// Loads a generated manuscript into MarkdownEditingController inside an
// EditableText styled like the real editor, types 30 characters in the
// middle, and prints build/raster times per frame, then exits.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import '../../test/features/editor/large_document_fixture.dart';

const int _words = int.fromEnvironment('WORDS', defaultValue: 100000);
const int _markupEvery = int.fromEnvironment('MARKUP_EVERY', defaultValue: 400);
const bool _plain = bool.fromEnvironment('PLAIN');

void main() => runApp(const _PerfApp());

class _PerfApp extends StatefulWidget {
  const _PerfApp();
  @override
  State<_PerfApp> createState() => _PerfAppState();
}

class _PerfAppState extends State<_PerfApp> {
  late final TextEditingController _c;
  final _focus = FocusNode();
  final List<FrameTiming> _timings = [];
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    final text = generateManuscript(_words, markupEvery: _markupEvery);
    _c = _plain ? TextEditingController(text: text) : MarkdownEditingController(text: text, theme: WriterTheme.presets[0]);
    SchedulerBinding.instance.addTimingsCallback((t) {
      if (_recording) _timings.addAll(t);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    int at = _c.text.length ~/ 2;
    while ((_c.text.codeUnitAt(at) & 0xFC00) == 0xDC00) {
      at++;
    }
    _recording = true;
    final sw = Stopwatch()..start();
    for (int i = 0; i < 30; i++) {
      _c.value = TextEditingValue(
        text: _c.text.replaceRange(at + i, at + i, 'x'),
        selection: TextSelection.collapsed(offset: at + i + 1),
      );
      await SchedulerBinding.instance.endOfFrame;
    }
    final wall = sw.elapsedMilliseconds;
    await Future<void>.delayed(const Duration(seconds: 1));
    _recording = false;
    final build = _timings.map((t) => t.buildDuration.inMicroseconds).toList()..sort();
    final raster = _timings.map((t) => t.rasterDuration.inMicroseconds).toList()..sort();
    int p(List<int> l, double q) => l.isEmpty ? -1 : l[((l.length - 1) * q).round()] ~/ 1000;
    stdout.writeln('PERF words=$_words markupEvery=$_markupEvery plain=$_plain chars=${_c.text.length} '
        'frames=${_timings.length} perKeystrokeWall=${wall ~/ 30}ms '
        'build p50=${p(build, .5)}ms p90=${p(build, .9)}ms raster p50=${p(raster, .5)}ms p90=${p(raster, .9)}ms');
    exit(0);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 700,
                child: EditableText(
                  controller: _c,
                  focusNode: _focus,
                  maxLines: null,
                  style: const TextStyle(fontSize: 16, height: 1.8, fontFamily: 'Georgia', color: Colors.black),
                  cursorColor: Colors.black,
                  backgroundCursorColor: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      );
}
