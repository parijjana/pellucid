// The ~127k-word manuscript the long-document E2E suite types into. Public
// domain text (Jane Austen, Pride and Prejudice, 1813) repeated in generated
// paragraphs, with a handful of landmarks planted far from the top so each
// check has something specific to find.

/// Offsets are into [text]; lines are 0-based.
class Fixture {
  final String text;
  final int words;

  /// Chapter 25 holds the landmarks below; chapters 12 and 38 hold the other
  /// "quokka" hits for Find.
  final int boldLine;
  final int headingLine; // "# Chapter 25"
  final int bulletFirstLine; // "- First item" (three bullets)
  final int tehLine;
  final int darcyLine;
  final int tehOffset; // start of "teh"
  final int darcyOffset; // start of "Darcy"
  final List<int> quokkaOffsets;
  final List<int> chapterLines; // line index of each "# Chapter N: ..." heading

  Fixture._(this.text, this.words, this.boldLine, this.headingLine, this.bulletFirstLine, this.tehLine,
      this.darcyLine, this.tehOffset, this.darcyOffset, this.quokkaOffsets, this.chapterLines);

  late final List<String> lines = text.split('\n');

  int lineStart(int line) {
    int o = 0;
    for (int i = 0; i < line; i++) {
      o += lines[i].length + 1;
    }
    return o;
  }
}

const List<String> _sentences = [
  'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
  'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.',
  'My dear Mr. Bennet, said his lady to him one day, have you heard that Netherfield Park is let at last?',
  'Mr. Bennet replied that he had not.',
  'But it is, returned she; for Mrs. Long has just been here, and she told me all about it.',
  'Mr. Bennet made no answer.',
  'Do you not want to know who has taken it? cried his wife impatiently.',
  'You want to tell me, and I have no objection to hearing it.',
  'This was invitation enough.',
  'Why, my dear, you must know, Mrs. Long says that Netherfield is taken by a young man of large fortune from the north of England.',
  'What is his name? Is he married or single?',
  'Oh, single, my dear, to be sure, a single man of large fortune; four or five thousand a year.',
  'What a fine thing for our girls!',
  'How so? How can it affect them?',
  'My dear Mr. Bennet, replied his wife, how can you be so tiresome! You must know that I am thinking of his marrying one of them.',
  'Is that his design in settling here?',
  'Design! Nonsense, how can you talk so! But it is very likely that he may fall in love with one of them, and therefore you must visit him as soon as he comes.',
];

Fixture buildFixture({int targetWords = 127000}) {
  final buf = StringBuffer();
  int words = 0;
  int line = 0;
  void emit(String l) {
    buf.write(l);
    buf.write('\n');
    line++;
    words += l.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  int offset() => buf.length;
  final chapterLines = <int>[];
  final quokkas = <int>[];
  int boldLine = -1, headingLine = -1, bulletFirst = -1, tehLine = -1, darcyLine = -1;
  int tehOffset = -1, darcyOffset = -1;
  const chapters = 49;
  const perChapter = 19;
  int s = 0;
  const names = ['The Lantern', 'The Harbour', 'The Letter', 'The Ball', 'The Visit'];
  for (int c = 1; c <= chapters; c++) {
    chapterLines.add(line);
    if (c == 25) headingLine = line;
    emit('# Chapter $c: ${names[c % 5]}');
    emit('');
    for (int p = 0; p < perChapter; p++) {
      final n = 6 + (c * 7 + p * 3) % 5;
      emit([for (int i = 0; i < n; i++) _sentences[(s++ * 5 + c) % _sentences.length]].join(' '));
      emit('');
      if (c == 12 && p == 3) {
        quokkas.add(offset() + 'Find me the '.length);
        emit('Find me the quokka at twelve.');
        emit('');
      }
      if (c == 38 && p == 3) {
        quokkas.add(offset() + 'Find me the '.length);
        emit('Find me the quokka at thirty-eight.');
        emit('');
      }
      if (c == 25 && p == 2) {
        boldLine = line;
        emit('A far line with **bold words** inside it.');
        emit('');
        bulletFirst = line;
        emit('- First item');
        emit('- Second item');
        emit('- Third item');
        emit('');
        tehLine = line;
        tehOffset = offset() + 'A deliberate slip: '.length;
        emit('A deliberate slip: teh end of it.');
        emit('');
        quokkas.add(offset() + 'Find me the '.length);
        emit('Find me the quokka at twenty-five.');
        emit('');
        darcyLine = line;
        darcyOffset = offset() + 'Then '.length;
        emit('Then Darcy walked in without a word.');
        emit('');
      }
    }
  }
  // Pad up to the target with plain paragraphs at the end (still "far").
  while (words < targetWords) {
    emit([for (int i = 0; i < 8; i++) _sentences[(s++ * 5) % _sentences.length]].join(' '));
    emit('');
  }
  quokkas.sort();
  return Fixture._(buf.toString(), words, boldLine, headingLine, bulletFirst, tehLine, darcyLine, tehOffset,
      darcyOffset, quokkas, chapterLines);
}
