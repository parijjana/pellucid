import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/long_document/line_heights.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import '../large_document_fixture.dart';

void main() {
  test('sums and offset searches agree with a linear scan, measured or estimated', () {
    final rnd = Random(3);
    final lengths = List.generate(500, (_) => rnd.nextInt(900));
    final real = List.generate(500, (_) => 29.0 * (1 + rnd.nextInt(8)));
    final h = LineHeights(measure: (i, _) => real[i], lengthOf: (i) => lengths[i], rowHeight: 29)
      ..reset(500)
      ..width = 680;
    h.ensure(100, 300); // half measured, half estimated
    double linear(int a, int b) {
      double t = 0;
      for (int i = a; i < b; i++) {
        t += h.heightOf(i);
      }
      return t;
    }

    for (int k = 0; k < 200; k++) {
      final a = rnd.nextInt(500), b = a + rnd.nextInt(500 - a + 1);
      expect(h.sum(a, b), closeTo(linear(a, b), 1e-6));
      final base = rnd.nextInt(500);
      final count = 500 - base;
      final off = rnd.nextDouble() * linear(base, 500);
      final i = h.indexBelow(base, count, off);
      expect(linear(base, base + i), lessThanOrEqualTo(off + 1e-6));
      expect(linear(base, base + i + 1), greaterThanOrEqualTo(off - 1e-6));
      final up = h.indexAbove(base, base, rnd.nextDouble() * linear(0, base));
      expect(up, inInclusiveRange(0, max(0, base - 1)));
    }
  });

  test('a styling change keeps the old heights as estimates until re-measured', () {
    double scale = 1;
    final h = LineHeights(measure: (i, _) => 58.0 * scale, lengthOf: (_) => 100, rowHeight: 29)
      ..reset(10)
      ..width = 600
      ..ensure(0, 10);
    final before = h.sum(0, 10);
    scale = 2;
    h.invalidateAll();
    expect(h.sum(0, 10), before, reason: 'nothing moves until lines are measured again');
    expect(h.isKnown(3), isFalse);
    h.ensure(3, 4);
    expect(h.heightOf(3), 116);
  });

  test('line changes shift heights with the lines', () {
    final h = LineHeights(measure: (i, _) => 10.0 + i, lengthOf: (_) => 5, rowHeight: 10)
      ..reset(6)
      ..width = 300
      ..ensure(0, 6);
    h.replaceLines(2, 1, 3); // line 2 split into three new lines
    expect(h.lineCount, 8);
    expect(h.heightOf(1), 11);
    expect(h.isKnown(2), isFalse);
    expect(h.heightOf(5), 13, reason: 'old line 3 is now line 5');
  });

  testWidgets('a far scroll lays out only the lines it shows, each at its true height', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final text = generateManuscript(100000, seed: 9, markupEvery: 60);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = const TextSelection.collapsed(offset: 10);
    final key = GlobalKey<WindowedEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WindowedEditor(
            key: key,
            controller: doc,
            focusNode: FocusNode(),
            theme: doc.theme,
            style: const TextStyle(fontSize: 16, height: 1.8, color: Colors.black),
            pageWidth: 800,
            horizontalPosition: 0.5,
            cursorColor: Colors.black,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    final s = key.currentState!;
    final measuredBefore = List.generate(s.heights.lineCount, s.heights.isKnown).where((k) => k).length;
    s.scroll.jumpTo(s.scroll.position.maxScrollExtent * 0.6);
    await tester.pump();
    final measured = List.generate(s.heights.lineCount, s.heights.isKnown).where((k) => k).length;
    expect(measured - measuredBefore, lessThan(120), reason: 'only the lines around the view are laid out');
    // Built static lines are contiguous and none is clipped or padded.
    final paragraphs = tester.renderObjectList<RenderParagraph>(find.byType(RichText)).where((p) => p.hasSize).toList()
      ..sort((a, b) => a.localToGlobal(Offset.zero).dy.compareTo(b.localToGlobal(Offset.zero).dy));
    expect(paragraphs.length, greaterThan(3));
    for (final p in paragraphs) {
      expect(p.size.height, closeTo(p.getMinIntrinsicHeight(p.size.width), 0.5));
    }
    for (int i = 1; i < paragraphs.length; i++) {
      final prevBottom = paragraphs[i - 1].localToGlobal(Offset(0, paragraphs[i - 1].size.height)).dy;
      expect(paragraphs[i].localToGlobal(Offset.zero).dy, closeTo(prevBottom, 0.5));
    }
  });
}
