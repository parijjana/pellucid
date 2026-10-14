// Owner checklist: hidden-marker editing (L60-L82), the long-doc caret items that apply to the normal
// editor (L50), shortcuts (L92), narrow toolbar (L94) and live Document Font + typewriter (L96).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/caret_formatting.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:pellucid/features/editor/widgets/format_menu.dart';
import 'package:pellucid/features/editor/widgets/formatting_toolbar.dart';

import '../support/editor_helpers.dart';
import '../support/harness.dart';

const _k = LogicalKeyboardKey.arrowRight;

int _count(String s, String sub) => sub.allMatches(s).length;

/// True when [off] in [text] lies inside a bold run's content.
bool _inBold(String text, int off) {
  final line = scanLineAt(text, off);
  return line.runs.any((r) => r.bold && r.contentStart <= off && off < r.contentEnd);
}

Future<void> reset(Rig rig, String doc) async {
  rig.doc.value = TextEditingValue(text: doc, selection: const TextSelection.collapsed(offset: 0));
  await rig.pump(3);
}

void registerMarkerChecks() {
  check('Check L60: arrows walk through bold, headings and bullets with no dead key press', (tester) async {
    const doc = '# Head\n\nA **bold** word and *it* x.\n\n- one\n- two\n\nEnd';
    final rig = await mount(tester, text: doc);
    await rig.placeCaret(0);
    final stops = <int>[0];
    for (int i = 0; i < doc.length + 5; i++) {
      final before = rig.sel.baseOffset;
      await rig.key(_k);
      final now = rig.sel.baseOffset;
      if (now == before) {
        expect(before, doc.length, reason: 'a Right press did nothing at offset $before (not the end): dead key');
        break;
      }
      expect(now, greaterThan(before));
      expect(canonicalOffset(doc, now), now, reason: 'the caret never rests inside a hidden marker (offset $now)');
      stops.add(now);
    }
    expect(stops.last, doc.length, reason: 'Right reaches the end of the document');
    // Visible characters + each line boundary: far fewer stops than raw characters, so markers were skipped.
    expect(stops.length, lessThan(doc.length), reason: 'hidden markers were stepped over (${stops.length} stops for ${doc.length} chars)');
    final first = canonicalOffset(doc, 0); // the "# " of the title is hidden: the first caret stop is after it
    for (int i = 0; i < doc.length + 5; i++) {
      final before = rig.sel.baseOffset;
      await rig.key(LogicalKeyboardKey.arrowLeft);
      final now = rig.sel.baseOffset;
      if (now == before) {
        expect(before, first, reason: 'a Left press did nothing at $before: dead key');
        break;
      }
      expect(canonicalOffset(doc, now), now, reason: 'Left never rests inside a marker ($now)');
    }
    expect(rig.sel.baseOffset, first);
    // ignore: avoid_print
    print('EVID|L60|${stops.length} Right presses walked ${doc.length} chars with no dead key');
    await rig.dispose();
  });

  check('Check L62: Cmd+B with no selection - end of a bold word, mid-word, plain text', (tester) async {
    final rig = await mount(tester, text: 'A **bold** word and plain.');
    // (a) end of a bold word: the next keystroke is plain.
    final endBold = rig.text.indexOf('bold') + 4;
    await rig.placeCaret(endBold);
    await rig.key(LogicalKeyboardKey.keyB, meta: true);
    await rig.typeText('X');
    var x = rig.text.indexOf('X');
    expect(x, greaterThan(0));
    expect(_inBold(rig.text, x), isFalse, reason: 'X typed after Cmd+B at the end of bold is not bold: "${rig.text}"');
    expect(visibleText(rig.text), 'A boldX word and plain.');
    expect(_count(rig.text, '**') % 2, 0);

    // (b) mid-word: ends the bold run there.
    await reset(rig, 'A **bold** word and plain.');
    await rig.placeCaret(rig.text.indexOf('bold') + 2);
    await rig.key(LogicalKeyboardKey.keyB, meta: true);
    await rig.typeText('X');
    x = rig.text.indexOf('X');
    expect(_inBold(rig.text, x), isFalse, reason: 'mid-word: X is outside bold: "${rig.text}"');
    expect(visibleText(rig.text), 'A boXld word and plain.');
    expect(_count(rig.text, '**') % 2, 0, reason: 'markers stay balanced');

    // (c) plain text: opens bold for the next keystroke.
    await reset(rig, 'A **bold** word and plain.');
    await rig.placeCaret(rig.text.indexOf('plain') + 5);
    await rig.key(LogicalKeyboardKey.keyB, meta: true);
    await rig.typeText('X');
    x = rig.text.indexOf('X');
    expect(_inBold(rig.text, x), isTrue, reason: 'in plain text Cmd+B makes the next keystroke bold: "${rig.text}"');
    expect(visibleText(rig.text), 'A bold word and plainX.');
    expect(_count(rig.text, '**') % 2, 0);
    // And toggling twice with nothing typed leaves no empty marker pair behind.
    await reset(rig, 'A **bold** word and plain.');
    await rig.placeCaret(rig.text.indexOf('plain') + 5);
    await rig.key(LogicalKeyboardKey.keyB, meta: true);
    await rig.key(LogicalKeyboardKey.keyB, meta: true);
    // ignore: avoid_print
    print('EVID|L62|Cmd+B twice with nothing typed leaves raw text "${rig.text}"');
    expect(visibleText(rig.text), 'A bold word and plain.', reason: 'nothing visible changed');
    await rig.dispose();
  });

  check('Check L64: Backspace at a heading/bullet start, Delete at the end of the line above a heading; undo', (tester) async {
    const doc = 'ab\n# Head\n\n- item\n\nxy\n# Tail';
    final rig = await mount(tester, text: doc);
    // Backspace at the start of the heading text: the heading becomes body, a second Backspace joins.
    await reset(rig, doc);
    final h = doc.indexOf('Head');
    await rig.placeCaret(h);
    await rig.key(LogicalKeyboardKey.backspace);
    rig.expectDoc(doc.replaceFirst('# Head', 'Head'), 'Backspace at heading start drops the # first');
    expect(rig.sel.baseOffset, h - 2);
    await rig.key(LogicalKeyboardKey.backspace);
    rig.expectDoc(doc.replaceFirst('ab\n# Head', 'abHead'), 'second Backspace joins the lines');

    // Backspace at the start of a bullet's text removes the bullet.
    await reset(rig, doc);
    final b = doc.indexOf('item');
    await rig.placeCaret(b);
    await rig.key(LogicalKeyboardKey.backspace);
    rig.expectDoc(doc.replaceFirst('- item', 'item'), 'Backspace at bullet start removes the marker');

    // Delete at the end of the line above a heading joins and drops the heading prefix.
    await reset(rig, doc);
    final y = doc.indexOf('xy') + 2;
    await rig.placeCaret(y);
    await rig.key(LogicalKeyboardKey.delete);
    rig.expectDoc(doc.replaceFirst('xy\n# Tail', 'xyTail'), 'Delete above a heading drops its prefix');
    await rig.dispose();
  });

  check('Check L66: select across a bold edge, then delete or type over it (markers stay balanced); undo', (tester) async {
    const doc = 'ab**cd**ef';
    final rig = await mount(tester, text: doc);
    rig.focus.requestFocus();
    await rig.pump(3);
    // Delete: selection "b**c" (starts outside, ends inside).
    rig.doc.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    await rig.pump(3);
    await rig.key(LogicalKeyboardKey.backspace);
    rig.expectDoc('a**d**ef', 'deleting across the opening edge keeps the rest bold');
    await reset(rig, doc);
    // Delete: selection "d**e" (starts inside, ends outside).
    rig.doc.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
    await rig.pump(3);
    await rig.key(LogicalKeyboardKey.backspace);
    rig.expectDoc('ab**c**f', 'deleting across the closing edge keeps the rest bold');
    await reset(rig, doc);
    // Type over "d**e".
    rig.doc.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
    await rig.pump(3);
    await rig.typeText('Z');
    expect(visibleText(rig.text), 'abcZf', reason: 'typed over the visible "de": "${rig.text}"');
    expect(_count(rig.text, '**') % 2, 0, reason: 'markers balanced: "${rig.text}"');
    await reset(rig, doc);
    // Type over "b**c".
    rig.doc.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    await rig.pump(3);
    await rig.typeText('Z');
    expect(visibleText(rig.text), 'aZdef', reason: 'typed over visible "bc": "${rig.text}"');
    expect(_count(rig.text, '**') % 2, 0);
    await rig.dispose();
  });

  check('Check L68: Enter mid-bold and Enter at the start of a heading keep markers sound; undo', (tester) async {
    const doc = 'a **bold** z\n\n# Head\n';
    final rig = await mount(tester, text: doc);
    await rig.placeCaret(doc.indexOf('bold') + 2);
    await rig.typeText('\n');
    final lines = rig.text.split('\n');
    expect(lines.take(2).map((l) => _count(l, '**') % 2), everyElement(0), reason: 'each half keeps balanced ** : ${lines.take(2).toList()}');
    expect(visibleText(rig.text).split('\n').take(2).toList(), ['a bo', 'ld z']);

    await reset(rig, doc);
    final h = doc.indexOf('Head');
    await rig.placeCaret(h);
    await rig.typeText('\n');
    final t = rig.text;
    // ignore: avoid_print
    print('EVID|L68|Enter at heading start ->${t.substring(doc.indexOf('# Head') - 1).replaceAll('\n', r'\n')}');
    expect(t.contains('Head'), isTrue);
    expect(visibleText(t).split('\n').where((l) => l.contains('Head')).single, 'Head', reason: 'the heading text is not split');
    await rig.dispose();
  });

  check('Check L82: toolbar and Format menu ticks follow the caret', (tester) async {
    const doc = '# Head\n\nA **bold** and *ital* word\n\n- bullet\n\n> quote\n\nplain';
    final rig = await mount(tester, text: doc);
    rig.shortcuts.toggleToolbar();
    await rig.pump(8);
    expect(find.byType(FormattingToolbar), findsOneWidget);
    bool active(String label) {
      final b = tester.widget<TextButton>(find.byKey(ValueKey('format-$label')));
      return b.style?.backgroundColor?.resolve({}) != null;
    }

    List<String> ticks() => [
          for (final i in formatMenuItems(caretFormatting.value))
            if (i.label.startsWith('✓')) i.label.substring(1).trim(),
        ];

    Future<void> at(int off) async {
      await rig.placeCaret(off);
      await rig.key(LogicalKeyboardKey.arrowRight);
      await rig.key(LogicalKeyboardKey.arrowLeft);
    }

    await at(doc.indexOf('bold') + 1);
    expect(active('BOLD'), isTrue);
    expect(active('ITALIC'), isFalse);
    expect(ticks(), contains('Bold'));
    await at(doc.indexOf('ital') + 1);
    expect(active('ITALIC'), isTrue);
    expect(active('BOLD'), isFalse);
    expect(ticks(), contains('Italic'));
    expect(ticks(), isNot(contains('Bold')));
    await at(doc.indexOf('Head') + 1);
    expect(active('TITLE'), isTrue, reason: 'a "# " line is the Title style');
    expect(ticks(), contains('Title'));
    await at(doc.indexOf('bullet') + 1);
    expect(active('BULLET'), isTrue);
    expect(active('TITLE'), isFalse);
    await at(doc.indexOf('quote') + 1);
    expect(active('QUOTE'), isTrue);
    expect(ticks(), contains('Quote'));
    await at(doc.indexOf('plain') + 1);
    expect(active('BODY'), isTrue);
    expect(active('BOLD') || active('ITALIC') || active('QUOTE') || active('BULLET'), isFalse);
    expect(ticks(), isNot(contains('Bold')));
    await rig.dispose();
  });

  check('Check L92: Cmd+Opt+J subheading, Cmd+Opt+Q quote, Cmd+Opt+X strikethrough', (tester) async {
    const doc = 'first line\n\nsecond line\n\nthird word here';
    final rig = await mount(tester, text: doc);
    await rig.placeCaret(2);
    await rig.key(LogicalKeyboardKey.keyJ, meta: true, alt: true);
    expect(rig.text.split('\n').first, '### first line', reason: 'Cmd+Opt+J makes a subheading');
    await reset(rig, doc);
    await rig.placeCaret(doc.indexOf('second') + 2);
    await rig.key(LogicalKeyboardKey.keyQ, meta: true, alt: true);
    expect(rig.text.split('\n')[2], '> second line', reason: 'Cmd+Opt+Q makes a quote');
    await reset(rig, doc);
    final w = doc.indexOf('word');
    rig.focus.requestFocus();
    rig.doc.selection = TextSelection(baseOffset: w, extentOffset: w + 4);
    await rig.pump(3);
    await rig.key(LogicalKeyboardKey.keyX, meta: true, alt: true);
    expect(rig.text, doc.replaceFirst('word', '~~word~~'), reason: 'Cmd+Opt+X strikes the selection');
    await rig.dispose();
  });

  check('Check L94: the formatting toolbar fits in a narrow window', (tester) async {
    final rig = await mount(tester, text: 'hello');
    rig.shortcuts.toggleToolbar();
    await rig.pump(6);
    final dpr = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = Size(640 * dpr, 700 * dpr); // above the 600 px compact breakpoint
    await rig.wait(const Duration(milliseconds: 600));
    expect(find.byType(FormattingToolbar), findsOneWidget, reason: 'still the desktop toolbar at 640 px');
    final bar = tester.getRect(find.byType(FormattingToolbar));
    expect(bar.right, lessThanOrEqualTo(640.5));
    for (final l in ['TITLE', 'BOLD', 'STRIKE', 'INDENT']) {
      final r = tester.getRect(find.byKey(ValueKey('format-$l')));
      expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$l inside the window (left)');
      expect(r.right, lessThanOrEqualTo(640.5), reason: '$l inside the window (right)');
    }
    expect(tester.takeException(), isNull, reason: 'no overflow error');
    tester.view.resetPhysicalSize();
    await rig.dispose();
  });

  check('Check L96: switching Document Font changes the editor live; typewriter stays centred', (tester) async {
    final rig = await mount(tester, text: filler(60), typewriter: true);
    String? family() => rig.field.widget.style.fontFamily;
    expect(family(), EditorFont.serif.family);
    // Put the caret deep in the page with typewriter on.
    final at = rig.text.indexOf('P30 ') + 20;
    await rig.placeCaret(at);
    await rig.typeText('a'); // typing is what typewriter scrolling follows
    await rig.wait(const Duration(milliseconds: 1500));
    double offFromCentre() {
      final re = rig.field.renderEditable;
      final c = re.localToGlobal(re.getLocalRectForCaret(rig.sel.extent).center);
      final v = tester.getRect(find.byType(Scrollable).first);
      return (c.dy - (v.top + v.height / 2)).abs();
    }

    final line = 16.0 * 1.8;
    // ignore: avoid_print
    print('EVID|L96|before switch: scroll ${tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels.toStringAsFixed(0)}, caret ${offFromCentre().toStringAsFixed(1)} px from centre, typewriter=${rig.settings.typewriterEnabled}, sel=${rig.sel}');
    expect(offFromCentre(), lessThan(line * 1.5), reason: 'caret line is centred before the switch');
    for (final f in [EditorFont.sans, EditorFont.monospace, EditorFont.serif]) {
      rig.settings.setEditorFont(f);
      await rig.wait(const Duration(milliseconds: 500));
      expect(family(), f.family, reason: 'the editor field switched to ${f.label} live');
      expect(leafSpans(rig).any((s) => s.style?.fontFamily == f.family || s.style?.fontFamily == null), isTrue);
      await rig.typeText('b');
      await rig.wait(const Duration(milliseconds: 1500));
      // ignore: avoid_print
      print('EVID|L96|font ${f.label}: caret ${offFromCentre().toStringAsFixed(1)} px from the viewport centre after the next keystroke');
      expect(offFromCentre(), lessThan(line * 1.5), reason: 'typewriter keeps the caret line centred after switching to ${f.label}');
    }
    await rig.dispose();
  });

  check('Check L80: undo after each hidden-marker edit restores the document', (tester) async {
    final rig = await mount(tester, text: 'x');
    final results = <String>[];
    Future<void> scenario(String name, String doc, int caret, int? selEnd, Future<void> Function() edit) async {
      rig.doc.value = TextEditingValue(text: doc, selection: TextSelection.collapsed(offset: caret));
      await rig.placeCaret(caret);
      if (selEnd != null) {
        rig.doc.selection = TextSelection(baseOffset: caret, extentOffset: selEnd);
        await rig.pump(3);
      }
      await rig.wait(const Duration(milliseconds: 700));
      await edit();
      final edited = rig.text;
      bool ok = false;
      for (int i = 0; i < 3 && !ok; i++) {
        await undo(rig);
        ok = rig.text == doc;
      }
      results.add('$name: ${ok ? "undo restores" : "undo does NOT restore (edited ${edited.replaceAll("\n", "\\n")} -> ${rig.text.replaceAll("\n", "\\n")})"}');
    }

    await scenario('Cmd+B mid-word then type', 'A **bold** word', 6, null, () async {
      await rig.key(LogicalKeyboardKey.keyB, meta: true);
      await rig.typeText('X');
    });
    await scenario('Backspace at heading start', 'ab\n# Head', 5, null, () => rig.key(LogicalKeyboardKey.backspace));
    await scenario('Delete above a heading', 'ab\n# Head', 2, null, () => rig.key(LogicalKeyboardKey.delete));
    await scenario('delete selection across bold edge', 'ab**cd**ef', 1, 5, () => rig.key(LogicalKeyboardKey.backspace));
    await scenario('type over selection across bold edge', 'ab**cd**ef', 5, 9, () => rig.typeText('Z'));
    await scenario('Enter mid-bold', 'a **bold** z', 6, null, () => rig.typeText('\n'));
    await scenario('Enter at heading start', 'a\n\n# Head', 5, null, () => rig.typeText('\n'));
    await scenario('Cmd+Opt+J subheading', 'first line', 2, null, () => rig.key(LogicalKeyboardKey.keyJ, meta: true, alt: true));
    for (final r in results) {
      // ignore: avoid_print
      print('EVID|L80|$r');
    }
    final bad = results.where((r) => r.contains('NOT')).toList();
    expect(bad, isEmpty, reason: 'undo did not restore: $bad');
    await rig.dispose();
  });
}
