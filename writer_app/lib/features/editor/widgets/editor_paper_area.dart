import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_spell_check_service.dart';
import '../providers/theme_provider.dart';
import '../providers/editor_provider.dart';
import '../providers/codex_index.dart';
import '../providers/editor_font.dart';
import '../../sidebar/providers/note_card.dart';
import 'codex_mention_detector.dart';
import '../marker_aware_editing.dart';
import '../marker_edit_rules.dart';
import 'editor_context_menu.dart';
import 'spell_check_driver.dart';
import 'grammar_hints.dart';
import 'smart_punctuation_scope.dart';
import 'checklist_tap.dart';
import '../list_editing.dart';

/// Extra Redo binding for non-Apple platforms (see [EditorPaperArea]).
Map<ShortcutActivator, Intent> get _redoShortcuts =>
    (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS)
        ? const <ShortcutActivator, Intent>{}
        : const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyY, control: true):
                RedoTextIntent(SelectionChangedCause.keyboard),
          };

class EditorPaperArea extends StatelessWidget {
  final WriterTheme theme;
  final EditorProvider provider;
  final TextEditingController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool codexEnabled;
  final CodexIndex codexIndex;
  final List<NoteCard> notes;
  final void Function(String noteId) onOpenNote;
  final bool spellCheckEnabled;
  final EditorFont editorFont;

  /// Spell checker to use; defaults to the OS one (macOS/Windows). Tests pass a fake.
  final EditorSpellService? spellService;
  final bool grammarHintsEnabled;
  final bool smartPunctuationEnabled;

  const EditorPaperArea({
    super.key,
    required this.theme,
    required this.provider,
    required this.controller,
    required this.scrollController,
    required this.focusNode,
    required this.onChanged,
    required this.codexEnabled,
    required this.codexIndex,
    required this.notes,
    required this.onOpenNote,
    required this.spellCheckEnabled,
    this.spellService,
    this.editorFont = EditorFont.defaultFont,
    this.grammarHintsEnabled = false,
    this.smartPunctuationEnabled = false,
  });

  /// Tab / Shift+Tab inside a list moves the item one level. True when the
  /// key was a list key (even if nothing could move), false elsewhere.
  bool _indentList({required bool outdent}) {
    if (!selectionTouchesList(controller.text, controller.selection)) return false;
    final next = indentLines(controller.value, outdent: outdent);
    if (next != null) {
      controller.value = next;
      onChanged(next.text);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final zoomLevel = provider.zoomLevel;
    final pageWidth = provider.pageWidth;
    final horizontalPos = provider.horizontalPosition;

    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment(horizontalPos * 2 - 1, 0),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 100),
        child: Container(
          width: pageWidth,
          constraints: const BoxConstraints(minHeight: 1000),
          decoration: BoxDecoration(
            color: theme.backgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(60),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.tab, shift: true): () {
                // In a list: unindent the item. Elsewhere Shift+Tab is what it
                // always was (previous focus).
                if (_indentList(outdent: true)) return;
                focusNode.previousFocus();
              },
              const SingleActivator(LogicalKeyboardKey.tab): () {
                // In a list: indent the item (backlog items 2 and 8).
                if (_indentList(outdent: false)) return;
                final text = controller.text;
                final selection = controller.selection;
                if (selection.isValid) {
                  const indent = '    '; // four spaces
                  final newText = text.replaceRange(selection.start, selection.end, indent);
                  final newCursorPosition = selection.start + indent.length;
                  controller.value = TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(offset: newCursorPosition),
                  );
                  onChanged(newText);
                }
              },
            },
            // Ctrl+Y is the other Redo on Windows/Linux; Flutter's defaults
            // only bind Ctrl+Shift+Z (and Cmd+Shift+Z on macOS).
            child: Shortcuts(
              shortcuts: _redoShortcuts,
              child: ChecklistTapListener(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                child: CodexMentionDetector(
              enabled: codexEnabled,
              theme: theme,
              index: codexIndex,
              notes: notes,
              onActivate: onOpenNote,
              child: SpellCheckDriver(
                enabled: spellCheckEnabled,
                focusNode: focusNode,
                controller: controller,
                service: spellService,
                notes: notes,
                child: GrammarHintDriver(
                enabled: grammarHintsEnabled,
                focusNode: focusNode,
                controller: controller,
                child: SmartPunctuationScope(
                enabled: smartPunctuationEnabled,
                controller: controller,
                onChanged: onChanged,
                builder: (context, formatters) => MarkerAwareEditing(
                controller: controller,
                onTextChanged: onChanged,
                child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                // Hidden markdown markers stay balanced while editing (item 24).
                inputFormatters: [const MarkerEditFormatter(), ...formatters],
                // The document could not be read, so we do not know what is on
                // disk. Accepting keystrokes here would invite the writer to
                // type into a blank page that can never be saved.
                readOnly: provider.documentLoadFailed,
                // macOS/Windows: off here, driven by SpellCheckDriver and
                // drawn by MarkdownEditingController, because EditableText's own
                // spell-check drawing replaces the markdown styling.
                spellCheckConfiguration: (spellCheckEnabled &&
                        !kIsWeb &&
                        !NativeSpellCheckService.isSupported &&
                        !Platform.environment.containsKey('FLUTTER_TEST'))
                    ? const SpellCheckConfiguration()
                    : const SpellCheckConfiguration.disabled(),
                cursorColor: theme.foregroundColor.withValues(alpha: 0.3),
                style: editorFont.apply(TextStyle(
                  color: theme.foregroundColor,
                  fontSize: 16 * zoomLevel,
                  height: 1.8,
                )),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
                contextMenuBuilder: (context, editableTextState) =>
                    buildEditorContextMenu(context, editableTextState),
                onChanged: onChanged,
              ),
                ),
                ),
              ),
              ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
