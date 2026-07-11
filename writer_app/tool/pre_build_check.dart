import 'dart:io';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    print('Error: lib directory not found. Please run this from the writer_app directory.');
    exit(1);
  }

  bool hasErrors = false;

  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    // Skip this tool directory itself
    if (file.path.contains('tool/')) continue;

    final content = file.readAsStringSync();
    if (content.contains('WindowCaption')) {
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('WindowCaption')) {
          // Check if the current line or adjacent lines (up to 2 lines before) contain a platform gate
          bool hasGuard = false;
          final start = (i - 2).clamp(0, lines.length - 1);
          final end = i;
          for (int j = start; j <= end; j++) {
            final checkLine = lines[j];
            if (checkLine.contains('Platform.isWindows') ||
                checkLine.contains('Platform.isLinux') ||
                checkLine.contains('!Platform.isMacOS') ||
                checkLine.contains('isWindows') ||
                checkLine.contains('isMac')) {
              hasGuard = true;
              break;
            }
          }

          if (!hasGuard) {
            print('ERROR: WindowCaption used without platform guard in ${file.path}:${i + 1}');
            print('  Line: ${line.trim()}');
            hasErrors = true;
          }
        }
      }
    }
  }

  if (hasErrors) {
    print('\nPre-build validation FAILED: Found platform-dependent controls without guards.');
    exit(1);
  } else {
    print('Pre-build validation PASSED: Platform controls are safely guarded.');
  }
}
