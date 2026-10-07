// Description: The one word-count rule (whitespace-separated runs) shared by
// the status bar total, the selection count and the stats.

/// Counts whitespace-separated words. Whitespace is space, tab, LF and CR.
int countWords(String text) {
  int count = 0;
  bool inWord = false;
  final length = text.length;
  for (int i = 0; i < length; i++) {
    final codeUnit = text.codeUnitAt(i);
    final isWhitespace = codeUnit == 32 || codeUnit == 10 || codeUnit == 13 || codeUnit == 9;
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

/// Status-bar label: "M words", or "N of M words" while text is selected.
String wordCountLabel(int total, {int selected = 0}) =>
    selected > 0 ? '$selected of $total words' : '$total words';
