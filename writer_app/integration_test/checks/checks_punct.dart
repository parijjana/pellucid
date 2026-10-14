// Owner checklist: smart punctuation (L119, L121, L123).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void registerPunctChecks() {
  check('Check L119: type " \' -- ... then one Cmd+Z undoes only the conversion', (tester) async {
    const base = 'Start ';
    final rig = await mount(tester, text: base);
    final cases = <(String typed, String converted, String straight)>[
      ('"', '“', '"'),
      ("'", '‘', "'"),
      ('wait--', 'wait—', 'wait--'),
      ('and so...', 'and so…', 'and so...'),
    ];
    for (final (typed, converted, straight) in cases) {
      rig.doc.value = TextEditingValue(text: base, selection: TextSelection.collapsed(offset: base.length));
      await rig.placeCaret(base.length);
      await rig.typeText(typed);
      rig.expectDoc('$base$converted', 'typing $typed converts');
      await rig.key(LogicalKeyboardKey.keyZ, meta: true);
      rig.expectDoc('$base$straight', 'ONE Cmd+Z undoes only the conversion (leaves what was typed) for $typed');
      expect(rig.sel.baseOffset, base.length + straight.length, reason: 'caret stays after the straight text');
    }
    // A closing quote after a word, and an apostrophe inside a word.
    rig.doc.value = const TextEditingValue(text: 'Start ', selection: TextSelection.collapsed(offset: 6));
    await rig.placeCaret(6);
    await rig.typeText('"hi," don\'t');
    rig.expectDoc('Start “hi,” don’t', 'quotes open and close by context');
    await rig.dispose();
  });

  check('Check L121: no conversion inside inline code or fenced blocks', (tester) async {
    final rig = await mount(tester, text: '');
    await rig.placeCaret(0);
    const inline = '`say "hi" -- it\'s...`';
    await rig.typeText(inline);
    rig.expectDoc(inline, 'inline code is left exactly as typed');
    await rig.typeText('\n\n```\nsay "hi" -- it\'s...\n');
    rig.expectDoc('$inline\n\n```\nsay "hi" -- it\'s...\n', 'a fenced block is left exactly as typed');
    // Outside the fence it converts again.
    await rig.typeText('```\n"ok"');
    expect(rig.text, endsWith('```\n“ok”'), reason: 'after the fence closes, conversion is back on: "${rig.text}"');
    await rig.dispose();
  });

  check('Check L123: Edit > Undo vs the shortcut after a conversion (recorded)', (tester) async {
    const base = 'Start ';
    final rig = await mount(tester, text: base);
    await rig.placeCaret(base.length);
    await rig.typeText('"');
    rig.expectDoc('$base“', 'converted');
    // What the Mac Edit > Undo menu item does: the Undo intent on the focused node.
    final ctx = FocusManager.instance.primaryFocus!.context!;
    Actions.invoke(ctx, const UndoTextIntent(SelectionChangedCause.keyboard));
    await rig.pump(4);
    final viaMenu = rig.text;
    // Reset and take the shortcut path for comparison.
    rig.doc.value = const TextEditingValue(text: base, selection: TextSelection.collapsed(offset: 6));
    await rig.placeCaret(base.length);
    await rig.typeText('"');
    await rig.key(LogicalKeyboardKey.keyZ, meta: true);
    final viaShortcut = rig.text;
    // ignore: avoid_print
    print('EVID|L123|after typing a quote: Edit>Undo gives "${viaMenu.replaceAll('\n', r'\n')}", Cmd+Z gives "$viaShortcut"');
    expect(viaShortcut, '$base"', reason: 'the shortcut undoes only the conversion');
    expect(viaMenu, isNot('$base"'),
        reason: 'documented limitation: the menu Undo does not use the single-step conversion undo (it gave "$viaMenu")');
    await rig.dispose();
  });
}
