import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/word_count.dart';

void main() {
  test('countWords uses whitespace-separated runs', () {
    expect(countWords(''), 0);
    expect(countWords('   \n\t'), 0);
    expect(countWords('one'), 1);
    expect(countWords('one  two\nthree\r\nfour\tfive '), 5);
    expect(countWords('# Heading **bold**'), 3);
  });

  test('label shows "N of M words" only while text is selected', () {
    expect(wordCountLabel(120), '120 words');
    expect(wordCountLabel(120, selected: 0), '120 words');
    expect(wordCountLabel(120, selected: 7), '7 of 120 words');
  });
}
