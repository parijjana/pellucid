// Small helpers for the Mac editor suite: reading the rendered spans, driving the real Settings
// screen, and short documents (well under 15,000 words, so the normal single editor is used).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/settings/screens/settings_screen.dart';

import 'harness.dart';

/// The leaf TextSpans the editor field renders for the whole document (what the user sees).
List<TextSpan> leafSpans(Rig rig) {
  final ctx = rig.tester.element(find.byType(EditableText).first);
  final root = rig.doc.buildTextSpan(context: ctx, style: rig.field.widget.style, withComposing: false);
  final out = <TextSpan>[];
  void visit(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) out.add(s);
      s.children?.forEach(visit);
    }
  }

  visit(root);
  return out;
}

bool hasBackground(TextSpan s) => s.style?.backgroundColor != null && s.style!.backgroundColor != Colors.transparent;
bool isWavy(TextSpan s) =>
    (s.style?.decoration?.contains(TextDecoration.underline) ?? false) && s.style?.decorationStyle == TextDecorationStyle.wavy;

/// A body of [paragraphs] ordinary paragraphs (about 40 words each), long enough to scroll.
String filler(int paragraphs, {String tag = 'P'}) => [
      for (int i = 0; i < paragraphs; i++)
        '$tag$i It is a truth universally acknowledged, that a single man in possession of a good fortune, '
            'must be in want of a wife. However little known the feelings or views of such a man may be on his first entering a neighbourhood.',
    ].join('\n\n');

/// Pushes the real Settings screen over the editor.
Future<void> openSettings(Rig rig) async {
  ignoreOverflowWarnings();
  final nav = rig.tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  await rig.wait(const Duration(milliseconds: 800));
  expect(find.byType(SettingsScreen), findsOneWidget);
}

Future<void> closeSettings(Rig rig) async {
  rig.tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await rig.wait(const Duration(milliseconds: 600));
}

/// Taps the switch of the Settings row labelled [label]. Returns after the frame settles.
Future<void> tapSwitch(Rig rig, String label) async {
  final tile = find.widgetWithText(SwitchListTile, label);
  await rig.tester.ensureVisible(tile);
  await rig.pump(3);
  await rig.tester.tap(tile);
  await rig.pump(6);
}

/// One Cmd+Z, the way a writer does it: after a beat, so the field's undo history (it records edits on a
/// 500 ms throttle) has the last edit in it.
Future<void> undo(Rig rig) async {
  await rig.wait(const Duration(milliseconds: 650));
  await rig.key(LogicalKeyboardKey.keyZ, meta: true);
}

/// Cmd+Z until the document equals [expected] (at most [max] presses). Returns how many it took.
Future<int> undoTo(Rig rig, String expected, String what, {int max = 4}) async {
  for (int i = 1; i <= max; i++) {
    await undo(rig);
    if (rig.text == expected) return i;
  }
  rig.expectDoc(expected, '$what (after $max undos)');
  return max;
}

/// Screen point at document offset [off] in the normal editor, scrolling it into the middle of the view first.
Future<Offset> pointAt(Rig rig, int off) async {
  final re = rig.field.renderEditable;
  Offset p() => re.localToGlobal(re.getLocalRectForCaret(TextPosition(offset: off)).center) + const Offset(1, 0);
  final scroll = rig.tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  final view = rig.tester.getRect(find.byType(Scrollable).first);
  if (p().dy < view.top + 20 || p().dy > view.bottom - 20) {
    scroll.jumpTo((scroll.pixels + p().dy - view.center.dy).clamp(0.0, scroll.maxScrollExtent));
    await rig.pump(4);
  }
  return p();
}

/// The Settings screen's project cards overflow by a few pixels in the debug build (a layout warning, not a
/// crash). Record it instead of failing the check that is about something else.
final List<String> overflowsSeen = [];
void ignoreOverflowWarnings() {
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) {
      overflowsSeen.add(d.exceptionAsString().split('\n').first);
      return;
    }
    old?.call(d);
  };
}
