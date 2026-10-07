// Description: Finds fenced code blocks and inline code spans in Markdown, so
// language tools (grammar hints, smart punctuation) can leave code alone.

import 'package:flutter/painting.dart';

/// Absolute ranges of fenced code blocks and inline code in [text].
///
/// A fence (```` ``` ```` or `~~~`) runs to the closing fence, or to the end
/// of the text while it is still open. Inline code is a run of backticks to
/// the next run of the same length on the same line. With [openEnded], an
/// unmatched backtick run counts as code to the end of its line (what a
/// writer mid-way through typing `code` means); without it, it is ignored.
List<TextRange> markdownCodeRanges(String text, {bool openEnded = false}) {
  final out = <TextRange>[];
  int pos = 0;
  int? fenceStart;
  String fenceChar = '';
  while (pos <= text.length) {
    int end = text.indexOf('\n', pos);
    if (end == -1) end = text.length;
    final line = text.substring(pos, end);
    final trimmed = line.trimLeft();
    final isFenceLine = trimmed.startsWith('```') || trimmed.startsWith('~~~');
    if (fenceStart != null) {
      if (isFenceLine && trimmed[0] == fenceChar) {
        out.add(TextRange(start: fenceStart, end: end));
        fenceStart = null;
      }
    } else if (isFenceLine) {
      fenceStart = pos;
      fenceChar = trimmed[0];
    } else if (line.contains('`')) {
      _inlineCode(line, pos, openEnded, out);
    }
    pos = end + 1;
  }
  if (fenceStart != null) out.add(TextRange(start: fenceStart, end: text.length));
  return out;
}

void _inlineCode(String line, int base, bool openEnded, List<TextRange> out) {
  int i = 0;
  while (i < line.length) {
    if (line[i] != '`') {
      i++;
      continue;
    }
    int n = 0;
    while (i + n < line.length && line[i + n] == '`') {
      n++;
    }
    // Find the next run of exactly n backticks.
    int j = i + n;
    int? close;
    while (j < line.length) {
      if (line[j] != '`') {
        j++;
        continue;
      }
      int m = 0;
      while (j + m < line.length && line[j + m] == '`') {
        m++;
      }
      if (m == n) {
        close = j + m;
        break;
      }
      j += m;
    }
    if (close != null) {
      out.add(TextRange(start: base + i, end: base + close));
      i = close;
    } else {
      if (openEnded) out.add(TextRange(start: base + i, end: base + line.length));
      return;
    }
  }
}

/// Whether [offset] sits strictly inside one of [ranges].
bool offsetInRanges(List<TextRange> ranges, int offset) {
  for (final r in ranges) {
    if (offset > r.start && offset < r.end) return true;
  }
  return false;
}
