// Description: Line-indexed text of one document for the windowed editor
// (slice 3b, backlog item 23). Holds the manuscript as lines plus each line's
// start offset, so offset <-> line lookups are a binary search and an edit
// touches only the lines it changes. Per-line word counts make the total a
// running sum instead of a whole-document scan per keystroke.

import 'dart:math';

import '../word_count.dart';

class DocumentBuffer {
  DocumentBuffer(String text) {
    _lines = text.split('\n');
    _rebuildIndex(0);
    _words = [for (final l in _lines) countWords(l)];
    _wordTotal = _words.fold(0, (a, b) => a + b);
    _text = text;
  }

  late List<String> _lines;
  // _starts[i] is the offset of line i; the newline after line i is at
  // _starts[i] + _lines[i].length.
  final List<int> _starts = [];
  late List<int> _words;
  late int _wordTotal;
  String? _text;

  int get lineCount => _lines.length;
  String line(int i) => _lines[i];
  int lineStart(int i) => _starts[i];
  int lineEnd(int i) => _starts[i] + _lines[i].length;
  int get length => _starts.last + _lines.last.length;
  int get wordCount => _wordTotal;
  int wordsInLine(int i) => _words[i];

  /// The whole text. Built on demand after an edit and cached until the next.
  String get text => _text ??= _lines.join('\n');

  /// Line containing [offset]; an offset on a newline belongs to the line it ends.
  int lineOfOffset(int offset) {
    final int o = offset.clamp(0, length);
    int lo = 0, hi = _lines.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= o) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Text of lines [first, last) joined by newlines.
  String textOfLines(int first, int last) => _lines.sublist(first, last).join('\n');

  /// Replaces [start, end) with [inserted]. Only the touched lines are re-split
  /// and recounted; later line starts shift by the length change.
  void replace(int start, int end, String inserted) {
    assert(0 <= start && start <= end && end <= length);
    final int first = lineOfOffset(start);
    final int last = lineOfOffset(end);
    final String head = _lines[first].substring(0, start - _starts[first]);
    final String tail = _lines[last].substring(end - _starts[last]);
    final List<String> replacement = '$head$inserted$tail'.split('\n');
    for (int i = first; i <= last; i++) {
      _wordTotal -= _words[i];
    }
    final List<int> counts = [for (final l in replacement) countWords(l)];
    for (final c in counts) {
      _wordTotal += c;
    }
    _lines.replaceRange(first, last + 1, replacement);
    _words.replaceRange(first, last + 1, counts);
    final int delta = inserted.length - (end - start);
    if (first == last && replacement.length == 1) {
      // A change inside one line: later lines just move by the length change.
      for (int i = first + 1; i < _lines.length; i++) {
        _starts[i] += delta;
      }
    } else {
      _starts.removeRange(min(first + 1, _starts.length), _starts.length);
      _rebuildIndex(first + 1);
    }
    _text = null;
  }

  /// Replaces everything (document load, an edit made outside the window).
  void reset(String text) {
    _lines = text.split('\n');
    _starts.clear();
    _rebuildIndex(0);
    _words = [for (final l in _lines) countWords(l)];
    _wordTotal = _words.fold(0, (a, b) => a + b);
    _text = text;
  }

  void _rebuildIndex(int from) {
    int offset = from == 0 ? 0 : _starts[from - 1] + _lines[from - 1].length + 1;
    if (from == 0) _starts.clear();
    for (int i = from; i < _lines.length; i++) {
      _starts.add(offset);
      offset += _lines[i].length + 1;
    }
  }
}

/// The smallest single replacement that turns [before] into [after], found
/// from the common prefix and suffix. Returned offsets are in [before].
({int start, int end, String inserted}) diffReplacement(String before, String after) {
  final int maxPrefix = min(before.length, after.length);
  int p = 0;
  while (p < maxPrefix && before.codeUnitAt(p) == after.codeUnitAt(p)) {
    p++;
  }
  int s = 0;
  final int maxSuffix = min(before.length, after.length) - p;
  while (s < maxSuffix &&
      before.codeUnitAt(before.length - 1 - s) == after.codeUnitAt(after.length - 1 - s)) {
    s++;
  }
  return (start: p, end: before.length - s, inserted: after.substring(p, after.length - s));
}
