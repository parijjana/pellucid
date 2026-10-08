// Item 21 (this slice): PDF and EPUB render H3, strikethrough, block quotes and
// the chosen font. One snapshot per format, stored in test/features/editor/goldens.
// Regenerate with: UPDATE_GOLDENS=1 flutter test test/features/editor/export_test.dart

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:pellucid/features/editor/services/export_markdown.dart';
import 'package:pellucid/features/editor/services/export_service.dart';

const _doc = '''# Chapter One

## Part

### Subheading here

Plain with ~~struck~~ and **bold** and *italic* words, ~5 minutes stays.

> A quoted line

Back to body.
''';

// Lists as the editor stores them: four-space nesting, 1. a. i. by level,
// checklists. Item 21 for slice 5.
const _listsDoc = '''# Lists

- bullet one
    - nested bullet
        - deep bullet
- bullet two

1. first
2. second
    1. nested one
    2. nested two
        1. deepest
3. third **bold**

- [ ] open task
- [x] done task
    - [ ] nested task

Prose with [x] in the middle stays as typed.
''';

void _matchesGolden(String name, String actual) {
  final file = File('test/features/editor/goldens/$name');
  if (Platform.environment['UPDATE_GOLDENS'] == '1' || !file.existsSync()) {
    file.writeAsStringSync(actual);
  }
  expect(actual, file.readAsStringSync());
}

/// Readable summary of an uncompressed PDF: the standard fonts it names, and
/// the text drawn, in order. Stable across runs (no dates, ids or offsets).
String _pdfSummary(List<int> bytes) {
  final text = latin1.decode(bytes);
  final fonts = RegExp(r'/BaseFont\s*/([A-Za-z\-]+)').allMatches(text).map((m) => m[1]!).toSet().toList()..sort();
  final shown = RegExp(r'\[?\(([^)]*)\)\]?\s*TJ|\(([^)]*)\)\s*Tj').allMatches(text).map((m) => m[1] ?? m[2]!).toList();
  final hasEmbeddedFontFile = text.contains('/FontFile');
  return 'fonts: ${fonts.join(', ')}\nembeddedFontFiles: $hasEmbeddedFontFile\ntext:\n${shown.join('\n')}\n';
}

void main() {
  final service = ExportService();

  group('shared markdown -> HTML', () {
    test('renders H3, strikethrough and block quotes', () {
      final html = markdownToExportHtml(_doc);
      expect(html, contains('<h3>Subheading here</h3>'));
      expect(html, contains('<del>struck</del>'));
      expect(html, contains('<blockquote>'));
      expect(html, contains('A quoted line'));
    });

    test('numbered and nested lists and checklists', () {
      final html = markdownToExportHtml(_listsDoc);
      expect(RegExp(r'<ol>').allMatches(html).length, 3); // top, nested, deepest
      expect(html, contains('<li>nested bullet'));
      expect(html, contains('<li class="task"><span class="task-box">\u2610</span> open task'));
      expect(html, contains('<span class="task-box done">\u2611</span> done task'));
      expect(html, contains('Prose with [x] in the middle'));
    });

    test('a lone tilde is not strikethrough', () {
      final html = markdownToExportHtml('about ~5 min and ~6 min');
      expect(html, isNot(contains('<del>')));
    });
  });

  group('PDF', () {
    test('snapshot (serif)', () async {
      final bytes = await service.buildPdf(_doc, font: EditorFont.serif, compress: false);
      _matchesGolden('export_pdf_serif.txt', _pdfSummary(bytes));
    });

    test('lists snapshot: numbers, nesting and checklists (serif)', () async {
      final bytes = await service.buildPdf(_listsDoc, font: EditorFont.serif, compress: false);
      final summary = _pdfSummary(bytes);
      _matchesGolden('export_pdf_lists.txt', summary);
      // Level-aware numbering, nested items in order, boxes drawn (no glyph needed).
      final shown = summary.split('text:\n').last.split('\n');
      expect(shown, containsAllInOrder(['1.', 'first', '2.', 'second', 'a.', 'nested', 'one', 'b.', 'nested', 'two']));
      expect(shown, containsAllInOrder(['i.', 'deepest', '3.', 'third']));
      expect(shown, containsAllInOrder(['bullet', 'one', 'nested', 'bullet', 'deep', 'bullet', 'bullet', 'two']));
      expect(summary, isNot(contains('\u2610')));
    });

    test('each font uses its own standard family and embeds nothing', () async {
      for (final entry in {
        EditorFont.serif: 'Times-Roman',
        EditorFont.sans: 'Helvetica',
        EditorFont.monospace: 'Courier',
      }.entries) {
        final text = latin1.decode(await service.buildPdf(_doc, font: entry.key, compress: false));
        expect(text, contains('/BaseFont/${entry.value}'), reason: entry.key.id);
        expect(text.contains('/FontFile'), isFalse, reason: 'no embedded font, so no licence to check');
      }
    });

    test('exportToPdf writes a PDF file', () async {
      final dir = Directory.systemTemp.createTempSync('pdf_export');
      final path = '${dir.path}/out.pdf';
      await service.exportToPdf(_doc, path, font: EditorFont.sans);
      expect(File(path).readAsBytesSync().sublist(0, 4), utf8.encode('%PDF'));
      dir.deleteSync(recursive: true);
    });
  });

  group('EPUB', () {
    String epubSummary(EditorFont font, {String doc = _doc}) {
      final bytes = service.buildEpub(markdown: doc, title: 'T', author: 'A', font: font);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toList()..sort();
      String read(String suffix) =>
          utf8.decode(archive.files.firstWhere((f) => f.name.endsWith(suffix)).content as List<int>);
      final chapter = names.firstWhere((n) => n.endsWith('.xhtml') && !n.contains('nav') && !n.contains('toc'));
      // Chapter ids are random per build; normalise them for the snapshot.
      final xhtml = read(chapter.split('/').last).replaceAll(RegExp(r'ch_[0-9a-f]+'), 'ch_ID');
      return 'css:\n${read('styles.css')}\nchapter:\n$xhtml\n';
    }

    test('snapshot (serif)', () {
      _matchesGolden('export_epub_serif.txt', epubSummary(EditorFont.serif));
    });

    test('lists snapshot: nested lists, level styles and checkboxes', () {
      final summary = epubSummary(EditorFont.serif, doc: _listsDoc);
      _matchesGolden('export_epub_lists.txt', summary);
      expect(summary, contains('ol ol { list-style-type: lower-alpha; }'));
      expect(summary, contains('ol ol ol { list-style-type: lower-roman; }'));
      expect(summary, contains('<li class="task">'));
    });

    test('stylesheet carries the chosen font', () {
      expect(epubSummary(EditorFont.monospace), contains("font-family: 'Menlo', 'Consolas'"));
      expect(epubSummary(EditorFont.sans), contains("'Helvetica Neue'"));
    });
  });
}
