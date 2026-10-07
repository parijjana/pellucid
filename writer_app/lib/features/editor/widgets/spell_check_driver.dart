import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../sidebar/providers/note_card.dart';
import '../services/native_spell_check_service.dart';
import 'markdown_controller.dart';

bool get _nativeSpellCheckAvailable =>
    !kIsWeb &&
    NativeSpellCheckService.isSupported &&
    !Platform.environment.containsKey('FLUTTER_TEST');

/// A misspelled word and what the spell checker proposed for it.
class SpellHit {
  final TextRange range;
  final String word;
  final List<String> suggestions;
  const SpellHit(this.range, this.word, this.suggestions);
}

/// Words that are never flagged: every word of a note title (codex names such
/// as characters and places), compared case-insensitively. The attribution
/// card is not part of the codex.
Set<String> codexKnownWords(List<NoteCard> notes) {
  final words = <String>{};
  for (final n in notes) {
    if (n.isAttribution) continue;
    for (final w in n.title.split(RegExp(r"[^\p{L}\p{N}'’]+", unicode: true))) {
      if (w.isNotEmpty) words.add(w.toLowerCase());
    }
  }
  return words;
}

/// Runs the OS spell checker over the manuscript and hands the misspelled
/// ranges to [MarkdownEditingController], which draws them. Checks when the
/// editor opens, shortly after typing pauses, and the moment the setting
/// flips (Alt+K, the macOS menu or Settings).
///
/// Also keeps the suggestions for the editor context menu ([hitAt]) and
/// performs Learn spelling / Ignore ([learn], [ignore]). Codex names and
/// ignored words are filtered out here, so span building never sees them.
class SpellCheckDriver extends StatefulWidget {
  final bool enabled;
  final FocusNode focusNode;
  final TextEditingController controller;
  final Widget child;

  /// Defaults to the OS checker, which exists on macOS and Windows only.
  final EditorSpellService? service;

  /// Project notes; their titles are known words.
  final List<NoteCard> notes;

  const SpellCheckDriver({
    super.key,
    required this.enabled,
    required this.focusNode,
    required this.controller,
    required this.child,
    this.service,
    this.notes = const [],
  });

  /// The driver above [context], or null when there is none.
  static SpellCheckDriverState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SpellScope>()?.state;

  @override
  State<SpellCheckDriver> createState() => SpellCheckDriverState();
}

class _SpellScope extends InheritedWidget {
  final SpellCheckDriverState state;
  const _SpellScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_SpellScope oldWidget) => false;
}

class SpellCheckDriverState extends State<SpellCheckDriver> {
  static const _pause = Duration(milliseconds: 400);

  Timer? _debounce;
  String? _checkedText;

  /// Lower-cased words ignored this session (also the fallback if the native
  /// call fails).
  final Set<String> _ignored = {};
  Set<String> _known = const {};
  // Suggestions from the latest check, by the word they were made for.
  Map<String, List<String>> _suggestions = const {};

  EditorSpellService get _service => widget.service ?? const NativeSpellCheckService();

  MarkdownEditingController? get _markdown {
    final c = widget.controller;
    return c is MarkdownEditingController ? c : null;
  }

  bool get _active =>
      widget.enabled && (widget.service != null || _nativeSpellCheckAvailable) && _markdown != null;

  Locale get _locale => Localizations.maybeLocaleOf(context) ?? const Locale('en', 'US');

  @override
  void initState() {
    super.initState();
    _known = codexKnownWords(widget.notes);
    widget.controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(SpellCheckDriver oldWidget) {
    super.didUpdateWidget(oldWidget);
    var recheck = false;
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _checkedText = null;
      recheck = true;
    }
    final known = codexKnownWords(widget.notes);
    if (!setEquals(known, _known)) {
      _known = known;
      recheck = true;
    }
    if (oldWidget.enabled != widget.enabled || recheck) {
      _debounce?.cancel();
      _checkedText = null;
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

  bool _isKnown(String word) {
    final w = word.toLowerCase();
    return _known.contains(w) || _ignored.contains(w);
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
        : await _service.fetchSpellCheckSuggestions(_locale, text) ?? const <SuggestionSpan>[];
    // Stale: the writer kept typing (a newer check is queued) or it was
    // switched off while the OS was checking.
    if (!mounted || !_active || markdown.text != text) return;
    _checkedText = text;
    final kept = <SuggestionSpan>[];
    final suggestions = <String, List<String>>{};
    for (final s in spans) {
      if (s.range.start < 0 || s.range.end > text.length) continue;
      final word = s.range.textInside(text);
      if (_isKnown(word)) continue;
      kept.add(s);
      suggestions[word] = s.suggestions;
    }
    _suggestions = suggestions;
    markdown.setMisspellings([for (final s in kept) s.range]);
    _repaint();
  }

  /// The misspelled word at [offset] (end of word included, so a caret just
  /// after it counts), or null.
  SpellHit? hitAt(int offset) {
    final markdown = _markdown;
    if (markdown == null || !_active) return null;
    for (final r in markdown.misspellings) {
      if (offset >= r.start && offset <= r.end && r.end <= markdown.text.length) {
        final word = r.textInside(markdown.text);
        return SpellHit(r, word, _suggestions[word] ?? const []);
      }
    }
    return null;
  }

  /// Learn spelling: add [word] to the user dictionary.
  Future<void> learn(String word) async {
    _ignored.add(word.toLowerCase()); // underline goes at once, even if native fails
    await _service.learnWord(word, locale: _locale);
    _checkedText = null;
    await _check();
  }

  /// Ignore: stop flagging [word] for this session.
  Future<void> ignore(String word) async {
    _ignored.add(word.toLowerCase());
    await _service.ignoreWord(word, locale: _locale);
    _checkedText = null;
    await _check();
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
  Widget build(BuildContext context) => _SpellScope(state: this, child: widget.child);
}
