// Description: "Add to note" / "Add to attributions" for the editor selection.
// One implementation behind the context menu and the Add-note / attribution
// shortcuts, so the two can never drift.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sidebar/providers/note_card.dart';
import '../../sidebar/providers/notes_provider.dart';
import '../../sidebar/widgets/note_editor_dialog.dart';
import '../../sync/providers/sync_provider.dart';
import '../providers/editor_provider.dart';
import '../rich_clipboard.dart';

/// The manuscript controller of the open editor, so app-level shortcuts
/// (main.dart) can read the current selection.
class ActiveEditor {
  static TextEditingController? controller;

  /// Selected manuscript text, or null when nothing (or only blanks) is selected.
  static String? get selectedText {
    final c = controller;
    if (c == null) return null;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed || sel.end > c.text.length) return null;
    final text = sel.textInside(c.text);
    return text.trim().isEmpty ? null : text;
  }
}

class EditorSelectionActions {
  EditorSelectionActions._();

  /// Copies the way the editor's Copy does (item 24): rich text and
  /// marker-free plain text for other apps, markdown for Pellucid. Uses the
  /// live selection when it is the text being added, so a run cut by the
  /// selection is closed properly; otherwise copies [selection] on its own.
  static Future<void> copySelection(String selection) {
    final c = ActiveEditor.controller;
    final sel = c?.selection;
    if (c != null && sel != null && sel.isValid && !sel.isCollapsed &&
        sel.end <= c.text.length && sel.textInside(c.text) == selection) {
      return RichClipboard.copy(c.text, sel.start, sel.end);
    }
    return RichClipboard.copy(selection, 0, selection.length);
  }

  /// "Add to note", New note: selection into a new note, note editor opens.
  static void addToNewNote(BuildContext context, String selection) {
    copySelection(selection);
    final notes = context.read<NotesProvider>();
    final id = notes.addNoteFromSelection(selection, syncProvider: context.read<SyncProvider>());
    showDialog(context: context, builder: (_) => NoteEditorDialog(noteId: id));
  }

  /// "Add to note", existing note: appended as a new paragraph.
  static void addToExistingNote(BuildContext context, String noteId, String selection) {
    copySelection(selection);
    context
        .read<NotesProvider>()
        .appendToNote(noteId, selection, syncProvider: context.read<SyncProvider>());
  }

  /// "Add to attributions": always a new item; card created when missing.
  static void addToAttributions(BuildContext context, String selection) {
    copySelection(selection);
    final notes = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final card = notes.addAttributionItem(selection, syncProvider: sync);
    context.read<EditorProvider>().syncAttributions(
          card,
          syncProvider: sync,
          projectName: context.read<SettingsProvider>().currentProjectName,
        );
    showDialog(context: context, builder: (_) => NoteEditorDialog(noteId: card.id));
  }

  /// Notes offered in the "Add to note" submenu (the attribution card has its own item).
  static List<NoteCard> targetNotes(List<NoteCard> cards) =>
      [for (final c in cards) if (!c.isAttribution) c];
}
