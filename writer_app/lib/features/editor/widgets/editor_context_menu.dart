// Description: The editor's one right-click menu. Spelling suggestions (with
// Learn spelling / Ignore) for a misspelled word, the usual cut/copy/paste, and
// "Add to note" / "Add to attributions" for a selection.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../sidebar/providers/notes_provider.dart';
import '../marker_aware_editing.dart';
import 'editor_selection_actions.dart';
import 'grammar_hints.dart';
import 'markdown_controller.dart';
import 'spell_check_driver.dart';

const _newNote = '\u0000new';

Widget buildEditorContextMenu(BuildContext context, EditableTextState editable) {
  final value = editable.textEditingValue;
  final sel = value.selection;
  final items = <ContextMenuButtonItem>[];

  // Spelling: the word under the caret, or a selection that is exactly one
  // misspelled word.
  final driver = SpellCheckDriver.maybeOf(editable.context);
  final hit = (driver == null || !sel.isValid)
      ? null
      : driver.hitAt(sel.isCollapsed ? sel.baseOffset : sel.start);
  if (driver != null &&
      hit != null &&
      (sel.isCollapsed || (sel.start >= hit.range.start && sel.end <= hit.range.end))) {
    for (final s in hit.suggestions.take(5)) {
      items.add(ContextMenuButtonItem(
        label: s,
        onPressed: () {
          editable.hideToolbar();
          final text = value.text.replaceRange(hit.range.start, hit.range.end, s);
          editable.userUpdateTextEditingValue(
            TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: hit.range.start + s.length),
            ),
            SelectionChangedCause.toolbar,
          );
        },
      ));
    }
    items.add(ContextMenuButtonItem(
      label: 'Learn spelling',
      onPressed: () {
        editable.hideToolbar();
        driver.learn(hit.word);
      },
    ));
    items.add(ContextMenuButtonItem(
      label: 'Ignore',
      onPressed: () {
        editable.hideToolbar();
        driver.ignore(hit.word);
      },
    ));
  }

  // Grammar hint under the caret (slice 8 checker): offer its fix.
  final markdown = editable.widget.controller;
  final issue = (markdown is MarkdownEditingController && sel.isValid && sel.isCollapsed)
      ? markdown.grammarIssueAt(sel.baseOffset)
      : null;
  if (issue != null) {
    final word = issue.replacement.trim();
    items.add(ContextMenuButtonItem(
      label: word.isEmpty ? 'Remove repeated word' : 'Use “$word”',
      onPressed: () {
        editable.hideToolbar();
        final f = issue.fixRange;
        editable.userUpdateTextEditingValue(
          TextEditingValue(
            text: issue.applyTo(value.text),
            selection: TextSelection.collapsed(offset: f.start + issue.replacement.length),
          ),
          SelectionChangedCause.toolbar,
        );
      },
    ));
  }

  // Cut / copy / paste / select all, with copy and paste keeping hidden
  // markers balanced and putting rich text on the clipboard (item 24).
  items.addAll(MarkerAwareEditing.routedButtonItems(editable));

  final selected = (sel.isValid && !sel.isCollapsed) ? sel.textInside(value.text) : '';
  if (selected.trim().isNotEmpty) {
    final anchor = editable.contextMenuAnchors.primaryAnchor;
    items.add(ContextMenuButtonItem(
      label: 'Add to note ▸',
      onPressed: () {
        editable.hideToolbar();
        _pickNote(editable.context, anchor, selected);
      },
    ));
    items.add(ContextMenuButtonItem(
      label: 'Add to attributions',
      onPressed: () {
        editable.hideToolbar();
        EditorSelectionActions.addToAttributions(editable.context, selected);
      },
    ));
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editable.contextMenuAnchors,
    buttonItems: items,
  );
}

/// The "Add to note" submenu: "New note" first, then the project's notes.
Future<void> _pickNote(BuildContext context, Offset anchor, String selected) async {
  final notes = EditorSelectionActions.targetNotes(context.read<NotesProvider>().cards);
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(anchor.dx, anchor.dy, anchor.dx, anchor.dy),
    items: [
      const PopupMenuItem(value: _newNote, child: Text('New note')),
      if (notes.isNotEmpty) const PopupMenuDivider(),
      for (final n in notes)
        PopupMenuItem(value: n.id, child: Text(n.title.isEmpty ? 'Untitled' : n.title)),
    ],
  );
  if (choice == null || !context.mounted) return;
  if (choice == _newNote) {
    EditorSelectionActions.addToNewNote(context, selected);
  } else {
    EditorSelectionActions.addToExistingNote(context, choice, selected);
  }
}
