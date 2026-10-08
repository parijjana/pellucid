// Description: Windowed editor for long documents (slice 3b, backlog item 23).
//
// One EditableText holding the whole manuscript re-lays out every line on
// every keystroke (~0.3-0.45 s at 100k words). Here the live field holds only
// a window of ~4,000 characters around the caret; every other line is a
// static, lazily built RichText styled by the same span builder
// (MarkdownEditingController.buildLineSpans). Typing costs one window layout
// whatever the document size.
//
// The screen's MarkdownEditingController stays the document of record: every
// edit made in the window is mirrored into it (text, selection, composing),
// so word count, TOC, Find, autosave and every other reader keep working on
// whole-document offsets. Changes made to it from outside (formatting
// commands, Replace, document load) are mirrored back into the window.
//
// Behind a flag until it does everything the single editor does
// (PLAN_3b_EDITOR.md). Phase 1: typing, caret and window moves, clicks on
// static lines, styling parity, document-level undo/redo.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../providers/theme_provider.dart';
import '../utils/grammar_checker.dart';
import '../widgets/markdown_controller.dart';
import 'document_buffer.dart';

/// Developer switch for phase 1: `--dart-define=PELLUCID_WINDOWED_EDITOR=true`.
const bool kWindowedEditorFlag = bool.fromEnvironment('PELLUCID_WINDOWED_EDITOR');

/// Documents at or above this many words open in the windowed editor when the
/// flag is on (PLAN_3b_EDITOR.md owner question 1, recommended answer).
const int kWindowedEditorMinWords = int.fromEnvironment('PELLUCID_WINDOWED_MIN_WORDS', defaultValue: 15000);

/// Characters kept in the live window (spike: ~25 normal lines; a 200-line
/// window already costs 12 ms per keystroke, markup-heavy text more).
const int kWindowBudgetChars = 4000;

/// The window moves when the caret comes this close to one of its edges.
const int kWindowEdgeMarginChars = 600;
const int kWindowEdgeMarginLines = 2;

/// Lines [first, last) of the document are live; the rest are static.
class EditorWindow {
  final int first;
  final int last;
  const EditorWindow(this.first, this.last);
  int get lineCount => last - first;
  @override
  String toString() => 'EditorWindow($first, $last)';
}

/// Picks the window of whole lines around [from]..[to] (document offsets):
/// those lines, then neighbours alternately below and above until [budget]
/// characters. Pure, for tests.
EditorWindow planWindow(DocumentBuffer buffer, int from, int to, {int budget = kWindowBudgetChars}) {
  int first = buffer.lineOfOffset(min(from, to));
  int last = buffer.lineOfOffset(max(from, to)) + 1;
  int size = buffer.lineEnd(last - 1) - buffer.lineStart(first);
  bool below = true;
  while (size < budget && (first > 0 || last < buffer.lineCount)) {
    if ((below && last < buffer.lineCount) || first == 0) {
      size += buffer.line(last).length + 1;
      last++;
    } else {
      first--;
      size += buffer.line(first).length + 1;
    }
    below = !below;
  }
  return EditorWindow(first, last);
}

/// The live field's controller: a MarkdownEditingController over the window
/// text whose spelling/grammar ranges are copied (line-relative) from the
/// document controller just before each span build, because the drivers set
/// them on the document controller without notifying.
class WindowFieldController extends MarkdownEditingController {
  WindowFieldController({required super.theme, required this.document});

  final MarkdownEditingController document;

  /// Document offset of this controller's text start.
  int windowStart = 0;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final int end = windowStart + text.length;
    setMisspellings(rangesInside(document.misspellings, windowStart, end));
    setGrammarIssues(grammarInside(document.grammarIssues, windowStart, end));
    return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
  }
}

/// Index of the first of [items] (sorted, non-overlapping) ending after [offset].
int _firstEndingAfter<T>(List<T> items, int offset, int Function(T) endOf) {
  int lo = 0, hi = items.length;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (endOf(items[mid]) <= offset) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// [ranges] (sorted, document offsets) clipped to [start, end) and shifted so
/// [start] is 0.
List<TextRange> rangesInside(List<TextRange> ranges, int start, int end) {
  final out = <TextRange>[];
  for (int i = _firstEndingAfter(ranges, start, (r) => r.end);
      i < ranges.length && ranges[i].start < end;
      i++) {
    final r = ranges[i];
    out.add(TextRange(start: max(r.start, start) - start, end: min(r.end, end) - start));
  }
  return out;
}

List<GrammarIssue> grammarInside(List<GrammarIssue> issues, int start, int end) {
  final out = <GrammarIssue>[];
  for (int i = _firstEndingAfter(issues, start, (g) => g.range.end);
      i < issues.length && issues[i].range.start < end;
      i++) {
    final g = issues[i];
    if (g.range.start < start || g.range.end > end) continue;
    out.add(GrammarIssue(
      range: TextRange(start: g.range.start - start, end: g.range.end - start),
      fixRange: TextRange(start: g.fixRange.start - start, end: g.fixRange.end - start),
      replacement: g.replacement,
      ruleId: g.ruleId,
      message: g.message,
    ));
  }
  return out;
}

/// One recorded document edit, for the windowed editor's own undo history.
/// The field's built-in history cannot be used: moving the window replaces
/// the field's text, which that history would record as an edit.
class _DocEdit {
  final int start;
  String removed;
  String inserted;
  final TextSelection before;
  TextSelection after;
  DateTime at;
  _DocEdit(this.start, this.removed, this.inserted, this.before, this.after, this.at);
}

class WindowedEditor extends StatefulWidget {
  /// The document of record (the screen's controller).
  final MarkdownEditingController controller;
  final FocusNode focusNode;
  final WriterTheme theme;
  final TextStyle style;
  final double pageWidth;
  final double horizontalPosition;
  final Color cursorColor;
  final bool readOnly;
  final List<TextInputFormatter> inputFormatters;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  /// Called with the whole document text after each edit made in the window.
  final ValueChanged<String> onChanged;

  /// Wraps the live field (MarkerAwareEditing, SmartPunctuationScope, ...)
  /// with the window controller those wrappers must act on; [field] builds
  /// the field with any extra input formatters a wrapper supplies.
  final Widget Function(WindowFieldController window, Widget Function(List<TextInputFormatter> extra) field)?
      wrapField;

  const WindowedEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.style,
    required this.pageWidth,
    required this.horizontalPosition,
    required this.cursorColor,
    required this.onChanged,
    this.readOnly = false,
    this.inputFormatters = const [],
    this.contextMenuBuilder,
    this.wrapField,
  });

  @override
  State<WindowedEditor> createState() => WindowedEditorState();
}

class WindowedEditorState extends State<WindowedEditor> {
  late DocumentBuffer buffer;
  late WindowFieldController window;
  EditorWindow span = const EditorWindow(0, 0);
  final ScrollController scroll = ScrollController();
  final Key _centerKey = UniqueKey();
  final GlobalKey _fieldKey = GlobalKey();

  String _lastWindowText = '';
  String? _lastDocText;
  bool _applying = false; // our own write to the window or the document
  bool _movePending = false;

  final List<_DocEdit> _undo = [];
  final List<_DocEdit> _redo = [];
  static const Duration _coalesceGap = Duration(milliseconds: 800);

  late final _StaticLines _static = _StaticLines(widget.controller);

  /// Number of window moves (tests and the perf harness read it).
  int windowMoves = 0;

  MarkdownEditingController get doc => widget.controller;

  @override
  void initState() {
    super.initState();
    buffer = DocumentBuffer(doc.text);
    _lastDocText = doc.text;
    window = WindowFieldController(theme: doc.theme, document: doc);
    _copySettings();
    final sel = doc.selection.isValid ? doc.selection : const TextSelection.collapsed(offset: 0);
    _load(planWindow(buffer, sel.start, sel.end), sel);
    window.addListener(_onWindowChanged);
    doc.addListener(_onDocChanged);
  }

  @override
  void didUpdateWidget(WindowedEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onDocChanged);
      widget.controller.addListener(_onDocChanged);
      _resetFromDoc();
    }
  }

  @override
  void dispose() {
    window.removeListener(_onWindowChanged);
    doc.removeListener(_onDocChanged);
    window.dispose();
    scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- window

  /// Loads lines [w.first, w.last) into the field with [docSelection].
  void _load(EditorWindow w, TextSelection docSelection) {
    span = w;
    window.windowStart = buffer.lineStart(w.first);
    final text = buffer.textOfLines(w.first, w.last);
    _lastWindowText = text;
    _applying = true;
    window.value = TextEditingValue(text: text, selection: _toWindow(docSelection));
    // A move started here (a click on a static line, undo) also moves the
    // document's selection; one started by the document already matches.
    if (doc.selection != docSelection) {
      doc.value = doc.value.copyWith(selection: docSelection, composing: TextRange.empty);
      _lastDocText = doc.text;
    }
    _applying = false;
  }

  TextSelection _toWindow(TextSelection s) {
    final int n = _lastWindowText.length;
    int c(int o) => (o - window.windowStart).clamp(0, n);
    return s.copyWith(baseOffset: c(s.baseOffset), extentOffset: c(s.extentOffset));
  }

  TextSelection _toDoc(TextSelection s) => s.isValid
      ? s.copyWith(baseOffset: s.baseOffset + window.windowStart, extentOffset: s.extentOffset + window.windowStart)
      : s;

  TextRange _rangeToDoc(TextRange r) =>
      r.isValid ? TextRange(start: r.start + window.windowStart, end: r.end + window.windowStart) : r;

  /// Moves the window so [docSelection] sits in its middle, keeping the caret
  /// at the same place on screen.
  void moveWindowTo(TextSelection docSelection) {
    final double? before = _caretScreenY();
    _load(planWindow(buffer, docSelection.start, docSelection.end), docSelection);
    windowMoves++;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final double? after = _caretScreenY();
      if (before != null && after != null && (after - before).abs() > 0.5) {
        scroll.jumpTo(scroll.offset + (after - before));
      } else if (before == null && after != null) {
        // The caret was off screen (a jump): bring it to a third of the view.
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final double top = box.localToGlobal(Offset.zero).dy;
          scroll.jumpTo(scroll.offset + (after - top) - box.size.height / 3);
        }
      }
    });
  }

  RenderEditable? _fieldRender() {
    RenderEditable? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final ro = _fieldKey.currentContext?.findRenderObject();
    if (ro != null) visit(ro);
    return found;
  }

  double? _caretScreenY() {
    final re = _fieldRender();
    if (re == null || !re.attached || !re.hasSize || !window.selection.isValid) return null;
    final rect = re.getLocalRectForCaret(TextPosition(offset: window.selection.extentOffset));
    return re.localToGlobal(rect.topLeft).dy;
  }

  bool _nearEdge(TextSelection s) {
    if (!s.isValid) return false;
    final int lo = min(s.start, s.end), hi = max(s.start, s.end);
    final bool topOpen = span.first > 0;
    final bool bottomOpen = span.last < buffer.lineCount;
    final int loLine = buffer.lineOfOffset(lo + window.windowStart) - span.first;
    final int hiLine = buffer.lineOfOffset(hi + window.windowStart) - span.first;
    final bool nearTop = topOpen && (lo < kWindowEdgeMarginChars || loLine < kWindowEdgeMarginLines);
    final bool nearBottom = bottomOpen &&
        (window.text.length - hi < kWindowEdgeMarginChars || span.lineCount - 1 - hiLine < kWindowEdgeMarginLines);
    return nearTop || nearBottom;
  }

  bool get _composing => window.value.composing.isValid && !window.value.composing.isCollapsed;

  void _maybeMove() {
    if (_composing) {
      _movePending = true;
      return;
    }
    if (!_nearEdge(window.selection)) {
      _movePending = false;
      return;
    }
    _movePending = false;
    final docSel = _toDoc(window.selection);
    // After the current frame: the field must finish handling the key first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_composing) moveWindowTo(docSel);
    });
  }

  // ------------------------------------------------- window -> document

  void _onWindowChanged() {
    if (_applying) return;
    final wv = window.value;
    if (wv.text != _lastWindowText) {
      final d = diffReplacement(_lastWindowText, wv.text);
      final int start = window.windowStart + d.start;
      final int end = window.windowStart + d.end;
      final String removed = _lastWindowText.substring(d.start, d.end);
      final TextSelection before = doc.selection;
      _lastWindowText = wv.text;
      _applyToBuffer(start, end, d.inserted);
      _writeDoc(start, end, d.inserted, _toDoc(wv.selection), _rangeToDoc(wv.composing));
      _record(start, removed, d.inserted, before, doc.selection);
      widget.onChanged(doc.text);
    } else if (_toDoc(wv.selection) != doc.selection || _rangeToDoc(wv.composing) != doc.value.composing) {
      _applying = true;
      doc.value = doc.value.copyWith(selection: _toDoc(wv.selection), composing: _rangeToDoc(wv.composing));
      _lastDocText = doc.text;
      _applying = false;
    }
    if (_movePending || _nearEdge(wv.selection)) _maybeMove();
  }

  void _applyToBuffer(int start, int end, String inserted) {
    final int firstBefore = span.first;
    final int linesBefore = buffer.lineCount;
    buffer.replace(start, end, inserted);
    // Edits made in the window stay in it: the window grows or shrinks by the
    // change in line count.
    span = EditorWindow(firstBefore, span.last + buffer.lineCount - linesBefore);
  }

  void _writeDoc(int start, int end, String inserted, TextSelection selection, TextRange composing) {
    _applying = true;
    doc.value = TextEditingValue(
      text: doc.text.replaceRange(start, end, inserted),
      selection: selection,
      composing: composing,
    );
    _lastDocText = doc.text;
    _applying = false;
  }

  // ------------------------------------------------- document -> window

  void _onDocChanged() {
    if (_applying) return;
    _copySettings();
    if (!identical(doc.text, _lastDocText) && doc.text != buffer.text) {
      // An edit made outside the window (formatting command, Replace, load).
      final d = diffReplacement(buffer.text, doc.text);
      buffer.replace(d.start, d.end, d.inserted);
      _lastDocText = doc.text;
      _undo.clear();
      _redo.clear();
      _syncWindowTo(doc.selection, force: true);
      return;
    }
    _lastDocText = doc.text;
    if (doc.selection != _toDoc(window.selection)) _syncWindowTo(doc.selection);
  }

  void _syncWindowTo(TextSelection docSel, {bool force = false}) {
    final sel = docSel.isValid ? docSel : const TextSelection.collapsed(offset: 0);
    final int ws = buffer.lineStart(span.first.clamp(0, buffer.lineCount - 1));
    final int we = buffer.lineEnd((span.last - 1).clamp(0, buffer.lineCount - 1));
    final bool inside = sel.start >= ws && sel.end <= we;
    if (inside && !force) {
      _applying = true;
      window.value = window.value.copyWith(selection: _toWindow(sel));
      _applying = false;
      return;
    }
    moveWindowTo(sel);
  }

  void _resetFromDoc() {
    buffer.reset(doc.text);
    _lastDocText = doc.text;
    _undo.clear();
    _redo.clear();
    moveWindowTo(doc.selection.isValid ? doc.selection : const TextSelection.collapsed(offset: 0));
  }

  /// Styling inputs that live on the document controller.
  void _copySettings() {
    window.theme = doc.theme;
    window.searchQuery = doc.searchQuery;
    final int active = doc.activeMatchOffset;
    final int rel = active - window.windowStart;
    window.activeMatchOffset = active >= 0 && rel >= 0 && rel <= _lastWindowText.length ? rel : -1;
    window.paragraphFocusEnabled = doc.paragraphFocusEnabled;
    window.codexLinkingEnabled = doc.codexLinkingEnabled;
    if (!identical(window.codexTitles, doc.codexTitles)) window.codexTitles = doc.codexTitles;
  }

  // ------------------------------------------------------------- undo

  void _record(int start, String removed, String inserted, TextSelection before, TextSelection after) {
    _redo.clear();
    final now = DateTime.now();
    final last = _undo.isEmpty ? null : _undo.last;
    final bool typing = removed.isEmpty && inserted.length == 1 && inserted != '\n';
    final bool deleting = inserted.isEmpty && removed.length == 1;
    if (last != null && now.difference(last.at) < _coalesceGap) {
      if (typing && last.removed.isEmpty && last.start + last.inserted.length == start) {
        last
          ..inserted += inserted
          ..after = after
          ..at = now;
        return;
      }
      if (deleting && last.inserted.isEmpty && start + removed.length == last.start) {
        // Backspace run: the new deletion sits just before the previous one.
        _undo[_undo.length - 1] = _DocEdit(start, removed + last.removed, '', last.before, after, now);
        return;
      }
    }
    _undo.add(_DocEdit(start, removed, inserted, before, after, now));
    if (_undo.length > 500) _undo.removeAt(0);
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    final e = _undo.removeLast();
    _applyEdit(e.start, e.start + e.inserted.length, e.removed, e.before);
    _redo.add(e);
  }

  void redo() {
    if (_redo.isEmpty) return;
    final e = _redo.removeLast();
    _applyEdit(e.start, e.start + e.removed.length, e.inserted, e.after);
    _undo.add(e..at = DateTime.fromMillisecondsSinceEpoch(0));
  }

  /// Applies a document edit that did not come from typing in the window.
  void _applyEdit(int start, int end, String inserted, TextSelection selection) {
    buffer.replace(start, end, inserted);
    _writeDoc(start, end, inserted, selection, TextRange.empty);
    widget.onChanged(doc.text);
    moveWindowTo(selection);
  }

  // ------------------------------------------------------------ build

  void _tapStatic(int line, TapUpDetails d, RenderParagraph? para) {
    if (para == null) return;
    final pos = para.getPositionForOffset(para.globalToLocal(d.globalPosition));
    final int offset = buffer.lineStart(line) + pos.offset.clamp(0, buffer.line(line).length);
    widget.focusNode.requestFocus();
    moveWindowTo(TextSelection.collapsed(offset: offset));
  }

  /// Which document lines paragraph focus leaves undimmed (the caret's
  /// paragraph: the run of non-blank lines around the caret line).
  ({int first, int last})? _focusLines() {
    if (!doc.paragraphFocusEnabled || !doc.selection.isValid) return null;
    final int caretLine = buffer.lineOfOffset(doc.selection.baseOffset);
    if (buffer.line(caretLine).trim().isEmpty) return (first: caretLine, last: caretLine);
    int a = caretLine, b = caretLine;
    while (a > 0 && buffer.line(a - 1).trim().isNotEmpty) {
      a--;
    }
    while (b < buffer.lineCount - 1 && buffer.line(b + 1).trim().isNotEmpty) {
      b++;
    }
    return (first: a, last: b);
  }

  Widget _staticLine(BuildContext context, int line, ({int first, int last})? focus) {
    final bool dim = focus != null && (line < focus.first || line > focus.last);
    final spans = _static.spansFor(buffer, line, dim, widget.style);
    return _StaticLine(
      key: ValueKey('L$line'),
      span: TextSpan(style: widget.style, children: spans),
      onTapUp: (d, p) => _tapStatic(line, d, p),
    );
  }

  @override
  Widget build(BuildContext context) {
    _static.prepare(widget.theme, widget.style);
    final focus = _focusLines();
    Widget field(List<TextInputFormatter> extra) => Actions(
          // Document-level undo: nearer the field than MarkerAwareEditing's
          // action, so it wins for this field.
          actions: <Type, Action<Intent>>{
            UndoTextIntent: CallbackAction<UndoTextIntent>(onInvoke: (_) {
              undo();
              return null;
            }),
            RedoTextIntent: CallbackAction<RedoTextIntent>(onInvoke: (_) {
              redo();
              return null;
            }),
          },
          child: TextField(
            key: _fieldKey,
            controller: window,
            focusNode: widget.focusNode,
            maxLines: null,
            inputFormatters: [...widget.inputFormatters, ...extra],
            readOnly: widget.readOnly,
            spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
            cursorColor: widget.cursorColor,
            style: widget.style,
            decoration: const InputDecoration(
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              isCollapsed: true,
            ),
            contextMenuBuilder: widget.contextMenuBuilder,
          ),
        );
    final Widget live = widget.wrapField?.call(window, field) ?? field(const []);

    const double pad = 60;
    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment(widget.horizontalPosition * 2 - 1, 0),
      child: Container(
        width: widget.pageWidth,
        decoration: BoxDecoration(
          color: widget.theme.backgroundColor,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 40, offset: const Offset(0, 10)),
          ],
        ),
        child: CustomScrollView(
          controller: scroll,
          center: _centerKey,
          slivers: [
            // Slivers before `center` grow upward: this padding is the page top.
            const SliverToBoxAdapter(child: SizedBox(height: 160)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _staticLine(context, span.first - 1 - i, focus),
                  childCount: span.first,
                ),
              ),
            ),
            SliverPadding(
              key: _centerKey,
              padding: const EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverToBoxAdapter(child: live),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _staticLine(context, span.last + i, focus),
                  childCount: max(0, buffer.lineCount - span.last),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 160)),
          ],
        ),
      ),
    );
  }
}

/// A static line: its spans, and a tap that moves the window there.
class _StaticLine extends StatelessWidget {
  final TextSpan span;
  final void Function(TapUpDetails, RenderParagraph?) onTapUp;
  const _StaticLine({super.key, required this.span, required this.onTapUp});

  static RenderParagraph? _paragraphIn(RenderObject? o) {
    if (o == null || o is RenderParagraph) return o as RenderParagraph?;
    RenderParagraph? found;
    o.visitChildren((c) => found ??= _paragraphIn(c));
    return found;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => onTapUp(d, _paragraphIn(context.findRenderObject())),
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: RichText(text: span, textScaler: TextScaler.noScaling),
        ),
      );
}

/// Builds and caches the spans of static lines with one scratch controller,
/// so they are styled exactly like the live field.
class _StaticLines {
  _StaticLines(this.document);
  final MarkdownEditingController document;
  late final MarkdownEditingController _scratch = MarkdownEditingController(theme: document.theme);
  final Map<String, List<InlineSpan>> _cache = {};
  WriterTheme? _theme;
  TextStyle? _style;
  String? _query;
  bool? _codex;
  Object? _titles;

  void prepare(WriterTheme theme, TextStyle style) {
    if (!identical(theme, _theme) ||
        style != _style ||
        document.searchQuery != _query ||
        document.codexLinkingEnabled != _codex ||
        !identical(document.codexTitles, _titles)) {
      _cache.clear();
      _theme = theme;
      _style = style;
      _query = document.searchQuery;
      _codex = document.codexLinkingEnabled;
      _titles = document.codexTitles;
      _scratch
        ..theme = theme
        ..searchQuery = document.searchQuery
        ..codexLinkingEnabled = document.codexLinkingEnabled
        ..codexTitles = document.codexTitles;
    }
    if (_cache.length > 4000) _cache.clear();
  }

  List<InlineSpan> spansFor(DocumentBuffer buffer, int line, bool dim, TextStyle style) {
    final String text = buffer.line(line);
    final int start = buffer.lineStart(line);
    final int end = start + text.length;
    final miss = rangesInside(document.misspellings, start, end);
    final grammar = grammarInside(document.grammarIssues, start, end);
    final int a = document.activeMatchOffset;
    final int active = a >= start && a < end ? a - start : -1;
    final key = '${dim ? 1 : 0}|$active|${miss.map((r) => '${r.start}-${r.end}').join(',')}'
        '|${grammar.map((g) => '${g.range.start}-${g.range.end}').join(',')}|$text';
    return _cache.putIfAbsent(key, () {
      _scratch.value = TextEditingValue(text: text);
      _scratch
        ..setMisspellings(miss)
        ..setGrammarIssues(grammar)
        ..activeMatchOffset = active;
      return _scratch.buildLineSpans(dim: dim, style: style);
    });
  }
}

@visibleForTesting
EditorWindow debugPlanWindow(DocumentBuffer b, int from, int to, {int budget = kWindowBudgetChars}) =>
    planWindow(b, from, to, budget: budget);
