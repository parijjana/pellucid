// Description: Copy from the editor (backlog item 24). Other apps get rich text
// (HTML) and plain text without markdown markers; Pellucid itself gets the
// markdown back on paste.
//
// macOS only for now (native channel in MainFlutterWindow.swift): it puts
// HTML, plain text and a private markdown type on one pasteboard item.
// Elsewhere copy keeps its old behaviour (the markdown as plain text) until
// the Windows/iOS side is built.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'hidden_markers.dart';
import 'list_marker.dart';

class _Attrs {
  final bool b;
  final bool i;
  final bool u;
  final bool s;
  const _Attrs(this.b, this.i, this.u, this.s);
  @override
  bool operator ==(Object o) => o is _Attrs && o.b == b && o.i == i && o.u == u && o.s == s;
  @override
  int get hashCode => Object.hash(b, i, u, s);
}

_Attrs _attrsAt(LineMarkers line, int k) {
  bool b = false, i = false, u = false, s = false;
  for (final r in line.runs) {
    if (r.contentStart <= k && k < r.contentEnd) {
      b |= r.bold;
      i |= r.italic;
      u |= r.underline;
      s |= r.strikethrough;
    }
  }
  return _Attrs(b, i, u, s);
}

/// One line of a copied range, as styled segments of visible text.
class _CopiedLine {
  final String? prefix; // block prefix, when the copy starts at the line start
  final List<(String, _Attrs)> segments;
  _CopiedLine(this.prefix, this.segments);
}

List<_CopiedLine> _copiedLines(String text, int start, int end) {
  final out = <_CopiedLine>[];
  int ls = lineStartOf(text, start);
  while (true) {
    final int le = lineEndOf(text, ls);
    final line = scanLine(text, ls, le);
    final int from = start > ls ? start : ls;
    final int to = end < le ? end : le;
    final String? prefix = (line.prefix != null && from <= line.prefixEnd) ? line.prefix : null;
    final segments = <(String, _Attrs)>[];
    final buf = StringBuffer();
    _Attrs? cur;
    for (int k = from; k < to; k++) {
      if (line.isHidden(k)) continue;
      final a = _attrsAt(line, k);
      if (cur != null && a != cur) {
        segments.add((buf.toString(), cur));
        buf.clear();
      }
      cur = a;
      buf.writeCharCode(text.codeUnitAt(k));
    }
    if (cur != null) segments.add((buf.toString(), cur));
    out.add(_CopiedLine(prefix, segments));
    if (le >= end || le >= text.length) break;
    ls = le + 1;
  }
  return out;
}

/// What a list marker reads as in plain text: • for a bullet, the number
/// as typed, ☐ / ☑ for a checklist item. Other prefixes read as nothing.
String _plainLead(String? prefix) {
  if (prefix == null) return '';
  if (prefix == '- ') return '• ';
  if (prefix.startsWith('- [')) return prefix.contains('[ ]') ? '$checkboxOff ' : '$checkboxOn ';
  if (RegExp(r'^\d').hasMatch(prefix)) return prefix;
  return '';
}

/// The plain text a reader sees in `[start, end)`.
String plainTextFor(String text, int start, int end) => _copiedLines(text, start, end)
    .map((l) => _plainLead(l.prefix) + l.segments.map((s) => s.$1).join())
    .join('\n');

/// `[start, end)` as markdown that renders on its own: runs cut by the range
/// are closed and reopened inside it.
String markdownFor(String text, int start, int end) => _copiedLines(text, start, end).map((l) {
      final sb = StringBuffer(l.prefix ?? '');
      for (final (s, a) in l.segments) {
        final stars = a.b && a.i ? '***' : (a.b ? '**' : (a.i ? '*' : ''));
        sb
          ..write(a.s ? '~~' : '')
          ..write(stars)
          ..write(a.u ? '<u>' : '')
          ..write(s)
          ..write(a.u ? '</u>' : '')
          ..write(stars)
          ..write(a.s ? '~~' : '');
      }
      return sb.toString();
    }).join('\n');

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// `[start, end)` as simple HTML for word processors and mail.
String htmlFor(String text, int start, int end) {
  final sb = StringBuffer();
  bool inList = false;
  String openList = 'ul';
  for (final l in _copiedLines(text, start, end)) {
    final inline = StringBuffer();
    for (final (s, a) in l.segments) {
      var h = _escape(s);
      if (a.u) h = '<u>$h</u>';
      if (a.i) h = '<em>$h</em>';
      if (a.b) h = '<strong>$h</strong>';
      if (a.s) h = '<s>$h</s>';
      inline.write(h);
    }
    final p = l.prefix;
    final isItem = p != null && parseListMarker(p) != null;
    final listTag = p != null && RegExp(r'^\d').hasMatch(p) ? 'ol' : 'ul';
    if (inList && (!isItem || listTag != openList)) sb.write('</$openList>');
    if (isItem && (!inList || listTag != openList)) sb.write('<$listTag>');
    inList = isItem;
    openList = listTag;
    final tag = isItem
        ? 'li'
        : switch (p) {
            '# ' => 'h1',
            '## ' => 'h2',
            '### ' => 'h3',
            '> ' => 'blockquote',
            _ => 'p',
          };
    final glyph = isItem && p.startsWith('- [') ? _plainLead(p) : '';
    sb.write('<$tag>$glyph$inline</$tag>');
  }
  if (inList) sb.write('</$openList>');
  return sb.toString();
}

class RichClipboard {
  static const MethodChannel _channel = MethodChannel('com.overengineeredhobbies.pellucid/clipboard');

  /// Tests set this to exercise the native path with a mocked channel.
  @visibleForTesting
  static bool? debugSupported;

  static bool get isSupported =>
      debugSupported ?? (!kIsWeb && Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST'));

  /// Copies `[start, end)` of [text].
  static Future<void> copy(String text, int start, int end) async {
    if (start >= end) return;
    final markdown = markdownFor(text, start, end);
    if (isSupported) {
      try {
        await _channel.invokeMethod<void>('setRich', {
          'plain': plainTextFor(text, start, end),
          'html': htmlFor(text, start, end),
          'markdown': markdown,
        });
        return;
      } on PlatformException {
        // fall through
      } on MissingPluginException {
        // fall through
      }
    }
    await Clipboard.setData(ClipboardData(text: markdown));
  }

  /// The markdown Pellucid put on the clipboard, or null when the clipboard
  /// holds something else (paste that as usual).
  static Future<String?> readMarkdown() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('getMarkdown');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
