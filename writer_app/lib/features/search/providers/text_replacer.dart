// Description: Pure text-replacement engine shared by in-editor Search & Replace
// (Phase 1: case-insensitive substring, mirrors search_provider's matcher) and the
// future rename-propagation engine (Phase 3: case-sensitive whole-word). No
// styling, no widgets, no provider access — callers supply the compiled RegExp
// and, for Replace-All, an optional skip range.

class ReplaceResult {
  final String text;
  final int count;
  const ReplaceResult(this.text, this.count);
}

/// Replaces every match of [pattern] in [source] with [replacement].
///
/// [pattern] is supplied by the caller so search (case-insensitive substring)
/// and rename (case-sensitive whole-word) can share this one replacer with two
/// different regex builders.
///
/// When both [skipRangeStart] and [skipRangeEnd] are supplied, any match that
/// overlaps `[skipRangeStart, skipRangeEnd)` is left untouched — used by
/// Phase 3 to exclude the auto-generated `# Attributions` region. Phase 1
/// always passes them null.
///
/// A [pattern] with an empty source (e.g. built from an empty query) matches
/// nothing, mirroring search's own empty-query short-circuit.
ReplaceResult replaceAll(
  String source,
  RegExp pattern,
  String replacement, {
  int? skipRangeStart,
  int? skipRangeEnd,
}) {
  if (pattern.pattern.isEmpty) return ReplaceResult(source, 0);

  final bool hasSkipRange = skipRangeStart != null && skipRangeEnd != null;
  final buffer = StringBuffer();
  int lastEnd = 0;
  int count = 0;

  for (final match in pattern.allMatches(source)) {
    final bool skipped = hasSkipRange &&
        match.start < skipRangeEnd &&
        match.end > skipRangeStart;
    if (skipped) continue;

    buffer.write(source.substring(lastEnd, match.start));
    buffer.write(replacement);
    lastEnd = match.end;
    count++;
  }

  if (count == 0) return ReplaceResult(source, 0);
  buffer.write(source.substring(lastEnd));
  return ReplaceResult(buffer.toString(), count);
}

/// Replaces only the single match of [pattern] that begins exactly at
/// [matchStart]. Returns [source] unchanged (count 0) if no such match exists.
ReplaceResult replaceOne(
  String source,
  RegExp pattern,
  String replacement,
  int matchStart,
) {
  if (pattern.pattern.isEmpty) return ReplaceResult(source, 0);

  for (final match in pattern.allMatches(source)) {
    if (match.start == matchStart) {
      final newText = source.replaceRange(match.start, match.end, replacement);
      return ReplaceResult(newText, 1);
    }
    if (match.start > matchStart) break;
  }
  return ReplaceResult(source, 0);
}
