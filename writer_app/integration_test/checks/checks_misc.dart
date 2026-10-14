// Owner checklist: typewriter drag-select (L189), new project with unsynced edits (L203), and the caret
// after bullets in a large document (L50, via the normal editor's click-to-caret mapping).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/settings/widgets/new_project_card.dart';

import '../support/editor_helpers.dart';
import '../support/harness.dart';

ScrollPosition _pos(WidgetTester t) => t.state<ScrollableState>(find.byType(Scrollable).first).position;
Rect _viewport(WidgetTester t) => t.getRect(find.byType(Scrollable).first);

void registerMiscChecks() {
  check('Check L189: typewriter - drag-select does not jump, the next arrow re-centres once', (tester) async {
    final rig = await mount(tester, text: filler(80), typewriter: true);
    final pos = _pos(tester);
    // Settle with the caret deep in the page, centred by typewriter.
    final at = rig.text.indexOf('P40 ') + 10;
    await rig.placeCaret(at);
    await rig.key(LogicalKeyboardKey.arrowRight);
    await rig.wait(const Duration(milliseconds: 1000));
    final settled = pos.pixels;
    expect(settled, greaterThan(200), reason: 'typewriter scrolled the page to the caret');

    // Drag-select with the mouse across a few visible lines.
    final v = _viewport(tester);
    final from = Offset(v.center.dx - 150, v.center.dy - 40), to = Offset(v.center.dx + 150, v.center.dy + 60);
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: from);
    await g.down(from);
    final seen = <double>[pos.pixels];
    for (int i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await rig.pump(3);
      seen.add(pos.pixels);
    }
    await g.up();
    await rig.wait(const Duration(milliseconds: 1200));
    seen.add(pos.pixels);
    await g.removePointer();
    expect(rig.sel.isCollapsed, isFalse, reason: 'the drag selected text');
    expect(seen.every((p) => (p - settled).abs() < 1.0), isTrue, reason: 'no jump while selecting or after release: $seen (was $settled)');

    // The next arrow key re-centres, once.
    final selStart = rig.sel.start;
    await rig.key(LogicalKeyboardKey.arrowRight);
    final samples = <double>[];
    for (int i = 0; i < 30; i++) {
      await rig.pump(2);
      samples.add(pos.pixels);
    }
    await rig.wait(const Duration(milliseconds: 800));
    final after = pos.pixels;
    final re = rig.field.renderEditable;
    final c = re.localToGlobal(re.getLocalRectForCaret(rig.sel.extent).center);
    final vv = _viewport(tester);
    // ignore: avoid_print
    print('EVID|L189|scroll settled=$settled during drag=${seen.last} after arrow=$after (caret was at ${selStart}); caret y offset from centre ${(c.dy - vv.center.dy).toStringAsFixed(1)}');
    expect((c.dy - vv.center.dy).abs(), lessThan(16.0 * 1.8 * 1.6), reason: 'after the arrow the caret line is centred again');
    // One move: the scroll value never reverses direction.
    int reversals = 0;
    for (int i = 2; i < samples.length; i++) {
      final d1 = samples[i - 1] - samples[i - 2], d2 = samples[i] - samples[i - 1];
      if (d1 * d2 < -0.01) reversals++;
    }
    expect(reversals, 0, reason: 'a single re-centre animation, no back-and-forth: $samples');
    // And it stays put afterwards.
    await rig.wait(const Duration(milliseconds: 600));
    expect((pos.pixels - after).abs(), lessThan(1.0));
    await rig.dispose();
  });

  check('Check L203: new project with unsynced edits is instant, and the old project still uploads', (tester) async {
    final rig = await mount(tester, text: 'Hello\n', masterDir: true, loggedIn: true);
    rig.sync.latency = const Duration(seconds: 4); // a slow Drive: waiting for it would take 4 s
    await rig.placeCaret(rig.text.length);
    await rig.typeText('typed but not yet synced');
    expect(rig.sync.uploads, isEmpty, reason: 'nothing uploaded yet (sync debounce has not fired)');
    expect(rig.editor.content, contains('typed but not yet synced'));
    final oldName = rig.settings.currentProjectName;
    expect(oldName, 'Long Book');

    await openSettings(rig);
    await tester.tap(find.byType(NewProjectCard));
    await rig.pump(8);
    await tester.enterText(find.byType(TextField).last, 'Fresh');
    await rig.pump(3);
    final sw = Stopwatch()..start();
    await tester.tap(find.text('Create'));
    while (rig.settings.currentProjectName != 'Fresh' && sw.elapsed < const Duration(seconds: 10)) {
      await rig.pump(2);
    }
    final created = sw.elapsedMilliseconds;
    // The editor has loaded the (empty) new project too.
    while (rig.editor.content.contains('typed') && sw.elapsed < const Duration(seconds: 10)) {
      await rig.pump(2);
    }
    final loaded = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('EVID|L203|Create tapped -> project switched after $created ms, new project loaded after $loaded ms (Drive latency 4000 ms)');
    expect(rig.settings.currentProjectName, 'Fresh');
    expect(loaded, lessThan(2000), reason: 'creating did not wait on the 4 s upload');
    expect(rig.sync.uploads.where((u) => u.project == 'Long Book'), isNotEmpty, reason: 'the old project upload was started');
    expect(rig.sync.finished, 0, reason: 'and was still in flight when the new project appeared');
    await rig.wait(const Duration(seconds: 5));
    final up = rig.sync.uploads.where((u) => u.project == 'Long Book').toList();
    expect(up, hasLength(1));
    expect(up.single.content, contains('typed but not yet synced'), reason: 'the upload carries the old project\'s text');
    expect(rig.sync.finished, 1, reason: 'the upload completed');
    await closeSettings(rig);
    await rig.dispose();
  });

  check('Check L50: clicking text below several bullets lands the caret where you click', (tester) async {
    final bullets = [for (int i = 0; i < 12; i++) '- bullet number $i with some words'].join('\n');
    final doc = 'Intro paragraph.\n\n$bullets\n\n- **bold bullet** here\n- *italic bullet* here\n\n## Heading after\n\nThe target paragraph sits well below all of the bullets above.\n\n${filler(5)}';
    final rig = await mount(tester, text: doc);
    final target = doc.indexOf('target paragraph');
    for (final delta in [0, 5, 12]) {
      final want = target + delta;
      final p = await pointAt(rig, want);
      await tester.tapAt(p, kind: PointerDeviceKind.mouse);
      await rig.wait(const Duration(milliseconds: 700)); // not a double-click
      expect((rig.sel.baseOffset - want).abs(), lessThanOrEqualTo(1), reason: 'caret at ${rig.sel.baseOffset}, wanted $want after clicking below the bullets');
    }
    // Arrow down from inside the last bullet lands on the next line's text, not off by marker widths.
    await rig.placeCaret(doc.indexOf('bullet number 5') + 3);
    await rig.key(LogicalKeyboardKey.arrowDown);
    expect(rig.text.substring(rig.sel.baseOffset - 3, rig.sel.baseOffset + 3), contains('bullet'), reason: 'Down lands in the next bullet line');
    await rig.dispose();
  });
}
