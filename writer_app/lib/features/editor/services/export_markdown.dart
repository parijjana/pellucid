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

/// The HTML both exporters consume.
String markdownToExportHtml(String markdown) => md
    .markdownToHtml(markdown, extensionSet: exportExtensionSet)
    .replaceAllMapped(_taskItem, (m) => '<li class="task">${m[1]}<span class="task-box');
