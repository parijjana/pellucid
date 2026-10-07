// Description: Spelling suggestions, Learn spelling and Ignore in the editor
// context menu (backlog item 4), against a fake spell service. Codex names are
// known words.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/services/native_spell_check_service.dart';
import 'package:pellucid/features/editor/widgets/editor_context_menu.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/editor/widgets/spell_check_driver.dart';
import 'package:pellucid/features/sidebar/providers/note_card.dart';

/// Flags every word in [bad] (case-insensitive) and proposes [fixes] for it.
class FakeSpell implements EditorSpellService {
  final Map<String, List<String>> bad;
  final Set<String> dictionary = {};
  final List<String> learned = [];
  final List<String> ignored = [];
  FakeSpell(this.bad);

  @override
  Future<List<SuggestionSpan>> fetchSpellCheckSuggestions(Locale locale, String text) async {
    final out = <SuggestionSpan>[];
    for (final m in RegExp(r'\p{L}+', unicode: true).allMatches(text)) {
      final w = m.group(0)!.toLowerCase();
      if (bad.containsKey(w) && !dictionary.contains(w)) {
        out.add(SuggestionSpan(TextRange(start: m.start, end: m.end), bad[w]!));
      }
    }
    return out;
  }

  @override
  Future<void> learnWord(String word, {Locale? locale}) async {
    learned.add(word);
    dictionary.add(word.toLowerCase());
  }

  @override
  Future<void> ignoreWord(String word, {Locale? locale}) async => ignored.add(word);
}

void main() {
  final macOnly = TargetPlatformVariant.only(TargetPlatform.macOS);
  const text = 'I saw Teh cat and Ravenscar';
  const tehStart = 6; // "Teh"

  late MarkdownEditingController controller;
  late FocusNode focus;
  late FakeSpell spell;
  String? lastChange;

  Future<void> pump(WidgetTester tester, {List<NoteCard> notes = const []}) async {
    controller = MarkdownEditingController(text: text, theme: WriterTheme.presets.first);
    focus = FocusNode();
    lastChange = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpellCheckDriver(
          enabled: true,
          focusNode: focus,
          controller: controller,
          service: spell,
          notes: notes,
          child: TextField(
            controller: controller,
            focusNode: focus,
            maxLines: null,
            contextMenuBuilder: (c, s) => buildEditorContextMenu(c, s),
            onChanged: (v) => lastChange = v,
          ),
        ),
      ),
    ));
    await tester.pump(); // post-frame check starts
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> openMenu(WidgetTester tester, TextSelection sel) async {
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = sel;
    await tester.pump();
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pump();
  }

  // Desktop toolbar lists every item (the mobile one folds extras into an overflow).
  setUp(() => spell = FakeSpell({'teh': ['the', 'tea', 'ten'], 'ravenscar': ['raven scar']}));

  testWidgets('misspelled word under the caret: suggestions, Learn and Ignore', (tester) async {
    await pump(tester);
    expect(controller.misspellings.map((r) => r.textInside(text)), ['Teh', 'Ravenscar']);

    await openMenu(tester, const TextSelection.collapsed(offset: tehStart + 1));
    expect(find.text('the'), findsOneWidget);
    expect(find.text('tea'), findsOneWidget);
    expect(find.text('Learn spelling'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    expect(find.text('Add to attributions'), findsNothing, reason: 'no selection');
  }, variant: macOnly);

  testWidgets('picking a suggestion replaces just that word', (tester) async {
    await pump(tester);
    await openMenu(tester, const TextSelection.collapsed(offset: tehStart));
    await tester.tap(find.text('the'));
    await tester.pump();
    expect(controller.text, 'I saw the cat and Ravenscar');
    expect(lastChange, 'I saw the cat and Ravenscar');
  }, variant: macOnly);

  testWidgets('Learn spelling teaches the service and clears the underline', (tester) async {
    await pump(tester);
    await openMenu(tester, const TextSelection.collapsed(offset: tehStart + 2));
    await tester.tap(find.text('Learn spelling'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(spell.learned, ['Teh']);
    expect(controller.misspellings.map((r) => r.textInside(text)), ['Ravenscar']);
  }, variant: macOnly);

  testWidgets('Ignore silences the word for the session, not others', (tester) async {
    await pump(tester);
    await openMenu(tester, const TextSelection.collapsed(offset: tehStart));
    await tester.tap(find.text('Ignore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(spell.ignored, ['Teh']);
    expect(controller.misspellings.map((r) => r.textInside(text)), ['Ravenscar']);
    // Still ignored after an edit-triggered re-check.
    controller.text = '$text again teh';
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.misspellings.map((r) => r.textInside(controller.text)), ['Ravenscar']);
  }, variant: macOnly);

  testWidgets('a correctly spelled word gets no spelling items', (tester) async {
    await pump(tester);
    await openMenu(tester, const TextSelection.collapsed(offset: 2)); // "saw"
    expect(find.text('Learn spelling'), findsNothing);
    expect(find.text('Ignore'), findsNothing);
  }, variant: macOnly);

  testWidgets('codex names are known words and never underlined', (tester) async {
    await pump(tester, notes: [
      NoteCard(title: 'Ravenscar', content: ''),
      NoteCard(title: 'Attributions', content: '', isAttribution: true),
    ]);
    expect(controller.misspellings.map((r) => r.textInside(text)), ['Teh']);
  }, variant: macOnly);

  testWidgets('a note added later makes its name known', (tester) async {
    await pump(tester);
    expect(controller.misspellings.length, 2);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpellCheckDriver(
          enabled: true,
          focusNode: focus,
          controller: controller,
          service: spell,
          notes: [NoteCard(title: 'Teh Ravenscar', content: '')],
          child: TextField(controller: controller, focusNode: focus),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.misspellings, isEmpty);
  }, variant: macOnly);

  testWidgets('a selection adds Add to note and Add to attributions', (tester) async {
    await pump(tester);
    await openMenu(tester, const TextSelection(baseOffset: 2, extentOffset: 5)); // "saw"
    expect(find.textContaining('Add to note'), findsOneWidget);
    expect(find.text('Add to attributions'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Cut'), findsOneWidget);
  }, variant: macOnly);

  test('codexKnownWords splits titles into lower-case words and skips attributions', () {
    final words = codexKnownWords([
      NoteCard(title: 'Anna Ravenscar', content: ''),
      NoteCard(title: "O'Neil-Hart", content: ''),
      NoteCard(title: 'Secret', content: '', isAttribution: true),
    ]);
    expect(words, {'anna', 'ravenscar', "o'neil", 'hart'});
  });
}
