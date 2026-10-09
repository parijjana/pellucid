// @trace BACKLOG-11
// Description: Grammar hints for the editor. A debounced driver (same rhythm as
// the spell-check driver) feeds GrammarChecker results to the controller, and
// an extension exposes lookup + fix for the right-click menu (slice 7).

import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/grammar_checker.dart';
import 'markdown_controller.dart';

extension GrammarHints on MarkdownEditingController {
  /// The hint under [offset] (the caret just after a word counts), or null.
  GrammarIssue? grammarIssueAt(int offset) {
    for (final i in grammarIssues) {
      if (offset >= i.range.start && offset <= i.range.end) return i;
    }
    return null;
  }

  /// Applies [issue]'s fix to the text and puts the caret after the change.
  /// Returns false when the issue is stale (the text there has moved on).
  /// This edits the controller's value like any edit, so the caller should
  /// also pass the new `text` to the editor's onChanged (autosave), as the Tab
  /// handler in EditorPaperArea does.
  bool applyGrammarFix(GrammarIssue issue) {
    final f = issue.fixRange;
    if (f.start < 0 || f.end > text.length || !grammarIssues.contains(issue)) return false;
    final newText = issue.applyTo(text);
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: f.start + issue.replacement.length),
    );
    return true;
  }
}

/// Runs [GrammarChecker] shortly after typing pauses and hands the issues to
/// the [MarkdownEditingController]. Checks when mounted and when [enabled]
/// flips; clears the hints when disabled.
class GrammarHintDriver extends StatefulWidget {
  final bool enabled;
  final FocusNode focusNode;
  final TextEditingController controller;
  final Widget child;

  const GrammarHintDriver({
    super.key,
    required this.enabled,
    required this.focusNode,
    required this.controller,
    required this.child,
  });

  @override
  State<GrammarHintDriver> createState() => _GrammarHintDriverState();
}

class _GrammarHintDriverState extends State<GrammarHintDriver> {
  static const _pause = Duration(milliseconds: 400);

  Timer? _debounce;
  String? _checkedText;
  // Exactly GrammarChecker.check(_checkedText): the base for incremental checks.
  List<GrammarIssue> _checkedIssues = const [];

  MarkdownEditingController? get _markdown {
    final c = widget.controller;
    return c is MarkdownEditingController ? c : null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(GrammarHintDriver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _checkedText = null;
      _checkedIssues = const [];
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
    if (!widget.enabled || widget.controller.text == _checkedText) return;
    _debounce?.cancel();
    _debounce = Timer(_pause, _check);
  }

  void _check() {
    final markdown = _markdown;
    if (!mounted || markdown == null) return;
    if (!widget.enabled) {
      _checkedText = null;
      _checkedIssues = const [];
      if (markdown.grammarIssues.isNotEmpty) {
        markdown.setGrammarIssues(const []);
        _repaint();
      }
      return;
    }
    final text = markdown.text;
    final before = _checkedText;
    // Re-check only the paragraphs changed since the last check.
    final issues = before == null
        ? GrammarChecker.check(text)
        : GrammarChecker.checkIncremental(before, _checkedIssues, text);
    _checkedText = text;
    _checkedIssues = issues;
    markdown.setGrammarIssues(issues);
    _repaint();
  }

  /// Rebuild the editor's spans without notifying the controller (whose
  /// listeners treat that as an edit), as the spell-check driver does.
  void _repaint() {
    final editable = widget.focusNode.context?.findAncestorStateOfType<EditableTextState>();
    if (editable == null || !editable.mounted) return;
    editable.renderEditable.text = editable.buildTextSpan();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
