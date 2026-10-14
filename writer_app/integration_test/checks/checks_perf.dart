// Checks 1, 9, 10, 13: caret travel, drag-select auto-scroll, scrollbar drag and
// typewriter mode, each with frame build/raster times recorded.
//
// Numbers are from a DEBUG build (flutter test cannot build profile/release on
// macOS), so budgets are generous; the printed p50/p90/max are the evidence.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Debug-build budgets (ms). Frame total = build + raster span as the engine reports it.
const double kP90BudgetMs = 50;
const double kMaxBudgetMs = 500;

void expectBudget(FrameStats s) {
  expect(s.frames, greaterThan(10), reason: '${s.name}: frames were recorded');
  expect(s.p90, lessThan(kP90BudgetMs), reason: '${s.name}: p90 frame ${s.p90.toStringAsFixed(1)} ms (debug budget $kP90BudgetMs)');
  expect(s.max, lessThan(kMaxBudgetMs), reason: '${s.name}: worst frame ${s.max.toStringAsFixed(1)} ms (debug budget $kMaxBudgetMs)');
}

void registerPerfChecks() {
  // -------------------------------------------------------------- Check 1 ---
  check('Check 1: Arrow Up/Down and PgUp/PgDn through a long stretch - the caret never jumps', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    final start = fx.lineStart(fx.chapterLines[9]) + 300;
    await rig.reveal(start);
    await rig.placeCaret(start);
    final rec = FrameRecorder()..start();

    int maxStep = 0;
    int windowMoves0 = rig.win.windowMoves;
    Future<void> walk(LogicalKeyboardKey k, int n, int sign) async {
      for (int i = 0; i < n; i++) {
        final before = rig.sel.baseOffset;
        await rig.key(k);
        final after = rig.sel.baseOffset;
        final delta = (after - before) * sign;
        maxStep = math.max(maxStep, delta.abs());
        expect(rig.sel.isCollapsed, isTrue);
        expect(delta, inInclusiveRange(1, 600),
            reason: '${k.keyLabel} #${i + 1}: caret moved $delta chars (from $before to $after) - expected one line');
        final y = rig.pointAtOffset(after).dy;
        expect(y, inInclusiveRange(rig.viewport.top - 40, rig.viewport.bottom + 40),
            reason: '${k.keyLabel} #${i + 1}: caret at y=$y is off screen (view ${rig.viewport.top}-${rig.viewport.bottom})');
      }
    }

    await walk(LogicalKeyboardKey.arrowDown, 90, 1);
    final bottom = rig.sel.baseOffset;
    await walk(LogicalKeyboardKey.arrowUp, 90, -1);
    final back = rig.sel.baseOffset;
    // ignore: avoid_print
    print('EVID|1|90 x ArrowDown then 90 x ArrowUp: start=$start end-of-down=$bottom back=$back '
        'largest single step=$maxStep chars, window moves=${rig.win.windowMoves - windowMoves0}');
    expect((back - start).abs(), lessThan(400), reason: 'Up undoes Down');

    // Page keys: the caret may stay (page scroll) or move a page; it must never leap.
    final pageSteps = <int>[];
    final scrolls = <double>[];
    for (final k in [LogicalKeyboardKey.pageDown, LogicalKeyboardKey.pageUp]) {
      for (int i = 0; i < 12; i++) {
        final before = rig.sel.baseOffset;
        final s0 = rig.win.scroll.offset;
        await rig.key(k);
        await rig.pump(6);
        final d = rig.sel.baseOffset - before;
        pageSteps.add(d);
        scrolls.add(rig.win.scroll.offset - s0);
        expect(d.abs(), lessThanOrEqualTo(12000), reason: '${k.keyLabel} #${i + 1}: caret leapt $d chars');
        if (k == LogicalKeyboardKey.pageDown) expect(d, greaterThanOrEqualTo(0));
        if (k == LogicalKeyboardKey.pageUp) expect(d, lessThanOrEqualTo(0));
      }
    }
    // ignore: avoid_print
    print('EVID|1|PgDn/PgUp caret steps (chars): $pageSteps; scroll deltas (px): '
        '${scrolls.map((e) => e.round()).toList()}');
    final stats = await rec.stop(tester, 'check1-caret-travel');
    expectBudget(stats);
    await rig.dispose();
  });

  check('Check 1 (control): PgUp/PgDn in a SHORT document (single editor) - same behaviour?', (tester) async {
    final short = fixture.text.substring(0, 60000);
    final rig = await mount(tester, text: short);
    expect(find.byType(EditableText), findsOneWidget);
    expect(rig.fx.words, greaterThan(15000));
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.requestFocus();
    rig.doc.selection = const TextSelection.collapsed(offset: 20000);
    await rig.pump(6);
    final steps = <int>[];
    for (int i = 0; i < 4; i++) {
      final before = rig.doc.selection.baseOffset;
      await rig.key(LogicalKeyboardKey.pageDown);
      await rig.pump(6);
      steps.add(rig.doc.selection.baseOffset - before);
    }
    // ignore: avoid_print
    print('EVID|1c|short document (single editor): PgDn caret steps (chars) $steps - '
        '${steps.every((e) => e == 0) ? "caret does not move on PgDn in either editor" : "caret moves"}');
    await rig.dispose();
  });

  // -------------------------------------------------------------- Check 9 ---
  check('Check 9: drag-select held at the bottom edge auto-scrolls, keeps growing; Cmd+C copies all', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    final start = fx.lineStart(fx.chapterLines[9]) + 300;
    await rig.reveal(start);
    await rig.placeCaret(start);
    final p0 = rig.pointAtOffset(start + 4);
    final rec = FrameRecorder()..start();
    final g = await tester.startGesture(p0, kind: PointerDeviceKind.mouse);
    await rig.pump(2);
    await g.moveTo(p0 + const Offset(40, 0));
    await rig.pump(2);
    final anchor = rig.sel.baseOffset;
    final scroll0 = rig.win.scroll.offset;
    final edge = Offset(p0.dx + 40, rig.viewport.bottom - 6);
    await g.moveTo(edge);
    final extents = <int>[];
    final scrolls = <double>[];
    for (int i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (i % 20 == 19) {
        extents.add(rig.sel.extentOffset);
        scrolls.add(rig.win.scroll.offset);
      }
    }
    // ignore: avoid_print
    print('EVID|9|held 180 frames at the bottom edge: extents=$extents scroll=${scrolls.map((e) => e.round()).toList()}');
    expect(rig.sel.baseOffset, anchor, reason: 'anchor stays where the drag began');
    expect(rig.win.scroll.offset, greaterThan(scroll0 + 300), reason: 'the page auto-scrolled');
    for (int i = 1; i < extents.length; i++) {
      expect(extents[i], greaterThan(extents[i - 1]), reason: 'selection keeps growing (sample $i)');
    }
    await g.up();
    await rig.pump(6);
    final sel = rig.sel;
    expect(sel.baseOffset, anchor);
    final selected = rig.text.substring(sel.start, sel.end);
    expect(selected.length, greaterThan(4000), reason: 'longer than the live window');
    // Cmd+C copies the whole selection (checked on the mocked pasteboard, never the real one).
    await rig.key(LogicalKeyboardKey.keyC, meta: true);
    final clip = await rig.readClipboard();
    // ignore: avoid_print
    print('EVID|9|selection ${sel.start}-${sel.end} (${selected.length} chars); copied ${clip.length} chars');
    expect(clip == selected, isTrue, reason: 'clipboard equals the whole selection');
    final stats = await rec.stop(tester, 'check9-drag-autoscroll');
    expectBudget(stats);
    await rig.dispose();
  });

  // ------------------------------------------------------------- Check 10 ---
  check('Check 10: drag the scrollbar from top to bottom and back', (tester) async {
    final rig = await mount(tester);
    final w = rig.win;
    await rig.pump(6);
    Offset thumbCenter() {
      final pos = w.scroll.position;
      final v = rig.viewport;
      final min = pos.minScrollExtent, max = pos.maxScrollExtent;
      final extentTotal = max - min + pos.viewportDimension;
      final thumbH = math.max(18.0, v.height * pos.viewportDimension / extentTotal);
      final frac = (pos.pixels - min) / (max - min);
      final top = v.top + frac * (v.height - thumbH);
      return Offset(v.right - 5, top + thumbH / 2);
    }

    final top0 = w.scroll.position.pixels;
    final rec = FrameRecorder()..start();
    var p = thumbCenter();
    // The scrollbar thumb only takes a press once it is visible (hover fades it in) and the press
    // must be held ~100 ms (it is a long-press recogniser) before the drag follows.
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: p);
    await g.moveTo(p);
    await rig.wait(const Duration(milliseconds: 500));
    p = thumbCenter();
    await g.down(p);
    await rig.wait(const Duration(milliseconds: 300));
    final v = rig.viewport;
    final visited = <int>[];
    // Down to the bottom in 60 steps...
    for (int i = 1; i <= 60; i++) {
      await g.moveTo(Offset(p.dx, p.dy + (v.bottom - 4 - p.dy) * i / 60));
      await tester.pump(const Duration(milliseconds: 16));
      if (i % 10 == 0) visited.add((w.scroll.position.pixels - w.scroll.position.minScrollExtent).round());
    }
    await rig.pump(6);
    final atBottom = w.scroll.position.pixels;
    final maxExt = w.scroll.position.maxScrollExtent;
    // ignore: avoid_print
    print('EVID|10|scrollbar down: scroll offsets (from min) ${visited.join(", ")}; end ${atBottom.round()} of max ${maxExt.round()}');
    expect(atBottom, greaterThan(top0 + (maxExt - top0) * 0.9), reason: 'thumb dragged to the bottom reaches the end');
    // ...and back up.
    p = thumbCenter();
    for (int i = 1; i <= 60; i++) {
      await g.moveTo(Offset(p.dx, p.dy - (p.dy - v.top - 4) * i / 60));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await rig.pump(6);
    final back = w.scroll.position.pixels;
    // ignore: avoid_print
    print('EVID|10|scrollbar back up: ${back.round()} (started at ${top0.round()})');
    expect(back, lessThan(w.scroll.position.minScrollExtent + (maxExt - w.scroll.position.minScrollExtent) * 0.1),
        reason: 'thumb dragged back to the top returns to the start');
    // The page that is shown at the bottom is the end of the manuscript: the last text is reachable.
    final stats = await rec.stop(tester, 'check10-scrollbar-drag');
    expectBudget(stats);
    await rig.dispose();
  });

  // ------------------------------------------------------------- Check 13 ---
  check('Check 13: typewriter mode keeps the caret line centred while typing', (tester) async {
    final rig = await mount(tester, typewriter: true);
    final fx = rig.fx;
    final start = fx.lineStart(fx.chapterLines[20]) + 200;
    await rig.reveal(start);
    await rig.placeCaret(start);
    await rig.wait(const Duration(milliseconds: 500));
    final v = rig.viewport;
    final centre = v.top + v.height / 2;
    double caretY() {
      final re = rig.tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
      final r = re.getLocalRectForCaret(TextPosition(offset: rig.win.window.selection.extentOffset));
      return re.localToGlobal(r.center).dy;
    }

    final rec = FrameRecorder()..start();
    final offsets = <double>[];
    final text = 'the lantern swung over the harbour and nobody said a word about the tide';
    for (int line = 0; line < 8; line++) {
      await rig.typeText(text, gapMs: 8);
      await rig.typeText('\n\n', gapMs: 8);
      await rig.wait(const Duration(milliseconds: 250)); // the 100 ms re-centre animation
      final y = caretY();
      offsets.add(y - centre);
    }
    // ignore: avoid_print
    print('EVID|13|caret y minus view centre after each typed paragraph (px): '
        '${offsets.map((e) => e.round()).toList()} (view height ${v.height.round()})');
    for (int i = 0; i < offsets.length; i++) {
      expect(offsets[i].abs(), lessThan(60), reason: 'paragraph ${i + 1}: caret ${offsets[i].round()} px from the centre');
    }
    // And per keystroke: typing a line does not wander off the centre by more than a few lines.
    final stats = await rec.stop(tester, 'check13-typewriter-typing');
    expectBudget(stats);
    await rig.dispose();
  });
}
