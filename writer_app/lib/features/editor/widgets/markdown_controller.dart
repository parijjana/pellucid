// @trace FEAT-20260516-120000-0001
// Description: A custom TextEditingController that styles Markdown in real-time and hides tags.

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../providers/codex_index.dart';
import '../../search/providers/text_replacer.dart';
import '../marker_edit_rules.dart';
import '../list_editing.dart';
import '../list_marker.dart';
import '../utils/grammar_checker.dart';
import '../utils/grammar_hint_style.dart';
import '../utils/underline_spans.dart';

/// Prefix of a block-quote line.
const String blockQuoteMarker = '> ';

class MarkdownEditingController extends TextEditingController {
  WriterTheme theme;
  String _searchQuery = '';
  int _activeMatchOffset = -1;
  bool _paragraphFocusEnabled = false;
  bool _codexLinkingEnabled = false;
  final CodexIndex codexIndex = CodexIndex();

  MarkdownEditingController({super.text, required this.theme});

  List<TextRange> _misspellings = const [];

  /// Misspelled ranges (absolute offsets), drawn with a wavy underline inside
  /// this controller's own spans. EditableText's built-in spell-check drawing
  /// replaces buildTextSpan wholesale, which would drop the markdown styling.
  List<TextRange> get misspellings => _misspellings;

  /// Deliberately does not notify: controller listeners (autosave, stats)
  /// treat a notification as an edit. The caller repaints the editor.
  void setMisspellings(List<TextRange> ranges) =>
      _misspellings = [...ranges]..sort((a, b) => a.start.compareTo(b.start));

  List<GrammarIssue> _grammarIssues = const [];

  /// Grammar hints (absolute offsets), drawn with a dotted underline. Set by
  /// the grammar-hint driver; like [setMisspellings] it does not notify.
  /// Query with `grammarIssueAt` (grammar_hints.dart).
  List<GrammarIssue> get grammarIssues => _grammarIssues;
  void setGrammarIssues(List<GrammarIssue> issues) =>
      _grammarIssues = [...issues]..sort((a, b) => a.range.start.compareTo(b.range.start));

  /// Keeps underlines on the right words between checks: ranges before the
  /// edit stay, ranges after it move with it, ranges touching it are dropped
  /// until the next check.
  /// Keeps a collapsed caret off hidden markers (backlog item 24).
  final MarkerCaret markerCaret = MarkerCaret();

  @override
  set value(TextEditingValue newValue) {
    final old = super.value;
    newValue = markerCaret.adjust(old, newValue);
    if ((_misspellings.isNotEmpty || _grammarIssues.isNotEmpty) && newValue.text != old.text) {
      // One edit span per keystroke, found from the selection (O(edit size));
      // the full prefix/suffix scan is only the fallback.
      final e = _EditSpan.fromValues(old, newValue);
      if (_misspellings.isNotEmpty) _misspellings = _shiftSorted(_misspellings, e);
      if (_grammarIssues.isNotEmpty) _grammarIssues = _shiftGrammarSorted(_grammarIssues, e);
    }
    super.value = newValue;
  }

  /// [ranges] (sorted, non-overlapping) moved past the edit [e]: binary search
  /// for the unaffected head and the shifted tail; ranges touching the edit go.
  static List<TextRange> _shiftSorted(List<TextRange> ranges, _EditSpan e) {
    final int head = firstRangeEndingAfter(ranges, e.prefix, (r) => r.end);
    // Ranges ending after the edit start but starting before its end touch it.
    int t = head;
    while (t < ranges.length && ranges[t].start < e.editEnd) {
      t++;
    }
    return [
      ...ranges.sublist(0, head),
      for (int i = t; i < ranges.length; i++) ?e.shift(ranges[i]),
    ];
  }

  static List<GrammarIssue> _shiftGrammarSorted(List<GrammarIssue> issues, _EditSpan e) {
    // Hints are sorted by range; a fix range never ends after its range, so the
    // head (range ends at or before the edit) is untouched.
    final int head = firstRangeEndingAfter(issues, e.prefix, (i) => i.range.end);
    int t = head;
    while (t < issues.length && issues[t].range.start < e.editEnd) {
      t++;
    }
    final out = <GrammarIssue>[...issues.sublist(0, head)];
    for (int k = t; k < issues.length; k++) {
      final i = issues[k];
      final r = e.shift(i.range);
      final f = e.shift(i.fixRange);
      if (r == null || f == null) continue;
      out.add(identical(r, i.range) && identical(f, i.fixRange)
          ? i
          : GrammarIssue(range: r, fixRange: f, replacement: i.replacement, ruleId: i.ruleId, message: i.message));
    }
    return out;
  }

  static List<TextRange> shiftRangesForEdit(List<TextRange> ranges, String oldText, String newText) {
    final e = _EditSpan.between(oldText, newText);
    return [
      for (final r in ranges) ?e.shift(r),
    ];
  }

  /// Index of the first range in [ranges] whose end is past [offset].
  /// [ranges] must be sorted and non-overlapping (spell-check results and
  /// Codex mentions both are), so their ends ascend and binary search works.
  @visibleForTesting
  static int firstRangeEndingAfter<T>(List<T> ranges, int offset, int Function(T) endOf) {
    int lo = 0;
    int hi = ranges.length;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (endOf(ranges[mid]) <= offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  bool get codexLinkingEnabled => _codexLinkingEnabled;
  set codexLinkingEnabled(bool val) {
    if (_codexLinkingEnabled != val) {
      _codexLinkingEnabled = val;
      notifyListeners();
    }
  }

  /// Feeds the current research-note titles used for mention recognition.
  set codexTitles(List<CodexTitle> titles) {
    _codexTitles = titles;
    if (codexIndex.setTitles(titles)) notifyListeners();
  }

  /// The titles last fed to [codexTitles] (the windowed editor copies them).
  List<CodexTitle> get codexTitles => _codexTitles;
  List<CodexTitle> _codexTitles = const [];

  String get searchQuery => _searchQuery;
  set searchQuery(String val) {
    if (_searchQuery != val) {
      _searchQuery = val;
      notifyListeners();
    }
  }

  bool get paragraphFocusEnabled => _paragraphFocusEnabled;
  set paragraphFocusEnabled(bool val) {
    if (_paragraphFocusEnabled != val) {
      _paragraphFocusEnabled = val;
      notifyListeners();
    }
  }

  /// Returns the inclusive line range of the paragraph containing [caretOffset].
  /// A paragraph is a run of contiguous non-blank lines delimited by blank
  /// lines (headers and bullets count as paragraph blocks). A blank line is
  /// its own (empty) paragraph. Returns null when the offset falls outside
  /// the text covered by [lines].
  static ({int startLine, int endLine})? paragraphLineRange(List<String> lines, int caretOffset) {
    if (caretOffset < 0) return null;
    int lineStart = 0;
    int caretLine = -1;
    for (int i = 0; i < lines.length; i++) {
      final lineEnd = lineStart + lines[i].length;
      if (caretOffset <= lineEnd) {
        caretLine = i;
        break;
      }
      lineStart = lineEnd + 1;
    }
    if (caretLine == -1) return null;
    if (lines[caretLine].trim().isEmpty) {
      return (startLine: caretLine, endLine: caretLine);
    }
    int start = caretLine;
    while (start > 0 && lines[start - 1].trim().isNotEmpty) {
      start--;
    }
    int end = caretLine;
    while (end < lines.length - 1 && lines[end + 1].trim().isNotEmpty) {
      end++;
    }
    return (startLine: start, endLine: end);
  }

  int get activeMatchOffset => _activeMatchOffset;
  set activeMatchOffset(int val) {
    if (_activeMatchOffset != val) {
      _activeMatchOffset = val;
      notifyListeners();
    }
  }

  List<InlineSpan> _highlightText(String text, TextStyle baseStyle, String query, int startOffset) {
    var spans = _searchHighlight(text, baseStyle, query, startOffset);
    if (_grammarIssues.isNotEmpty) {
      spans = underlineRanges(spans, startOffset, [for (final i in _grammarIssues) i.range],
          decorationStyle: TextDecorationStyle.dotted, color: grammarHintColor(theme));
    }
    return _misspellings.isEmpty ? spans : _underlineMisspellings(spans, startOffset);
  }

  /// Splits leaf spans (contiguous from [startOffset]) wherever they cross a
  /// misspelled range and gives those pieces the wavy underline.
  List<InlineSpan> _underlineMisspellings(List<InlineSpan> spans, int startOffset) {
    final List<InlineSpan> out = [];
    int offset = startOffset;
    // Skip straight to the first range that can reach this segment: scanning
    // from the start for every segment was quadratic on long manuscripts.
    final int first = firstRangeEndingAfter(_misspellings, startOffset, (r) => r.end);
    for (final span in spans) {
      final textSpan = span as TextSpan;
      final String run = textSpan.text ?? '';
      final int runEnd = offset + run.length;
      int cursor = 0;
      for (int i = first; i < _misspellings.length; i++) {
        final r = _misspellings[i];
        if (r.end <= offset + cursor) continue;
        if (r.start >= runEnd) break;
        final int mStart = (r.start < offset ? offset : r.start) - offset;
        final int mEnd = (r.end > runEnd ? runEnd : r.end) - offset;
        if (mStart > cursor) {
          out.add(TextSpan(text: run.substring(cursor, mStart), style: textSpan.style));
        }
        out.add(TextSpan(
          text: run.substring(mStart, mEnd),
          style: (textSpan.style ?? const TextStyle()).copyWith(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: _misspellingColor,
            decorationThickness: 2.0,
          ),
        ));
        cursor = mEnd;
      }
      if (cursor == 0) {
        out.add(span);
      } else if (cursor < run.length) {
        out.add(TextSpan(text: run.substring(cursor), style: textSpan.style));
      }
      offset = runEnd;
    }
    return out;
  }

  /// Full-strength red, lighter on dark themes: dark red at partial opacity
  /// all but disappears on near-black pages such as Cyberpunk.
  Color get _misspellingColor =>
      theme.backgroundColor.computeLuminance() < 0.2 ? const Color(0xFFFF5370) : const Color(0xFFD32F2F);

  /// Tint for every Find match. Amber disappears on the yellow/cream pages
  /// (Citrus, Sepia, Solarized Light), so light themes get blue and dark
  /// themes amber.
  static Color matchColor(WriterTheme theme) => theme.backgroundColor.computeLuminance() < 0.4
      ? const Color(0xFFFFC107).withValues(alpha: 0.40)
      : const Color(0xFF1E88E5).withValues(alpha: 0.35);

  /// The current Find match: opaque orange with black text, readable on every
  /// theme whatever the theme's text colour is. No bold: a heavier weight
  /// would reflow the line each time Next/Previous moves the match.
  static Color currentMatchColor(WriterTheme theme) => const Color(0xFFFF9800);

  List<InlineSpan> _searchHighlight(String text, TextStyle baseStyle, String query, int startOffset) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    
    final List<InlineSpan> spans = [];
    final escaped = RegExp.escape(query);
    final regex = RegExp(escaped, caseSensitive: false);
    
    int lastEnd = 0;
    final matches = regex.allMatches(text);
    
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }
      
      final matchAbsoluteStart = startOffset + match.start;
      final isCurrentActiveMatch = _activeMatchOffset == matchAbsoluteStart;

      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: isCurrentActiveMatch
            ? baseStyle.copyWith(
                backgroundColor: currentMatchColor(theme),
                color: Colors.black,
              )
            : baseStyle.copyWith(backgroundColor: matchColor(theme)),
      ));
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    return spans;
  }

  /// Emits [segment] (absolute range [absOffset, absOffset+segment.length)) into
  /// [children], layering a barely-visible underline over Codex mentions while
  /// delegating each sub-run to [_highlightText] so search highlighting still
  /// applies. When Codex Linking is off (or no mentions overlap) this is byte
  /// identical to a direct [_highlightText] call.
  void _emitStyled(List<InlineSpan> children, String segment, TextStyle baseStyle, int absOffset) {
    final List<MentionRange> ranges =
        _codexLinkingEnabled ? codexIndex.rangesFor(text) : const [];
    if (ranges.isEmpty) {
      children.addAll(_highlightText(segment, baseStyle, searchQuery, absOffset));
      return;
    }

    final TextStyle mentionStyle = baseStyle.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.foregroundColor.withValues(alpha: 0.18),
      decorationThickness: 1.0,
    );
    final int segEnd = absOffset + segment.length;
    int cursor = 0; // local index into segment

    for (int i = firstRangeEndingAfter(ranges, absOffset, (r) => r.end); i < ranges.length; i++) {
      final r = ranges[i];
      if (r.end <= absOffset) continue;
      if (r.start >= segEnd) break;
      final int mStart = (r.start < absOffset ? absOffset : r.start) - absOffset;
      final int mEnd = (r.end > segEnd ? segEnd : r.end) - absOffset;
      if (mStart > cursor) {
        children.addAll(_highlightText(
            segment.substring(cursor, mStart), baseStyle, searchQuery, absOffset + cursor));
      }
      children.addAll(_highlightText(
          segment.substring(mStart, mEnd), mentionStyle, searchQuery, absOffset + mStart));
      cursor = mEnd;
    }
    if (cursor < segment.length) {
      children.addAll(_highlightText(
          segment.substring(cursor), baseStyle, searchQuery, absOffset + cursor));
    }
  }

  // Per-line span cache (backlog item 23). A line's spans depend only on its
  // text, whether it is dimmed, and the ranges that fall inside it (spelling,
  // grammar, codex mentions, the current Find match), measured
  // from the line start; everything else that styles a line (theme, base
  // style, search query) clears the cache when it changes. Relative keys keep
  // lines after an edit cacheable even though their absolute offsets moved.
  Map<String, List<_CachedLine>> _lineCache = {};
  WriterTheme? _cacheTheme;
  TextStyle? _cacheStyle;
  String? _cacheQuery;
  BulletStyle? _cacheBullet;
  double? _indentUnitSize;

  BulletStyle _bulletStyle = BulletStyle.defaultStyle;

  /// Settings > Bullet Style: the glyph set bullets are drawn with (display
  /// only). A change redraws every list line, so it clears the line cache.
  BulletStyle get bulletStyle => _bulletStyle;
  set bulletStyle(BulletStyle value) {
    if (_bulletStyle == value) return;
    _bulletStyle = value;
    notifyListeners();
  }

  @visibleForTesting
  bool lineCacheEnabled = true;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> children = [];
    final lines = text.split('\n');
    int currentOffset = 0;

    // Paragraph Focus: dim every line outside the caret's paragraph.
    // Invalid selections fall back to no dimming.
    ({int startLine, int endLine})? focusRange;
    if (_paragraphFocusEnabled && selection.baseOffset >= 0 && selection.baseOffset <= text.length) {
      focusRange = paragraphLineRange(lines, selection.baseOffset);
    }

    if (!identical(theme, _cacheTheme) || style != _cacheStyle || searchQuery != _cacheQuery || _bulletStyle != _cacheBullet) {
      _lineCache = {};
      _cacheBullet = _bulletStyle;
      _indentUnitSize = null;
      _cacheTheme = theme;
      _cacheStyle = style;
      _cacheQuery = searchQuery;
    }
    final Map<String, List<_CachedLine>> previous = _lineCache;
    final Map<String, List<_CachedLine>> next = {};
    final List<MentionRange> mentions =
        _codexLinkingEnabled ? codexIndex.rangesFor(text) : const [];
    int missIndex = 0;
    int grammarIndex = 0;
    int mentionIndex = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLastLine = i == lines.length - 1;
      final bool dim = focusRange != null && (i < focusRange.startLine || i > focusRange.endLine);

      if (!lineCacheEnabled) {
        _addLine(children, line, currentOffset, dim, style);
      } else {
        final int lineEnd = currentOffset + line.length;
        final List<int> miss = [];
        while (missIndex < _misspellings.length && _misspellings[missIndex].end <= currentOffset) {
          missIndex++;
        }
        for (int m = missIndex; m < _misspellings.length && _misspellings[m].start < lineEnd; m++) {
          miss..add(_misspellings[m].start - currentOffset)..add(_misspellings[m].end - currentOffset);
        }
        final List<int> grammar = [];
        while (grammarIndex < _grammarIssues.length && _grammarIssues[grammarIndex].range.end <= currentOffset) {
          grammarIndex++;
        }
        for (int g = grammarIndex; g < _grammarIssues.length && _grammarIssues[g].range.start < lineEnd; g++) {
          grammar..add(_grammarIssues[g].range.start - currentOffset)..add(_grammarIssues[g].range.end - currentOffset);
        }
        final List<int> marks = [];
        while (mentionIndex < mentions.length && mentions[mentionIndex].end <= currentOffset) {
          mentionIndex++;
        }
        for (int m = mentionIndex; m < mentions.length && mentions[m].start < lineEnd; m++) {
          marks..add(mentions[m].start - currentOffset)..add(mentions[m].end - currentOffset);
        }
        final int active = _activeMatchOffset >= currentOffset && _activeMatchOffset < lineEnd
            ? _activeMatchOffset - currentOffset
            : -1;
        final key = _CachedLine(dim, active, miss, grammar, marks);

        _CachedLine? hit;
        for (final c in previous[line] ?? const <_CachedLine>[]) {
          if (c.sameKey(key)) {
            hit = c;
            break;
          }
        }
        if (hit == null) {
          final List<InlineSpan> lineSpans = [];
          _addLine(lineSpans, line, currentOffset, dim, style);
          hit = key..spans = lineSpans;
        }
        final bucket = next.putIfAbsent(line, () => []);
        if (!bucket.contains(hit)) bucket.add(hit);
        children.addAll(hit.spans);
      }

      currentOffset += line.length;
      if (!isLastLine) {
        children.add(const TextSpan(text: '\n'));
        currentOffset += 1;
      }
    }
    if (lineCacheEnabled) _lineCache = next;

    return TextSpan(style: style, children: children);
  }

  /// Spans for one line drawn outside a live field (slice 3b windowed editor:
  /// the static lines around the editing window). Same styling as
  /// [buildTextSpan]; this controller's text must be [line], so its ranges
  /// (spelling, grammar, Find match, Codex mentions) are line-relative.
  List<InlineSpan> buildLineSpans({required bool dim, TextStyle? style}) {
    final List<InlineSpan> spans = [];
    _addLine(spans, text, 0, dim, style);
    return spans;
  }

  void _addLine(List<InlineSpan> children, String line, int lineOffset, bool dim, TextStyle? style) {
    final Color? contentColor = dim ? theme.foregroundColor.withValues(alpha: 0.38) : null;
    if (line.startsWith('# ')) {
      _addStyledBlock(children, line, r'^# ', 32.0, FontWeight.bold, lineOffset, contentColor: contentColor);
    } else if (line.startsWith('## ')) {
      _addStyledBlock(children, line, r'^## ', 24.0, FontWeight.bold, lineOffset, contentColor: contentColor);
    } else if (line.startsWith('### ')) {
      _addStyledBlock(children, line, r'^### ', 18.0, FontWeight.bold, lineOffset, contentColor: contentColor);
    } else if (line.startsWith(blockQuoteMarker)) {
      _addBlockQuote(children, line, lineOffset, style ?? const TextStyle(), contentColor);
    } else if (parseListMarker(line) case final ListMarker lm) {
      _addListLine(children, line, lm, lineOffset, contentColor);
    } else {
      final baseStyle = style ?? const TextStyle();
      final int indentCount = paragraphIndentCount(line);
      if (indentCount > 0) {
        // Paragraph indent (slice 5b): the em spaces are blank space of
        // exactly one list level each, drawn in the stored length.
        children.add(TextSpan(
          text: line.substring(0, indentCount),
          style: TextStyle(color: Colors.transparent, fontSize: _paragraphIndentFontSize(baseStyle)),
        ));
        line = line.substring(indentCount);
        lineOffset += indentCount;
      }
      _addInlineStyledText(children, line, contentColor != null ? baseStyle.copyWith(color: contentColor) : baseStyle, lineOffset);
    }
  }

  /// Font size at which one em space is as wide as one list level (four
  /// spaces at 18 px, what a list item indents by) in the current font.
  double _paragraphIndentFontSize(TextStyle base) {
    final cached = _indentUnitSize;
    if (cached != null) return cached;
    double size = 17.5;
    try {
      double width(String t, double fontSize) {
        final tp = TextPainter(text: TextSpan(text: t, style: base.copyWith(fontSize: fontSize)), textDirection: TextDirection.ltr)
          ..layout();
        final w = tp.width;
        tp.dispose();
        return w;
      }

      final double em = width(paragraphIndentChar, 100) / 100;
      if (em > 0) size = (width('    ', 18) / em).clamp(8.0, 24.0);
    } catch (_) {}
    return _indentUnitSize = size;
  }

  /// Block quote (`> text`): marker hidden, content italic and slightly muted.
  /// Inline formatting inside the quote is still rendered.
  void _addBlockQuote(List<InlineSpan> children, String line, int lineOffset, TextStyle base, Color? dimColor) {
    children.add(const TextSpan(text: blockQuoteMarker, style: _hiddenMarkerStyle));
    _addInlineStyledText(
      children,
      line.substring(blockQuoteMarker.length),
      base.copyWith(
        fontStyle: FontStyle.italic,
        color: dimColor ?? theme.foregroundColor.withValues(alpha: 0.75),
      ),
      lineOffset + blockQuoteMarker.length,
    );
  }

  /// Heading line: the `# ` marker is hidden; the text keeps its inline
  /// formatting (bold, italic, underline, strike) at the heading's size.
  void _addStyledBlock(List<InlineSpan> children, String line, String pattern, double fontSize, FontWeight weight, int lineOffset, {Color? contentColor}) {
    final match = RegExp(pattern).firstMatch(line);
    if (match == null) return;
    final TextStyle contentStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      color: contentColor ?? theme.foregroundColor,
    );
    children.add(TextSpan(text: match.group(0), style: _hiddenMarkerStyle));
    _addInlineStyledText(children, line.substring(match.end), contentStyle, lineOffset + match.end);
  }

  /// List line (bullet, numbered, checklist; backlog items 2, 3, 9, 10, 17).
  /// The stored marker is drawn as a glyph for its level (• ◦ ▪, 1. a. i.,
  /// ☐ ☑) in exactly the same number of characters, so the span text stays
  /// character-for-character aligned with the document text. EditableText
  /// maps caret, selection and taps through the span text; a drawn marker of
  /// another length shifted every offset after it. Filler characters are
  /// drawn invisibly, and a long label (viii.) sits over the end of the indent.
  void _addListLine(List<InlineSpan> children, String line, ListMarker m, int lineOffset, Color? dimColor) {
    final glyph = listGlyph(m, _bulletStyle);
    final bool done = m.kind == ListKind.check && m.checked;
    final Color base = dimColor ?? theme.foregroundColor;
    final TextStyle contentStyle = TextStyle(
      fontSize: 18.0,
      fontWeight: FontWeight.normal,
      color: done && dimColor == null ? base.withValues(alpha: 0.55) : base,
    );
    final int keep = m.indent.length - glyph.absorbed;
    if (keep > 0) children.add(TextSpan(text: m.indent.substring(0, keep), style: contentStyle));
    if (glyph.absorbed > 0) {
      children.add(TextSpan(text: glyph.shown.substring(0, glyph.absorbed), style: contentStyle));
    }
    children.add(TextSpan(
      text: glyph.shown.substring(glyph.absorbed),
      style: contentStyle.copyWith(color: base),
      spellOut: false, // the tag read by [isListMarkerSpan]
    ));
    if (glyph.pad > 0) children.add(TextSpan(text: ' ' * glyph.pad, style: _hiddenMarkerStyle));
    _addInlineStyledText(children, line.substring(m.length), contentStyle, lineOffset + m.length);
  }

  /// True for the span that draws a list marker glyph. The renderer tags it
  /// with `spellOut: false` (no visible or layout effect; semantics only,
  /// unlike `semanticsLabel`, which would replace the span's text in
  /// `toPlainText` and so break offsets).
  static bool isListMarkerSpan(TextSpan span) => span.spellOut == false;

  void _addInlineStyledText(List<InlineSpan> children, String line, TextStyle baseStyle, int lineOffset) {
    // Scan for Bold + Italic (***), Bold (**), Italic (*), or Underline (<u>)
    final regex = RegExp(r'(\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|<u>.*?</u>|~~.*?~~)');
    int lastMatchEnd = 0;
    
    final matches = regex.allMatches(line);
    
    for (final match in matches) {
      // Add text BEFORE the match
      if (match.start > lastMatchEnd) {
        _emitStyled(children, line.substring(lastMatchEnd, match.start), baseStyle, lineOffset + lastMatchEnd);
      }
      
      final matchText = match.group(0)!;
      // Each run is checked at both ends: the bold alternative can match
      // "***a**", whose closing marker is "**", not "***".
      if (matchText.startsWith('***') && matchText.endsWith('***') && matchText.length >= 6) {
        _addHiddenRun(children, matchText, 3, 3,
            baseStyle.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic), lineOffset + match.start);
      } else if (matchText.startsWith('**') && matchText.endsWith('**') && matchText.length >= 4) {
        _addHiddenRun(children, matchText, 2, 2, baseStyle.copyWith(fontWeight: FontWeight.bold), lineOffset + match.start);
      } else if (matchText.startsWith('*') && matchText.endsWith('*') && matchText.length >= 2) {
        _addHiddenRun(children, matchText, 1, 1, baseStyle.copyWith(fontStyle: FontStyle.italic), lineOffset + match.start);
      } else if (matchText.startsWith('<u>') && matchText.endsWith('</u>') && matchText.length >= 7) {
        _addHiddenRun(children, matchText, 3, 4, baseStyle.copyWith(decoration: TextDecoration.underline), lineOffset + match.start);
      } else if (matchText.startsWith('~~') && matchText.endsWith('~~') && matchText.length >= 4) {
        _addHiddenRun(
          children,
          matchText,
          2,
          2,
          baseStyle.copyWith(decoration: TextDecoration.combine([
            if (baseStyle.decoration != null) baseStyle.decoration!,
            TextDecoration.lineThrough,
          ])),
          lineOffset + match.start,
        );
      } else {
        // Fallback for malformed matches
        _emitStyled(children, matchText, baseStyle, lineOffset + match.start);
      }

      lastMatchEnd = match.end;
    }

    // Add remaining text after last match
    if (lastMatchEnd < line.length) {
      _emitStyled(children, line.substring(lastMatchEnd), baseStyle, lineOffset + lastMatchEnd);
    }
  }

  /// Hidden markdown markers: transparent and 1 px tall, about half a pixel
  /// wide per character. No negative letterSpacing to squeeze them to zero:
  /// every run with letter spacing makes the engine's paragraph layout much
  /// slower, and typing in a 100k-word manuscript went from about 2 s to
  /// about 0.35 s per keystroke without it (Mac profile build).
  static const TextStyle _hiddenMarkerStyle = TextStyle(color: Colors.transparent, fontSize: 1.0);

  /// Emits [run] as hidden opening marker, styled content, hidden closing
  /// marker. The markers are cut from [run] itself, so the span text always
  /// equals the document text.
  void _addHiddenRun(List<InlineSpan> children, String run, int openLen, int closeLen, TextStyle contentStyle, int runOffset) {
    children.add(TextSpan(text: run.substring(0, openLen), style: _hiddenMarkerStyle));
    _addInlineStyledText(children, run.substring(openLen, run.length - closeLen), contentStyle, runOffset + openLen);
    children.add(TextSpan(text: run.substring(run.length - closeLen), style: _hiddenMarkerStyle));
  }

  /// Replace-one / Replace-All for the in-editor Search & Replace palette.
  ///
  /// When [matchStart] is null every match of [pattern] is rewritten in one
  /// bulk edit (Replace All: one `value` assignment = one native undo step).
  /// When [matchStart] is given, only the single match beginning there is
  /// replaced (Replace one). No-op (returns count 0, `value` untouched) when
  /// nothing matches, so callers can skip the downstream provider/offset
  /// refresh.
  ///
  /// The caret is left collapsed just past the replaced span, which is a
  /// harmless resting place whether or not the editor currently has focus.
  ReplaceResult replaceMatches(RegExp pattern, String replacement, {int? matchStart}) {
    final result = matchStart != null
        ? replaceOne(text, pattern, replacement, matchStart)
        : replaceAll(text, pattern, replacement);
    if (result.count == 0) return result;

    final int caretOffset = matchStart != null
        ? (matchStart + replacement.length).clamp(0, result.text.length)
        : result.text.length;
    value = value.copyWith(
      text: result.text,
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    return result;
  }

  void toggleFormat(String tag) {
    final selection = this.selection;
    if (!selection.isValid) return;
    if (tag == 'indent' || tag == 'outdent') {
      indentListItems(outdent: tag == 'outdent');
      return;
    }
    if (tag == 'body') {
      _toggleLineFormat(tag);
      return;
    }
    if (selection.isCollapsed && !tag.endsWith(' ')) {
      // No selection: end the run at the caret, or style the next keystroke.
      final toggle = toggleInlineAtCaret(text, selection.baseOffset, tag);
      if (toggle != null) {
        markerCaret.setToggle(toggle);
        value = TextEditingValue(text: toggle.text, selection: TextSelection.collapsed(offset: toggle.caret));
      }
      return;
    }

    final selectedText = text.substring(selection.start, selection.end);
    
    if (tag.endsWith(' ') || tag == 'body') {
      // Line-based formatting (Title, Heading, Subheading, Bullet, Body)
      _toggleLineFormat(tag);
    } else {
      // Selection-based formatting (Bold, Italic)
      _toggleSelectionFormat(tag, selectedText);
    }
  }

  void _toggleSelectionFormat(String tag, String selectedText) {
    final selection = this.selection;
    final ranges = _findFormatRanges(text, 0);
    final activeRange = _findActiveRangeForTag(ranges, tag, selection.start, selection.end);

    String newText;
    int newStart;
    int newEnd;

    if (activeRange != null) {
      // Remove formatting
      final r = activeRange;
      if (r.tag == tag) {
        // Simple remove
        final prefixLen = r.contentStart - r.start;
        newText = text.replaceRange(r.contentEnd, r.end, '');
        newText = newText.replaceRange(r.start, r.contentStart, '');
        newStart = selection.start - prefixLen;
        newEnd = selection.end - prefixLen;
      } else if (r.tag == '***' && tag == '**') {
        // Convert *** to * (Remove Bold, keep Italic)
        newText = text.replaceRange(r.contentEnd, r.end, '*');
        newText = newText.replaceRange(r.start, r.contentStart, '*');
        newStart = selection.start - 2; // prefix *** (3) to * (1) -> shifted by 2
        newEnd = selection.end - 2;
      } else if (r.tag == '***' && tag == '*') {
        // Convert *** to ** (Remove Italic, keep Bold)
        newText = text.replaceRange(r.contentEnd, r.end, '**');
        newText = newText.replaceRange(r.start, r.contentStart, '**');
        newStart = selection.start - 1; // prefix *** (3) to ** (2) -> shifted by 1
        newEnd = selection.end - 1;
      } else {
        newText = text;
        newStart = selection.start;
        newEnd = selection.end;
      }
    } else {
      // Add formatting
      final endTag = tag == '<u>' ? '</u>' : tag;
      newText = text.replaceRange(selection.start, selection.end, '$tag$selectedText$endTag');
      newStart = selection.start + tag.length;
      newEnd = selection.end + tag.length;
    }

    value = value.copyWith(
      text: newText,
      selection: TextSelection(
        baseOffset: newStart.clamp(0, newText.length),
        extentOffset: newEnd.clamp(0, newText.length),
      ),
    );
  }

  List<_FormatRange> _findFormatRanges(String text, int offset) {
    final List<_FormatRange> ranges = [];
    _findRangesRecursive(text, offset, ranges);
    return ranges;
  }

  void _findRangesRecursive(String text, int offset, List<_FormatRange> ranges) {
    final regex = RegExp(r'(\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|<u>.*?</u>|~~.*?~~)');
    final matches = regex.allMatches(text);
    
    for (final match in matches) {
      final matchText = match.group(0)!;
      final matchStart = offset + match.start;
      final matchEnd = offset + match.end;
      
      if (matchText.startsWith('***') && matchText.endsWith('***') && matchText.length >= 6) {
        ranges.add(_FormatRange('***', matchStart, matchStart + 3, matchEnd - 3, matchEnd));
        _findRangesRecursive(matchText.substring(3, matchText.length - 3), matchStart + 3, ranges);
      } else if (matchText.startsWith('**') && matchText.endsWith('**') && matchText.length >= 4) {
        ranges.add(_FormatRange('**', matchStart, matchStart + 2, matchEnd - 2, matchEnd));
        _findRangesRecursive(matchText.substring(2, matchText.length - 2), matchStart + 2, ranges);
      } else if (matchText.startsWith('*') && matchText.endsWith('*') && matchText.length >= 2) {
        ranges.add(_FormatRange('*', matchStart, matchStart + 1, matchEnd - 1, matchEnd));
        _findRangesRecursive(matchText.substring(1, matchText.length - 1), matchStart + 1, ranges);
      } else if (matchText.startsWith('~~') && matchText.endsWith('~~') && matchText.length >= 4) {
        ranges.add(_FormatRange('~~', matchStart, matchStart + 2, matchEnd - 2, matchEnd));
        _findRangesRecursive(matchText.substring(2, matchText.length - 2), matchStart + 2, ranges);
      } else if (matchText.startsWith('<u>') && matchText.endsWith('</u>') && matchText.length >= 7) {
        ranges.add(_FormatRange('<u>', matchStart, matchStart + 3, matchEnd - 4, matchEnd));
        _findRangesRecursive(matchText.substring(3, matchText.length - 4), matchStart + 3, ranges);
      }
    }
  }

  _FormatRange? _findActiveRangeForTag(List<_FormatRange> ranges, String targetTag, int selStart, int selEnd) {
    for (final r in ranges) {
      if (selStart >= r.contentStart && selEnd <= r.contentEnd) {
        if (r.tag == targetTag) {
          return r;
        }
        if (targetTag == '**' && r.tag == '***') {
          return r;
        }
        if (targetTag == '*' && r.tag == '***') {
          return r;
        }
      }
    }
    return null;
  }

  void _toggleLineFormat(String tag) {
    final selection = this.selection;
    // Find the start and end of the current line(s)
    int start = selection.start;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }

    int end = selection.end;
    while (end < text.length && text[end] != '\n') {
      end++;
    }

    final lines = text.substring(start, end).split('\n');
    final bool turnOff = tag != 'body' && _lineHasStyle(lines.first, tag);
    final isList = tag == '- ' || tag == '1. ' || tag == '- [ ] ';
    final out = <String>[];
    for (final line in lines) {
      if (tag == 'body' || turnOff) {
        out.add(_stripBlockPrefix(line, keepIndent: false));
      } else {
        final lm = parseListMarker(line);
        final String indent = isList && lm != null ? lm.indent : '';
        out.add('$indent$tag${_stripBlockPrefix(line, keepIndent: false)}');
      }
    }
    final String newBlock = out.join('\n');
    var next = value.copyWith(
      text: text.replaceRange(start, end, newBlock),
      selection: TextSelection.collapsed(offset: start + newBlock.length),
      composing: TextRange.empty,
    );
    // Numbers around the changed lines count on (or close up).
    final bool numbered = isList || lines.any((l) => parseListMarker(l)?.kind == ListKind.number);
    if (numbered) {
      final int? bridge = lines.length == 1 && newBlock.trim().isNotEmpty && parseListMarker(newBlock) == null ? start : null;
      next = renumberValue(next, start, start + newBlock.length, bridge: bridge);
    }
    value = next;
  }

  static bool _lineHasStyle(String line, String tag) {
    switch (tag) {
      case '- ':
        return parseListMarker(line)?.kind == ListKind.bullet;
      case '1. ':
        return parseListMarker(line)?.kind == ListKind.number;
      case '- [ ] ':
        return parseListMarker(line)?.kind == ListKind.check;
      default:
        return line.startsWith(tag);
    }
  }

  /// [line] without its heading, quote or list marker (and indent).
  static String _stripBlockPrefix(String line, {required bool keepIndent}) {
    final lm = parseListMarker(line);
    if (lm != null) return (keepIndent ? lm.indent : '') + line.substring(lm.length);
    return line.replaceFirst(RegExp(r'^(#+\s*|-\s*|>\s*)'), '');
  }

  /// Indents (or unindents) the list items in the selection by one level.
  /// Returns false when no list line moved.
  bool indentListItems({required bool outdent}) {
    final next = indentLines(value, outdent: outdent);
    if (next == null) return false;
    value = next;
    return true;
  }

  /// Ticks / unticks the checkbox of the checklist item on the line at [lineStart].
  bool toggleCheckboxAt(int lineStart) {
    final next = toggleCheckbox(value, lineStart);
    if (next == null) return false;
    value = next;
    return true;
  }
}

class _FormatRange {
  final String tag;
  final int start;
  final int contentStart;
  final int contentEnd;
  final int end;
  
  _FormatRange(this.tag, this.start, this.contentStart, this.contentEnd, this.end);
}

/// One line's spans plus the line-relative state they were built from:
/// [misspellings], [grammar] and [mentions] are flattened start/end pairs measured from
/// the line start, [activeMatch] is the current Find match's line-relative
/// start or -1.
class _CachedLine {
  final bool dim;
  final int activeMatch;
  final List<int> misspellings;
  final List<int> grammar;
  final List<int> mentions;
  List<InlineSpan> spans = const [];

  _CachedLine(this.dim, this.activeMatch, this.misspellings, this.grammar, this.mentions);

  bool sameKey(_CachedLine other) =>
      dim == other.dim &&
      activeMatch == other.activeMatch &&
      _sameInts(misspellings, other.misspellings) &&
      _sameInts(grammar, other.grammar) &&
      _sameInts(mentions, other.mentions);

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The changed middle of an edit (common prefix/suffix trimmed) and its length delta.
class _EditSpan {
  final int prefix, editEnd, delta;
  const _EditSpan(this.prefix, this.editEnd, this.delta);

  factory _EditSpan.between(String oldText, String newText) {
    final int maxPrefix = oldText.length < newText.length ? oldText.length : newText.length;
    int prefix = 0;
    while (prefix < maxPrefix && oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    int suffix = 0;
    while (suffix < maxPrefix - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) == newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }
    return _EditSpan(prefix, oldText.length - suffix, newText.length - oldText.length);
  }

  /// The edit between two values, read off the selection: a pure insertion
  /// ends at the new caret, a pure deletion sits at it. Anything else (a
  /// replacement, a moved caret, or a mismatch in the text around the guess)
  /// falls back to the full scan.
  factory _EditSpan.fromValues(TextEditingValue oldV, TextEditingValue newV) {
    final String o = oldV.text, n = newV.text;
    final int delta = n.length - o.length;
    final sel = newV.selection;
    if (delta != 0 && sel.isValid && sel.isCollapsed) {
      final int c = sel.baseOffset;
      const int w = 48; // context compared on each side of the guess
      if (delta > 0 && oldV.selection.isValid && oldV.selection.isCollapsed) {
        final int start = c - delta; // insertion at [start, c) of the new text
        if (start >= 0 && c <= n.length && _sameWindow(o, start, n, c, w) && _sameBefore(o, n, start, w)) {
          return _EditSpan(start, start, delta);
        }
      } else if (delta < 0) {
        final int cut = c - delta; // old [c, cut) is gone
        if (c >= 0 && cut <= o.length && _sameWindow(o, cut, n, c, w) && _sameBefore(o, n, c, w)) {
          return _EditSpan(c, cut, delta);
        }
      }
    }
    return _EditSpan.between(o, n);
  }

  /// Whether [a] from [ai] and [b] from [bi] agree for up to [w] units and end together.
  static bool _sameWindow(String a, int ai, String b, int bi, int w) {
    final int la = a.length - ai, lb = b.length - bi;
    if (la != lb) return false;
    final int len = la < w ? la : w;
    for (int k = 0; k < len; k++) {
      if (a.codeUnitAt(ai + k) != b.codeUnitAt(bi + k)) return false;
    }
    // The tail matters as much as the window: check the very end too.
    return la <= w || a.codeUnitAt(a.length - 1) == b.codeUnitAt(b.length - 1);
  }

  static bool _sameBefore(String a, String b, int end, int w) {
    final int from = end < w ? 0 : end - w;
    for (int k = from; k < end; k++) {
      if (a.codeUnitAt(k) != b.codeUnitAt(k)) return false;
    }
    return true;
  }

  /// [r] unchanged if before the edit, moved if after, null if it touches it.
  TextRange? shift(TextRange r) {
    if (r.end <= prefix) return r;
    if (r.start >= editEnd) return delta == 0 ? r : TextRange(start: r.start + delta, end: r.end + delta);
    return null;
  }
}
