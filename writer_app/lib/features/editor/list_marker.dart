// Description: What a Markdown list line looks like (backlog items 2, 3, 8-10, 17),
// and how the editor draws its marker. Pure string logic, no Flutter, so the
// scanner, the renderer, the edit rules and the exporters all agree.
//
// Stored Markdown stays standard: `- `, `1. `, `- [ ] `, `- [x] `, nested by
// leading spaces. The glyphs (bullet by level, 1./a./i. by level, the checkbox)
// are display only. The drawn text always has exactly the length of the
// stored text, so caret and selection offsets never drift.

/// Spaces per indent level. Tab inserts four spaces already, and four is the
/// one width every Markdown parser nests under both `- ` and `1. ` items
/// (two spaces fail under `1. ` in CommonMark).
const int listIndentUnit = 4;

enum ListKind { bullet, number, check }

class ListMarker {
  /// Leading whitespace (spaces, or tabs read as four columns).
  final String indent;
  final ListKind kind;

  /// The stored marker after the indent: `- `, `12. `, `- [ ] `, `- [x] `.
  final String marker;

  /// The number of a numbered item (0 otherwise).
  final int number;
  final bool checked;

  const ListMarker(this.indent, this.kind, this.marker, {this.number = 0, this.checked = false});

  /// Indent in columns.
  int get width {
    int w = 0;
    for (int i = 0; i < indent.length; i++) {
      w += indent.codeUnitAt(i) == 0x09 ? listIndentUnit : 1;
    }
    return w;
  }

  /// Nesting level: 0 at the margin, 1 for 1-4 columns, 2 for 5-8, ...
  /// (so a two-space indent from another editor still nests).
  int get level => (width + listIndentUnit - 1) ~/ listIndentUnit;

  /// Characters before the item text (indent + marker).
  int get length => indent.length + marker.length;

  @override
  String toString() => 'ListMarker(${indent.length}, $kind, "$marker")';
}

final RegExp _listLine = RegExp(r'^([ \t]*)(- \[([ xX])\] |- |(\d{1,3})\. )');

/// The list marker at the start of [line] (no newline), or null.
ListMarker? parseListMarker(String line) {
  if (line.isEmpty) return null;
  final int c = line.codeUnitAt(0);
  // Cheap reject: list lines start with space, tab, '-' or a digit.
  if (c != 0x20 && c != 0x09 && c != 0x2D && (c < 0x30 || c > 0x39)) return null;
  final m = _listLine.firstMatch(line);
  if (m == null) return null;
  final String indent = m.group(1)!;
  final String marker = m.group(2)!;
  if (m.group(4) != null) {
    return ListMarker(indent, ListKind.number, marker, number: int.parse(m.group(4)!));
  }
  if (m.group(3) != null) {
    return ListMarker(indent, ListKind.check, marker, checked: m.group(3) != ' ');
  }
  return ListMarker(indent, ListKind.bullet, marker);
}

/// Bullet glyph by level: • ◦ ▪, then round again.
const List<String> bulletGlyphs = ['•', '◦', '▪'];
String bulletGlyphForLevel(int level) => bulletGlyphs[level % bulletGlyphs.length];

String _letters(int n) {
  final out = StringBuffer();
  while (n > 0) {
    n -= 1;
    out.writeCharCode(0x61 + n % 26);
    n ~/= 26;
  }
  return out.toString().split('').reversed.join();
}

String _roman(int n) {
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = ['m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i'];
  final out = StringBuffer();
  for (int i = 0; i < values.length; i++) {
    while (n >= values[i]) {
      out.write(symbols[i]);
      n -= values[i];
    }
  }
  return out.toString();
}

/// Numbering label by level: 1. → a. → i., then round again.
String numberLabelForLevel(int number, int level) {
  switch (level % 3) {
    case 1:
      return number >= 1 ? _letters(number) : '$number';
    case 2:
      return number >= 1 && number <= 39 ? _roman(number) : '$number';
    default:
      return '$number';
  }
}

/// How a list marker is drawn. The drawn text is `absorbed` characters taken
/// from the end of the indent, then the marker label, then [pad] filler
/// characters drawn invisibly: always exactly indent + marker long.
class ListGlyph {
  /// Total visible label, e.g. `• `, `iii. `, `☐ `.
  final String shown;

  /// How many of [shown]'s leading characters sit over the end of the indent
  /// (right-aligns long labels such as `viii.` without changing the length).
  final int absorbed;

  /// Invisible filler characters after the label.
  final int pad;

  const ListGlyph(this.shown, this.absorbed, this.pad);
}

const String checkboxOff = '☐';
const String checkboxOn = '☑';

ListGlyph listGlyph(ListMarker m) {
  switch (m.kind) {
    case ListKind.bullet:
      return ListGlyph('${bulletGlyphForLevel(m.level)} ', 0, m.marker.length - 2);
    case ListKind.check:
      return ListGlyph('${m.checked ? checkboxOn : checkboxOff} ', 0, m.marker.length - 2);
    case ListKind.number:
      String shown = '${numberLabelForLevel(m.number, m.level)}. ';
      int absorbed = shown.length - m.marker.length;
      final int room = m.indent.length < 3 ? m.indent.length : 3;
      if (absorbed > room) {
        shown = m.marker; // does not fit: show the stored number
        absorbed = 0;
      }
      return ListGlyph(shown, absorbed < 0 ? 0 : absorbed, absorbed < 0 ? -absorbed : 0);
  }
}
