import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import '../large_document_fixture.dart';

Future<WindowedEditorState> _pump(WidgetTester tester, MarkdownEditingController doc) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  return key.currentState!;
}

Future<void> _ticks(WidgetTester tester, int n) async {
  for (int i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('a mouse drag on static lines held at the bottom edge scrolls and keeps selecting', (tester) async {
    final text = generateManuscript(20000, seed: 31);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    s.scroll.jumpTo(-1600); // static lines above the window fill the view
    await tester.pump();
    final from = tester.getTopLeft(find.byType(RichText).at(2)) + const Offset(4, 4);
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveTo(from + const Offset(20, 0));
    await tester.pump();
    final anchor = doc.selection.baseOffset;
    final double start = s.scroll.offset;
    await g.moveTo(const Offset(500, 1395)); // inside the bottom edge zone
    await _ticks(tester, 30);
    expect(s.scroll.offset, greaterThan(start + 100), reason: 'the page scrolls by itself');
    expect(doc.selection.baseOffset, anchor, reason: 'the anchor stays where the drag began');
    final int extentAfterScroll = doc.selection.extentOffset;
    expect(extentAfterScroll, greaterThan(anchor));
    await _ticks(tester, 20);
    expect(doc.selection.extentOffset, greaterThan(extentAfterScroll), reason: 'the selection follows the scroll');
    await g.moveTo(const Offset(500, 700)); // back in the middle: scrolling stops
    await tester.pump();
    final double stopped = s.scroll.offset;
    await _ticks(tester, 10);
    expect(s.scroll.offset, stopped);
    await g.up();
    await tester.pump();
  });

  testWidgets('auto-scroll speed grows with the distance past the edge', (tester) async {
    final text = generateManuscript(20000, seed: 32);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = const TextSelection.collapsed(offset: 0);
    final s = await _pump(tester, doc);
    Future<double> run(Offset at) async {
      doc.selection = const TextSelection.collapsed(offset: 0); // window at the top
      await tester.pump();
      await tester.pump();
      s.scroll.jumpTo(s.scroll.position.maxScrollExtent / 2); // static lines only
      await tester.pump();
      const from = Offset(500, 600);
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await g.moveTo(from + const Offset(20, 0));
      await g.moveTo(at);
      final double before = s.scroll.offset;
      await _ticks(tester, 10);
      final double moved = s.scroll.offset - before;
      await g.up();
      await tester.pump();
      return moved;
    }

    final slow = await run(const Offset(500, 1400 - 40));
    final fast = await run(const Offset(500, 1400 + 60));
    expect(slow, greaterThan(0));
    expect(fast, greaterThan(slow * 2));
  });

  testWidgets('a drag that starts in the live field selects past the window while scrolling', (tester) async {
    final text = generateManuscript(20000, seed: 33);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
    final s = await _pump(tester, doc);
    final field = find.byType(TextField);
    final from = tester.getTopLeft(field) + const Offset(30, 10);
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveTo(from + const Offset(40, 0));
    await tester.pump();
    final int anchor = doc.selection.baseOffset;
    await g.moveTo(const Offset(500, 1400 + 60)); // past the edge: full speed
    await _ticks(tester, 90);
    final int windowEnd = s.window.windowStart + s.window.text.length;
    expect(doc.selection.baseOffset, anchor);
    expect(doc.selection.extentOffset, greaterThan(windowEnd), reason: 'the selection reaches static lines below');
    await g.up();
    await tester.pump();
    await tester.pump();
    expect(doc.selection.baseOffset, anchor, reason: 'releasing keeps the selection');
  });
}
