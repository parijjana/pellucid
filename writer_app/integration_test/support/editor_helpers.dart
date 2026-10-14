// Small helpers for the Mac editor suite: reading the rendered spans, driving the real Settings
// screen, and short documents (well under 15,000 words, so the normal single editor is used).

import 'package:flutter/material.dart';
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
