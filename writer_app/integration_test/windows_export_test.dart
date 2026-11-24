// Windows: produce PDF and EPUB from a fixture manuscript with the real ExportService, written to D:.
// Validate the output with tool/windows/validate_exports.py (zip layout, OPF/nav, PDF parse).
//
//   flutter test integration_test/windows_export_test.dart -d windows ^
//     --dart-define=PELLUCID_DATA_DIR=D:\projects\.scratch\pellucid-data-export ^
//     --dart-define=PELLUCID_EXPORT_OUT=D:\projects\.scratch\export-out
//   python -I tool\windows\validate_exports.py D:\projects\.scratch\export-out

import 'dart:convert' show LineSplitter;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/services/export_service.dart';

import 'support/fixture.dart';
import 'support/windows_support.dart';

const String _out = String.fromEnvironment('PELLUCID_EXPORT_OUT', defaultValue: r'D:\projects\.scratch\export-out');

const String _small = '''# Chapter One: The Beginning

It was a bright cold day in April, and the **clocks** were striking thirteen. She said, \u201cWhat is this?\u201d and *he* laughed \u2014 once.

## A Section

- first bullet
- second bullet with **bold**
- third

1. step one
2. step two

> A block quote that goes on for a little while.

### Subheading

Caf\u00e9 na\u00efve ~~struck~~ text with `code` and a [link](https://example.com).

# Chapter Two & <More>

Plain closing paragraph with an ampersand & angle <brackets> that must be escaped.
''';

void main() {
  initWindowsTest();
  final svc = ExportService();

  setUpAll(() => Directory(_out).createSync(recursive: true));

  testWidgets('export output stays on D:', (tester) async {
    expect(_out.toUpperCase().startsWith(r'D:\'), isTrue);
    await expectDataOnD();
  });

  testWidgets('small fixture: PDF and EPUB', (tester) async {
    await svc.exportToPdf(_small, '$_out\\small.pdf');
    await svc.exportToEpub(markdown: _small, title: 'Small Fixture', author: 'Test Author', filePath: '$_out\\small.epub');
    expect(File('$_out\\small.pdf').lengthSync(), greaterThan(1000));
    expect(File('$_out\\small.epub').lengthSync(), greaterThan(1000));
  });

  testWidgets('long fixture (about 30k words): PDF and EPUB, timed', (tester) async {
    final text = buildFixture(targetWords: 30000).text;
    final sw = Stopwatch()..start();
    await svc.exportToPdf(text, '$_out\\long.pdf');
    final pdfMs = sw.elapsedMilliseconds;
    sw.reset();
    await svc.exportToEpub(markdown: text, title: 'Long Fixture', author: 'Test Author', filePath: '$_out\\long.epub');
    // ignore: avoid_print
    print('EVID|export|30k words: pdf ${pdfMs} ms (${File('$_out\\long.pdf').lengthSync()} bytes), '
        'epub ${sw.elapsedMilliseconds} ms (${File('$_out\\long.epub').lengthSync()} bytes)');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('validate_exports.py passes on every export (well-formed XHTML, one h1 per chapter, PDF parses)',
      (tester) async {
    // Needs the venv with pypdf: D:\projects\.scratch\pdfval-venv (see tool/windows/validate_exports.py).
    final r = await tester.runAsync(() => Process.run(
        r'D:\projects\.scratch\pdfval-venv\Scripts\python.exe', ['-I', 'tool/windows/validate_exports.py', _out]));
    // ignore: avoid_print
    print('EVID|export|validator: ${LineSplitter.split(r!.stdout as String).where((l) => l.contains('FAIL') || l.contains('RESULT')).take(8).join(' | ')}');
    expect(r.exitCode, 0, reason: r.stdout.toString());
  }, timeout: const Timeout(Duration(minutes: 2)));
}
