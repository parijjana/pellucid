// Slice 3c: a touch long press on a static line (far from the caret) takes
// one press, not one to move the window and a second for the field.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import '../large_document_fixture.dart';

Future<(WindowedEditorState, FocusNode)> _pump(WidgetTester tester, MarkdownEditingController doc) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<WindowedEditorState>();
  final focus = FocusNode();
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WindowedEditor(
          key: key,
          controller: doc,
          focusNode: focus,
          theme: doc.theme,
          style: const TextStyle(fontSize: 16, height: 1.8, color: Colors.black),
          pageWidth: 800,
          horizontalPosition: 0.5,
          cursorColor: Colors.black,
          onChanged: (_) {},
          contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
        ),
      ),
    ),
  );
  await tester.pump();
  return (key.currentState!, focus);
}

/// The document line of the static line under [at].
int _lineAt(WidgetTester tester, Offset at) {
  final lines = find.byWidgetPredicate((w) => w is MouseRegion && w.key is ValueKey<String>);
  for (final e in lines.evaluate()) {
    final key = (e.widget.key! as ValueKey<String>).value;
    if (tester.getRect(find.byWidget(e.widget)).contains(at)) return int.parse(key.substring(1));
  }
  throw StateError('no static line at $at');
}

void main() {
  Future<(MarkdownEditingController, WindowedEditorState, FocusNode, int, Offset)> farFromCaret(
    WidgetTester tester,
  ) async {
    final text = generateManuscript(20000, seed: 41);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = const TextSelection.collapsed(offset: 0);
    final (s, focus) = await _pump(tester, doc);
    s.scroll.jumpTo(s.scroll.position.maxScrollExtent / 2);
    await tester.pump();
    expect(find.byType(TextField).hitTestable(), findsNothing, reason: 'only static lines in view');
    // A line with text under the point.
    Offset at = const Offset(500, 600);
    int line = _lineAt(tester, at);
    while (text.split('\n')[line].trim().isEmpty) {
      at += const Offset(0, 30);
      line = _lineAt(tester, at);
    }
    return (doc, s, focus, line, at);
  }

  int lineStart(String text, int line) {
    int at = 0;
    for (int i = 0; i < line; i++) {
      at = text.indexOf('\n', at) + 1;
    }
    return at;
  }

  testWidgets('iOS: one long press far from the caret places it there, with magnifier then toolbar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final (doc, s, focus, line, at) = await farFromCaret(tester);
      final g = await tester.startGesture(at, kind: PointerDeviceKind.touch);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      final ls = lineStart(doc.text, line), le = doc.text.indexOf('\n', ls);
      expect(doc.selection.isCollapsed, isTrue);
      expect(doc.selection.baseOffset, inInclusiveRange(ls, le), reason: 'the caret is on the pressed line');
      expect(focus.hasFocus, isTrue);
      expect(s.window.windowStart, lessThanOrEqualTo(ls));
      expect(s.window.windowStart + s.window.text.length, greaterThanOrEqualTo(le), reason: 'the window moved there');
      final editable = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editable.selectionOverlay?.magnifierIsVisible, isTrue, reason: 'magnifier while held');
      // Sliding keeps moving the caret.
      final int before = doc.selection.baseOffset;
      await g.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(doc.selection.baseOffset, lessThan(before));
      await g.up();
      await tester.pumpAndSettle();
      expect(editable.selectionOverlay?.magnifierIsVisible, isFalse);
      expect(editable.selectionOverlay?.toolbarIsVisible, isTrue, reason: 'one press: the toolbar is up');
      expect(doc.selection.isCollapsed, isTrue, reason: 'release is not a second tap');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android: one long press far from the caret selects the word with handles', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final (doc, _, focus, line, at) = await farFromCaret(tester);
      final g = await tester.startGesture(at, kind: PointerDeviceKind.touch);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      final ls = lineStart(doc.text, line), le = doc.text.indexOf('\n', ls);
      expect(doc.selection.isCollapsed, isFalse, reason: 'a word');
      expect(doc.selection.start, greaterThanOrEqualTo(ls));
      expect(doc.selection.end, lessThanOrEqualTo(le));
      expect(focus.hasFocus, isTrue);
      final editable = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editable.selectionOverlay?.handlesAreVisible, isTrue);
      await g.up();
      await tester.pumpAndSettle();
      expect(editable.selectionOverlay?.toolbarIsVisible, isTrue);
      expect(doc.selection.isCollapsed, isFalse, reason: 'release keeps the word');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a short touch on a static line is still a tap, and a finger drag still scrolls', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final (doc, s, _, line, at) = await farFromCaret(tester);
      final double offset = s.scroll.offset;
      final g = await tester.startGesture(at, kind: PointerDeviceKind.touch);
      for (int i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(s.scroll.offset, greaterThan(offset + 100));
      expect(doc.selection.baseOffset, 0, reason: 'scrolling moves no caret');
      final int l2 = _lineAt(tester, at);
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      final ls = lineStart(doc.text, l2);
      expect(doc.selection.baseOffset, inInclusiveRange(ls, doc.text.indexOf('\n', ls)));
      expect(line, isNonNegative);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
