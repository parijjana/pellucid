// Description: Hooks the hidden-marker rules (backlog item 24) into the
// editor's TextField: Left/Right arrows step over hidden markers, and
// copy/cut/paste go through RichClipboard. EditableText makes these actions
// overridable, so an ancestor Actions widget replaces them for this field only.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hidden_markers.dart';
import 'html_to_markdown.dart';
import 'marker_edit_rules.dart';
import 'rich_clipboard.dart';

EditableTextState? _editableOf(BuildContext? context) {
  final focused = FocusManager.instance.primaryFocus?.context;
  return (focused ?? context)?.findAncestorStateOfType<EditableTextState>() ??
      (context is StatefulElement && context.state is EditableTextState ? context.state as EditableTextState : null);
}

class MarkerAwareEditing extends StatelessWidget {
  final TextEditingController controller;
  final Widget child;

  const MarkerAwareEditing({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Paste as plain text (item 22): Cmd+Shift+V on Mac, Ctrl+Shift+V elsewhere.
        SingleActivator(LogicalKeyboardKey.keyV, shift: true, meta: mac, control: !mac): const PastePlainTextIntent(),
      },
      child: Actions(
      actions: <Type, Action<Intent>>{
        PastePlainTextIntent: _PastePlainAction(),
        ExtendSelectionByCharacterIntent: _StepAction(controller),
        CopySelectionTextIntent: _CopyAction(controller),
        PasteTextIntent: _PasteAction(controller),
        UndoTextIntent: _UndoRedoAction<UndoTextIntent>(),
        RedoTextIntent: _UndoRedoAction<RedoTextIntent>(),
      },
      child: child,
      ),
    );
  }

  /// The editor's right-click/long-press menu with copy, cut and paste routed
  /// through the same rules as the shortcuts.
  static Widget contextMenu(BuildContext context, EditableTextState state) {
    return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors, buttonItems: routedButtonItems(state));
  }

  /// The field's default cut/copy/paste/select-all items, with cut, copy and
  /// paste routed through [markerCopy] / [markerPaste]. The editor's own menu
  /// (editor_context_menu.dart) builds on these.
  static List<ContextMenuButtonItem> routedButtonItems(EditableTextState state) {
    return [
      for (final item in state.contextMenuButtonItems)
        switch (item.type) {
          ContextMenuButtonType.copy => item.copyWith(onPressed: () {
              markerCopy(state, cut: false);
              state.hideToolbar();
            }),
          ContextMenuButtonType.cut => item.copyWith(onPressed: () {
              markerCopy(state, cut: true);
              state.hideToolbar();
            }),
          ContextMenuButtonType.paste => item.copyWith(onPressed: () {
              markerPaste(state, SelectionChangedCause.toolbar);
              state.hideToolbar();
            }),
          _ => item,
        },
    ];
  }

  /// "Paste as plain text" for the context menu, or null when the field is read-only.
  static ContextMenuButtonItem? pastePlainItem(EditableTextState state) {
    if (state.widget.readOnly) return null;
    return ContextMenuButtonItem(
      label: 'Paste as plain text',
      onPressed: () {
        markerPastePlain(state, SelectionChangedCause.toolbar);
        state.hideToolbar();
      },
    );
  }
}

class _StepAction extends ContextAction<ExtendSelectionByCharacterIntent> {
  final TextEditingController controller;
  _StepAction(this.controller);

  @override
  Object? invoke(ExtendSelectionByCharacterIntent intent, [BuildContext? context]) {
    final value = controller.value;
    final sel = value.selection;
    if (!sel.isValid) return null;
    final text = value.text;
    TextSelection next;
    if (intent.collapseSelection) {
      if (!sel.isCollapsed) {
        next = TextSelection.collapsed(offset: canonicalOffset(text, intent.forward ? sel.end : sel.start));
      } else {
        final p = intent.forward ? stepRight(text, sel.extentOffset) : stepLeft(text, sel.extentOffset);
        next = TextSelection.collapsed(offset: p);
      }
    } else {
      final p = intent.forward ? stepRight(text, sel.extentOffset) : stepLeft(text, sel.extentOffset);
      next = sel.extendTo(TextPosition(offset: p));
    }
    final state = _editableOf(context);
    if (state != null) {
      state.userUpdateTextEditingValue(value.copyWith(selection: next), SelectionChangedCause.keyboard);
      state.bringIntoView(next.extent);
    } else {
      controller.selection = next;
    }
    return null;
  }
}

/// Copies (and for [cut], deletes) the field's selection.
Future<void> markerCopy(EditableTextState state, {required bool cut}) async {
  final value = state.textEditingValue;
  final sel = value.selection;
  if (!sel.isValid || sel.isCollapsed) return;
  await RichClipboard.copy(value.text, sel.start, sel.end);
  if (cut && !state.widget.readOnly) {
    final now = state.textEditingValue;
    state.userUpdateTextEditingValue(
      TextEditingValue(
        text: now.text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      ),
      SelectionChangedCause.toolbar,
    );
  }
}

/// Paste as plain text (item 22): the clipboard's text, no conversion.
class PastePlainTextIntent extends Intent {
  const PastePlainTextIntent([this.cause = SelectionChangedCause.keyboard]);
  final SelectionChangedCause cause;
}

class _PastePlainAction extends ContextAction<PastePlainTextIntent> {
  @override
  Object? invoke(PastePlainTextIntent intent, [BuildContext? context]) {
    final state = _editableOf(context);
    if (state == null) return null;
    markerPastePlain(state, intent.cause);
    return null;
  }
}

/// Pastes the clipboard's plain text as is. This is the plain-text flavour of
/// the field's normal paste: no markdown, no HTML conversion.
Future<void> markerPastePlain(EditableTextState state, SelectionChangedCause cause) async {
  if (state.widget.readOnly) return;
  await state.pasteText(cause);
}

/// Pastes Pellucid's own markdown when the clipboard holds it, otherwise
/// formatted text from another app converted to markdown (item 22), otherwise
/// the field's normal (plain) paste.
Future<void> markerPaste(EditableTextState state, SelectionChangedCause cause) async {
  if (state.widget.readOnly) return;
  var markdown = await RichClipboard.readMarkdown();
  if (markdown == null) {
    final html = await RichClipboard.readHtml();
    if (html != null && html.isNotEmpty) {
      final converted = htmlToMarkdown(html);
      if (converted != null) {
        // Only when the HTML says more than the plain text does; otherwise the
        // plain paste keeps the text exactly as copied (code, spacing).
        final plain = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        if (htmlAddsStructure(converted, plain)) markdown = converted;
      }
    }
  }
  if (markdown == null) {
    await state.pasteText(cause);
    return;
  }
  final value = state.textEditingValue;
  final sel = value.selection;
  if (!sel.isValid) return;
  final caret = sel.start + markdown.length;
  state.userUpdateTextEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(sel.start, sel.end, markdown),
      selection: TextSelection.collapsed(offset: caret),
    ),
    cause,
  );
  state.bringIntoView(state.textEditingValue.selection.extent);
}

class _CopyAction extends ContextAction<CopySelectionTextIntent> {
  final TextEditingController controller;
  _CopyAction(this.controller);

  @override
  Object? invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    final state = _editableOf(context);
    if (state == null) return null;
    markerCopy(state, cut: intent.collapseSelection);
    return null;
  }
}

class _PasteAction extends ContextAction<PasteTextIntent> {
  final TextEditingController controller;
  _PasteAction(this.controller);

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    final state = _editableOf(context);
    if (state == null) return null;
    markerPaste(state, intent.cause);
    return null;
  }
}

/// Undo/redo run the field's own history with the marker rules off, so the
/// recorded value is restored exactly.
class _UndoRedoAction<T extends Intent> extends ContextAction<T> {
  @override
  bool isEnabled(T intent, [BuildContext? context]) => callingAction?.isEnabled(intent) ?? false;

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    markerRulesSuspended++;
    try {
      return callingAction?.invoke(intent);
    } finally {
      markerRulesSuspended--;
    }
  }
}
