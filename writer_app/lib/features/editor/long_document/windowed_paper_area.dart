// Description: Hook from EditorPaperArea into the windowed editor (slice 3b).
// Builds the same wrappers as the single editor, but the ones that act on the
// field's text (smart punctuation, marker-aware editing) get the window's
// controller, and the ones that check the whole document (spelling, grammar,
// Codex mentions) keep the document controller.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../list_editing.dart';
import '../marker_aware_editing.dart';
import '../marker_edit_rules.dart';
import '../widgets/checklist_tap.dart';
import '../widgets/codex_mention_detector.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/editor_paper_area.dart';
import '../widgets/grammar_hints.dart';
import '../widgets/markdown_controller.dart';
import '../widgets/smart_punctuation_scope.dart';
import '../widgets/spell_check_driver.dart';
import 'windowed_editor.dart';

/// Which documents are in windowed mode. Once on, a document stays on until
/// it shrinks well below the threshold, so typing across the threshold never
/// swaps editors under the caret.
final Expando<bool> _windowedOn = Expando<bool>('windowedEditor');

/// Characters per word used to turn the word threshold into an O(1) length
/// check (the build must not count words).
const int _charsPerWord = 6;

@visibleForTesting
bool debugForceWindowedEditor = false;

bool useWindowedEditor(TextEditingController controller) {
  if (!(kWindowedEditorFlag || debugForceWindowedEditor) || controller is! MarkdownEditingController) return false;
  final int on = kWindowedEditorMinWords * _charsPerWord;
  final bool was = _windowedOn[controller] ?? false;
  final bool now = was ? controller.text.length >= on * 0.8 : controller.text.length >= on;
  _windowedOn[controller] = now;
  return now;
}

/// The windowed editor for [area], or null when the single editor is used.
Widget? windowedPaperArea(EditorPaperArea area) {
  if (!useWindowedEditor(area.controller)) return null;
  final doc = area.controller as MarkdownEditingController;
  final style = area.editorFont.apply(
    TextStyle(color: area.theme.foregroundColor, fontSize: 16 * area.provider.zoomLevel, height: 1.8),
  );
  return CodexMentionDetector(
    enabled: area.codexEnabled,
    theme: area.theme,
    index: area.codexIndex,
    notes: area.notes,
    onActivate: area.onOpenNote,
    offsetAt: (global) => windowedEditorFor(doc)?.docOffsetAtPoint(global),
    child: SpellCheckDriver(
      enabled: area.spellCheckEnabled,
      focusNode: area.focusNode,
      controller: doc,
      service: area.spellService,
      notes: area.notes,
      child: GrammarHintDriver(
        enabled: area.grammarHintsEnabled,
        focusNode: area.focusNode,
        controller: doc,
        child: WindowedEditor(
          controller: doc,
          focusNode: area.focusNode,
          theme: area.theme,
          style: style,
          pageWidth: area.provider.pageWidth,
          horizontalPosition: area.provider.horizontalPosition,
          cursorColor: area.theme.foregroundColor.withValues(alpha: 0.3),
          readOnly: area.provider.documentLoadFailed,
          inputFormatters: const <TextInputFormatter>[MarkerEditFormatter()],
          contextMenuBuilder: (context, editableTextState) => buildEditorContextMenu(
            context,
            editableTextState,
            documentOffset: windowedEditorFor(doc)?.window.windowStart ?? 0,
          ),
          onChanged: area.onChanged,
          // Everything that edits the field's text acts on the window; the
          // windowed editor mirrors each change into the document (and
          // onChanged), so these wrappers get no-op change callbacks.
          wrapField: (window, field) => CallbackShortcuts(
            bindings: _tabBindings(window, area.focusNode),
            child: ChecklistTapListener(
              controller: window,
              focusNode: area.focusNode,
              onChanged: (_) {},
              child: SmartPunctuationScope(
                enabled: area.smartPunctuationEnabled,
                controller: window,
                onChanged: (_) {},
                builder: (context, formatters) => MarkerAwareEditing(
                  controller: window,
                  onTextChanged: (_) {},
                  child: Listener(onPointerDown: (_) => area.typewriterPause?.pointerDown(), child: field(formatters)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Tab / Shift+Tab as in the single editor (editor_paper_area.dart): indent
/// or outdent a list item, otherwise Tab types four spaces and Shift+Tab
/// moves focus back.
Map<ShortcutActivator, VoidCallback> _tabBindings(TextEditingController window, FocusNode focusNode) {
  bool indentList({required bool outdent}) {
    if (!selectionTouchesList(window.text, window.selection)) return false;
    final next = indentLines(window.value, outdent: outdent);
    if (next != null) window.value = next;
    return true;
  }

  return {
    const SingleActivator(LogicalKeyboardKey.tab, shift: true): () {
      if (indentList(outdent: true)) return;
      focusNode.previousFocus();
    },
    const SingleActivator(LogicalKeyboardKey.tab): () {
      if (indentList(outdent: false)) return;
      final selection = window.selection;
      if (selection.isValid) {
        const indent = '    ';
        window.value = TextEditingValue(
          text: window.text.replaceRange(selection.start, selection.end, indent),
          selection: TextSelection.collapsed(offset: selection.start + indent.length),
        );
      }
    },
  };
}
