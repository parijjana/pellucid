// @trace FEAT-20260516-120000-0001
// Description: A custom TextEditingController that styles Markdown in real-time and hides tags.

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../providers/codex_index.dart';
import '../../search/providers/text_replacer.dart';

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

  /// Keeps underlines on the right words between checks: ranges before the
  /// edit stay, ranges after it move with it, ranges touching it are dropped
  /// until the next check.
  @override
  set value(TextEditingValue newValue) {
    if (_misspellings.isNotEmpty && newValue.text != text) {
      _misspellings = shiftRangesForEdit(_misspellings, text, newValue.text);
    }
    super.value = newValue;
  }

  static List<TextRange> shiftRangesForEdit(List<TextRange> ranges, String oldText, String newText) {
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
    final int editEnd = oldText.length - suffix;
    final int delta = newText.length - oldText.length;
    return [
      for (final r in ranges)
        if (r.end <= prefix)
          r
        else if (r.start >= editEnd)
          TextRange(start: r.start + delta, end: r.end + delta),
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
    if (codexIndex.setTitles(titles)) notifyListeners();
  }

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
    final spans = _searchHighlight(text, baseStyle, query, startOffset);
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
  // text, whether it is dimmed, and the ranges that fall inside it, measured
  // from the line start; everything else that styles a line (theme, base
  // style, search query) clears the cache when it changes. Relative keys keep
  // lines after an edit cacheable even though their absolute offsets moved.
  Map<String, List<_CachedLine>> _lineCache = {};
  WriterTheme? _cacheTheme;
  TextStyle? _cacheStyle;
  String? _cacheQuery;

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

    if (!identical(theme, _cacheTheme) || style != _cacheStyle || searchQuery != _cacheQuery) {
      _lineCache = {};
      _cacheTheme = theme;
      _cacheStyle = style;
      _cacheQuery = searchQuery;
    }
    final Map<String, List<_CachedLine>> previous = _lineCache;
    final Map<String, List<_CachedLine>> next = {};
    final List<MentionRange> mentions =
        _codexLinkingEnabled ? codexIndex.rangesFor(text) : const [];
    int missIndex = 0;
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
        final key = _CachedLine(dim, active, miss, marks);

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

  void _addLine(List<InlineSpan> children, String line, int lineOffset, bool dim, TextStyle? style) {
    final Color? contentColor = dim ? theme.foregroundColor.withValues(alpha: 0.38) : null;
    if (line.startsWith('# ')) {
      _addStyledBlock(children, line, r'^# ', 32.0, FontWeight.bold, lineOffset, contentColor: contentColor);
    } else if (line.startsWith('## ')) {
      _addStyledBlock(children, line, r'^## ', 24.0, FontWeight.bold, lineOffset, contentColor: contentColor);
    } else if (line.startsWith('### ')) {
      _addStyledBlock(children, line, r'^### ', 18.0, FontWeight.bold, lineOffset, contentColor: contentColor);
    } else if (line.startsWith('- ')) {
      _addStyledBlock(children, line, r'^- ', 18.0, FontWeight.normal, lineOffset, isBullet: true, contentColor: contentColor);
    } else {
      final baseStyle = style ?? const TextStyle();
      _addInlineStyledText(children, line, contentColor != null ? baseStyle.copyWith(color: contentColor) : baseStyle, lineOffset);
    }
  }

  void _addStyledBlock(List<InlineSpan> children, String line, String pattern, double fontSize, FontWeight weight, int lineOffset, {bool isBullet = false, Color? contentColor}) {
    final regex = RegExp(pattern);
    final match = regex.firstMatch(line);
    
    if (match != null) {
      final TextStyle contentStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: weight,
        color: contentColor ?? theme.foregroundColor,
      );
      if (isBullet) {
        // The "- " marker is drawn as "• " in its place: same length, so the
        // span text stays character-for-character aligned with the document
        // text. EditableText maps caret, selection and taps through the
        // span text; an extra glyph shifted every offset after each bullet.
        children.add(TextSpan(text: '• ', style: contentStyle));
      } else {
        // Hide the markdown tag
        children.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(color: Colors.transparent, fontSize: 1.0, letterSpacing: -1.0),
        ));
      }
      final String content = line.substring(match.end);
      final int blockOffset = lineOffset + match.end;
      _emitStyled(children, content, contentStyle, blockOffset);
    }
  }

  void _addInlineStyledText(List<InlineSpan> children, String line, TextStyle baseStyle, int lineOffset) {
    // Scan for Bold + Italic (***), Bold (**), Italic (*), or Underline (<u>)
    final regex = RegExp(r'(\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|<u>.*?</u>)');
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

  static const TextStyle _hiddenMarkerStyle = TextStyle(color: Colors.transparent, fontSize: 1.0, letterSpacing: -1.0);

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
    if (selection.isCollapsed && !tag.endsWith(' ')) {
      // For selection-based tags like ** or *, do nothing if no selection
      return;
    }

    final selectedText = text.substring(selection.start, selection.end);
    
    if (tag.endsWith(' ')) {
      // Line-based formatting (Title, Heading, Bullet)
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
    final regex = RegExp(r'(\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|<u>.*?</u>)');
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

    final lineContent = text.substring(start, end);
    String newLineContent;

    if (tag == 'body') {
      // Remove any leading header or bullet tags
      newLineContent = lineContent.replaceFirst(RegExp(r'^(#+\s*|-\s*)'), '');
    } else if (lineContent.startsWith(tag)) {
      // Remove existing tag
      newLineContent = lineContent.substring(tag.length);
    } else {
      // Remove existing tag first if any, then add new tag
      final stripped = lineContent.replaceFirst(RegExp(r'^(#+\s*|-\s*)'), '');
      newLineContent = '$tag$stripped';
    }

    value = value.copyWith(
      text: text.replaceRange(start, end, newLineContent),
      selection: TextSelection.collapsed(offset: start + newLineContent.length),
    );
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
/// [misspellings] and [mentions] are flattened start/end pairs measured from
/// the line start, [activeMatch] is the current Find match's line-relative
/// start or -1.
class _CachedLine {
  final bool dim;
  final int activeMatch;
  final List<int> misspellings;
  final List<int> mentions;
  List<InlineSpan> spans = const [];

  _CachedLine(this.dim, this.activeMatch, this.misspellings, this.mentions);

  bool sameKey(_CachedLine other) =>
      dim == other.dim &&
      activeMatch == other.activeMatch &&
      _sameInts(misspellings, other.misspellings) &&
      _sameInts(mentions, other.mentions);

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
