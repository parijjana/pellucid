// Description: Backlog item 22. Converts clipboard HTML (Word, Google Docs,
// web pages, mail) to the Markdown Pellucid can express: bold, italic,
// strikethrough, headings H1-H3, bullet / numbered / nested lists, checklists,
// links and block quotes. Everything else (colours, fonts, sizes, images,
// scripts) is dropped; tables become plain text rows (cells separated by a tab).
//
// Pure Dart on top of package:html (MIT), so it is testable without a clipboard.
// Blocks are joined with a single newline, matching how Pellucid writes
// paragraphs (one line each, see markdownFor in rich_clipboard.dart).

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Markdown for [html], or null when it holds no text.
String? htmlToMarkdown(String html) {
  final doc = html_parser.parse(html);
  final body = doc.body;
  if (body == null) return null;
  final out = _Converter().convert(body);
  return out.trim().isEmpty ? null : out;
}

/// True when [markdown] says more than the clipboard's [plain] text does, i.e.
/// the conversion is worth using over a plain paste.
bool htmlAddsStructure(String markdown, String? plain) {
  if (plain == null) return true;
  String squash(String s) => s.replaceAll(RegExp(r'\s+'), '');
  return squash(markdown) != squash(plain);
}

class _Attrs {
  final bool bold, italic, strike, code, underline;
  final String? href;
  const _Attrs({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.underline = false,
    this.href,
  });
  _Attrs copy({
    bool? bold,
    bool? italic,
    bool? strike,
    bool? code,
    bool? underline,
    String? href,
  }) => _Attrs(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strike: strike ?? this.strike,
    code: code ?? this.code,
    underline: underline ?? this.underline,
    href: href ?? this.href,
  );
  @override
  bool operator ==(Object o) =>
      o is _Attrs &&
      o.bold == bold &&
      o.italic == italic &&
      o.strike == strike &&
      o.code == code &&
      o.underline == underline &&
      o.href == href;
  @override
  int get hashCode => Object.hash(bold, italic, strike, code, underline, href);
}

class _Seg {
  String text;
  final _Attrs a;
  _Seg(this.text, this.a);
}

const _skipTags = {
  'head',
  'style',
  'script',
  'meta',
  'title',
  'link',
  'template',
  'noscript',
  'img',
  'svg',
  'canvas',
  'iframe',
  'object',
  'video',
  'audio',
  'button',
  'select',
  'textarea',
};
const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'nav',
  'aside',
  'figure',
  'figcaption',
  'address',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'table',
  'tr',
  'dl',
  'dt',
  'dd',
  'hr',
  'form',
  'fieldset',
  'center',
};

String _style(Element e) =>
    (e.attributes['style'] ?? '').toLowerCase().replaceAll(' ', '');

bool _isBoldStyle(String st) {
  final m = RegExp(r'(?<![-\w])font-weight:(\w+)').firstMatch(st);
  if (m == null) return false;
  final v = m.group(1)!;
  return v == 'bold' || v == 'bolder' || (int.tryParse(v) ?? 0) >= 600;
}

bool _isNormalWeight(String st) {
  final m = RegExp(r'(?<![-\w])font-weight:(\w+)').firstMatch(st);
  if (m == null) return false;
  final v = m.group(1)!;
  return v == 'normal' || v == 'lighter' || (int.tryParse(v) ?? 700) < 600;
}

class _ListCtx {
  final bool ordered;
  int next;
  _ListCtx(this.ordered, this.next);
}

class _Converter {
  final List<String> _lines = [];

  /// Word "list paragraphs" (mso-list) arrive flat with a level; these remember
  /// the numbering per level.
  final Map<int, int> _msoCounters = {};

  String convert(Element body) {
    _blocks(body.nodes, prefix: '', lists: const [], pre: false);
    // Collapse runs of blank lines to one and trim the ends.
    final sb = StringBuffer();
    int blanks = 0;
    for (final l in _lines) {
      if (l.trim().isEmpty) {
        blanks++;
        if (blanks > 1) continue;
        sb.writeln();
      } else {
        blanks = 0;
        sb.writeln(l.trimRight());
      }
    }
    return sb.toString().replaceAll(RegExp(r'^\n+|\n+$'), '');
  }

  // ---- blocks -------------------------------------------------------------

  /// Walks [nodes]; consecutive inline nodes are gathered into one paragraph.
  void _blocks(
    List<Node> nodes, {
    required String prefix,
    required List<_ListCtx> lists,
    required bool pre,
  }) {
    var inline = <Node>[];
    void flush() {
      if (inline.isEmpty) return;
      final segs = <_Seg>[];
      for (final n in inline) {
        _inline(n, const _Attrs(), segs, pre);
      }
      inline = [];
      _emitParagraph(segs, prefix, pre);
    }

    for (final n in nodes) {
      if (n is Element && _skipTags.contains(n.localName)) continue;
      if (n is Element && _blockTags.contains(n.localName)) {
        flush();
        _block(n, prefix: prefix, lists: lists, pre: pre);
      } else if (n is Element && _containsBlock(n)) {
        // A span / font / a wrapping blocks: descend.
        flush();
        _blocks(n.nodes, prefix: prefix, lists: lists, pre: pre);
      } else if (n is Element || n is Text) {
        inline.add(n);
      }
    }
    flush();
  }

  bool _containsBlock(Element e) {
    for (final c in e.children) {
      if (_blockTags.contains(c.localName) || _containsBlock(c)) return true;
    }
    return false;
  }

  void _emitParagraph(
    List<_Seg> segs,
    String prefix,
    bool pre, {
    String first = '',
  }) {
    final text = _render(segs, pre: pre);
    if (text.trim().isEmpty) return;
    final parts = text.split('\n');
    for (int i = 0; i < parts.length; i++) {
      _lines.add('$prefix${i == 0 ? first : ''}${parts[i]}');
    }
  }

  void _block(
    Element e, {
    required String prefix,
    required List<_ListCtx> lists,
    required bool pre,
  }) {
    final tag = e.localName!;
    final st = _style(e);
    final preserve = pre || tag == 'pre' || st.contains('white-space:pre');
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(tag.substring(1)).clamp(1, 3);
        final segs = <_Seg>[];
        for (final n in e.nodes) {
          _inline(n, const _Attrs(), segs, false);
        }
        // Headings are bold already; drop the redundant inline bold.
        final text = _render(
          segs.map((s) => _Seg(s.text, s.a.copy(bold: false))).toList(),
          pre: false,
        ).replaceAll('\n', ' ');
        if (text.trim().isNotEmpty) {
          _lines.add('$prefix${'#' * level} ${text.trim()}');
        }
      case 'ul' || 'ol':
        final start = int.tryParse(e.attributes['start'] ?? '') ?? 1;
        final ctx = _ListCtx(tag == 'ol', start);
        _blocks(e.nodes, prefix: prefix, lists: [...lists, ctx], pre: preserve);
      case 'li':
        _listItem(e, prefix, lists, preserve);
      case 'blockquote':
        _blocks(e.nodes, prefix: '$prefix> ', lists: lists, pre: preserve);
      case 'table':
        _table(e, prefix);
      case 'hr':
        break;
      case 'p' || 'div':
        if (_isMsoList(e)) {
          _msoListItem(e, prefix);
        } else if (_msoTitle(e)) {
          final segs = <_Seg>[];
          for (final n in e.nodes) {
            _inline(n, const _Attrs(), segs, false);
          }
          final t = _render(segs, pre: false).replaceAll('\n', ' ').trim();
          if (t.isNotEmpty) _lines.add('$prefix# $t');
        } else {
          _paragraphLike(e, prefix, lists, preserve);
        }
      default:
        _paragraphLike(e, prefix, lists, preserve);
    }
  }

  /// p / div / pre / etc.: a paragraph, or children when it holds blocks.
  void _paragraphLike(
    Element e,
    String prefix,
    List<_ListCtx> lists,
    bool preserve,
  ) {
    if (_containsBlock(e)) {
      _blocks(e.nodes, prefix: prefix, lists: lists, pre: preserve);
      return;
    }
    final segs = <_Seg>[];
    for (final n in e.nodes) {
      _inline(n, _styleAttrs(e, const _Attrs()), segs, preserve);
    }
    final text = _render(segs, pre: preserve);
    if (text.trim().isEmpty) {
      // An empty paragraph (<p><br></p>) is a deliberate blank line.
      if (e.localName == 'p' || e.querySelector('br') != null) _lines.add('');
      return;
    }
    // Paragraph indent (slice 5b): a clean margin-left / padding-left (whole
    // paragraph) or text-indent (first line) becomes em-space levels. Anything
    // unclear (negative, tiny, odd unit) is dropped.
    if (!preserve && prefix.isEmpty && lists.isEmpty && (e.localName == 'p' || e.localName == 'div')) {
      final st = _style(e);
      final left = _indentLevel(st, const ['margin-left', 'padding-left']);
      if (left > 0) {
        _emitParagraph(segs, '\u2003' * left, preserve);
        return;
      }
      final first = _indentLevel(st, const ['text-indent']);
      if (first > 0) {
        _emitParagraph(segs, prefix, preserve, first: '\u2003' * first);
        return;
      }
    }
    _emitParagraph(segs, prefix, preserve);
  }

  /// Indent levels (1-4, 0.5 in each) of the first of [props] set in the
  /// style string [st] to a plain positive length; 0 when absent or unclear.
  static int _indentLevel(String st, List<String> props) {
    for (final prop in props) {
      final m = RegExp('(?:^|;)$prop:(\\d+(?:\\.\\d+)?)(px|pt|em|in|cm)(?:;|\$)').firstMatch(st);
      if (m == null) continue;
      final value = double.parse(m.group(1)!);
      final px = value *
          switch (m.group(2)) {
            'px' => 1.0,
            'pt' => 96 / 72,
            'em' => 16.0,
            'in' => 96.0,
            _ => 96 / 2.54,
          };
      if (px < 24) return 0; // too small to be a deliberate indent
      final level = (px / 48).round();
      return level < 1 ? 1 : (level > 4 ? 4 : level);
    }
    return 0;
  }

  void _listItem(
    Element li,
    String prefix,
    List<_ListCtx> lists,
    bool preserve,
  ) {
    final ctx = lists.isEmpty ? _ListCtx(false, 1) : lists.last;
    final indent = '    ' * (lists.length > 1 ? lists.length - 1 : 0);
    String marker = ctx.ordered ? '${ctx.next++}. ' : '- ';
    // Checklist: <input type=checkbox> or a leading ballot-box character.
    final box = li.querySelector('input[type=checkbox]');
    String? check;
    if (box != null) check = box.attributes.containsKey('checked') ? 'x' : ' ';

    // The item's own inline content, then any nested lists / blocks.
    final inlineNodes = <Node>[];
    final nested = <Node>[];
    for (final n in li.nodes) {
      if (n is Element &&
          (n.localName == 'ul' ||
              n.localName == 'ol' ||
              n.localName == 'blockquote')) {
        nested.add(n);
      } else if (n is Element &&
          _containsBlock(n) &&
          _blockTags.contains(n.localName)) {
        // <li><p>text</p></li>: take the paragraph's inline content.
        for (final c in n.nodes) {
          if (c is Element && (c.localName == 'ul' || c.localName == 'ol')) {
            nested.add(c);
          } else {
            inlineNodes.add(c);
          }
        }
      } else if (n is Element &&
          _blockTags.contains(n.localName) &&
          n.localName != 'li') {
        inlineNodes.addAll(n.nodes);
      } else {
        inlineNodes.add(n);
      }
    }
    final segs = <_Seg>[];
    for (final n in inlineNodes) {
      _inline(n, const _Attrs(), segs, false);
    }
    var text = _render(segs, pre: false).replaceAll('\n', ' ').trim();
    final ballot = RegExp(r'^([☐☑☒✓✔])\s*').firstMatch(text);
    if (ballot != null) {
      check = ballot.group(1) == '☐' ? ' ' : 'x';
      text = text.substring(ballot.end);
    }
    if (check != null) marker = '${ctx.ordered ? marker : '- '}[$check] ';
    _lines.add('$prefix$indent$marker$text');
    for (final n in nested) {
      if (n is Element && n.localName == 'blockquote') {
        _blocks(
          n.nodes,
          prefix: '$prefix$indent    > ',
          lists: lists,
          pre: preserve,
        );
      } else if (n is Element) {
        _block(n, prefix: prefix, lists: lists, pre: preserve);
      }
    }
  }

  // ---- Word (mso-list) paragraphs -----------------------------------------

  bool _isMsoList(Element e) =>
      (e.attributes['style'] ?? '').toLowerCase().contains('mso-list:') &&
      !(e.attributes['style'] ?? '').toLowerCase().contains('mso-list:none');

  bool _msoTitle(Element e) => (e.attributes['class'] ?? '') == 'MsoTitle';

  void _msoListItem(Element p, String prefix) {
    final st = (p.attributes['style'] ?? '').toLowerCase();
    final level =
        int.tryParse(RegExp(r'level(\d+)').firstMatch(st)?.group(1) ?? '1') ??
        1;
    // The bullet / number Word draws is in a span marked mso-list:Ignore.
    String bullet = '';
    for (final s in p.querySelectorAll('span')) {
      if (_style(s).contains('mso-list:ignore')) {
        bullet = s.text.replaceAll(' ', ' ').trim();
        break;
      }
    }
    final ordered = RegExp(r'^(\d+|[a-zA-Z]|[ivxIVX]+)[.)]$').hasMatch(bullet);
    final segs = <_Seg>[];
    for (final n in p.nodes) {
      _inline(n, const _Attrs(), segs, false);
    }
    var text = _render(segs, pre: false).replaceAll('\n', ' ').trim();
    String marker;
    if (ordered) {
      _msoCounters.removeWhere((k, _) => k > level);
      marker = '${_msoCounters[level] = (_msoCounters[level] ?? 0) + 1}. ';
    } else {
      _msoCounters.removeWhere((k, _) => k >= level);
      marker = '- ';
      final ballot = RegExp(r'^([☐☑☒])\s*').firstMatch(bullet + text);
      if (ballot != null) marker = '- [${ballot.group(1) == '☐' ? ' ' : 'x'}] ';
    }
    _lines.add('$prefix${'    ' * (level - 1)}$marker$text');
  }

  // ---- tables -------------------------------------------------------------

  void _table(Element table, String prefix) {
    for (final tr in table.querySelectorAll('tr')) {
      final cells = <String>[];
      for (final c in tr.children) {
        if (c.localName != 'td' && c.localName != 'th') continue;
        final segs = <_Seg>[];
        for (final n in c.nodes) {
          _inline(n, const _Attrs(), segs, false);
        }
        cells.add(_render(segs, pre: false).replaceAll('\n', ' ').trim());
      }
      if (cells.any((c) => c.isNotEmpty)) {
        _lines.add('$prefix${cells.join('\t')}');
      }
    }
  }

  // ---- inline -------------------------------------------------------------

  _Attrs _styleAttrs(Element e, _Attrs a) {
    final st = _style(e);
    if (st.isEmpty) return a;
    var out = a;
    if (_isBoldStyle(st)) out = out.copy(bold: true);
    if (_isNormalWeight(st)) out = out.copy(bold: false);
    if (st.contains('font-style:italic') || st.contains('font-style:oblique')) {
      out = out.copy(italic: true);
    }
    if (st.contains('font-style:normal')) out = out.copy(italic: false);
    if (RegExp(r'text-decoration(-line)?:[^;]*line-through').hasMatch(st)) {
      out = out.copy(strike: true);
    }
    // A link's own underline is just the browser default, not formatting.
    if (a.href == null &&
        RegExp(r'text-decoration(-line)?:[^;]*underline').hasMatch(st)) {
      out = out.copy(underline: true);
    }
    return out;
  }

  void _inline(Node n, _Attrs a, List<_Seg> out, bool pre) {
    if (n is Text) {
      var t = n.text;
      if (!pre) {
        t = t.replaceAll(' ', ' ').replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
      }
      if (t.isNotEmpty) out.add(_Seg(t, a));
      return;
    }
    if (n is! Element) return;
    final tag = n.localName!;
    if (_skipTags.contains(tag)) return;
    if (_style(n).contains('mso-list:ignore')) return;
    if (_style(n).contains('display:none')) return;
    var attrs = _styleAttrs(n, a);
    switch (tag) {
      case 'br':
        out.add(_Seg('\n', a));
        return;
      case 'b' || 'strong':
        // Google Docs wraps whole documents in <b style="font-weight:normal">.
        attrs = _isNormalWeight(_style(n)) ? attrs : attrs.copy(bold: true);
      case 'i' || 'em' || 'cite' || 'dfn':
        attrs = attrs.copy(italic: true);
      case 's' || 'strike' || 'del':
        attrs = attrs.copy(strike: true);
      case 'code' || 'kbd' || 'samp' || 'tt':
        attrs = attrs.copy(code: true);
      case 'a':
        final href = (n.attributes['href'] ?? '').trim();
        if (RegExp(
          r'^(https?:|mailto:)',
          caseSensitive: false,
        ).hasMatch(href)) {
          attrs = attrs.copy(href: href, underline: false);
        }
      case 'u' || 'ins':
        if (attrs.href == null) {
          attrs = attrs.copy(underline: true);
        }
      case 'sup' ||
          'sub' ||
          'mark' ||
          'small' ||
          'big' ||
          'span' ||
          'font' ||
          'label' ||
          'abbr' ||
          'time':
        break;
      default:
        break;
    }
    for (final c in n.nodes) {
      _inline(c, attrs, out, pre);
    }
  }

  // ---- rendering ----------------------------------------------------------

  String _render(List<_Seg> segs, {required bool pre}) {
    // Merge neighbours with the same attributes so markers are not repeated.
    final merged = <_Seg>[];
    for (final s in segs) {
      if (merged.isNotEmpty && merged.last.a == s.a) {
        merged.last.text += s.text;
      } else {
        merged.add(_Seg(s.text, s.a));
      }
    }
    final sb = StringBuffer();
    int i = 0;
    while (i < merged.length) {
      final href = merged[i].a.href;
      if (href == null) {
        sb.write(_format(merged[i]));
        i++;
        continue;
      }
      int j = i;
      final inner = StringBuffer();
      while (j < merged.length && merged[j].a.href == href) {
        inner.write(_format(merged[j]));
        j++;
      }
      final label = inner.toString();
      if (label.trim().isEmpty) {
        sb.write(label);
      } else {
        final lead = label.substring(0, label.length - label.trimLeft().length);
        final trail = label.substring(label.trimRight().length);
        final safeHref = href.replaceAll(' ', '%20').replaceAll(')', '%29');
        sb.write('$lead[${label.trim()}]($safeHref)$trail');
      }
      i = j;
    }
    var text = sb.toString();
    if (!pre) {
      // Tidy spaces around line breaks and at the ends.
      text = text
          .replaceAll(RegExp(r' *\n *'), '\n')
          .replaceAll(RegExp(r' {2,}'), ' ');
      text = text.replaceAll(RegExp(r'^\n+|\n+$'), '');
      text = text.trim();
    }
    return text;
  }

  /// One run as markdown. Edge whitespace stays outside the markers
  /// (`**bold **` would not render).
  String _format(_Seg s) {
    final a = s.a;
    final raw = s.text;
    if (raw.trim().isEmpty) return raw;
    // A run holding line breaks is formatted line by line.
    if (raw.contains('\n')) {
      return raw.split('\n').map((l) => _format(_Seg(l, a))).join('\n');
    }
    final lead = raw.substring(0, raw.length - raw.trimLeft().length);
    final trail = raw.substring(raw.trimRight().length);
    var core = raw.trim();
    if (a.code) core = '`$core`';
    final stars = a.bold && a.italic
        ? '***'
        : (a.bold ? '**' : (a.italic ? '*' : ''));
    if (a.underline) {
      core = '<u>$core</u>';
    }
    core = '$stars$core$stars';
    if (a.strike) core = '~~$core~~';
    return '$lead$core$trail';
  }
}
