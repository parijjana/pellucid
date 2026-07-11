// Description: Pure helpers for building the Table of Contents header list and
// per-chapter word counts. Kept out of any widget so header parsing and the
// roll-up word count can be computed once on text change and reused in build().

/// A parsed markdown header plus the word count that "rolls up" into it.
///
/// The word count spans from the header down to (but excluding) the next header
/// of the SAME or HIGHER level. A `#` chapter therefore includes the words of
/// its `##`/`###` subsections, while a `##` covers only its own subsection.
typedef TocHeader = ({String title, int line, int level, int wordCount});

/// Zero-allocation word scanner over a slice of [text] from [start] (inclusive)
/// to [end] (exclusive). Counts runs of non-whitespace characters without
/// splitting the string.
int countWordsInRange(String text, int start, int end) {
  int count = 0;
  bool inWord = false;
  for (int i = start; i < end; i++) {
    final codeUnit = text.codeUnitAt(i);
    final isWhitespace =
        codeUnit == 32 || codeUnit == 10 || codeUnit == 13 || codeUnit == 9;
    if (isWhitespace) {
      if (inWord) {
        count++;
        inWord = false;
      }
    } else {
      inWord = true;
    }
  }
  if (inWord) count++;
  return count;
}

/// Parses markdown headers from [text] and computes each header's rolled-up
/// word count in a single pass over the lines.
///
/// Header lines' own tag/title text is not counted; only the prose (non-header)
/// lines beneath a header contribute, and each such line's words are attributed
/// to every ancestor header currently in scope (so subsection words roll up into
/// their parent chapter).
List<TocHeader> parseTocHeaders(String text) {
  final headers = <({String title, int line, int level})>[];
  final counts = <int>[];
  // Stack of indices into `counts`/`headers` for the currently open header chain,
  // kept in strictly increasing header level order.
  final openStack = <int>[];

  final lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) {
      int level = 0;
      while (level < trimmed.length && trimmed.codeUnitAt(level) == 35) {
        level++;
      }
      // Require a space after the hashes and a non-empty title (matches the
      // markdown header shape used elsewhere in the app).
      if (level < trimmed.length && trimmed.codeUnitAt(level) == 32) {
        final title = trimmed.substring(level + 1).trim();
        if (title.isNotEmpty) {
          // Close any open headers at this level or deeper.
          while (openStack.isNotEmpty && headers[openStack.last].level >= level) {
            openStack.removeLast();
          }
          final index = headers.length;
          headers.add((title: title, line: i, level: level));
          counts.add(0);
          openStack.add(index);
          continue;
        }
      }
    }
    // Prose line: attribute its words to every open (ancestor) header.
    if (openStack.isNotEmpty) {
      final wc = countWordsInRange(line, 0, line.length);
      if (wc != 0) {
        for (final idx in openStack) {
          counts[idx] += wc;
        }
      }
    }
  }

  return [
    for (int i = 0; i < headers.length; i++)
      (
        title: headers[i].title,
        line: headers[i].line,
        level: headers[i].level,
        wordCount: counts[i],
      ),
  ];
}
