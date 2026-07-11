// Description: Shared formatting helpers for cloud + local snapshot rows/previews.

int countSnapshotWords(String text) {
  int count = 0;
  bool inWord = false;
  for (int i = 0; i < text.length; i++) {
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

String formatSnapshotTime(DateTime dt) {
  return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
