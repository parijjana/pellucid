// Description: Splits styled text spans so chosen ranges carry an underline.
// Shared by the editor's spell-check and grammar-hint underlines.

import 'package:flutter/material.dart';

/// Splits leaf spans (contiguous from [startOffset]) wherever they cross one
/// of [ranges] (sorted by start) and gives those pieces [decoration].
List<InlineSpan> underlineRanges(
  List<InlineSpan> spans,
  int startOffset,
  List<TextRange> ranges, {
  required TextDecorationStyle decorationStyle,
  required Color color,
  double thickness = 2.0,
}) {
  final List<InlineSpan> out = [];
  int offset = startOffset;
  for (final span in spans) {
    final textSpan = span as TextSpan;
    final String run = textSpan.text ?? '';
    final int runEnd = offset + run.length;
    int cursor = 0;
    for (final r in ranges) {
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
          decorationStyle: decorationStyle,
          decorationColor: color,
          decorationThickness: thickness,
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
