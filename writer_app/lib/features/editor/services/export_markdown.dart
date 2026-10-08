// Markdown -> HTML for PDF and EPUB export (item 21).
//
// One conversion shared by both formats so they cannot drift. It renders what
// the editor renders: H1-H3, bold/italic/<u>, strikethrough (`~~x~~`, the same
// double-tilde-only rule as the editor) and block quotes (`> `).
//
// Lists: numbered and nested lists come from CommonMark itself (the editor
// nests by four spaces, which CommonMark nests under both `- ` and `1. `).
// Checklists (`- [ ] ` / `- [x] `) are [TaskBoxSyntax] in [_extraInlineSyntaxes].
//
// EXTENSION POINT: add block syntaxes to [_extraBlockSyntaxes] and inline
// syntaxes to [_extraInlineSyntaxes]. Both export paths pick them up with no
// other change.

import 'package:markdown/markdown.dart' as md;

/// `~~text~~` -> `<del>text</del>`. Only the double-tilde form, so a lone `~`
/// in prose ("~5 minutes") is never struck, matching the editor.
class DoubleTildeStrikethroughSyntax extends md.InlineSyntax {
  DoubleTildeStrikethroughSyntax() : super(r'~~(?=\S)(.+?)(?<=\S)~~');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('del', match[1]!));
    return true;
  }
}

/// `[ ] ` / `[x] ` at the very start of a list item's text -> a
/// `<span class="task-box">` holding the box glyph (☐ / ☑); `done` when ticked.
/// Anywhere else in a paragraph (a prose "[x]") it is left as typed.
class TaskBoxSyntax extends md.InlineSyntax {
  TaskBoxSyntax() : super(r'\[([ xX])\] ');

  // Only at the start of the text. (Returning false from onMatch would leave
  // the parser standing still, so the check has to be here.)
  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    if ((startMatchPos ?? parser.pos) != 0) return false;
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final done = match[1] != ' ';
    final box = md.Element.text('span', done ? '\u2611' : '\u2610')
      ..attributes['class'] = done ? 'task-box done' : 'task-box';
    parser.addNode(box);
    parser.addNode(md.Text(' '));
    return true;
  }
}

/// Block syntaxes added on top of CommonMark (none yet; see the note above).
final List<md.BlockSyntax> _extraBlockSyntaxes = <md.BlockSyntax>[];

/// Inline syntaxes added on top of CommonMark.
final List<md.InlineSyntax> _extraInlineSyntaxes = <md.InlineSyntax>[
  DoubleTildeStrikethroughSyntax(),
  TaskBoxSyntax(),
];

final md.ExtensionSet exportExtensionSet = md.ExtensionSet(
  [...md.ExtensionSet.commonMark.blockSyntaxes, ..._extraBlockSyntaxes],
  [..._extraInlineSyntaxes, ...md.ExtensionSet.commonMark.inlineSyntaxes],
);

/// A list item that starts with a checkbox is marked so a stylesheet can drop
/// its bullet: `<li><span class="task-box"` -> `<li class="task"><span ...`.
final RegExp _taskItem = RegExp(r'<li>(\s*(?:<p>)?\s*)<span class="task-box');

/// Paragraph indent (slice 5b). The Markdown parser trims the em spaces at the
/// start of a paragraph, so before parsing each leading run (outside code
/// fences) is swapped for the same number of private-use marks; the HTML
/// step turns them into `class="in1".."in4"`, the PDF step into padding. The
/// em space itself never reaches the output outside code.
const String exportIndentMark = '\uE000';

final RegExp _indentedParagraph = RegExp('<p>\uE000+');
final RegExp _softBreakIndent = RegExp('\n\uE000+');
final RegExp _preBlock = RegExp(r'<pre>.*?</pre>', dotAll: true);

/// [markdown] with each leading em-space run replaced by [exportIndentMark]s.
/// Lines inside fenced code are left as they are.
String markParagraphIndents(String markdown) {
  if (!markdown.contains('\u2003')) return markdown;
  final out = <String>[];
  bool fenced = false;
  for (final line in markdown.split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('```') || t.startsWith('~~~')) fenced = !fenced;
    if (!fenced && line.startsWith('\u2003')) {
      int n = 0;
      while (n < line.length && line.codeUnitAt(n) == 0x2003) {
        n++;
      }
      out.add(exportIndentMark * n + line.substring(n));
    } else {
      out.add(line);
    }
  }
  return out.join('\n');
}

/// The HTML both exporters consume.
String markdownToExportHtml(String markdown) {
  final html = md
      .markdownToHtml(markParagraphIndents(markdown), extensionSet: exportExtensionSet)
      .replaceAllMapped(_taskItem, (m) => '<li class="task">${m[1]}<span class="task-box');
  final indented = html
      .replaceAllMapped(_indentedParagraph, (m) => '<p class="in${(m[0]!.length - 3).clamp(1, 4)}">')
      .replaceAll(_softBreakIndent, '\n');
  // Stray em spaces and marks outside code never print.
  final sb = StringBuffer();
  int at = 0;
  String clean(String t) => t.replaceAll('\u2003', '').replaceAll(exportIndentMark, '');
  for (final m in _preBlock.allMatches(indented)) {
    sb
      ..write(clean(indented.substring(at, m.start)))
      ..write(indented.substring(m.start, m.end));
    at = m.end;
  }
  sb.write(clean(indented.substring(at)));
  return sb.toString();
}

/// [text] without paragraph-indent marks, and the indent level it had.
({String text, int level}) takeParagraphIndent(String text) {
  int n = 0;
  while (n < text.length && text[n] == exportIndentMark) {
    n++;
  }
  return (text: text.substring(n).replaceAll(_softBreakIndent, '\n').replaceAll(exportIndentMark, ''), level: n > 4 ? 4 : n);
}
