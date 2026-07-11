// Description: Unit tests for the Table of Contents header parser and the
// per-chapter rolled-up word count semantics.

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/utils/toc_parser.dart';

void main() {
  group('parseTocHeaders', () {
    test('returns empty list for a document with no headers', () {
      final headers = parseTocHeaders('just some words here\nand another line');
      expect(headers, isEmpty);
    });

    test('counts prose words under a single header (excluding its title)', () {
      final headers = parseTocHeaders('# Chapter One\nalpha beta gamma');
      expect(headers.length, 1);
      expect(headers[0].title, 'Chapter One');
      expect(headers[0].level, 1);
      expect(headers[0].line, 0);
      // Only the prose words count; the header title "Chapter One" does not.
      expect(headers[0].wordCount, 3);
    });

    test('rolls subsection words up into the parent chapter', () {
      const text = '# Ch1\n'
          'a\n'
          '## S1\n'
          'b c\n'
          '## S2\n'
          'd\n'
          '# Ch2\n'
          'e f';
      final headers = parseTocHeaders(text);
      expect(headers.map((h) => h.title).toList(), ['Ch1', 'S1', 'S2', 'Ch2']);
      // Ch1 = its own prose (a=1) + S1 body (b c=2) + S2 body (d=1) = 4.
      expect(headers[0].wordCount, 4);
      // S1 covers only its own subsection.
      expect(headers[1].wordCount, 2);
      // S2 covers only its own subsection.
      expect(headers[2].wordCount, 1);
      // Ch2 counts its prose to the end of the document.
      expect(headers[3].wordCount, 2);
    });

    test('a same-or-higher level header closes the previous section', () {
      const text = '## A\none two\n## B\nthree';
      final headers = parseTocHeaders(text);
      expect(headers[0].wordCount, 2); // A does not include B's words
      expect(headers[1].wordCount, 1);
    });

    test('the last chapter counts words through the end of the document', () {
      const text = '# First\none\n# Last\ntwo three four';
      final headers = parseTocHeaders(text);
      expect(headers.last.title, 'Last');
      expect(headers.last.wordCount, 3);
    });

    test('empty sections report a zero word count', () {
      const text = '# Empty\n## Also Empty\n# Has Words\none two three';
      final headers = parseTocHeaders(text);
      expect(headers.map((h) => h.title).toList(),
          ['Empty', 'Also Empty', 'Has Words']);
      expect(headers[0].wordCount, 0); // no prose, only an empty subsection
      expect(headers[1].wordCount, 0);
      expect(headers[2].wordCount, 3);
    });

    test('ignores hash sequences that are not valid headers', () {
      // No space after the hashes -> not a header; counts as prose under Real.
      const text = '# Real\n#notaheader still prose';
      final headers = parseTocHeaders(text);
      expect(headers.length, 1);
      expect(headers[0].title, 'Real');
      expect(headers[0].wordCount, 3); // "#notaheader still prose"
    });
  });

  group('countWordsInRange', () {
    test('counts whitespace-separated runs', () {
      const s = '  hello   world\tfoo\nbar ';
      expect(countWordsInRange(s, 0, s.length), 4);
    });

    test('respects the range bounds', () {
      const s = 'one two three';
      expect(countWordsInRange(s, 0, 3), 1); // "one"
      expect(countWordsInRange(s, 4, s.length), 2); // "two three"
    });
  });
}
