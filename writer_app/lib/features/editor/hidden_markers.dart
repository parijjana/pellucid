// Description: Where MarkdownEditingController hides markdown markers, and the
// caret rules that follow from it (backlog item 24).
//
// The scan mirrors MarkdownEditingController.buildTextSpan line by line: block
// prefixes (`# `, `## `, `### `, `> `, `- `) on block lines, inline runs (`***`,
// `**`, `*`, `<u>`, `~~`) on every other line and inside block quotes. test/features/editor/hidden_markers_test.dart
// checks the two agree, so a change to the renderer that is not made here fails.

import 'package:flutter/services.dart';

import 'list_marker.dart';

/// Block-line markers the renderer hides, longest first so `### ` wins over
/// `# `-style prefixes. A line starting with one is styled as a block and its
/// inline markers are left as typed (the renderer does not parse them), except
/// in a block quote, whose text is rendered inline.
const List<String> hiddenBlockPrefixes = ['# ', '## ', '### ', '> ', '- '];

// Every block line renders inline formatting (bold, italic, underline, strike)
// in its text, so `**` and friends are hidden on heading, quote and list lines
// too. List lines may start with indent and carry `1. ` or `- [ ] ` markers:
// see list_marker.dart.

/// An inline formatting run: `[start, contentStart)` is the opening marker,
/// `[contentEnd, end)` the closing one. Absolute offsets.
class InlineRun {
  final String tag;
  final int start;
  final int contentStart;
  final int contentEnd;
  final int end;

  const InlineRun(this.tag, this.start, this.contentStart, this.contentEnd, this.end);

  String get closingTag => tag == '<u>' ? '</u>' : tag;
  bool get isEmpty => contentStart == contentEnd;
  bool get bold => tag == '**' || tag == '***';
  bool get italic => tag == '*' || tag == '***';
  bool get underline => tag == '<u>';
  bool get strikethrough => tag == '~~';

  @override
  String toString() => 'InlineRun($tag, $start, $contentStart, $contentEnd, $end)';
}

/// The hidden markers of one line (`[lineStart, lineEnd)`, no newline).
class LineMarkers {
  final int lineStart;
  final int lineEnd;

  /// The hidden block prefix (`# `, `- `, `1. `, `- [ ] `, ...) or null on an
  /// inline line. On a list line it follows [indent].
  final String? prefix;

  /// Characters of visible indent before a list prefix (0 otherwise).
  final int indent;

  /// The list marker of a list line, else null.
  final ListMarker? list;

  /// Inline runs, outermost first within each match.
  final List<InlineRun> runs;

  /// Every hidden range, sorted, absolute.
  final List<TextRange> hidden;

  const LineMarkers(this.lineStart, this.lineEnd, this.prefix, this.runs, this.hidden,
      {this.indent = 0, this.list});

  int get prefixStart => lineStart + indent;
  int get prefixEnd => prefixStart + (prefix?.length ?? 0);

  /// True when [prefix] is a paragraph indent (em spaces), not a block marker.
  bool get isParagraphIndent => prefix != null && list == null && prefix!.codeUnitAt(0) == 0x2003;

  bool isHidden(int offset) {
    for (final r in hidden) {
      if (offset < r.start) return false;
      if (offset < r.end) return true;
    }
    return false;
  }
}

final RegExp _inlineRegex = RegExp(r'(\*\*\*.*?\*\*\*|\*\*.*?\*\*|\*.*?\*|<u>.*?</u>|~~.*?~~)');

/// Start of the line containing [offset] (an offset at a newline belongs to
/// the line that newline ends).
int lineStartOf(String text, int offset) {
  int i = offset.clamp(0, text.length);
  while (i > 0 && text.codeUnitAt(i - 1) != 0x0A) {
    i--;
  }
  return i;
}

int lineEndOf(String text, int offset) {
  int i = offset.clamp(0, text.length);
  while (i < text.length && text.codeUnitAt(i) != 0x0A) {
    i++;
  }
  return i;
}

LineMarkers scanLineAt(String text, int offset) {
  final int start = lineStartOf(text, offset);
  return scanLine(text, start, lineEndOf(text, start));
}

LineMarkers scanLine(String text, int lineStart, int lineEnd) {
  final String line = text.substring(lineStart, lineEnd);
  final ListMarker? lm = parseListMarker(line);
  if (lm != null) {
    final int pStart = lineStart + lm.indent.length;
    final hidden = [TextRange(start: pStart, end: pStart + lm.marker.length)];
    final runs = <InlineRun>[];
    _scanInline(line.substring(lm.length), lineStart + lm.length, runs, hidden);
    hidden.sort((a, b) => a.start.compareTo(b.start));
    return LineMarkers(lineStart, lineEnd, lm.marker, runs, hidden, indent: lm.indent.length, list: lm);
  }
  // Paragraph indent (slice 5b): leading U+2003 em spaces are a hidden prefix
  // (the caret rests after them) drawn as blank space.
  final int indentCount = paragraphIndentCount(line);
  if (indentCount > 0) {
    final String run = line.substring(0, indentCount);
    final hidden = [TextRange(start: lineStart, end: lineStart + indentCount)];
    final runs = <InlineRun>[];
    _scanInline(line.substring(indentCount), lineStart + indentCount, runs, hidden);
    hidden.sort((a, b) => a.start.compareTo(b.start));
    return LineMarkers(lineStart, lineEnd, run, runs, hidden);
  }
  for (final p in _prefixCheckOrder) {
    if (line.startsWith(p)) {
      final hidden = [TextRange(start: lineStart, end: lineStart + p.length)];
      final runs = <InlineRun>[];
      _scanInline(line.substring(p.length), lineStart + p.length, runs, hidden);
      hidden.sort((a, b) => a.start.compareTo(b.start));
      return LineMarkers(lineStart, lineEnd, p, runs, hidden);
    }
  }
  final runs = <InlineRun>[];
  final hidden = <TextRange>[];
  _scanInline(line, lineStart, runs, hidden);
  hidden.sort((a, b) => a.start.compareTo(b.start));
  return LineMarkers(lineStart, lineEnd, null, runs, hidden);
}

// Same order as buildTextSpan's if/else chain.
const List<String> _prefixCheckOrder = ['# ', '## ', '### ', '> '];

void _scanInline(String s, int offset, List<InlineRun> runs, List<TextRange> hidden) {
  for (final m in _inlineRegex.allMatches(s)) {
    final t = m.group(0)!;
    final int a = offset + m.start;
    final int b = offset + m.end;
    int open;
    int close;
    String tag;
    if (t.startsWith('***') && t.length >= 6) {
      tag = '***';
      open = 3;
      close = 3;
    } else if (t.startsWith('**') && t.length >= 4) {
      tag = '**';
      open = 2;
      close = 2;
    } else if (t.startsWith('*') && t.length >= 2) {
      tag = '*';
      open = 1;
      close = 1;
    } else if (t.startsWith('<u>') && t.endsWith('</u>') && t.length >= 7) {
      tag = '<u>';
      open = 3;
      close = 4;
    } else if (t.startsWith('~~') && t.endsWith('~~') && t.length >= 4) {
      tag = '~~';
      open = 2;
      close = 2;
    } else {
      continue; // malformed: rendered as typed
    }
    runs.add(InlineRun(tag, a, a + open, b - close, b));
    hidden.add(TextRange(start: a, end: a + open));
    hidden.add(TextRange(start: b - close, end: b));
    _scanInline(t.substring(open, t.length - close), a + open, runs, hidden);
  }
}

/// A maximal stretch of touching hidden ranges. Every offset in
/// `[start, end]` draws at the same place on screen.
class MarkerCluster {
  final int start;
  final int end;
  final bool isBlockPrefix;
  const MarkerCluster(this.start, this.end, this.isBlockPrefix);
}

MarkerCluster? clusterAt(LineMarkers line, int offset) {
  int? cs;
  int? ce;
  for (final r in line.hidden) {
    if (ce != null && r.start == ce) {
      ce = r.end;
    } else {
      if (cs != null && offset >= cs && offset <= ce!) break;
      cs = r.start;
      ce = r.end;
    }
  }
  if (cs == null || offset < cs || offset > ce!) return null;
  return MarkerCluster(cs, ce, line.prefix != null && cs == line.prefixStart);
}

/// Where the caret rests when it is anywhere in a cluster of hidden markers:
/// - after a block prefix (typing there writes the heading/bullet text);
/// - otherwise before the cluster, which is inside a run that ends there and
///   outside a run that starts there: text typed at the end of a styled run
///   continues the style, text typed at its start does not.
int canonicalOffset(String text, int offset) {
  if (offset < 0 || offset > text.length) return offset;
  final line = scanLineAt(text, offset);
  if (line.hidden.isEmpty) return offset;
  final c = clusterAt(line, offset);
  if (c == null) return offset;
  return c.isBlockPrefix ? c.end : c.start;
}

bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;

/// One visible character to the right of [offset]: hidden markers are crossed
/// as if they had no width, then canonicalised.
int stepRight(String text, int offset) {
  int q = offset;
  LineMarkers line = scanLineAt(text, q);
  while (q < line.lineEnd && line.isHidden(q)) {
    q++;
  }
  if (q >= text.length) return canonicalOffset(text, text.length);
  if (q < text.length - 1 && _isHigh(text.codeUnitAt(q)) && _isLow(text.codeUnitAt(q + 1))) {
    q += 2;
  } else {
    q += 1;
  }
  return canonicalOffset(text, q);
}

/// One visible character to the left of [offset].
int stepLeft(String text, int offset) {
  int q = offset;
  final line = scanLineAt(text, q);
  while (q > line.lineStart && line.isHidden(q - 1)) {
    q--;
  }
  if (q <= 0) return canonicalOffset(text, 0);
  if (q > 1 && _isLow(text.codeUnitAt(q - 1)) && _isHigh(text.codeUnitAt(q - 2))) {
    q -= 2;
  } else {
    q -= 1;
  }
  final int c = canonicalOffset(text, q);
  // Landing back where we started (a cluster that canonicalises forward, such
  // as a block prefix) would make the key do nothing: go one more.
  return c == offset && q > 0 ? stepLeft(text, q) : c;
}

/// The plain text a reader sees: hidden markers removed, a bullet prefix
/// shown as the glyph the editor draws.
String visibleText(String text) {
  final out = StringBuffer();
  int ls = 0;
  while (ls <= text.length) {
    final int le = lineEndOf(text, ls);
    final line = scanLine(text, ls, le);
    int i = ls;
    final lm = line.list;
    if (lm != null) {
      // The drawn glyph stands in for the stored marker (and may sit over the
      // end of the indent).
      final g = listGlyph(lm);
      out.write(lm.indent.substring(0, lm.indent.length - g.absorbed));
      out.write(g.shown);
    }
    if (line.isParagraphIndent) out.write(line.prefix); // the indent is visible space
    for (final r in line.hidden) {
      if (lm != null && r.start == line.prefixStart) {
        i = r.end;
        continue;
      }
      if (r.start > i) out.write(text.substring(i, r.start));
      i = r.end;
    }
    if (i < le) out.write(text.substring(i, le));
    if (le >= text.length) break;
    out.write('\n');
    ls = le + 1;
  }
  return out.toString();
}
