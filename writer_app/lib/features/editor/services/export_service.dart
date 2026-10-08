import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:epub_builder/epub_builder.dart' as eb;
import '../list_marker.dart';
import '../providers/editor_font.dart';
import 'export_markdown.dart';
import 'export_pdf_lists.dart';

class ExportService {
  /// PDF theme for the chosen document font. These are the PDF standard
  /// fonts (Times, Helvetica, Courier): every viewer supplies them, so nothing
  /// is embedded and no font licence applies. If a bundled font is ever
  /// embedded here it must pass the font rule in the project CLAUDE.md.
  static pw.ThemeData pdfThemeFor(EditorFont font) {
    switch (font) {
      case EditorFont.serif:
        return pw.ThemeData.withFont(
          base: pw.Font.times(),
          bold: pw.Font.timesBold(),
          italic: pw.Font.timesItalic(),
          boldItalic: pw.Font.timesBoldItalic(),
        );
      case EditorFont.sans:
        return pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
        );
      case EditorFont.monospace:
        return pw.ThemeData.withFont(
          base: pw.Font.courier(),
          bold: pw.Font.courierBold(),
          italic: pw.Font.courierOblique(),
          boldItalic: pw.Font.courierBoldOblique(),
        );
    }
  }

  /// Builds the PDF in memory. [compress] is off in tests so the content
  /// streams can be inspected.
  Future<Uint8List> buildPdf(
    String markdown, {
    EditorFont font = EditorFont.defaultFont,
    bool compress = true,
  }) async {
    final pdf = pw.Document(compress: compress);

    // Convert Markdown to PDF Widgets
    final widgets = await markdownToPdfWidgets(markdown);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pdfThemeFor(font),
        build: (context) => widgets,
      ),
    );

    return pdf.save();
  }

  Future<void> exportToPdf(
    String markdown,
    String filePath, {
    EditorFont font = EditorFont.defaultFont,
  }) async {
    final file = File(filePath);
    await file.writeAsBytes(await buildPdf(markdown, font: font));
  }

  /// The stylesheet shipped inside the EPUB: the chosen font for the book.
  static String epubCssFor(EditorFont font, {BulletStyle bullets = BulletStyle.classic}) =>
      'body { font-family: ${font.cssFamily}; }\n'
      'blockquote { margin: 1em 2em; font-style: italic; }\n'
      'del { text-decoration: line-through; }\n'
      // Nested lists change marker with the level, as in the editor.
      'ul ul { list-style-type: circle; }\nul ul ul { list-style-type: square; }\n'
      'ol ol { list-style-type: lower-alpha; }\nol ol ol { list-style-type: lower-roman; }\n'
      'p.in1 { margin-left: 1.6em; }\np.in2 { margin-left: 3.2em; }\np.in3 { margin-left: 4.8em; }\np.in4 { margin-left: 6.4em; }\n'
      '${_epubBulletCss(bullets)}'
      'li.task { list-style: none; margin-left: -1.4em; }\n.task-box { margin-right: 0.3em; }\n';

  /// CSS for a non-classic bullet set (slice 5b): the glyph is the list marker
  /// (`list-style-type` string, EPUB 3; a reader that ignores it keeps the
  /// classic marker above). Classic needs nothing.
  static String _epubBulletCss(BulletStyle b) {
    if (b == BulletStyle.classic) return '';
    final g = b.glyphs;
    return "ul { list-style-type: '${g[0]} '; }\nul ul { list-style-type: '${g[1]} '; }\nul ul ul { list-style-type: '${g[2]} '; }\n";
  }

  /// Builds the EPUB in memory (also used by the tests).
  Uint8List buildEpub({
    required String markdown,
    required String title,
    required String author,
    EditorFont font = EditorFont.defaultFont,
    BulletStyle bullets = BulletStyle.classic,
  }) {
    final book = eb.EpubBook.create(
      title: title,
      authors: [author],
      cssContent: epubCssFor(font, bullets: bullets),
    );

    // Split markdown by headers to create chapters
    final chapters = _splitIntoChapters(markdown);

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final htmlContent = markdownToExportHtml(chapter.content);

      book.addChapter(
        eb.EpubChapter(
          title: chapter.title.isEmpty ? 'Chapter ${i + 1}' : chapter.title,
          content: '<h1>${chapter.title}</h1>$htmlContent',
        ),
      );
    }

    final bytes = eb.EpubBuilder(book).encode();
    if (bytes == null) throw Exception('Failed to encode EPUB');
    return Uint8List.fromList(bytes);
  }

  Future<void> exportToEpub({
    required String markdown,
    required String title,
    required String author,
    required String filePath,
    EditorFont font = EditorFont.defaultFont,
    BulletStyle bullets = BulletStyle.classic,
  }) async {
    final bytes = buildEpub(markdown: markdown, title: title, author: author, font: font, bullets: bullets);
    await File(filePath).writeAsBytes(bytes);
  }

  List<_Chapter> _splitIntoChapters(String markdown) {
    final List<_Chapter> chapters = [];
    final lines = markdown.split('\n');
    
    String currentTitle = '';
    StringBuffer currentContent = StringBuffer();
    
    for (final line in lines) {
      if (line.startsWith('# ')) {
        // Save previous chapter if it has content
        if (currentContent.isNotEmpty || currentTitle.isNotEmpty) {
          chapters.add(_Chapter(currentTitle, currentContent.toString()));
        }
        currentTitle = line.substring(2).trim();
        currentContent = StringBuffer();
      } else {
        currentContent.writeln(line);
      }
    }
    
    // Add last chapter
    if (currentContent.isNotEmpty || currentTitle.isNotEmpty) {
      chapters.add(_Chapter(currentTitle, currentContent.toString()));
    }
    
    // If no chapters found, return everything as one chapter
    if (chapters.isEmpty) {
      chapters.add(_Chapter('', markdown));
    }
    
    return chapters;
  }
}

class _Chapter {
  final String title;
  final String content;
  _Chapter(this.title, this.content);
}
