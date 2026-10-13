import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/html_to_markdown.dart';

void main() {
  test('HTML made from Pages-style RTF converts to Markdown', () {
    // Fixture produced by pellucidHtmlFromAttributed (MainFlutterWindow.swift).
    final html = File('test/fixtures/pages_rtf_paste.html').readAsStringSync();
    expect(htmlToMarkdown(html), '''
Plain **bold** *ital* ***both*** <u>under</u> ~~gone~~ [link](https://example.com/a?b=1&c=2) a<b>&
- one
    - nested
- two
1. first
2. second
After''');
  });
}
