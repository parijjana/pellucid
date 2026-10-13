// Checks 14 (Find, TOC), 15 (spelling), 16 (save/reopen) and the Codex.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/widgets/codex_mention_peek.dart';
import 'package:pellucid/features/editor/widgets/editor_navigation_sidebar.dart';
import 'package:pellucid/features/search/widgets/search_popup.dart';
import 'package:pellucid/features/sidebar/widgets/note_editor_dialog.dart';

import '../support/harness.dart';

/// Screen y of the character at [off] must be inside the editor's viewport.
void expectOffsetOnScreen(Rig rig, int off, String what) {
  final p = rig.pointAtOffset(off);
  final v = rig.viewport;
  expect(p.dy, inInclusiveRange(v.top, v.bottom), reason: '$what is on screen (y=${p.dy}, view ${v.top}-${v.bottom})');
}

void registerNavChecks() {
  // ------------------------------------------------------------ Check 14 ---
  check('Check 14: Find - next/previous move to far matches and scroll them into view', (tester) async {
    final rig = await mount(tester);
    final offs = rig.fx.quokkaOffsets;
    rig.search.toggleSearch(isOpen: true);
    await rig.pump(10);
    final field = find.descendant(of: find.byType(SearchPopup), matching: find.byType(TextField)).first;
    await tester.enterText(field, 'quokka');
    await rig.wait(const Duration(milliseconds: 900));
    expect(rig.search.matchOffsets, offs, reason: 'three far matches');
    var lastScroll = rig.win.scroll.offset;

    Future<void> expectAtMatch(int index, String what) async {
      expect(rig.search.currentMatchIndex, index, reason: what);
      expect(rig.doc.activeMatchOffset, offs[index], reason: '$what: active match highlighted');
      expectOffsetOnScreen(rig, offs[index], '$what: match ${index + 1}');
      // ignore: avoid_print
      print('EVID|14|$what -> match ${index + 1}/3 at ${offs[index]}, scroll ${rig.win.scroll.offset.toStringAsFixed(0)}');
    }

    await expectAtMatch(0, 'typing the query');
    Future<void> press(String tooltip) async {
      await tester.tap(find.byTooltip(tooltip));
      await rig.wait(const Duration(milliseconds: 900));
    }

    await press('Next Match');
    await expectAtMatch(1, 'next');
    expect(rig.win.scroll.offset, isNot(lastScroll), reason: 'the page scrolled');
    lastScroll = rig.win.scroll.offset;
    await press('Next Match');
    await expectAtMatch(2, 'next');
    await press('Next Match');
    await expectAtMatch(0, 'next wraps to the first');
    await press('Previous Match');
    await expectAtMatch(2, 'previous wraps to the last');
    await press('Previous Match');
    await expectAtMatch(1, 'previous');
    await rig.dispose();
  });

  check('Check 14: a TOC click on a far chapter scrolls there', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    rig.shortcuts.toggleLeftSidebar();
    await rig.wait(const Duration(milliseconds: 700));
    for (final chapter in [40, 7]) {
      final upwards = chapter == 7; // the sidebar list is at chapter 40 after the first click
      final line = fx.chapterLines[chapter - 1];
      final title = fx.lines[line].substring(2); // "Chapter 40: The Lantern"
      final scrollable = find.descendant(of: find.byType(EditorNavigationSidebar), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text(title), upwards ? -80 : 80, scrollable: scrollable);
      await rig.pump(3);
      await tester.tap(find.text(title));
      await rig.wait(const Duration(milliseconds: 900));
      final r = rig.lineRect(line);
      expect(r, isNotNull, reason: 'chapter $chapter heading line is built');
      final v = rig.viewport;
      expect(r!.center.dy, inInclusiveRange(v.top, v.top + v.height * 0.25),
          reason: 'chapter $chapter heading sits near the top of the view (centre=${r.center.dy}, view ${v.top}-${v.bottom})');
      // ignore: avoid_print
      print('EVID|14|TOC "$title" -> heading at y=${(r.top - v.top).toStringAsFixed(0)}px below the view top, '
          'scroll ${rig.win.scroll.offset.toStringAsFixed(0)}');
    }
    await rig.dispose();
  });

  // ------------------------------------------------------------ Check 15 ---
  check('Check 15: far misspelling is flagged after the spell pause; context menu has suggestions/Learn/Ignore',
      (tester) async {
    final rig = await mount(tester, spell: true);
    final fx = rig.fx;
    final teh = TextRange(start: fx.tehOffset, end: fx.tehOffset + 3);
    expect(rig.text.substring(teh.start, teh.end), 'teh');
    bool flagged(TextRange r) => rig.doc.misspellings.any((m) => m.start == r.start && m.end == r.end);
    // ignore: avoid_print
    print('EVID|15|FLUTTER_TEST env=${Platform.environment['FLUTTER_TEST']} (native macOS spell check needs it unset)');
    final sw = Stopwatch()..start();
    while (!flagged(teh) && sw.elapsed < const Duration(seconds: 120)) {
      await rig.wait(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print('EVID|15|initial whole-document check flagged "teh" after ${sw.elapsed.inMilliseconds} ms '
        '(${rig.doc.misspellings.length} misspellings in the document)');
    expect(flagged(teh), isTrue, reason: 'native macOS spell check flagged the far "teh"');

    // After the pause: a new far misspelling typed now is flagged only once the 1.5 s pause has passed.
    final at = fx.lineStart(fx.darcyLine) + fx.lines[fx.darcyLine].length;
    await rig.reveal(at);
    await rig.placeCaret(at);
    await rig.typeText(' recieve');
    final typedAt = Stopwatch()..start();
    final recieve = TextRange(start: at + 1, end: at + 1 + 7);
    expect(rig.text.substring(recieve.start, recieve.end), 'recieve');
    await rig.wait(const Duration(milliseconds: 900));
    expect(flagged(recieve), isFalse, reason: 'not yet: the spell pause is 1.5 s');
    while (!flagged(recieve) && typedAt.elapsed < const Duration(seconds: 60)) {
      await rig.wait(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('EVID|15|new misspelling flagged ${typedAt.elapsed.inMilliseconds} ms after the last key (pause 1500 ms + check)');
    expect(flagged(recieve), isTrue, reason: 'flagged after the pause');
    expect(typedAt.elapsed.inMilliseconds, greaterThanOrEqualTo(1400));

    // Context menu on the far "teh": click the word, then right-click it.
    await rig.reveal(fx.tehOffset);
    await tester.tapAt(rig.pointAtOffset(fx.tehOffset + 1), kind: PointerDeviceKind.mouse);
    await rig.wait(const Duration(milliseconds: 500));
    await tester.tapAt(rig.pointAtOffset(fx.tehOffset + 1),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await rig.wait(const Duration(milliseconds: 1200)); // lazy suggestions are asked of the OS
    final labels = [
      for (final w in find.byType(Text).evaluate().map((e) => e.widget as Text))
        if (w.data != null) w.data!,
    ];
    final buttons = labels.where((l) => ['Learn spelling', 'Ignore', 'the', 'Teh', 'Te', 'Tech', 'Th', 'The'].contains(l)).toList();
    // ignore: avoid_print
    print('EVID|15|context menu entries seen: $buttons');
    expect(find.text('Learn spelling'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    final learnY = tester.getTopLeft(find.text('Learn spelling')).dy;
    final suggestionAbove = find
        .byType(Text)
        .evaluate()
        .map((e) => e.widget as Text)
        .where((w) => w.data != null && w.data!.length <= 8 && w.data != 'Learn spelling' && w.data != 'Ignore')
        .any((w) => tester.getTopLeft(find.byWidget(w)).dy < learnY && tester.getTopLeft(find.byWidget(w)).dx > 300);
    expect(suggestionAbove, isTrue, reason: 'at least one spelling suggestion is listed above Learn spelling');
    await tester.tap(find.text('Ignore'));
    await rig.wait(const Duration(milliseconds: 1500));
    expect(flagged(teh), isFalse, reason: 'Ignore stops flagging the word');
    await rig.dispose();
  });

  // ------------------------------------------------------------ Check 16 ---
  check('Check 16: save, close and reopen - the file is byte-identical to the expected text', (tester) async {
    final rig = await mount(tester);
    final fx = rig.fx;
    final orig = rig.text;
    final at = fx.lineStart(fx.chapterLines[29]) + 25;
    await rig.reveal(at);
    await rig.placeCaret(at);
    await rig.typeText('Saved é 😀 words');
    var expected = orig.replaceRange(at, at, 'Saved é 😀 words');
    rig.expectDoc(expected, 'typing');
    // Autosave fires 2 s after the last edit.
    await rig.wait(const Duration(milliseconds: 3000));
    final file = File('${rig.projectPath}/document.md');
    var bytes = await file.readAsBytes();
    expect(listEquals(bytes, utf8.encode(expected)), isTrue,
        reason: 'document.md (${bytes.length} bytes) equals the expected text (${utf8.encode(expected).length} bytes)');
    final root = rig.root;
    // Close the project...
    await rig.dispose();
    // ...and reopen it from disk in a fresh editor.
    final again = await mount(tester, reuse: root);
    again.expectWindowed();
    expect(again.text == expected, isTrue, reason: 'reopened document equals what was saved');
    bytes = await file.readAsBytes();
    expect(listEquals(bytes, utf8.encode(expected)), isTrue, reason: 'file unchanged by reopening');
    // And an edit after reopen saves again, still byte-exact.
    final at2 = again.fx.lineStart(again.fx.darcyLine);
    await again.reveal(at2);
    await again.placeCaret(at2);
    await again.typeText('Z');
    expected = expected.replaceRange(at2, at2, 'Z');
    await again.wait(const Duration(milliseconds: 3000));
    bytes = await file.readAsBytes();
    expect(listEquals(bytes, utf8.encode(expected)), isTrue, reason: 'second save is byte-exact too');
    await again.dispose();
  });

  // --------------------------------------------------------------- Codex ---
  check('Check Codex - hovering a far "Darcy" resolves to the note; Cmd+Opt click opens it', (tester) async {
    final rig = await mount(tester, codex: true);
    final fx = rig.fx;
    await rig.reveal(fx.darcyOffset);
    rig.doc.codexIndex.rangesFor(rig.text); // what the detector does before it looks a mention up
    expect(rig.doc.codexIndex.noteIdAt(fx.darcyOffset + 2), rig.codexId, reason: 'the index maps Darcy to the note');
    final p = rig.pointAtOffset(fx.darcyOffset + 2);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 5));
    await mouse.moveTo(p);
    await rig.pump(6);
    expect(find.byType(CodexMentionPeek), findsOneWidget, reason: 'hover peek for the far mention');
    final peek = tester.widget<CodexMentionPeek>(find.byType(CodexMentionPeek));
    expect(peek.title, 'Darcy');
    expect(peek.content, contains('Proud'));
    // Hovering plain text elsewhere closes it.
    await mouse.moveTo(rig.pointInLine(fx.darcyLine + 2, dx: 20));
    await rig.pump(4);
    expect(find.byType(CodexMentionPeek), findsNothing);
    // Cmd+Opt click opens the note.
    await mouse.moveTo(p);
    await rig.pump(3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await mouse.down(p);
    await mouse.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await rig.pump(10);
    expect(find.byType(NoteEditorDialog), findsOneWidget, reason: 'Cmd+Opt click opens the codex note');
    expect(tester.widget<NoteEditorDialog>(find.byType(NoteEditorDialog)).noteId, rig.codexId);
    await mouse.removePointer();
    await rig.dispose();
  });
}
