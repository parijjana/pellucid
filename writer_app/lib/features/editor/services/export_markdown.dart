// Markdown -> HTML for PDF and EPUB export (item 21).
//
// One conversion shared by both formats so they cannot drift. It renders what
// the editor renders: H1-H3, bold/italic/<u>, strikethrough (`~~x~~`, the same
// double-tilde-only rule as the editor) and block quotes (`> `).
//
// EXTENSION POINT (later slice: numbered and nested lists, checklists):
// add block syntaxes to [_extraBlockSyntaxes] and inline syntaxes to
// [_extraInlineSyntaxes]. Both export paths pick them up with no other change.

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

/// Block syntaxes added on top of CommonMark (none yet; see the note above).
final List<md.BlockSyntax> _extraBlockSyntaxes = <md.BlockSyntax>[];

/// Inline syntaxes added on top of CommonMark.
final List<md.InlineSyntax> _extraInlineSyntaxes = <md.InlineSyntax>[
  DoubleTildeStrikethroughSyntax(),
];

final md.ExtensionSet exportExtensionSet = md.ExtensionSet(
  [...md.ExtensionSet.commonMark.blockSyntaxes, ..._extraBlockSyntaxes],
  [..._extraInlineSyntaxes, ...md.ExtensionSet.commonMark.inlineSyntaxes],
);

/// The HTML both exporters consume.
String markdownToExportHtml(String markdown) =>
    md.markdownToHtml(markdown, extensionSet: exportExtensionSet);
