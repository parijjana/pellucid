// Description: Add selection to a note / to attributions (backlog item 19).

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/editor/widgets/editor_selection_actions.dart';

void main() {
  test('New note: a single word becomes the title, body stays empty', () {
    final p = NotesProvider();
    final id = p.addNoteFromSelection('  Ravenscar ');
    final card = p.cards.singleWhere((c) => c.id == id);
    expect(card.title, 'Ravenscar');
    expect(card.content, '');
  });

  test('New note: several words go into the body', () {
    final p = NotesProvider();
    final id = p.addNoteFromSelection('The old mill\nstood alone.');
    final card = p.cards.singleWhere((c) => c.id == id);
    expect(card.title, 'New Note');
    expect(card.content, 'The old mill\nstood alone.');
  });

  test('existing note: appended as a new paragraph, old text intact', () {
    final p = NotesProvider();
    final id = p.addNoteFromSelection('first paragraph here');
    expect(p.appendToNote(id, 'second bit'), isTrue);
    expect(p.cards.single.content, 'first paragraph here\n\nsecond bit');
    p.appendToNote(id, 'third');
    expect(p.cards.single.content, 'first paragraph here\n\nsecond bit\n\nthird');
  });

  test('existing note with a trailing newline gets one blank line, not three', () {
    final p = NotesProvider();
    final id = p.addNoteFromSelection('one two');
    p.updateCard(id, content: 'one two\n');
    p.appendToNote(id, 'x');
    expect(p.cards.single.content, 'one two\n\nx');
  });

  test('append to an empty note does not add leading blank lines', () {
    final p = NotesProvider();
    p.addCard();
    p.appendToNote(p.cards.single.id, 'hello world');
    expect(p.cards.single.content, 'hello world');
  });

  test('append refuses the attribution card and unknown ids', () {
    final p = NotesProvider();
    p.addAttributionCard();
    expect(p.appendToNote(p.cards.single.id, 'x'), isFalse);
    expect(p.appendToNote('nope', 'x'), isFalse);
  });

  test('attributions are append-only and the card is created when missing', () {
    final p = NotesProvider();
    expect(p.cards, isEmpty);
    p.addAttributionItem('Photo by Anna');
    p.addAttributionItem('Photo by Anna'); // duplicates are allowed
    p.addAttributionItem('Song by Bo');
    final card = p.cards.single;
    expect(card.isAttribution, isTrue);
    expect([for (final i in card.attributionItems!) i.text], ['Photo by Anna', 'Photo by Anna', 'Song by Bo']);
  });

  test('the submenu lists notes without the attribution card', () {
    final p = NotesProvider();
    p.addCard();
    p.addAttributionCard();
    p.addCard();
    final targets = EditorSelectionActions.targetNotes(p.cards);
    expect(targets.length, 2);
    expect(targets.any((c) => c.isAttribution), isFalse);
  });

  test('ActiveEditor.selectedText is null without a real selection', () {
    ActiveEditor.controller = null;
    expect(ActiveEditor.selectedText, isNull);
  });
}
