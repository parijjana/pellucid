import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/long_document/document_buffer.dart';
import 'package:pellucid/features/editor/word_count.dart';

import '../large_document_fixture.dart';

void _expectConsistent(DocumentBuffer b, String reference) {
  expect(b.text, reference);
  expect(b.length, reference.length);
  expect(b.wordCount, countWords(reference));
  final lines = reference.split('\n');
  expect(b.lineCount, lines.length);
  int offset = 0;
  for (int i = 0; i < lines.length; i++) {
    expect(b.line(i), lines[i]);
    expect(b.lineStart(i), offset, reason: 'start of line $i');
    expect(b.lineOfOffset(offset), i);
    expect(b.lineOfOffset(offset + lines[i].length), i, reason: 'offset on the newline ending line $i');
    offset += lines[i].length + 1;
  }
}

void main() {
  test('index and counts match the text after random edits', () {
    final rnd = Random(3);
    String reference = generateManuscript(3000, seed: 11, markupEvery: 60);
    final b = DocumentBuffer(reference);
    _expectConsistent(b, reference);
    const pieces = ['x', 'word ', '\n', '\n\n', 'two\nlines', '', '**bold** ', '😀'];
    for (int step = 0; step < 300; step++) {
      final int s = rnd.nextInt(reference.length + 1);
      final int e = min(reference.length, s + rnd.nextInt(rnd.nextBool() ? 3 : 400));
      final String ins = pieces[rnd.nextInt(pieces.length)];
      reference = reference.replaceRange(s, e, ins);
      b.replace(s, e, ins);
      if (step % 25 == 0) _expectConsistent(b, reference);
      expect(b.text, reference);
      expect(b.wordCount, countWords(reference), reason: 'step $step');
    }
    _expectConsistent(b, reference);
  });

  test('edits at the very start and end, and an emptied buffer', () {
    final b = DocumentBuffer('a\nb');
    b.replace(0, 0, 'x');
    b.replace(b.length, b.length, '\nz');
    _expectConsistent(b, 'xa\nb\nz');
    b.replace(0, b.length, '');
    _expectConsistent(b, '');
    b.reset('one two\nthree');
    _expectConsistent(b, 'one two\nthree');
  });

  test('diffReplacement is the minimal single replacement', () {
    expect(diffReplacement('hello world', 'hello brave world'), (start: 6, end: 6, inserted: 'brave '));
    expect(diffReplacement('abc', 'ac'), (start: 1, end: 2, inserted: ''));
    expect(diffReplacement('aaa', 'aaaa'), (start: 3, end: 3, inserted: 'a'));
    expect(diffReplacement('same', 'same'), (start: 4, end: 4, inserted: ''));
  });
}
