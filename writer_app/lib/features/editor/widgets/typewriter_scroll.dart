// Description: Caret measurement helper for typewriter scrolling.
// Lays out only the text up to the caret so the cost stays proportional to
// caret position (same approximation as the editor's search jump logic).

import 'package:flutter/material.dart';

/// Vertical inset between the top of the scroll content and the first text
/// line: SingleChildScrollView vertical padding (100) + paper padding (60).
const double kEditorTextTopInset = 160.0;

/// Returns the scroll offset that vertically centers the caret line in the
/// viewport. Mirrors the editor's text style parameters (16.0 * zoom,
/// height 1.8, Georgia, maxWidth = pageWidth - 120.0). Result is NOT clamped
/// to the scroll extents; callers must clamp.
double typewriterTargetOffset({
  required String text,
  required int caretOffset,
  required double zoomLevel,
  required double pageWidth,
  required double viewportHeight,
}) {
  final int clampedCaret = caretOffset.clamp(0, text.length);
  final String measured = text.substring(0, clampedCaret);

  final textPainter = TextPainter(
    text: TextSpan(
      text: measured,
      style: TextStyle(
        fontSize: 16.0 * zoomLevel,
        height: 1.8,
        fontFamily: 'Georgia',
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  textPainter.layout(maxWidth: pageWidth - 120.0);

  final double caretTop = textPainter
      .getOffsetForCaret(TextPosition(offset: measured.length), Rect.zero)
      .dy;
  final double lineHeight = 16.0 * zoomLevel * 1.8;
  final double caretCenter = kEditorTextTopInset + caretTop + (lineHeight / 2);
  return caretCenter - (viewportHeight / 2);
}
