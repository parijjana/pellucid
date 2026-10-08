// Description: The formatting at the caret (backlog item 25), for the toolbar
// and the macOS menu bar to show as active states.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'hidden_markers.dart';
import 'list_marker.dart';

enum BlockStyle { title, heading, subheading, quote, body }

/// List kind of the caret's line.
enum ListStyle { none, bullet, numbered, checklist }

@immutable
class FormattingState {
  final bool bold;
  final bool italic;
  final bool underline;

  final bool strikethrough;
  final BlockStyle block;
  final ListStyle list;

  const FormattingState({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.block = BlockStyle.body,
    this.list = ListStyle.none,
  });

  static const FormattingState none = FormattingState();

  @override
  bool operator ==(Object other) =>
      other is FormattingState &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.block == block &&
      other.list == list;

  @override
  int get hashCode => Object.hash(bold, italic, underline, strikethrough, block, list);

  @override
  String toString() =>
      'FormattingState(b:$bold i:$italic u:$underline s:$strikethrough $block $list)';
}

/// What the editor shows at [selection]. A collapsed caret reports the style
/// the next typed character gets; a selection reports a style only when every
/// visible character in it has it. The block style is that of the line the
/// selection starts on.
FormattingState formattingAt(String text, TextSelection selection) {
  if (!selection.isValid || selection.end > text.length) return FormattingState.none;
  final int s = selection.start;
  final first = scanLineAt(text, s);
  final BlockStyle block = switch (first.list != null ? null : first.prefix) {
    '# ' => BlockStyle.title,
    '## ' => BlockStyle.heading,
    '### ' => BlockStyle.subheading,
    '> ' => BlockStyle.quote,
    _ => BlockStyle.body,
  };
  final ListStyle list = switch (first.list?.kind) {
    ListKind.bullet => ListStyle.bullet,
    ListKind.number => ListStyle.numbered,
    ListKind.check => ListStyle.checklist,
    null => ListStyle.none,
  };

  if (selection.isCollapsed) {
    bool b = false, i = false, u = false, st = false;
    for (final r in first.runs) {
      if (r.contentStart <= s && s <= r.contentEnd) {
        b |= r.bold;
        i |= r.italic;
        u |= r.underline;
        st |= r.strikethrough;
      }
    }
    return FormattingState(bold: b, italic: i, underline: u, strikethrough: st, block: block, list: list);
  }

  bool b = true, i = true, u = true, st = true;
  bool anyVisible = false;
  int ls = first.lineStart;
  LineMarkers line = first;
  while (true) {
    final int from = s > line.lineStart ? s : line.lineStart;
    final int to = selection.end < line.lineEnd ? selection.end : line.lineEnd;
    for (int k = from; k < to; k++) {
      if (line.isHidden(k)) continue;
      anyVisible = true;
      bool cb = false, ci = false, cu = false, cs = false;
      for (final r in line.runs) {
        if (r.contentStart <= k && k < r.contentEnd) {
          cb |= r.bold;
          ci |= r.italic;
          cu |= r.underline;
          cs |= r.strikethrough;
        }
      }
      b &= cb;
      i &= ci;
      u &= cu;
      st &= cs;
      if (!b && !i && !u && !st) break;
    }
    if ((!b && !i && !u && !st) || line.lineEnd >= selection.end || line.lineEnd >= text.length) break;
    ls = line.lineEnd + 1;
    line = scanLine(text, ls, lineEndOf(text, ls));
  }
  if (!anyVisible) return formattingAt(text, TextSelection.collapsed(offset: s));
  return FormattingState(bold: b, italic: i, underline: u, strikethrough: st, block: block, list: list);
}

/// The caret formatting of the open editor, shared with the toolbars and the
/// macOS menu bar (which sits above the editor in the widget tree).
final ValueNotifier<FormattingState> caretFormatting = ValueNotifier(FormattingState.none);
