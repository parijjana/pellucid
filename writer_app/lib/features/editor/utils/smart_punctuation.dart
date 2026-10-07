// @trace BACKLOG-27
// Description: Smart punctuation as a TextInputFormatter: straight quotes to
// curly, "--" to an em dash, "..." to an ellipsis, as the writer types.
// Never inside inline code or code blocks. The last conversion can be undone
// on its own (see SmartPunctuationFormatter.undoLast).

import 'package:flutter/services.dart';
import 'markdown_code_ranges.dart';

/// A conversion that just happened: the value now in the field, and what the
/// field held (the writer's literal keystroke) before it.
class SmartConversion {
  final TextEditingValue converted;
  final TextEditingValue straight;
  const SmartConversion(this.converted, this.straight);
}

class SmartPunctuation {
  const SmartPunctuation._();

  static const _openers = '([{<—–-“‘/';

  static bool _isSpace(String c) => c.trim().isEmpty;

  /// Converts the keystroke that turned [oldValue] into [newValue], or returns
  /// null when it is not a single typed character, not one of `" ' - .`,
  /// inside code, or does not complete a `--` / `...`.
  static SmartConversion? convert(TextEditingValue oldValue, TextEditingValue newValue) {
    final sel = newValue.selection;
    if (!sel.isValid || !sel.isCollapsed || sel.baseOffset < 1) return null;
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) return null;
    final t = newValue.text;
    final i = sel.baseOffset - 1;
    final ch = t[i];
    if (ch != '"' && ch != "'" && ch != '-' && ch != '.') return null;

    // Exactly one typed character (replacing the old selection, if any).
    final os = oldValue.selection;
    final int s = os.isValid ? os.start : oldValue.text.length;
    final int e = os.isValid ? os.end : oldValue.text.length;
    if (oldValue.text.replaceRange(s, e, ch) != t || s != i) return null;

    String prev(int back) => i - back >= 0 ? t[i - back] : '';

    String? replacement; // replaces t[from, i + 1)
    int from = i;
    switch (ch) {
      case '"':
        final p = prev(1);
        replacement = (p.isEmpty || _isSpace(p) || _openers.contains(p)) ? '“' : '”';
      case "'":
        final p = prev(1);
        replacement = (p.isEmpty || _isSpace(p) || _openers.contains(p)) ? '‘' : '’';
      case '-':
        if (prev(1) != '-' || prev(2) == '-') return null;
        if (i + 1 < t.length && t[i + 1] == '-') return null;
        final before = prev(2);
        if (before == '|' || before == ':' || (before == '!' && prev(3) == '<')) return null; // <!--, |--|
        final lineStart = i >= 2 ? t.lastIndexOf('\n', i - 2) + 1 : 0;
        if (t.substring(lineStart, i - 1).trim().isEmpty) return null; // "---" rule
        from = i - 1;
        replacement = '—';
      case '.':
        if (prev(1) != '.' || prev(2) != '.' || prev(3) == '.') return null;
        if (i + 1 < t.length && t[i + 1] == '.') return null;
        from = i - 2;
        replacement = '…';
    }
    if (replacement == null) return null;
    if (offsetInRanges(markdownCodeRanges(t, openEnded: true), i)) return null;

    final newText = t.replaceRange(from, i + 1, replacement);
    final converted = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: from + replacement.length),
    );
    return SmartConversion(converted, newValue);
  }
}

/// Formatter wrapper that remembers the last conversion so one Undo can take
/// just that conversion back (leaving the characters as typed).
class SmartPunctuationFormatter extends TextInputFormatter {
  SmartPunctuationFormatter({this.enabled = true});

  /// Switch (Settings). Read on every keystroke.
  bool enabled;

  SmartConversion? _last;

  /// The conversion an Undo would revert right now, or null.
  SmartConversion? get lastConversion => _last;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    _last = null;
    if (!enabled) return newValue;
    final result = SmartPunctuation.convert(oldValue, newValue);
    if (result == null) return newValue;
    _last = result;
    return result.converted;
  }

  /// True when the field still holds exactly what the last conversion made.
  bool canUndo(TextEditingValue current) {
    final l = _last;
    return l != null && current.text == l.converted.text && current.selection == l.converted.selection;
  }

  /// Returns the pre-conversion value if [current] is still the converted one
  /// (and forgets the conversion), else null.
  TextEditingValue? undoLast(TextEditingValue current) {
    if (!canUndo(current)) return null;
    final straight = _last!.straight;
    _last = null;
    return straight;
  }
}
