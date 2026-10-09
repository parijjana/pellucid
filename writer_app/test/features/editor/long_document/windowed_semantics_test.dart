// Slice 3c: screen readers reach the whole document, not only the live
// window: every static line is a semantics node with the text a reader sees
// and an Edit action that brings it into the field.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

import '../large_document_fixture.dart';

void main() {
  testWidgets('static lines are labelled without markers and Edit moves the caret there', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final text = generateManuscript(20000, seed: 52, markupEvery: 3);
    final doc = MarkdownEditingController(text: text, theme: WriterTheme.presets[0])
      ..selection = const TextSelection.collapsed(offset: 0);
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
          ),
        ),
      ),
    );
    await tester.pump();
    final s = key.currentState!;
    s.scroll.jumpTo(s.scroll.position.maxScrollExtent * 0.7);
    await tester.pump();
    expect(find.byType(TextField).hitTestable(), findsNothing, reason: 'far from the window');

    // Every built static line with text has a node labelled with its visible text.
    final lines = text.split('\n');
    final built = find
        .byWidgetPredicate((w) => w is MouseRegion && w.key is ValueKey<String>, skipOffstage: false)
        .evaluate()
        .map((e) => int.parse((e.widget.key! as ValueKey<String>).value.substring(1)))
        .where((l) => lines[l].trim().isNotEmpty)
        .toList();
    expect(built.length, greaterThanOrEqualTo(2));
    int? marked;
    for (final l in built) {
      final label = visibleText(lines[l]);
      expect(find.bySemanticsLabel(label, skipOffstage: false), findsWidgets, reason: 'line $l');
      if (label != lines[l] && marked == null) marked = l;
    }
    expect(marked, isNotNull, reason: 'the fixture has markup on screen');
    final node = tester.getSemantics(find.bySemanticsLabel(visibleText(lines[marked!])).first);
    expect(node.label, isNot(lines[marked]), reason: 'markers are not read out');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    // Lines below the screen are in the tree too (the cache extent), so the
    // reader can move on past the screen and the list scrolls.
    final view = tester.getRect(find.byType(CustomScrollView));
    expect(
      built.any((l) => tester.getRect(find.byKey(ValueKey('L$l'), skipOffstage: false)).top > view.bottom),
      isTrue,
      reason: 'a line past the bottom edge is in the tree',
    );

    // Edit (VoiceOver double tap) brings the line into the field, caret on it.
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(type: SemanticsAction.tap, nodeId: node.id, viewId: tester.view.viewId),
    );
    await tester.pump();
    await tester.pump();
    int ls = 0;
    for (int i = 0; i < marked; i++) {
      ls += lines[i].length + 1;
    }
    final le = ls + lines[marked].length;
    expect(focus.hasFocus, isTrue);
    expect(doc.selection.isCollapsed, isTrue);
    expect(doc.selection.baseOffset, inInclusiveRange(ls, le));
    expect(s.window.windowStart, lessThanOrEqualTo(ls));
    expect(s.window.windowStart + s.window.text.length, greaterThanOrEqualTo(le));
    await tester.pump(const Duration(milliseconds: 300));
    final re = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    final caret = re.localToGlobal(re.getLocalRectForCaret(re.selection!.extent).center);
    expect(caret.dy, inInclusiveRange(0, 1400), reason: 'the caret is on screen');

    // Typing there edits that line.
    await tester.enterText(
      find.byType(EditableText),
      '${s.window.text.substring(0, doc.selection.baseOffset - s.window.windowStart)}Z${s.window.text.substring(doc.selection.baseOffset - s.window.windowStart)}',
    );
    await tester.pump();
    expect(doc.text.substring(ls, le + 1), contains('Z'));
    handle.dispose();
  });
}
