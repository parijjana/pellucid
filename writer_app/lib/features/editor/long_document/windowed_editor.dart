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
// static lines, styling parity, document-level undo/redo. Phase 2: selections
// past the window (mouse drag and shift-click on static lines, Select All):
// the document controller holds the real selection, the field shows the part
// inside the window, static lines paint the rest, and copy, cut, delete and
// typing act on the whole selection.

import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../list_editing.dart';
import '../marker_aware_editing.dart';
import '../providers/theme_provider.dart';
import '../rich_clipboard.dart';
import '../utils/grammar_checker.dart';
import '../widgets/markdown_controller.dart';
import 'document_buffer.dart';
import 'line_heights.dart';

/// On by default for long documents (1.1.0). Escape hatch back to the single
/// editor for every document: `--dart-define=PELLUCID_WINDOWED_EDITOR=false`.
const bool kWindowedEditorFlag = bool.fromEnvironment('PELLUCID_WINDOWED_EDITOR', defaultValue: true);

/// Documents at or above this many words open in the windowed editor when the
/// flag is on (PLAN_3b_EDITOR.md owner question 1, recommended answer).
const int kWindowedEditorMinWords = int.fromEnvironment('PELLUCID_WINDOWED_MIN_WORDS', defaultValue: 15000);

/// Characters kept in the live window (spike: ~25 normal lines; a 200-line
/// window already costs 12 ms per keystroke, markup-heavy text more).
const int kWindowBudgetChars = 4000;

/// The window moves when the caret comes this close to one of its edges.
const int kWindowEdgeMarginChars = 600;
const int kWindowEdgeMarginLines = 2;

/// A selection up to this size is loaded whole into the window (about 20k
/// words), so the field draws it and shift+arrows extend it. A larger one
/// (Select All on a long document) stays a document selection.
const int kWindowSelectionCapChars = 120000;

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

  /// Called when a span build sees new spelling or grammar results on the
  /// document (the drivers repaint the field only), so static lines refresh.
  VoidCallback? onDecorationsChanged;
  Object? _seenMisspellings;
  Object? _seenGrammar;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final int end = windowStart + text.length;
    if (!identical(document.misspellings, _seenMisspellings) || !identical(document.grammarIssues, _seenGrammar)) {
      final bool first = _seenMisspellings == null && _seenGrammar == null;
      _seenMisspellings = document.misspellings;
      _seenGrammar = document.grammarIssues;
      if (!first) onDecorationsChanged?.call();
    }
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
  for (int i = _firstEndingAfter(ranges, start, (r) => r.end); i < ranges.length && ranges[i].start < end; i++) {
    final r = ranges[i];
    out.add(TextRange(start: max(r.start, start) - start, end: min(r.end, end) - start));
  }
  return out;
}

List<GrammarIssue> grammarInside(List<GrammarIssue> issues, int start, int end) {
  final out = <GrammarIssue>[];
  for (
    int i = _firstEndingAfter(issues, start, (g) => g.range.end);
    i < issues.length && issues[i].range.start < end;
    i++
  ) {
    final g = issues[i];
    if (g.range.start < start || g.range.end > end) continue;
    out.add(
      GrammarIssue(
        range: TextRange(start: g.range.start - start, end: g.range.end - start),
        fixRange: TextRange(start: g.fixRange.start - start, end: g.fixRange.end - start),
        replacement: g.replacement,
        ruleId: g.ruleId,
        message: g.message,
      ),
    );
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
  final Widget Function(WindowFieldController window, Widget Function(List<TextInputFormatter> extra) field)? wrapField;

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

/// The windowed editor showing [controller], or null when the document is in
/// the single editor. The screen asks it to scroll (typewriter, Find, TOC).
WindowedEditorState? windowedEditorFor(TextEditingController controller) => _editors[controller];
final Expando<WindowedEditorState> _editors = Expando<WindowedEditorState>('windowedEditors');

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
  final Map<int, _RenderStaticLine> _built = {};

  /// Static-line heights, so a far scroll lays out only the lines it shows.
  late final LineHeights heights;
  TextDirection _textDirection = TextDirection.ltr;
  Locale? _locale;

  // Pointer state: a press on the field defers window moves until release
  // (the field's drag gesture keeps window offsets); a press on a static line
  // is a click or a drag-select handled here.
  bool _fieldPointer = false;
  int? _dragAnchor;
  Offset _downPos = Offset.zero;
  bool _dragging = false;
  DateTime _lastClickAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastClickPos = Offset.zero;
  int _clickCount = 0;
  bool _reloadPending = false;

  /// Number of window moves (tests and the perf harness read it).
  int windowMoves = 0;

  MarkdownEditingController get doc => widget.controller;

  @override
  void initState() {
    super.initState();
    buffer = DocumentBuffer(doc.text);
    heights = LineHeights(
      measure: _measureLine,
      lengthOf: (i) => buffer.line(i).length,
      rowHeight: _rowHeight(widget.style),
    )..reset(buffer.lineCount);
    buffer.onLinesChanged = heights.replaceLines;
    _lastDocText = doc.text;
    window = WindowFieldController(theme: doc.theme, document: doc)..onDecorationsChanged = _decorationsChanged;
    _editors[doc] = this;
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
      if (identical(_editors[oldWidget.controller], this)) _editors[oldWidget.controller] = null;
      widget.controller.addListener(_onDocChanged);
      _editors[widget.controller] = this;
      _resetFromDoc();
    }
  }

  @override
  void dispose() {
    window.removeListener(_onWindowChanged);
    doc.removeListener(_onDocChanged);
    if (identical(_editors[doc], this)) _editors[doc] = null;
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
    final double? before = _docOffsetScreenY(docSelection.extentOffset);
    final bool fits = docSelection.end - docSelection.start <= kWindowSelectionCapChars;
    _load(
      fits
          ? planWindow(buffer, docSelection.start, docSelection.end)
          : planWindow(buffer, docSelection.extentOffset, docSelection.extentOffset),
      docSelection,
    );
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

  /// Screen Y of [offset]: the field's caret inside the window, the built
  /// static line's text outside it; null when off screen.
  double? _docOffsetScreenY(int offset) {
    final int ws = window.windowStart;
    if (offset >= ws && offset <= ws + _lastWindowText.length) {
      final re = _fieldRender();
      if (re == null || !re.attached || !re.hasSize) return null;
      final rect = re.getLocalRectForCaret(TextPosition(offset: offset - ws));
      return re.localToGlobal(rect.topLeft).dy;
    }
    final int line = buffer.lineOfOffset(offset);
    final ro = _built[line];
    if (ro == null || !ro.attached || !ro.hasSize) return null;
    final para = ro.paragraph;
    final double dy = para == null
        ? 0
        : para.getOffsetForCaret(TextPosition(offset: offset - buffer.lineStart(line)), Rect.zero).dy;
    return ro.localToGlobal(Offset(0, dy)).dy;
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
    final bool nearBottom =
        bottomOpen &&
        (window.text.length - hi < kWindowEdgeMarginChars || span.lineCount - 1 - hiLine < kWindowEdgeMarginLines);
    return nearTop || nearBottom;
  }

  bool get _composing => window.value.composing.isValid && !window.value.composing.isCollapsed;

  /// The document selection reaches outside the window.
  bool _isWide(TextSelection s) =>
      s.isValid &&
      !s.isCollapsed &&
      (s.start < window.windowStart || s.end > window.windowStart + _lastWindowText.length);

  void _maybeMove() {
    if (_composing || _fieldPointer) {
      _movePending = true;
      return;
    }
    // A window grown to hold a long selection shrinks back once it is gone.
    final bool oversized = window.selection.isCollapsed && _lastWindowText.length > 3 * kWindowBudgetChars;
    if (!oversized && !_nearEdge(window.selection)) {
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
    if (_applying || _reloadPending) return;
    final wv = window.value;
    if (wv.text != _lastWindowText && _isWide(doc.selection) && _replaceWideSelection(wv.text)) return;
    if (wv.text == _lastWindowText && _isWide(doc.selection)) {
      // The field only sees the part of the selection inside the window.
      final clamped = _toWindow(doc.selection);
      if (wv.selection == clamped) return;
      final TextSelection next = !wv.selection.isCollapsed && wv.selection.baseOffset == clamped.baseOffset
          ? doc.selection.copyWith(extentOffset: wv.selection.extentOffset + window.windowStart)
          : _toDoc(wv.selection);
      _setDocSelection(next, move: false);
      if (_movePending || _nearEdge(wv.selection)) _maybeMove();
      return;
    }
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

  /// Typing, deleting or pasting over a selection that reaches outside the
  /// window: the field replaced its visible part, the document replaces all of
  /// it. False when the change is not a replacement of that part.
  bool _replaceWideSelection(String now) {
    final clamped = _toWindow(doc.selection);
    final String old = _lastWindowText;
    final int tail = old.length - clamped.end;
    if (now.length < clamped.start + tail ||
        !now.startsWith(old.substring(0, clamped.start)) ||
        !now.endsWith(old.substring(clamped.end))) {
      return false;
    }
    final String inserted = now.substring(clamped.start, now.length - tail);
    _lastWindowText = now;
    final sel = doc.selection;
    _editDoc(
      sel.start,
      sel.end,
      inserted,
      TextSelection.collapsed(offset: sel.start + inserted.length),
      deferMove: true,
    );
    return true;
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
    if (doc.selection != _toDoc(window.selection)) {
      _syncWindowTo(doc.selection);
    } else if (_paintedWide) {
      setState(() {});
    }
  }

  bool _paintedWide = false;

  /// Sets the document selection; [move] lets the window follow it.
  void _setDocSelection(TextSelection sel, {bool move = true}) {
    _applying = true;
    doc.value = doc.value.copyWith(selection: sel, composing: TextRange.empty);
    _lastDocText = doc.text;
    _applying = false;
    if (move) {
      _syncWindowTo(sel);
      return;
    }
    _applying = true;
    window.value = window.value.copyWith(selection: _toWindow(sel), composing: TextRange.empty);
    _applying = false;
    setState(() {});
  }

  void _syncWindowTo(TextSelection docSel, {bool force = false}) {
    final sel = docSel.isValid ? docSel : const TextSelection.collapsed(offset: 0);
    final int ws = buffer.lineStart(span.first.clamp(0, buffer.lineCount - 1));
    final int we = buffer.lineEnd((span.last - 1).clamp(0, buffer.lineCount - 1));
    final bool inside = sel.start >= ws && sel.end <= we;
    // A selection too long for the window stays put while its moving end is
    // in view (shift-click) or it covers the whole window (Select All).
    final bool keep =
        !inside &&
        sel.end - sel.start > kWindowSelectionCapChars &&
        ((sel.extentOffset >= ws && sel.extentOffset <= we) || (sel.start <= ws && sel.end >= we));
    if ((inside || keep) && !force) {
      _applying = true;
      window.value = window.value.copyWith(selection: _toWindow(sel));
      _applying = false;
      setState(() {});
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
    window.bulletStyle = doc.bulletStyle;
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
  void _applyEdit(int start, int end, String inserted, TextSelection selection, {bool deferMove = false}) {
    buffer.replace(start, end, inserted);
    _writeDoc(start, end, inserted, selection, TextRange.empty);
    widget.onChanged(doc.text);
    if (!deferMove) {
      moveWindowTo(selection);
      return;
    }
    // Called from the field's own update: reload once it has finished.
    _reloadPending = true;
    scheduleMicrotask(() {
      _reloadPending = false;
      if (mounted) moveWindowTo(selection);
    });
  }

  /// A recorded (undoable) document edit made here rather than by typing.
  void _editDoc(int start, int end, String inserted, TextSelection selection, {bool deferMove = false}) {
    final before = doc.selection;
    final String removed = buffer.text.substring(start, end);
    _applyEdit(start, end, inserted, selection, deferMove: deferMove);
    _record(start, removed, inserted, before, selection);
  }

  bool _decorationsQueued = false;

  void _decorationsChanged() {
    if (_decorationsQueued) return;
    _decorationsQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _decorationsQueued = false;
      if (mounted) setState(() {});
    });
  }

  // ------------------------------------------------- scrolling for the screen

  double _viewportTop() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null || !box.attached ? 0 : box.localToGlobal(Offset.zero).dy;
  }

  /// Scrolls so [offset] sits [fraction] of the way down the view, without
  /// moving the caret (Find, TOC, typewriter). Lines not yet built are reached
  /// by an estimate from the window's height per character, then corrected.
  Future<void> revealOffset(
    int offset, {
    double fraction = 1 / 3,
    Duration duration = const Duration(milliseconds: 300),
  }) async {
    if (!scroll.hasClients) return;
    final int target = offset.clamp(0, buffer.length);
    for (int attempt = 0; attempt < 4 && mounted && scroll.hasClients; attempt++) {
      final double viewport = scroll.position.viewportDimension;
      final double? y = _docOffsetScreenY(target);
      if (y != null) {
        final double to = (scroll.offset + (y - _viewportTop()) - viewport * fraction).clamp(
          scroll.position.minScrollExtent,
          scroll.position.maxScrollExtent,
        );
        if ((to - scroll.offset).abs() < 1) return;
        if (duration == Duration.zero || attempt > 0) {
          scroll.jumpTo(to);
        } else {
          await scroll.animateTo(to, duration: duration, curve: Curves.easeInOut);
        }
        return;
      }
      final re = _fieldRender();
      final double fieldHeight = re != null && re.hasSize ? re.size.height : 0;
      // Lines not built yet: their known or estimated heights place them.
      final int line = buffer.lineOfOffset(target);
      final double estimate = line < span.first
          ? -heights.sum(line, span.first)
          : fieldHeight + heights.sum(span.last, line);
      scroll.jumpTo(
        (estimate - viewport * fraction).clamp(scroll.position.minScrollExtent, scroll.position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// The document offset of the text under [global] (null on blank space):
  /// Codex mentions in the live field and on static lines.
  int? docOffsetAtPoint(Offset global) {
    final hit = _hitDoc(global);
    if (hit == null) return null;
    if (hit.onField) {
      final re = _fieldRender()!;
      final pos = re.getPositionForPoint(global);
      final caret = re.getLocalRectForCaret(pos);
      final local = re.globalToLocal(global);
      if (local.dy < caret.top - 2 || local.dy > caret.bottom + 2) return null;
    }
    return hit.offset;
  }

  // ------------------------------------------------- selection actions

  void selectAll() => _setDocSelection(TextSelection(baseOffset: 0, extentOffset: buffer.length));

  void _copy({required bool cut}) {
    final sel = doc.selection;
    if (_isWide(sel)) {
      RichClipboard.copy(doc.text, sel.start, sel.end);
      if (cut && !widget.readOnly) _editDoc(sel.start, sel.end, '', TextSelection.collapsed(offset: sel.start));
      return;
    }
    final state = _editableState();
    if (state != null) markerCopy(state, cut: cut);
  }

  EditableTextState? _editableState() {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }

    final ctx = _fieldKey.currentContext;
    if (ctx is Element) visit(ctx);
    return found;
  }

  // ------------------------------------------------- pointer on the page

  /// The document offset under [global], and whether it is on the field.
  ({int offset, bool onField})? _hitDoc(Offset global) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, global, View.of(context).viewId);
    final field = _fieldRender();
    for (final entry in result.path) {
      final target = entry.target;
      if (field != null && identical(target, field)) {
        final pos = field.getPositionForPoint(global);
        return (offset: window.windowStart + pos.offset.clamp(0, _lastWindowText.length), onField: true);
      }
      if (target is _RenderStaticLine) {
        final para = target.paragraph;
        final int len = buffer.line(target.line).length;
        final int at = para == null ? 0 : para.getPositionForOffset(para.globalToLocal(global)).offset.clamp(0, len);
        return (offset: buffer.lineStart(target.line) + at, onField: false);
      }
    }
    return null;
  }

  int _countClick(Offset pos) {
    final now = DateTime.now();
    final bool again =
        now.difference(_lastClickAt) < const Duration(milliseconds: 450) && (pos - _lastClickPos).distance < 6;
    _clickCount = again ? _clickCount + 1 : 1;
    _lastClickAt = now;
    _lastClickPos = pos;
    return _clickCount;
  }

  /// Word (2 clicks) or line (3 clicks) around [offset].
  TextSelection _unitAt(int offset, int clicks) {
    final int line = buffer.lineOfOffset(offset);
    final int ls = buffer.lineStart(line);
    final String text = buffer.line(line);
    if (clicks >= 3) return TextSelection(baseOffset: ls, extentOffset: ls + text.length);
    bool word(int i) {
      final c = text.codeUnitAt(i);
      return c == 0x27 ||
          c == 0x2019 ||
          c >= 0x80 ||
          (c >= 0x30 && c <= 0x39) ||
          ((c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a);
    }

    int a = offset - ls, b = offset - ls;
    while (a > 0 && word(a - 1)) {
      a--;
    }
    while (b < text.length && word(b)) {
      b++;
    }
    return TextSelection(baseOffset: ls + a, extentOffset: ls + b);
  }

  void _onPointerDown(PointerDownEvent e) {
    final hit = _hitDoc(e.position);
    if (hit == null) return;
    if (hit.onField) {
      _fieldPointer = true;
      return;
    }
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
    _dragAnchor = hit.offset;
    _downPos = e.position;
    _dragging = false;
    if (HardwareKeyboard.instance.isShiftPressed && doc.selection.isValid) {
      _dragAnchor = doc.selection.baseOffset;
      _dragging = true;
      _setDocSelection(TextSelection(baseOffset: _dragAnchor!, extentOffset: hit.offset), move: false);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final int? anchor = _dragAnchor;
    if (anchor == null) return;
    if (e.kind != PointerDeviceKind.mouse) {
      // A finger moving on static lines scrolls; it is not a tap.
      if ((e.position - _downPos).distance > kTouchSlop) _dragAnchor = null;
      return;
    }
    if (!_dragging && (e.position - _downPos).distance < 4) return;
    _dragging = true;
    final hit = _hitDoc(e.position);
    if (hit == null) return;
    _setDocSelection(TextSelection(baseOffset: anchor, extentOffset: hit.offset), move: false);
  }

  void _onPointerUp(PointerEvent e) {
    if (_fieldPointer) {
      _fieldPointer = false;
      // A double click whose first click was on a static line: the window
      // moved under the pointer, so the field saw a single click.
      if (e is PointerUpEvent &&
          _clickCount >= 1 &&
          _lastClickAt.isAfter(DateTime.now().subtract(const Duration(milliseconds: 450)))) {
        final int clicks = _countClick(e.position);
        final hit = clicks >= 2 ? _hitDoc(e.position) : null;
        if (hit != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setDocSelection(_unitAt(hit.offset, clicks));
          });
        }
      }
      if (_movePending) _maybeMove();
      return;
    }
    final int? anchor = _dragAnchor;
    _dragAnchor = null;
    if (anchor == null || e is! PointerUpEvent) return;
    if (_dragging) {
      _dragging = false;
      // Bring a selection that fits into the field, so shift+arrows extend it.
      final sel = doc.selection;
      if (_isWide(sel) && sel.end - sel.start <= kWindowSelectionCapChars) moveWindowTo(sel);
      return;
    }
    widget.focusNode.requestFocus();
    final int clicks = _countClick(e.position);
    _setDocSelection(clicks >= 2 ? _unitAt(anchor, clicks) : TextSelection.collapsed(offset: anchor));
    // A click on a static checkbox ticks it, as in the live field.
    if (clicks == 1 && !widget.readOnly) {
      final int at = anchor - window.windowStart;
      final int? lineStart = at >= 0 && at <= window.text.length ? checkboxLineAt(window.text, at) : null;
      final next = lineStart == null ? null : toggleCheckbox(window.value, lineStart);
      if (next != null) window.value = next;
    }
  }

  // ------------------------------------------------------------ build

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

  static double _rowHeight(TextStyle style) => (style.fontSize ?? 14) * (style.height ?? 1.2);

  /// Lays out [line] exactly as its static line's RichText does.
  double _measureLine(int line, double width) {
    final painter = TextPainter(
      text: TextSpan(style: widget.style, children: _static.spansFor(buffer, line, false, widget.style)),
      textDirection: _textDirection,
      textScaler: TextScaler.noScaling,
      locale: _locale,
    )..layout(maxWidth: width);
    final double h = painter.height;
    painter.dispose();
    return h;
  }

  Widget _staticLine(BuildContext context, int line, ({int first, int last})? focus, Color selectionColor) {
    final bool dim = focus != null && (line < focus.first || line > focus.last);
    final spans = _static.spansFor(buffer, line, dim, widget.style);
    // The part of a document selection on this line (collapsed: an empty
    // line inside the selection).
    TextSelection? selected;
    final ds = doc.selection;
    if (ds.isValid && !ds.isCollapsed) {
      final int ls = buffer.lineStart(line), le = buffer.lineEnd(line);
      if (ds.start <= le && ds.end > ls) {
        selected = TextSelection(baseOffset: max(ds.start, ls) - ls, extentOffset: min(ds.end, le) - ls);
      }
    }
    return MouseRegion(
      key: ValueKey('L$line'),
      cursor: SystemMouseCursors.text,
      child: _StaticLine(
        line: line,
        registry: _built,
        selection: selected,
        selectionColor: selectionColor,
        child: RichText(
          text: TextSpan(style: widget.style, children: spans),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _copySettings();
    if (_static.prepare(widget.theme, widget.style)) heights.invalidateAll();
    heights.rowHeight = _rowHeight(widget.style);
    _textDirection = Directionality.of(context);
    _locale = Localizations.maybeLocaleOf(context);
    final focus = _focusLines();
    _paintedWide = _isWide(doc.selection);
    final Color selectionColor =
        DefaultSelectionStyle.of(context).selectionColor ??
        Theme.of(context).textSelectionTheme.selectionColor ??
        const Color(0x663390FF);
    Widget field(List<TextInputFormatter> extra) => Actions(
      // Document-level undo: nearer the field than MarkerAwareEditing's
      // action, so it wins for this field.
      actions: <Type, Action<Intent>>{
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            undo();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            redo();
            return null;
          },
        ),
        SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
          onInvoke: (_) {
            selectAll();
            return null;
          },
        ),
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) {
            _copy(cut: intent.collapseSelection);
            return null;
          },
        ),
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
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: CustomScrollView(
            controller: scroll,
            center: _centerKey,
            slivers: [
              // Slivers before `center` grow upward: this padding is the page top.
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: pad),
                sliver: LineSliver(
                  heights: heights,
                  base: span.first,
                  upward: true,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _staticLine(context, span.first - 1 - i, focus, selectionColor),
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
                sliver: LineSliver(
                  heights: heights,
                  base: span.last,
                  upward: false,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _staticLine(context, span.last + i, focus, selectionColor),
                    childCount: max(0, buffer.lineCount - span.last),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A static line: hit-tested as a whole (the pointer handler asks it for its
/// line), paints its part of a document selection behind the text, and
/// registers itself so window moves can keep its text still on screen.
class _StaticLine extends SingleChildRenderObjectWidget {
  final int line;
  final Map<int, _RenderStaticLine> registry;
  final TextSelection? selection;
  final Color selectionColor;
  const _StaticLine({
    required this.line,
    required this.registry,
    required this.selection,
    required this.selectionColor,
    required super.child,
  });

  @override
  _RenderStaticLine createRenderObject(BuildContext context) =>
      _RenderStaticLine(line, registry, selection, selectionColor);

  @override
  void updateRenderObject(BuildContext context, _RenderStaticLine renderObject) {
    renderObject
      ..line = line
      ..selection = selection
      ..selectionColor = selectionColor;
  }
}

class _RenderStaticLine extends RenderProxyBox {
  _RenderStaticLine(this._line, this.registry, this._selection, this._selectionColor);
  final Map<int, _RenderStaticLine> registry;

  int _line;
  int get line => _line;
  set line(int v) {
    if (v == _line) return;
    if (identical(registry[_line], this)) registry.remove(_line);
    _line = v;
    if (attached) registry[_line] = this;
  }

  TextSelection? _selection;
  set selection(TextSelection? v) {
    if (v == _selection) return;
    _selection = v;
    markNeedsPaint();
  }

  Color _selectionColor;
  set selectionColor(Color v) {
    if (v == _selectionColor) return;
    _selectionColor = v;
    markNeedsPaint();
  }

  RenderParagraph? get paragraph => child is RenderParagraph ? child as RenderParagraph : null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    registry[_line] = this;
  }

  @override
  void detach() {
    if (identical(registry[_line], this)) registry.remove(_line);
    super.detach();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final sel = _selection;
    final para = paragraph;
    if (sel != null && para != null) {
      final paint = Paint()..color = _selectionColor;
      if (sel.isCollapsed) {
        context.canvas.drawRect(offset & Size(6, size.height), paint);
      } else {
        for (final box in para.getBoxesForSelection(sel)) {
          context.canvas.drawRect(box.toRect().shift(offset), paint);
        }
      }
    }
    super.paint(context, offset);
  }
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
  Object? _bullets;
  String? _query;
  bool? _codex;
  Object? _titles;

  /// Refreshes the styling inputs; true when they changed (cached spans and
  /// measured heights are stale).
  bool prepare(WriterTheme theme, TextStyle style) {
    bool changed = false;
    if (!identical(theme, _theme) ||
        style != _style ||
        document.searchQuery != _query ||
        document.codexLinkingEnabled != _codex ||
        !identical(document.codexTitles, _titles) ||
        document.bulletStyle != _bullets) {
      _cache.clear();
      changed = true;
      _bullets = document.bulletStyle;
      _theme = theme;
      _style = style;
      _query = document.searchQuery;
      _codex = document.codexLinkingEnabled;
      _titles = document.codexTitles;
      _scratch
        ..theme = theme
        ..searchQuery = document.searchQuery
        ..codexLinkingEnabled = document.codexLinkingEnabled
        ..codexTitles = document.codexTitles
        ..bulletStyle = document.bulletStyle;
    }
    if (_cache.length > 4000) _cache.clear();
    return changed;
  }

  List<InlineSpan> spansFor(DocumentBuffer buffer, int line, bool dim, TextStyle style) {
    final String text = buffer.line(line);
    final int start = buffer.lineStart(line);
    final int end = start + text.length;
    final miss = rangesInside(document.misspellings, start, end);
    final grammar = grammarInside(document.grammarIssues, start, end);
    final int a = document.activeMatchOffset;
    final int active = a >= start && a < end ? a - start : -1;
    final key =
        '${dim ? 1 : 0}|$active|${miss.map((r) => '${r.start}-${r.end}').join(',')}'
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
