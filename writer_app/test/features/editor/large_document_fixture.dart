// Description: Deterministic manuscript generator for large-document tests.
// Mixes every construct MarkdownEditingController styles (headings, bullets,
// bold, italic, bold+italic, underline) with the malformed and edge-case
// markers a real draft contains: stray asterisks, unclosed tags, emoji
// (surrogate pairs) and very long lines.

import 'dart:math';

const List<String> _words = [
  'the', 'lantern', 'swung', 'over', 'harbour', 'Mira', 'said', 'nothing', 'and',
  'waited', 'for', 'tide', 'Ostrava', 'counted', 'boats', 'a', 'hour', 'rain',
  'quietly', 'Teh', 'recieved', 'letter', 'door', 'café', 'naïve', '—', '…',
];

const List<String> _malformed = [
  '*', '**', '***', '****', 'x * y', '<u>', '</u>', '<u>open', '5 * 3 * 2',
  '**unclosed', 'trailing*', '* *', '<u></u>', '😀', '🧭 map', '#hashtag', '-dash',
];

/// Roughly [words] words of manuscript. Same [seed] → same text. The
/// default [markupEvery] is markup-heavy (a stress case); a few hundred is
/// closer to a novel draft.
String generateManuscript(int words, {int seed = 7, int markupEvery = 40}) {
  final rnd = Random(seed);
  final buf = StringBuffer();
  int written = 0;
  String word() => _words[rnd.nextInt(_words.length)];

  String sentence(int n) {
    // One word in [markupEvery] gets inline markup or a malformed marker.
    final parts = <String>[];
    for (int i = 0; i < n; i++) {
      final roll = rnd.nextInt(markupEvery);
      final w = word();
      if (roll == 0) {
        parts.add('**$w ${word()}**');
      } else if (roll == 1) {
        parts.add('*$w*');
      } else if (roll == 2) {
        parts.add('***$w***');
      } else if (roll == 3) {
        parts.add('<u>$w</u>');
      } else if (roll == 4) {
        parts.add(_malformed[rnd.nextInt(_malformed.length)]);
      } else if (roll == 5) {
        parts.add('**bold *nested* bold**');
      } else {
        parts.add(w);
      }
    }
    return '${parts.join(' ')}.';
  }

  while (written < words) {
    final kind = rnd.nextInt(20);
    if (kind == 0) {
      buf.writeln('# ${sentence(4)}');
      written += 4;
    } else if (kind == 1) {
      buf.writeln('## ${sentence(5)}');
      written += 5;
    } else if (kind == 2) {
      buf.writeln('### ${sentence(5)}');
      written += 5;
    } else if (kind < 5) {
      buf.writeln('- ${sentence(8)}');
      written += 8;
    } else if (kind == 5) {
      buf.writeln();
    } else {
      // A paragraph: one long line, as the editor stores it.
      final n = 40 + rnd.nextInt(160);
      final sentences = <String>[];
      int count = 0;
      while (count < n) {
        final len = 6 + rnd.nextInt(14);
        sentences.add(sentence(len));
        count += len;
      }
      buf.writeln(sentences.join(' '));
      buf.writeln();
      written += count;
    }
  }
  return buf.toString();
}
