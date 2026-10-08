// Description: Lists must not cost the editor its speed (backlog item 23).
// Sits beside large_document_perf_test.dart: a 100k-word manuscript that is
// almost all list (bullets, nested bullets, numbers, checklists), timed for the
// span build, for a cached keystroke, and for the Enter/renumber edit rules.
// The bounds are generous (debug JIT, a loaded machine): they catch a return
// to quadratic behaviour, not a few milliseconds.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/list_editing.dart';
import 'package:pellucid/features/editor/marker_edit_rules.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

String listHeavyManuscript(int words) {
  final rnd = Random(11);
  const w = ['harbour', 'lantern', 'tide', 'quietly', 'swung', 'Mira', 'café', 'naïve', 'door', 'rain'];
  String line() => List.generate(8, (_) => w[rnd.nextInt(w.length)]).join(' ');
  final b = StringBuffer();
  int written = 0;
  while (written < words) {
    b.writeln('## ${line()}');
    written += 8;
    for (int i = 1; i <= 12; i++) {
      b.writeln('$i. ${line()}');
      b.writeln('    - ${line()} **bold**');
      b.writeln('        $i. ${line()}');
      b.writeln('- [${i.isEven ? 'x' : ' '}] ${line()}');
      written += 32;
    }
    b.writeln();
    b.writeln('- ${line()}');
    written += 8;
  }
  return b.toString();
}

void main() {
  testWidgets('100k-word list-heavy manuscript: span build and cached keystroke', (tester) async {
    final text = listHeavyManuscript(100000);
    final c = MarkdownEditingController(text: text, theme: WriterTheme.presets[0]);
    late BuildContext ctx;
    await tester.pumpWidget(Builder(builder: (context) {
      ctx = context;
      return const SizedBox();
    }));
    final sw = Stopwatch()..start();
    c.buildTextSpan(context: ctx, style: const TextStyle(), withComposing: false);
    final cold = sw.elapsedMilliseconds;
    // A keystroke in the middle of a list item: only that line misses the cache.
    final at = text.length ~/ 2;
    c.value = TextEditingValue(
        text: text.replaceRange(at, at, 'x'), selection: TextSelection.collapsed(offset: at + 1));
    sw
      ..reset()
      ..start();
    final span = c.buildTextSpan(context: ctx, style: const TextStyle(), withComposing: false);
    final warm = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('LISTBENCH chars=${text.length} cold=${cold}ms keystroke(cached)=${warm}ms');
    expect(span.toPlainText().length, c.text.length, reason: 'drawn text keeps the document length');
    expect(cold, lessThan(3000));
    expect(warm, lessThan(1500));
  });

  test('Enter in a 900-item numbered list renumbers the block in bounded time', () {
    final lines = [for (int i = 1; i <= 900; i++) '$i. item number $i'];
    final text = lines.join('\n');
    // Enter at the end of item 10 (so ~900 items below must shift by one).
    final p = text.indexOf('\n11. ');
    final from = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: p));
    final next = TextEditingValue(
        text: text.replaceRange(p, p, '\n'), selection: TextSelection.collapsed(offset: p + 1));
    final sw = Stopwatch()..start();
    final out = applyMarkerEditRules(from, next);
    final ms = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('RENUMBER 900 items: ${ms}ms');
    final outLines = out.text.split('\n');
    expect(outLines[10], '11. ');
    expect(outLines[11], '12. item number 11');
    expect(outLines.last, '901. item number 900');
    expect(ms, lessThan(1500));
  });

  test('typing inside an item of a long numbered list does not renumber or scan the list', () {
    final text = [for (int i = 1; i <= 900; i++) '$i. item number $i'].join('\n');
    final p = text.indexOf('\n500. ') + 12;
    final from = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: p));
    final next = TextEditingValue(
        text: text.replaceRange(p, p, 'a'), selection: TextSelection.collapsed(offset: p + 1));
    final sw = Stopwatch()..start();
    for (int i = 0; i < 20; i++) {
      applyMarkerEditRules(from, next);
    }
    final per = sw.elapsedMilliseconds / 20;
    // ignore: avoid_print
    print('KEYSTROKE in 900-item list: ${per.toStringAsFixed(1)}ms');
    expect(per, lessThan(150));
    expect(applyMarkerEditRules(from, next).text, next.text);
    expect(listAutoContinueEnabled, isTrue);
  });
}
