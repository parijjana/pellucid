// Typing cost in a 100k-word manuscript: windowed editor vs the single
// EditableText (backlog item 23). flutter_test numbers are debug JIT with test
// fonts, so the bound is generous; the profile figures come from
// tool/perf/windowed_editor_perf_main.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import '../large_document_fixture.dart';

int _p50(List<int> l) => (l..sort())[l.length ~/ 2];

void main() {
  testWidgets('keystroke at 100k words stays flat in the windowed editor', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const style = TextStyle(fontSize: 16, height: 1.8, color: Colors.black);
    final text = generateManuscript(100000, markupEvery: 400);
    final results = <String, int>{};
    for (final windowed in [true, false]) {
      final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
        ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
      final key = GlobalKey<WindowedEditorState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: windowed
              ? WindowedEditor(
                  key: key,
                  controller: doc,
                  focusNode: FocusNode(),
                  theme: doc.theme,
                  style: style,
                  pageWidth: 800,
                  horizontalPosition: 0.5,
                  cursorColor: Colors.black,
                  onChanged: (_) {},
                )
              : SingleChildScrollView(child: TextField(controller: doc, maxLines: null, style: style)),
        ),
      ));
      await tester.pump();
      final times = <int>[];
      for (int i = 0; i < 20; i++) {
        final sw = Stopwatch()..start();
        if (windowed) {
          final w = key.currentState!.window;
          final at = w.selection.extentOffset;
          w.value = TextEditingValue(
              text: w.text.replaceRange(at, at, 'x'), selection: TextSelection.collapsed(offset: at + 1));
        } else {
          final at = doc.selection.extentOffset;
          doc.value = TextEditingValue(
              text: doc.text.replaceRange(at, at, 'x'), selection: TextSelection.collapsed(offset: at + 1));
        }
        await tester.pump();
        times.add(sw.elapsedMicroseconds);
      }
      results[windowed ? 'windowed' : 'single'] = _p50(times);
    }
    // ignore: avoid_print
    print('EVID|test|keystroke 100k words p50: windowed=${results['windowed']! ~/ 1000}ms '
        'single=${results['single']! ~/ 1000}ms');
    expect(results['windowed']!, lessThan(results['single']! ~/ 5));
    expect(results['windowed']!, lessThan(80000), reason: 'debug-mode bound, survives a loaded machine');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
