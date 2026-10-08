// Description: Editing rules for Markdown lists (backlog items 2, 3, 8, 17):
// renumbering, indent / unindent, the checkbox, line-style toggles and the
// one-step undo of an automatically added marker. Pure functions on text plus
// the two switches the editor flips; marker_edit_rules.dart calls into this
// for Enter and Backspace.

import 'package:flutter/services.dart';

import 'hidden_markers.dart';
import 'list_marker.dart';

/// Settings > Auto-continue Lists. Read by the Enter rule (the editor screen
/// copies SettingsProvider.autoContinueListsEnabled here). Off: Enter is a
/// plain line break; Backspace, Tab and renumbering still work.
bool listAutoContinueEnabled = true;

/// A text change made by [renumberLists]: `[start, end)` of the old text was
/// replaced by [replacement].
class ListChange {
  final int start;
  final int end;
  final String replacement;
  const ListChange(this.start, this.end, this.replacement);
}

class Renumbered {
  final String text;
  final List<ListChange> changes;
  const Renumbered(this.text, this.changes);

  /// Where an old offset lands in the new text.
  int map(int offset) {
    int delta = 0;
    for (final c in changes) {
      if (c.end <= offset) {
        delta += c.replacement.length - (c.end - c.start);
      } else if (c.start < offset) {
        return c.start + delta + c.replacement.length; // inside a number: after it
      } else {
        break;
      }
    }
    return offset + delta;
  }

  TextSelection mapSelection(TextSelection s) => s.copyWith(baseOffset: map(s.baseOffset), extentOffset: map(s.extentOffset));
}

ListMarker? _markerOfLine(String text, int lineStart) => parseListMarker(text.substring(lineStart, lineEndOf(text, lineStart)));

/// Renumbers the numbered items of the list block(s) around `[from, to]`
/// (offsets in [text]). Only that stretch is touched: it grows over the list
/// lines touching it and stops at the first line that is not a list line.
///
/// Each nesting level counts on its own: the first item of a level keeps the
/// number it has (a list may start at 3), the rest follow it; a shallower line
/// ends the deeper counts, and so does a bullet at the same level.
/// [restart]: lines (by start offset) that become the first of a new nested
/// list and so restart at 1. [bridge]: a line (start offset) that stopped
/// being numbered but sits inside the list, which keeps counting across it.
Renumbered renumberLists(String text, int from, int to, {Set<int> restart = const {}, int? bridge}) {
  int s = lineStartOf(text, from.clamp(0, text.length));
  bool listAt(int ls) => ls == bridge || _markerOfLine(text, ls) != null;
  while (s > 0) {
    final int ps = lineStartOf(text, s - 1);
    if (!listAt(ps)) break;
    s = ps;
  }
  int e = lineEndOf(text, to.clamp(0, text.length));
  while (e < text.length) {
    final int ns = e + 1;
    if (!listAt(ns)) break;
    e = lineEndOf(text, ns);
  }

  final changes = <ListChange>[];
  final last = <int, int>{}; // indent width -> number of the previous item there
  int ls = s;
  while (ls <= e) {
    final int le = lineEndOf(text, ls);
    final m = ls == bridge ? null : _markerOfLine(text, ls);
    if (ls == bridge) {
      // Transparent: neither counted nor ending the list.
    } else if (m == null) {
      last.clear();
    } else {
      final int w = m.width;
      last.removeWhere((k, _) => k > w);
      if (m.kind != ListKind.number) {
        last.remove(w);
      } else {
        final int n = last.containsKey(w) ? last[w]! + 1 : (restart.contains(ls) ? 1 : m.number);
        last[w] = n;
        if (n != m.number) {
          final int ds = ls + m.indent.length;
          changes.add(ListChange(ds, ds + '${m.number}'.length, '$n'));
        }
      }
    }
    if (le >= e) break;
    ls = le + 1;
  }
  if (changes.isEmpty) return Renumbered(text, const []);
  final sb = StringBuffer();
  int at = 0;
  for (final c in changes) {
    sb
      ..write(text.substring(at, c.start))
      ..write(c.replacement);
    at = c.end;
  }
  sb.write(text.substring(at));
  return Renumbered(sb.toString(), changes);
}

/// [value] with the lists around its caret renumbered (selection mapped).
TextEditingValue renumberValue(TextEditingValue value, int from, int to, {Set<int> restart = const {}, int? bridge}) {
  final r = renumberLists(value.text, from, to, restart: restart, bridge: bridge);
  if (r.changes.isEmpty) return value;
  return value.copyWith(text: r.text, selection: r.mapSelection(value.selection), composing: TextRange.empty);
}

/// The marker a new item after [m] starts with (same indent; numbers count on).
String nextItemPrefix(ListMarker m) {
  switch (m.kind) {
    case ListKind.bullet:
      return '${m.indent}- ';
    case ListKind.check:
      return '${m.indent}- [ ] ';
    case ListKind.number:
      return '${m.indent}${m.number + 1}. ';
  }
}

/// The marker a new item after [m] starts with (same indent; numbers count on).
/// The item text of a list line is empty (nothing but whitespace after the marker).
bool isEmptyListItem(String text, LineMarkers line) =>
    line.list != null && text.substring(line.prefixEnd, line.lineEnd).trim().isEmpty;

/// Result of ending a list on an empty item: the text and caret.
class ListExit {
  final String text;
  final int caret;
  const ListExit(this.text, this.caret);
}

/// Enter on an empty item: a nested item moves out one level, a top-level one
/// loses its marker (the line becomes empty body text).
ListExit endEmptyItem(String text, LineMarkers line) {
  final m = line.list!;
  if (m.width > 0) {
    final int cut = _indentCut(m.indent);
    final newText = text.replaceRange(line.lineStart, line.lineStart + cut, '');
    return ListExit(newText, line.lineEnd - cut);
  }
  final newText = text.replaceRange(line.lineStart, line.lineEnd, '');
  return ListExit(newText, line.lineStart);
}

/// How many leading characters of [indent] one unindent removes (up to four
/// columns: four spaces, or one tab).
int _indentCut(String indent) {
  int cols = 0;
  int i = 0;
  while (i < indent.length && cols < listIndentUnit) {
    final int c = indent.codeUnitAt(i);
    cols += c == 0x09 ? listIndentUnit : 1;
    i++;
  }
  return i;
}

/// Indents (or unindents) every list line touched by [value]'s selection by
/// one level ([listIndentUnit] spaces). An item nests at most one level below
/// the list line above it, so the Markdown stays valid. Numbered items that
/// move are renumbered (a new nested list restarts at 1). Null when nothing
/// would change: no list line, already at the margin, or nothing to nest under.
TextEditingValue? indentLines(TextEditingValue value, {required bool outdent}) {
  final String text = value.text;
  final sel = value.selection;
  if (!sel.isValid) return null;
  final int firstLs = lineStartOf(text, sel.start);
  final int lastLs = lineStartOf(text, sel.end > sel.start && text.codeUnitAt(sel.end - 1) == 0x0A ? sel.end - 1 : sel.end);

  int prevWidth = -1;
  if (firstLs > 0) prevWidth = _markerOfLine(text, lineStartOf(text, firstLs - 1))?.width ?? -1;

  final out = StringBuffer();
  final restart = <int>{};
  final edits = <(int at, int removed, int added)>[]; // old offset, chars removed, chars added
  int copied = 0;
  int delta = 0;
  int ls = firstLs;
  while (true) {
    final int le = lineEndOf(text, ls);
    final m = _markerOfLine(text, ls);
    int width = m?.width ?? -1;
    if (m != null) {
      if (outdent) {
        final int cut = _indentCut(m.indent);
        if (cut > 0) {
          out.write(text.substring(copied, ls));
          copied = ls + cut;
          edits.add((ls, cut, 0));
          delta -= cut;
          width = m.width - listIndentUnit < 0 ? 0 : m.width - listIndentUnit;
        }
      } else if (prevWidth >= 0 && m.width <= prevWidth) {
        out
          ..write(text.substring(copied, ls))
          ..write(' ' * listIndentUnit);
        copied = ls;
        edits.add((ls, 0, listIndentUnit));
        delta += listIndentUnit;
        width = m.width + listIndentUnit;
        if (m.kind == ListKind.number) restart.add(ls + delta - listIndentUnit);
      }
    }
    prevWidth = width;
    if (le >= text.length || ls >= lastLs) break;
    ls = le + 1;
  }
  if (edits.isEmpty) return null;
  // A numbered item right after the moved lines that is now deeper than the
  // last one starts a new nested list: it counts from 1 again.
  final int afterLast = lineEndOf(text, lastLs) + 1;
  if (afterLast < text.length && prevWidth >= 0) {
    final nm = _markerOfLine(text, afterLast);
    if (nm != null && nm.kind == ListKind.number && nm.width > prevWidth) restart.add(afterLast + delta);
  }
  out.write(text.substring(copied));
  final newText = out.toString();

  int map(int offset) {
    int d = 0;
    for (final (at, removed, added) in edits) {
      if (removed > 0) {
        if (offset >= at + removed) {
          d -= removed;
        } else if (offset > at) {
          return at + d;
        }
      } else if (offset >= at) {
        d += added;
      }
    }
    return offset + d;
  }

  var result = value.copyWith(
    text: newText,
    selection: sel.copyWith(baseOffset: map(sel.baseOffset), extentOffset: map(sel.extentOffset)),
    composing: TextRange.empty,
  );
  final int endNew = lineEndOf(text, lastLs) + delta; // every edit is at or before the last line's start
  result = renumberValue(result, map(firstLs), endNew.clamp(0, newText.length), restart: restart);
  return result;
}

/// True when any line touched by [selection] is a list line.
bool selectionTouchesList(String text, TextSelection selection) {
  if (!selection.isValid || selection.end > text.length) return false;
  int ls = lineStartOf(text, selection.start);
  final int last = lineStartOf(text, selection.end > selection.start && text.codeUnitAt(selection.end - 1) == 0x0A ? selection.end - 1 : selection.end);
  while (true) {
    if (_markerOfLine(text, ls) != null) return true;
    final int le = lineEndOf(text, ls);
    if (ls >= last || le >= text.length) return false;
    ls = le + 1;
  }
}

/// Switches the checkbox on the list line at [lineStart] on or off. Null if
/// that line is not a checklist item.
TextEditingValue? toggleCheckbox(TextEditingValue value, int lineStart) {
  final m = _markerOfLine(value.text, lineStart);
  if (m == null || m.kind != ListKind.check) return null;
  final int at = lineStart + m.indent.length + 3;
  final text = value.text.replaceRange(at, at + 1, m.checked ? ' ' : 'x');
  return value.copyWith(text: text, composing: TextRange.empty);
}

/// Line start of the checklist item whose checkbox is at [offset] (a text
/// position found by hit-testing the editor), or null. The box and the space
/// after it are the hit area; the rest of the marker is hidden filler.
int? checkboxLineAt(String text, int offset) {
  if (offset < 0 || offset > text.length) return null;
  final int ls = lineStartOf(text, offset);
  final m = _markerOfLine(text, ls);
  if (m == null || m.kind != ListKind.check) return null;
  final int box = ls + m.indent.length;
  return offset >= box && offset <= box + 1 ? ls : null;
}

/// The marker an automatic edit just added, so the next Undo can remove only
/// it and keep the line break (Word does the same).
class AutoMarkerUndo {
  final String text; // text right after the automatic edit
  final int caret;
  final int markerStart;
  final int markerEnd;
  const AutoMarkerUndo(this.text, this.caret, this.markerStart, this.markerEnd);

  /// True while [value] is exactly what the edit left behind.
  bool applies(TextEditingValue value) =>
      value.text == text && value.selection.isCollapsed && value.selection.baseOffset == caret;

  TextEditingValue undo() => TextEditingValue(
        text: text.replaceRange(markerStart, markerEnd, ''),
        selection: TextSelection.collapsed(offset: caret - (markerEnd - markerStart)),
      );
}

/// Set by the Enter rule; consumed by the editor's Undo handler.
AutoMarkerUndo? lastAutoMarker;
