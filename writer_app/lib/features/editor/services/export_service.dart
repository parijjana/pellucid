import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:epub_builder/epub_builder.dart' as eb;
import 'package:markdown/markdown.dart' as md;
import 'package:htmltopdfwidgets/htmltopdfwidgets.dart' as htp;

class ExportService {
  Future<void> exportToPdf(String markdown, String filePath) async {
    final pdf = pw.Document();
    
    // Convert Markdown to PDF Widgets
    final widgets = await htp.HTMLToPdf().convert(
      md.markdownToHtml(markdown),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => widgets,
      ),
    );

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
  }

  Future<void> exportToEpub({
    required String markdown,
    required String title,
    required String author,
    required String filePath,
  }) async {
    final book = eb.EpubBook.create(
      title: title,
      authors: [author],
    );

    // Split markdown by headers to create chapters
    final chapters = _splitIntoChapters(markdown);
    
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final htmlContent = md.markdownToHtml(chapter.content);
      
      book.addChapter(
        eb.EpubChapter(
          title: chapter.title.isEmpty ? 'Chapter ${i + 1}' : chapter.title,
          content: '<h1>${chapter.title}</h1>$htmlContent',
        ),
      );
    }

    final bytes = eb.EpubBuilder(book).encode();
    if (bytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(bytes);
    } else {
      throw Exception('Failed to encode EPUB');
    }
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
