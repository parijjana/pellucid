// Owner checklist: Find (L36, L38), Settings and the status bar (L42, L44, L46).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/search/widgets/search_popup.dart';

import '../support/editor_helpers.dart';
import '../support/harness.dart';

const _findDoc = 'The quokka sat. Another quokka ran by.\n\nA deliberate slip: teh end of it, and teh quokka again.\n';

Future<void> _find(Rig rig, String q) async {
  rig.search.toggleSearch(isOpen: true);
  await rig.pump(10);
  final field = find.descendant(of: find.byType(SearchPopup), matching: find.byType(TextField)).first;
  await rig.tester.enterText(field, q);
  await rig.wait(const Duration(milliseconds: 900));
}

void registerFindSettingsChecks() {
  check('Check L36: closing Find clears every highlight', (tester) async {
    final rig = await mount(tester, text: _findDoc);
    await _find(rig, 'quokka');
    expect(rig.doc.searchQuery, 'quokka');
    final lit = leafSpans(rig).where(hasBackground).map((s) => s.text).toList();
    expect(lit, ['quokka', 'quokka', 'quokka'], reason: 'all three matches are highlighted while Find is open');
    rig.search.toggleSearch(isOpen: false);
    await rig.wait(const Duration(milliseconds: 600));
    expect(find.byType(SearchPopup), findsNothing, reason: 'the Find popup is gone');
    expect(rig.doc.searchQuery, '', reason: 'the controller no longer has a query');
    expect(leafSpans(rig).where(hasBackground), isEmpty, reason: 'no span keeps a highlight');
    await rig.dispose();
  });

  check('Check L38: a misspelled Find match has both the tint and the wavy underline', (tester) async {
    final rig = await mount(tester, text: _findDoc, spell: true);
    bool flagged() => rig.doc.misspellings.any((m) => rig.text.substring(m.start, m.end) == 'teh');
    final sw = Stopwatch()..start();
    while (!flagged() && sw.elapsed < const Duration(seconds: 60)) {
      await rig.wait(const Duration(milliseconds: 250));
    }
    expect(flagged(), isTrue, reason: 'native spell check flags "teh"');
    await _find(rig, 'teh');
    final tehSpans = leafSpans(rig).where((s) => s.text == 'teh').toList();
    expect(tehSpans, hasLength(2));
    for (final s in tehSpans) {
      expect(hasBackground(s), isTrue, reason: 'the match tint is on the misspelled word');
      expect(isWavy(s), isTrue, reason: 'the wavy spelling underline is on the same word');
    }
    // A match that is spelled correctly gets the tint only.
    await _find(rig, 'quokka');
    final q = leafSpans(rig).where((s) => s.text == 'quokka').toList();
    expect(q.every((s) => hasBackground(s) && !isWavy(s)), isTrue);
    await rig.dispose();
  });

  check('Check L42: Settings lists Projects first, it collapses, and Setup is reachable', (tester) async {
    final rig = await mount(tester, text: _findDoc, masterDir: true);
    await openSettings(rig);
    final projects = find.text('PROJECTS'), setup = find.text('SETUP');
    expect(projects, findsOneWidget);
    expect(setup, findsOneWidget, reason: 'Setup is reachable');
    expect(tester.getTopLeft(projects).dy, lessThan(tester.getTopLeft(setup).dy), reason: 'Projects comes first');
    expect(find.text('PUBLISH & EXPORT'), findsOneWidget, reason: 'Projects is open by default');
    await tester.tap(projects);
    await rig.pump(6);
    expect(find.text('PUBLISH & EXPORT'), findsNothing, reason: 'Projects collapses');
    expect(setup, findsOneWidget);
    await tester.tap(projects);
    await rig.pump(6);
    expect(find.text('PUBLISH & EXPORT'), findsOneWidget, reason: 'and expands again');
    // Setup opens its switches.
    expect(find.text('Smart Punctuation'), findsOneWidget);
    await tester.tap(setup);
    await rig.pump(6);
    expect(find.text('Smart Punctuation'), findsNothing, reason: 'Setup collapses too');
    await tester.tap(setup);
    await rig.pump(6);
    expect(find.text('Smart Punctuation'), findsOneWidget);
    await rig.dispose();
  });

  check('Check L44: selecting text shows "N of M words" and deselecting reverts', (tester) async {
    const t = 'one two three four five six seven eight nine ten';
    final rig = await mount(tester, text: t);
    expect(find.text('10 words'), findsOneWidget);
    await rig.placeCaret(0);
    rig.doc.selection = const TextSelection(baseOffset: 0, extentOffset: 13); // "one two three"
    await rig.pump(6);
    expect(find.text('3 of 10 words'), findsOneWidget, reason: 'selection count');
    rig.doc.selection = const TextSelection.collapsed(offset: 4);
    await rig.pump(6);
    expect(find.text('10 words'), findsOneWidget, reason: 'reverts on deselect');
    expect(find.textContaining(' of 10 words'), findsNothing);
    await rig.dispose();
  });

  check('Check L46: each new switch turns its feature off', (tester) async {
    const t = 'This is is a test.';
    final rig = await mount(tester, text: t, masterDir: true);
    final s = rig.settings;
    expect([s.grammarHintsEnabled, s.smartPunctuationEnabled, s.autoContinueListsEnabled, s.attributionDuplicateHighlightEnabled],
        everyElement(isTrue), reason: 'all on by default');

    // Grammar hints: on -> the repeated "is is" is flagged; off -> cleared.
    final sw = Stopwatch()..start();
    while (rig.doc.grammarIssues.isEmpty && sw.elapsed < const Duration(seconds: 10)) {
      await rig.wait(const Duration(milliseconds: 200));
    }
    expect(rig.doc.grammarIssues, isNotEmpty, reason: 'grammar hint present while the switch is on');
    await openSettings(rig);
    await tapSwitch(rig, 'Grammar Hints');
    expect(s.grammarHintsEnabled, isFalse);
    await tapSwitch(rig, 'Smart Punctuation');
    expect(s.smartPunctuationEnabled, isFalse);
    await tapSwitch(rig, 'Auto-continue Lists');
    expect(s.autoContinueListsEnabled, isFalse);
    await tapSwitch(rig, 'Highlight Duplicate Attributions');
    expect(s.attributionDuplicateHighlightEnabled, isFalse);
    await closeSettings(rig);
    await rig.wait(const Duration(milliseconds: 800));
    expect(rig.doc.grammarIssues, isEmpty, reason: 'grammar hints off: no hints');

    // Smart punctuation off: a straight quote stays straight.
    await rig.placeCaret(rig.text.length);
    await rig.typeText(' "q"');
    expect(rig.text, endsWith(' "q"'), reason: 'no curly quotes with the switch off');
    // Auto-continue off: Enter after a bullet adds no marker.
    await rig.typeText('\n- item');
    await rig.typeText('\n');
    expect(rig.text, endsWith('- item\n'), reason: 'Enter does not continue the list');
    await rig.dispose();
  });
}
