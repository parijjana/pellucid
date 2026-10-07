// Item 14: the document font, an app-level choice (markdown cannot carry a
// per-span font). Three families, all resolved from fonts the platform already
// ships, so nothing is bundled and no font licence applies. The PDF export maps
// the same ids to the PDF standard fonts (Times, Helvetica, Courier), which are
// also not embedded; see export_service.dart.

import 'package:flutter/painting.dart';

enum EditorFont {
  serif('serif', 'Serif', 'Georgia', ['Times New Roman', 'Noto Serif', 'serif']),
  sans('sans', 'Sans', 'Helvetica Neue', ['Segoe UI', 'Roboto', 'Arial', 'sans-serif']),
  monospace('monospace', 'Monospace', 'Menlo', ['Consolas', 'Roboto Mono', 'Courier New', 'monospace']);

  const EditorFont(this.id, this.label, this.family, this.fallback);

  /// Stable id stored in the settings database.
  final String id;
  final String label;
  final String family;
  final List<String> fallback;

  /// The default (and what every document used before this setting existed).
  static const EditorFont defaultFont = EditorFont.serif;

  static EditorFont fromId(String? id) =>
      EditorFont.values.firstWhere((f) => f.id == id, orElse: () => defaultFont);

  /// Applies this family to [base]. Every editor text style (the TextField,
  /// typewriter and jump-to-header measurement) goes through here so they all
  /// agree on glyph widths.
  TextStyle apply([TextStyle base = const TextStyle()]) =>
      base.copyWith(fontFamily: family, fontFamilyFallback: fallback);
}
