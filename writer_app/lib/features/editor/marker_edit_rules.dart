// Description: Editing with hidden markdown markers (backlog item 24).
//
// The editor hides `**`, `*`, `<u>`, `# ` and friends, so a plain text edit
// can leave a marker half-deleted and shown raw. These rules rewrite each
// keyboard edit so the markdown stays balanced:
// - Backspace right after a block prefix removes the prefix (the line becomes
//   body text); the next Backspace joins lines.
// - Backspace/Delete never eat a hidden marker: they delete the next visible
//   character instead.
// - Deleting or replacing a selection that cuts through a styled run keeps the
//   markers of the part that survives.
// - A styled run whose last character goes also loses its markers.
// - A line break typed inside a styled run closes it and reopens it on the
//   new line; Enter right after a block prefix opens a line above instead.
// Toggling a style at a collapsed caret (end/start a run there) is
// [toggleInlineAtCaret]; the caret rules live in [MarkerCaret].

import 'package:flutter/services.dart';

import 'hidden_markers.dart';

/// A text edit on [oldText]: `[start, end)` replaced by [inserted].
class TextEdit {
  final int start;
  final int end;
  final String inserted;
  const TextEdit(this.start, this.end, this.inserted);

  @override
  String toString() => 'TextEdit($start, $end, "$inserted")';
}

/// Works out which edit turned [oldValue] into [newValue], preferring the
/// reading that agrees with the old selection (so typing a repeated letter or
/// deleting one of `**` is attributed to the caret, not to a lookalike).
TextEdit? diffEdit(TextEditingValue oldValue, TextEditingValue newValue) {
  final String o = oldValue.text;
  final String n = newValue.text;
  if (o == n) return null;
  final sel = oldValue.selection;
  if (sel.isValid && sel.end <= o.length) {
    final int s = sel.start;
    final int e = sel.end;
    final int insLen = n.length - (o.length - (e - s));
    if (insLen >= 0 &&
        n.startsWith(o.substring(0, s)) &&
        n.endsWith(o.substring(e)) &&
        s + insLen <= n.length &&
        (insLen > 0 || e > s)) {
      return TextEdit(s, e, n.substring(s, s + insLen));
    }
    if (sel.isCollapsed) {
      final int p = s;
      for (final int w in const [1, 2]) {
        if (p - w >= 0 && n.length == o.length - w && n == o.substring(0, p - w) + o.substring(p)) {
          return TextEdit(p - w, p, '');
        }
        if (p + w <= o.length && n.length == o.length - w && n == o.substring(0, p) + o.substring(p + w)) {
          return TextEdit(p, p + w, '');
        }
      }
    }
  }
  int prefix = 0;
  final int maxPrefix = o.length < n.length ? o.length : n.length;
  while (prefix < maxPrefix && o.codeUnitAt(prefix) == n.codeUnitAt(prefix)) {
    prefix++;
  }
  int suffix = 0;
  while (suffix < maxPrefix - prefix &&
      o.codeUnitAt(o.length - 1 - suffix) == n.codeUnitAt(n.length - 1 - suffix)) {
    suffix++;
  }
  return TextEdit(prefix, o.length - suffix, n.substring(prefix, n.length - suffix));
}

/// Non-zero while undo/redo restores a recorded value: that value must land
/// exactly as recorded (UndoHistory asserts it), so no rule may touch it.
int markerRulesSuspended = 0;

/// Rewrites a keyboard/paste edit so hidden markers stay balanced. Returns
/// [newValue] untouched when no rule applies.
TextEditingValue applyMarkerEditRules(TextEditingValue oldValue, TextEditingValue newValue) {
  if (markerRulesSuspended > 0) return newValue;
  // IME composition (accents, CJK): leave the platform alone until it commits.
  if (newValue.composing.isValid && !newValue.composing.isCollapsed) return newValue;
  final edit = diffEdit(oldValue, newValue);
  if (edit == null) return newValue;
  final String o = oldValue.text;
  final sel = oldValue.selection;

  if (edit.inserted.isEmpty && sel.isValid && sel.isCollapsed && edit.end - edit.start <= 2) {
    final int p = sel.baseOffset;
    if (edit.end == p) return _backspace(o, edit, p) ?? newValue;
    if (edit.start == p) return _forwardDelete(o, edit, p) ?? newValue;
  }
  return _replace(o, edit.start, edit.end, edit.inserted) ?? newValue;
}

TextEditingValue? _backspace(String o, TextEdit edit, int p) {
  final line = scanLineAt(o, p);
  // Rule: Backspace at the start of a heading/bullet line removes the style.
  if (line.prefix != null && p == line.prefixEnd) {
    return _value(o.replaceRange(line.lineStart, line.prefixEnd, ''), line.lineStart);
  }
  if (p > line.lineStart && line.isHidden(p - 1)) {
    int q = p;
    while (q > line.lineStart && line.isHidden(q - 1)) {
      q--;
    }
    if (q == line.lineStart) {
      if (q == 0) return _value(o, p);
      return _replace(o, q - 1, q, '');
    }
    final int w = (q > 1 && _isLow(o.codeUnitAt(q - 1)) && _isHigh(o.codeUnitAt(q - 2))) ? 2 : 1;
    return _replace(o, q - w, q, '');
  }
  return _replace(o, edit.start, edit.end, '');
}

TextEditingValue? _forwardDelete(String o, TextEdit edit, int p) {
  final line = scanLineAt(o, p);
  int q = p;
  while (q < line.lineEnd && line.isHidden(q)) {
    q++;
  }
  if (q == line.lineEnd) {
    if (q >= o.length) return _value(o, p);
    return _replace(o, q, q + 1, '', caret: p);
  }
  if (q == p) return _replace(o, edit.start, edit.end, '');
  final int w = (q + 1 < o.length && _isHigh(o.codeUnitAt(q)) && _isLow(o.codeUnitAt(q + 1))) ? 2 : 1;
  return _replace(o, q, q + w, '', caret: p);
}

bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;

TextEditingValue _value(String text, int caret) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)));

/// Replaces `[s, e)` of [o] with [ins], keeping the markers of runs that
/// survive, then drops runs left empty at the caret. [caret], when given, is
/// where the caret goes (in old offsets, before [s]); otherwise after [ins].
TextEditingValue? _replace(String o, int s, int e, String ins, {int? caret}) {
  final first = scanLineAt(o, s);

  // Enter straight after a block prefix with text after it: open a body line
  // above instead of splitting the prefix from its text.
  if (s == e && ins == '\n' && first.prefix != null && s == first.prefixEnd && first.lineEnd > s) {
    return _value(o.replaceRange(first.lineStart, first.lineStart, '\n'), s + 1);
  }

  final last = e <= first.lineEnd ? first : scanLineAt(o, e);
  // A deleted line break joins the next line into this one: its block prefix
  // goes too, so the joined text takes this line's style.
  if (!identical(last, first) && last.prefix != null && e <= last.prefixEnd) {
    e = last.prefixEnd;
  }

  final protected = <int>{};
  void protect(LineMarkers line) {
    for (final r in line.runs) {
      if (r.start >= s && r.end <= e) continue;
      for (int i = r.start; i < r.contentStart; i++) {
        if (i >= s && i < e) protected.add(i);
      }
      for (int i = r.contentEnd; i < r.end; i++) {
        if (i >= s && i < e) protected.add(i);
      }
    }
  }

  protect(first);
  if (!identical(last, first)) protect(last);
  // A selection that starts inside a block prefix keeps the line's style.
  if (first.prefix != null && s < first.prefixEnd) {
    for (int i = s; i < first.prefixEnd && i < e; i++) {
      protected.add(i);
    }
  }

  // A line break inside a styled run closes the run and reopens it after.
  String insert = ins;
  if (insert.contains('\n') && identical(last, first)) {
    final enclosing = [
      for (final r in first.runs)
        if (r.contentStart <= s && e <= r.contentEnd) r,
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (enclosing.isNotEmpty) {
      final closers = enclosing.reversed.map((r) => r.closingTag).join();
      final openers = enclosing.map((r) => r.tag).join();
      final int firstNl = insert.indexOf('\n');
      final int lastNl = insert.lastIndexOf('\n');
      insert = insert.substring(0, firstNl) +
          closers +
          insert.substring(firstNl, lastNl + 1) +
          openers +
          insert.substring(lastNl + 1);
    }
  }

  final middle = StringBuffer();
  bool inserted = false;
  int caretAt = -1;
  for (int i = s; i < e; i++) {
    if (protected.contains(i)) {
      middle.writeCharCode(o.codeUnitAt(i));
    } else if (!inserted) {
      middle.write(insert);
      inserted = true;
      caretAt = s + middle.length;
    }
  }
  if (!inserted) {
    if (s == e) {
      middle.write(insert);
      caretAt = s + middle.length;
    } else {
      // Only hidden markers were selected: put the text after them.
      middle.write(insert);
      caretAt = s + middle.length;
    }
  }
  String n = o.substring(0, s) + middle.toString() + o.substring(e);
  int c = caret ?? caretAt;
  if (caret != null && caret > s) c = s;

  // Drop runs the edit left empty around the caret (nested ones in turn).
  for (int guard = 0; guard < 8; guard++) {
    final line = scanLineAt(n, c);
    InlineRun? empty;
    for (final r in line.runs) {
      if (r.isEmpty && r.start <= c && c <= r.end) {
        empty = r;
        break;
      }
    }
    if (empty == null) break;
    n = n.replaceRange(empty.contentEnd, empty.end, '').replaceRange(empty.start, empty.contentStart, '');
    c = empty.start;
  }
  return _value(n, canonicalOffset(n, c));
}

/// Applies [applyMarkerEditRules] to every edit EditableText makes.
class MarkerEditFormatter extends TextInputFormatter {
  const MarkerEditFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      applyMarkerEditRules(oldValue, newValue);
}

/// Result of toggling a style with a collapsed caret: the new text, where the
/// caret goes, and (when an empty run was opened for the next keystroke) that
/// run, so it can be removed again if nothing is typed into it.
class CaretToggle {
  final String text;
  final int caret;
  final TextRange? pendingEmptyRun;
  const CaretToggle(this.text, this.caret, this.pendingEmptyRun);
}

/// Bold/italic/underline toggled with no selection: inside a run of that
/// style, end the run at the caret (the next keystroke is plain); elsewhere,
/// open an empty run so the next keystroke is styled. Null when the toggle
/// cannot be expressed without changing what the reader sees (heading lines
/// do not render inline styles; some `*` combinations would re-pair).
CaretToggle? toggleInlineAtCaret(String text, int caret, String tag) {
  final line = scanLineAt(text, caret);
  if (line.prefix != null) return null;
  final closing = tag == '<u>' ? '</u>' : tag;

  InlineRun? run;
  for (final r in line.runs) {
    final matches = r.tag == tag || (r.tag == '***' && (tag == '**' || tag == '*'));
    if (matches && r.contentStart <= caret && caret <= r.contentEnd) {
      if (run == null || r.start >= run.start) run = r; // innermost
    }
  }

  CaretToggle? checked(String newText, int newCaret, TextRange? pending) {
    // The reader must see the same characters before and after.
    final before = visibleText(text.substring(line.lineStart, line.lineEnd));
    final ls = lineStartOf(newText, newCaret);
    final after = visibleText(newText.substring(ls, lineEndOf(newText, ls)));
    if (before != after) return null;
    if (pending != null) {
      final check = scanLineAt(newText, newCaret);
      final ok = check.runs.any((r) => r.isEmpty && r.start == pending.start && r.end == pending.end);
      if (!ok) return null;
    }
    return CaretToggle(newText, newCaret, pending);
  }

  if (run == null) {
    final newText = text.replaceRange(caret, caret, '$tag$closing');
    return checked(newText, caret + tag.length, TextRange(start: caret, end: caret + tag.length + closing.length));
  }

  if (run.tag == tag) {
    if (caret == run.contentEnd) return CaretToggle(text, run.end, null);
    if (caret == run.contentStart) return CaretToggle(text, run.start, null);
    final newText = text.replaceRange(caret, caret, '${run.closingTag}${run.tag}');
    return checked(newText, caret + run.closingTag.length, null);
  }

  // Inside `***`: end one of the two styles, keep the other, at the run's end.
  if (caret != run.contentEnd) return null;
  final keep = tag == '**' ? '*' : '**';
  final newText = text.replaceRange(run.end, run.end, '$keep$keep');
  return checked(newText, run.end + keep.length, TextRange(start: run.end, end: run.end + 2 * keep.length));
}

/// The caret half of item 24: a collapsed caret never rests inside hidden
/// markers ([canonicalOffset]), except at the one spot a caret toggle chose
/// ([sticky]). An empty run opened by a toggle and never typed into is
/// removed when the caret leaves.
class MarkerCaret {
  int? sticky;
  TextRange? pendingEmptyRun;
  String? _pendingMarkers;
  String? _toggleText;

  /// Call before applying [t] to the controller.
  void setToggle(CaretToggle t) {
    _toggleText = t.text;
    sticky = t.caret;
    pendingEmptyRun = t.pendingEmptyRun;
    _pendingMarkers = t.pendingEmptyRun?.textInside(t.text);
  }

  void clear() {
    sticky = null;
    pendingEmptyRun = null;
    _pendingMarkers = null;
    _toggleText = null;
  }

  TextEditingValue adjust(TextEditingValue oldValue, TextEditingValue newValue) {
    if (markerRulesSuspended > 0) {
      clear();
      return newValue;
    }
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) return newValue;
    if (newValue.text != oldValue.text) {
      if (newValue.text == _toggleText && newValue.selection == TextSelection.collapsed(offset: sticky!)) {
        _toggleText = null; // the toggle itself landing
        return newValue;
      }
      clear();
      return newValue;
    }
    final sel = newValue.selection;
    if (!sel.isValid || sel.end > newValue.text.length) return newValue;
    if (sticky != null && sel.isCollapsed && sel.baseOffset == sticky) return newValue;

    String text = newValue.text;
    TextSelection selection = sel;
    final pending = pendingEmptyRun;
    if (pending != null && pending.end <= text.length && pending.textInside(text) == _pendingMarkers) {
      text = text.replaceRange(pending.start, pending.end, '');
      final int len = pending.end - pending.start;
      int shift(int x) => x <= pending.start ? x : (x >= pending.end ? x - len : pending.start);
      selection = selection.copyWith(baseOffset: shift(selection.baseOffset), extentOffset: shift(selection.extentOffset));
    }
    clear();
    if (selection.isCollapsed) {
      selection = TextSelection.collapsed(
        offset: canonicalOffset(text, selection.baseOffset),
        affinity: selection.affinity,
      );
    }
    if (text == newValue.text && selection == sel) return newValue;
    return newValue.copyWith(text: text, selection: selection, composing: TextRange.empty);
  }
}
