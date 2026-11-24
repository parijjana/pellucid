import 'package:flutter/services.dart' show SuggestionSpan;
import 'package:flutter/widgets.dart' show TextRange;

/// One checkable piece of the manuscript: a paragraph (text between line breaks), or a stretch of an
/// over-long paragraph cut at whitespace so that no piece exceeds the chunk size. Offsets are into the
/// whole text; [end] is exclusive and never includes the line break.
class SpellUnit {
  final int start;
  final int end;
  const SpellUnit(this.start, this.end);
  int get length => end - start;
  @override
  String toString() => 'SpellUnit($start, $end)';
}

/// Splits [text] into paragraph pieces of at most [maxChars] UTF-16 units. Blank lines produce no unit.
/// A paragraph longer than [maxChars] is cut at the last whitespace within the limit (never inside a
/// word when it can be avoided, never between the two halves of a surrogate pair). A carriage return
/// before a line feed stays at the end of its piece, so CRLF documents keep their offsets.
List<SpellUnit> splitSpellUnits(String text, {int maxChars = 2000}) {
  assert(maxChars >= 16);
  final units = <SpellUnit>[];
  int lineStart = 0;
  while (lineStart <= text.length) {
    int lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd < 0) lineEnd = text.length;
    int s = lineStart;
    while (s < lineEnd) {
      int e = lineEnd;
      if (e - s > maxChars) {
        e = s + maxChars;
        int cut = e;
        while (cut > s + 1 && !_isSpace(text.codeUnitAt(cut - 1))) {
          cut--;
        }
        if (cut > s + 1) {
          e = cut;
        } else if (_isHigh(text.codeUnitAt(e - 1))) {
          e--; // do not split a surrogate pair
        }
      }
      if (text.substring(s, e).trim().isNotEmpty) units.add(SpellUnit(s, e));
      s = e;
    }
    lineStart = lineEnd + 1;
  }
  return units;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0D || c == 0xA0 || c == 0x3000 || (c >= 0x2000 && c <= 0x200A);
bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;

/// Runs a whole-text spell check as many short calls and remembers the answer per piece (keyed by the
/// piece's text), so an edit costs one piece and the first check of a long manuscript never blocks the
/// UI for longer than one batch of about [maxChars] characters.
///
/// Results equal the whole-text check's: a span never crosses a line break, and the pieces are cut only
/// at line breaks and whitespace.
class SpellChunkChecker {
  SpellChunkChecker(this._check, {this.maxChars = 2000, this.yieldAfter = const Duration(milliseconds: 30)});

  final Future<List<SuggestionSpan>?> Function(String text) _check;
  final int maxChars;

  /// After a batch that took at least this long the loop yields to the event loop (input, frames).
  final Duration yieldAfter;

  final Map<String, List<_Rel>> _cache = {};

  /// Native calls made by the last [check] (for tests and timing).
  int callsLastCheck = 0;

  int get cachedPieces => _cache.length;

  /// Forget everything (dictionary changed, language changed, spell check toggled).
  void clear() => _cache.clear();

  /// Spans for [text], absolute offsets. Returns null when [cancelled] became true (the partial work stays
  /// cached). [onProgress] gets the spans known so far, at most about once a second, while batches remain.
  Future<List<SuggestionSpan>?> check(
    String text, {
    bool Function()? cancelled,
    void Function(List<SuggestionSpan> partial)? onProgress,
  }) async {
    callsLastCheck = 0;
    final units = splitSpellUnits(text, maxChars: maxChars);
    final keys = [for (final u in units) text.substring(u.start, u.end)];
    final clock = Stopwatch()..start();
    var lastYield = clock.elapsed;
    var lastProgress = clock.elapsed;

    int i = 0;
    while (i < units.length) {
      if (cancelled?.call() ?? false) return null;
      if (_cache.containsKey(keys[i])) {
        i++;
        continue;
      }
      // Batch: this piece plus the pieces after it while they fit in maxChars.
      int j = i;
      while (j + 1 < units.length && units[j + 1].end - units[i].start <= maxChars) {
        j++;
      }
      final from = units[i].start, to = units[j].end;
      final spans = await _check(text.substring(from, to));
      callsLastCheck++;
      if (cancelled?.call() ?? false) return null;
      for (int k = i; k <= j; k++) {
        _cache[keys[k]] = const [];
      }
      int k = i;
      final fresh = <int, List<_Rel>>{};
      for (final s in spans ?? const <SuggestionSpan>[]) {
        final abs = from + s.range.start;
        final absEnd = from + s.range.end;
        while (k <= j && units[k].end <= abs) {
          k++;
        }
        if (k > j) break;
        if (abs < units[k].start || absEnd > units[k].end) continue; // not inside one piece: cannot happen
        (fresh[k] ??= []).add(_Rel(abs - units[k].start, absEnd - units[k].start, s.suggestions));
      }
      fresh.forEach((idx, rels) => _cache[keys[idx]] = rels);
      i = j + 1;

      if (i < units.length) {
        final now = clock.elapsed;
        if (onProgress != null && now - lastProgress > const Duration(seconds: 1)) {
          lastProgress = now;
          onProgress(_assemble(units, keys));
        }
        if (now - lastYield >= yieldAfter) {
          await Future<void>.delayed(Duration.zero);
          lastYield = clock.elapsed;
        }
      }
    }
    return _assemble(units, keys);
  }

  List<SuggestionSpan> _assemble(List<SpellUnit> units, List<String> keys) {
    final out = <SuggestionSpan>[];
    for (int n = 0; n < units.length; n++) {
      final rels = _cache[keys[n]];
      if (rels == null) continue;
      for (final r in rels) {
        out.add(SuggestionSpan(TextRange(start: units[n].start + r.start, end: units[n].start + r.end), r.suggestions));
      }
    }
    return out;
  }
}

class _Rel {
  final int start, end;
  final List<String> suggestions;
  const _Rel(this.start, this.end, this.suggestions);
}
