// Description: Duplicate check for the attribution list. Duplicates stay
// allowed; the editor highlights every line that has one.

final RegExp _leadingMarker = RegExp(r'^(?:[-*+•◦▪–—]|\d+[.)])\s+');

/// Comparison key for an attribution line: trimmed, leading bullet or number
/// dropped, whitespace collapsed, case ignored.
String normalizeAttribution(String text) {
  var t = text.trim();
  t = t.replaceFirst(_leadingMarker, '');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

/// Indexes of every line that has at least one duplicate (both sides of a
/// pair). Blank lines never count.
Set<int> duplicateAttributionIndexes(List<String> texts) {
  final byKey = <String, List<int>>{};
  for (var i = 0; i < texts.length; i++) {
    final key = normalizeAttribution(texts[i]);
    if (key.isEmpty) continue;
    byKey.putIfAbsent(key, () => []).add(i);
  }
  return {
    for (final group in byKey.values)
      if (group.length > 1) ...group,
  };
}
