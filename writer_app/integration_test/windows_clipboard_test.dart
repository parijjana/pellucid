// Windows: rich copy and paste through the REAL native clipboard channel (clipboard_channel.cpp).
//
//   flutter test integration_test/windows_clipboard_test.dart -d windows ^
//     --dart-define=PELLUCID_DATA_DIR=D:\projects\.scratch\pellucid-data-clipboard
//
// OVERWRITES THE SYSTEM CLIPBOARD while it runs. The clipboard's text is saved first and put back at the end
// (other formats are not restored). Raw formats are read with dart:ffi (support/win_clipboard.dart).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/rich_clipboard.dart';

import 'support/harness.dart';
import 'support/win_clipboard.dart' as cb;
import 'support/windows_support.dart';

const String _doc = '# Chapter One\n\nSome **bold** words and plain ones.\n\n- first bullet\n- second bullet\n';

String? _savedText;

Future<void> _settle(WidgetTester tester) async {
  // The copy action is async and the platform call completes on the platform thread.
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  initWindowsTest();

  setUpAll(() {
    RichClipboard.debugSupported = true; // FLUTTER_TEST would otherwise switch the native path off
    _savedText = cb.saveClipboardText();
  });
  tearDownAll(() {
    cb.restoreText(_savedText);
    // ignore: avoid_print
    print('EVID|clipboard|restored clipboard text (${_savedText?.length ?? 'none'} chars)');
  });

  testWidgets('data dir override keeps app folders on D:', (tester) async {
    await expectDataOnD();
  });

  testWidgets('native copy from the editor: formats, CF_HTML offsets, fragment tags, no markdown in plain text',
      (tester) async {
    final rig = await mount(tester, text: _doc, realClipboard: true);
    cb.clearClipboard();
    await rig.placeCaret(0);
    rig.doc.selection = TextSelection(baseOffset: 0, extentOffset: _doc.length);
    await rig.pump(4);
    await rig.key(LogicalKeyboardKey.keyC, meta: true); // meta maps to Ctrl on Windows
    await _settle(tester);

    final formats = cb.listFormats();
    // ignore: avoid_print
    print('EVID|clipboard|formats after copy: $formats');
    expect(formats.values, contains('HTML Format'));
    expect(formats.keys, contains(cb.cfUnicodeText));
    expect(formats.values, contains('com.overengineeredhobbies.pellucid.markdown'));

    final htmlFmt = formats.entries.firstWhere((e) => e.value == 'HTML Format').key;
    final raw = cb.readFormat(htmlFmt)!;
    final h = cb.parseCfHtml(raw);
    // ignore: avoid_print
    print('EVID|clipboard|CF_HTML header: ${h.header.replaceAll('\r\n', ' | ')}\nEVID|clipboard|fragment: ${h.fragment}');
    expect(h.problems, isEmpty, reason: 'CF_HTML header validates against the bytes: ${h.problems}');
    expect(h.fragment, contains('<h1>'));
    expect(h.fragment, contains('Chapter One'));
    expect(h.fragment, anyOf(contains('<b>bold</b>'), contains('<strong>bold</strong>')));
    expect(h.fragment, contains('<li>first bullet</li>'));
    expect(h.fragment, contains('<ul>'));
    expect(h.fragment, isNot(contains('**')));

    final plain = cb.readUnicodeText()!;
    // ignore: avoid_print
    print('EVID|clipboard|CF_UNICODETEXT: ${jsonEncode(plain)}');
    expect(plain, isNot(contains('**')));
    expect(plain, isNot(contains('#')), reason: 'heading marker is gone from plain text');
    expect(plain, contains('Chapter One'));
    expect(plain, contains('bold'));
    expect(plain.contains('\r\n'), isTrue, reason: 'Windows line endings');

    final md = cb.readFormat(formats.entries.firstWhere((e) => e.value.endsWith('.markdown')).key)!;
    expect(utf8.decode(cb.untilNul(md)), _doc, reason: 'private markdown format holds the exact source');
    await rig.dispose();
  });

  testWidgets('copy then paste inside Pellucid keeps formatting (private markdown format)', (tester) async {
    final rig = await mount(tester, text: '$_doc\nEND', realClipboard: true);
    cb.clearClipboard();
    await rig.placeCaret(0);
    rig.doc.selection = TextSelection(baseOffset: 0, extentOffset: _doc.length);
    await rig.pump(4);
    await rig.key(LogicalKeyboardKey.keyC, meta: true);
    await _settle(tester);
    final end = rig.text.length;
    await rig.placeCaret(end);
    await rig.key(LogicalKeyboardKey.keyV, meta: true);
    await _settle(tester);
    expect(rig.text, '$_doc\nEND$_doc');
    await rig.dispose();
  });

  Future<Rig> pasteHtml(WidgetTester tester, cb.CfHtml? unused, Uint8List block, String plain) async {
    final rig = await mount(tester, text: 'Start: ', realClipboard: true);
    cb.setFormats({
      cb.registerFormat('HTML Format'): block,
      cb.cfUnicodeText: cb.utf16Bytes(plain),
    });
    await rig.placeCaret(rig.text.length);
    await rig.key(LogicalKeyboardKey.keyV, meta: true);
    await _settle(tester);
    return rig;
  }

  testWidgets('paste Word-style CF_HTML keeps heading, bold, bullets', (tester) async {
    // Shaped like Word's clipboard HTML: namespaces, mso classes, conditional comments, <o:p>.
    const prefix = '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" '
        'xmlns="http://www.w3.org/TR/REC-html40">\r\n<head><meta http-equiv=Content-Type content="text/html; charset=utf-8">'
        '<style><!-- p.MsoNormal {margin:0in;font-size:11.0pt;} --></style></head>\r\n<body lang=EN-US>\r\n<!--StartFragment-->';
    const fragment = '<h1 style="margin-top:12pt"><span style="font-size:16.0pt">Word Title</span><o:p></o:p></h1>'
        '<p class=MsoNormal>Plain then <b><span style="font-weight:bold">strong words</span></b> end.<o:p></o:p></p>'
        '<ul type=disc><li class=MsoListParagraph>alpha item</li><li class=MsoListParagraph>beta item</li></ul>';
    const suffix = '<!--EndFragment-->\r\n</body>\r\n</html>';
    final block = cb.buildCfHtml(prefix, fragment, suffix);
    expect(cb.parseCfHtml(block).problems, isEmpty, reason: 'the test fixture itself is valid CF_HTML');
    final rig = await pasteHtml(tester, null, block, 'Word Title\r\nPlain then strong words end.\r\nalpha item\r\nbeta item');
    // ignore: avoid_print
    print('EVID|clipboard|Word paste result: ${jsonEncode(rig.text)}');
    expect(rig.text, contains('# Word Title'));
    expect(rig.text, contains('**strong words**'));
    expect(rig.text, contains('- alpha item'));
    expect(rig.text, contains('- beta item'));
    expect(rig.text, isNot(contains('<')), reason: 'no raw tags');
    expect(rig.text, isNot(contains('o:p')));
    await rig.dispose();
  });

  testWidgets('paste browser-style (Chrome) CF_HTML keeps bold, italic, heading, list', (tester) async {
    const prefix = '<html><body>\r\n<!--StartFragment-->';
    const fragment = '<h2 style="color: rgb(0, 0, 0);">Browser Head</h2><p><strong>Strong</strong> and <em>emphasis</em> and '
        '<a href="https://example.com">a link</a>.</p><ol><li>one</li><li>two</li></ol>';
    const suffix = '<!--EndFragment-->\r\n</body>\r\n</html>';
    final block = cb.buildCfHtml(prefix, fragment, suffix, extraHeader: 'SourceURL:https://example.com/page\r\n');
    expect(cb.parseCfHtml(block).problems, isEmpty);
    final rig = await pasteHtml(tester, null, block, 'Browser Head\r\nStrong and emphasis and a link.\r\none\r\ntwo');
    // ignore: avoid_print
    print('EVID|clipboard|browser paste result: ${jsonEncode(rig.text)}');
    expect(rig.text, contains('## Browser Head'));
    expect(rig.text, contains('**Strong**'));
    expect(rig.text, contains('*emphasis*'));
    expect(rig.text, contains('1. one'));
    expect(rig.text, contains('a link'));
    await rig.dispose();
  });

  testWidgets('non-ASCII fragment survives byte-offset arithmetic (UTF-8)', (tester) async {
    const prefix = '<html><body><!--StartFragment-->';
    const fragment = '<p>Caf\u00e9 <b>na\u00efve \u2014 \u65e5\u672c</b></p>';
    const suffix = '<!--EndFragment--></body></html>';
    final block = cb.buildCfHtml(prefix, fragment, suffix);
    final rig = await pasteHtml(tester, null, block, 'Caf\u00e9 na\u00efve \u2014 \u65e5\u672c');
    // ignore: avoid_print
    print('EVID|clipboard|non-ASCII paste result: ${jsonEncode(rig.text)}');
    expect(rig.text, contains('Caf\u00e9'));
    expect(rig.text, contains('**na\u00efve \u2014 \u65e5\u672c**'));
    // And our own copy of non-ASCII text produces valid offsets.
    rig.doc.text = '**Caf\u00e9 \u65e5\u672c** x';
    await rig.pump(2);
    rig.doc.selection = TextSelection(baseOffset: 0, extentOffset: rig.text.length);
    cb.clearClipboard();
    await rig.key(LogicalKeyboardKey.keyC, meta: true);
    await _settle(tester);
    final htmlFmt = cb.listFormats().entries.firstWhere((e) => e.value == 'HTML Format').key;
    final h = cb.parseCfHtml(cb.readFormat(htmlFmt)!);
    expect(h.problems, isEmpty, reason: '${h.problems}');
    expect(h.fragment, contains('Caf\u00e9'));
    await rig.dispose();
  });
}
