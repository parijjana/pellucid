// Description: Colour of the grammar-hint underline, distinct from the red
// wavy spell-check underline (these are dotted and blue/teal).

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Candidates, tried in order; the first with at least 3:1 against the page
/// wins, else the best available.
const _candidates = <Color>[
  Color(0xFF1565C0), // deep blue, light pages
  Color(0xFF64B5F6), // light blue, dark pages
  Color(0xFF00695C), // deep teal
  Color(0xFF80DEEA), // light cyan
  Color(0xFFFFFFFF),
  Color(0xFF000000),
];

Color grammarHintColor(WriterTheme theme) {
  Color best = _candidates.first;
  double bestRatio = 0;
  for (final c in _candidates) {
    final r = contrastRatio(c, theme.backgroundColor);
    if (r >= 3.0) return c;
    if (r > bestRatio) {
      best = c;
      bestRatio = r;
    }
  }
  return best;
}
