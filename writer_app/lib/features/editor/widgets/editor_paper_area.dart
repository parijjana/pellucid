import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_spell_check_service.dart';
import '../providers/theme_provider.dart';
import '../providers/editor_provider.dart';
import '../providers/codex_index.dart';
import '../../sidebar/providers/note_card.dart';
import 'codex_mention_detector.dart';
import 'markdown_controller.dart';
import 'grammar_hints.dart';
import 'smart_punctuation_scope.dart';

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
    this.grammarHintsEnabled = false,
    this.smartPunctuationEnabled = false,
  });

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
              const SingleActivator(LogicalKeyboardKey.tab): () {
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
              child: CodexMentionDetector(
              enabled: codexEnabled,
              theme: theme,
              index: codexIndex,
              notes: notes,
              onActivate: onOpenNote,
              child: _NativeSpellCheckDriver(
                enabled: spellCheckEnabled,
                focusNode: focusNode,
                controller: controller,
                child: GrammarHintDriver(
                enabled: grammarHintsEnabled,
                focusNode: focusNode,
                controller: controller,
                child: SmartPunctuationScope(
                enabled: smartPunctuationEnabled,
                controller: controller,
                onChanged: onChanged,
                builder: (context, formatters) => TextField(
                controller: controller,
                inputFormatters: formatters,
                focusNode: focusNode,
                maxLines: null,
                // The document could not be read, so we do not know what is on
                // disk. Accepting keystrokes here would invite the writer to
                // type into a blank page that can never be saved.
                readOnly: provider.documentLoadFailed,
                // macOS/Windows: off here, driven by _NativeSpellCheckDriver and
                // drawn by MarkdownEditingController, because EditableText's own
                // spell-check drawing replaces the markdown styling.
                spellCheckConfiguration: (spellCheckEnabled &&
                        !kIsWeb &&
                        !NativeSpellCheckService.isSupported &&
                        !Platform.environment.containsKey('FLUTTER_TEST'))
                    ? const SpellCheckConfiguration()
                    : const SpellCheckConfiguration.disabled(),
                cursorColor: theme.foregroundColor.withValues(alpha: 0.3),
                style: TextStyle(
                  color: theme.foregroundColor,
                  fontSize: 16 * zoomLevel,
                  height: 1.8,
                  fontFamily: 'Georgia',
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
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
    );
  }
}

bool get _nativeSpellCheckAvailable =>
    !kIsWeb &&
    NativeSpellCheckService.isSupported &&
    !Platform.environment.containsKey('FLUTTER_TEST');

/// Runs the OS spell checker over the manuscript and hands the misspelled
/// ranges to [MarkdownEditingController], which draws them. Checks when the
/// editor opens, shortly after typing pauses, and the moment the setting
/// flips (Alt+K, the macOS menu or Settings).
class _NativeSpellCheckDriver extends StatefulWidget {
  final bool enabled;
  final FocusNode focusNode;
  final TextEditingController controller;
  final Widget child;

  const _NativeSpellCheckDriver({
    required this.enabled,
    required this.focusNode,
    required this.controller,
    required this.child,
  });

  @override
  State<_NativeSpellCheckDriver> createState() => _NativeSpellCheckDriverState();
}

class _NativeSpellCheckDriverState extends State<_NativeSpellCheckDriver> {
  static const _service = NativeSpellCheckService();
  static const _pause = Duration(milliseconds: 400);

  Timer? _debounce;
  String? _checkedText;

  MarkdownEditingController? get _markdown {
    final c = widget.controller;
    return c is MarkdownEditingController ? c : null;
  }

  bool get _active => widget.enabled && _nativeSpellCheckAvailable && _markdown != null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(_NativeSpellCheckDriver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _checkedText = null;
    }
    if (oldWidget.enabled != widget.enabled || oldWidget.controller != widget.controller) {
      _debounce?.cancel();
      _check();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (!_active || widget.controller.text == _checkedText) return;
    _debounce?.cancel();
    _debounce = Timer(_pause, _check);
  }

  Future<void> _check() async {
    final markdown = _markdown;
    if (markdown == null) return;
    if (!_active) {
      _checkedText = null;
      if (markdown.misspellings.isNotEmpty) {
        markdown.setMisspellings(const []);
        _repaint();
      }
      return;
    }
    final text = markdown.text;
    final spans = text.isEmpty
        ? const <SuggestionSpan>[]
        : await _service.fetchSpellCheckSuggestions(
            Localizations.maybeLocaleOf(context) ?? const Locale('en', 'US'), text);
    // Stale: the writer kept typing (a newer check is queued) or it was
    // switched off while the OS was checking.
    if (!mounted || !_active || markdown.text != text) return;
    _checkedText = text;
    markdown.setMisspellings([for (final s in spans) s.range]);
    _repaint();
  }

  /// Rebuild the editor's spans without notifying the controller (whose
  /// listeners treat that as an edit), the same way EditableText applies its
  /// own spell-check results.
  void _repaint() {
    final editable = widget.focusNode.context?.findAncestorStateOfType<EditableTextState>();
    if (editable == null || !editable.mounted) return;
    editable.renderEditable.text = editable.buildTextSpan();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
