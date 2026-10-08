import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/long_document/windowed_paper_area.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

void main() {
  tearDown(() => debugForceWindowedEditor = false);

  test('on by default for long documents; the flag turns it off', () {
    expect(kWindowedEditorFlag, isTrue, reason: 'default build (no dart-define)');
    expect(kWindowedEditorMinWords, 15000);
    final c = MarkdownEditingController(text: 'x' * 200000, theme: WriterTheme.presets[0]);
    expect(useWindowedEditor(c), kWindowedEditorFlag);
  });

  test('long documents switch on; a document stays on until it shrinks well below', () {
    debugForceWindowedEditor = true;
    final on = kWindowedEditorMinWords * 6;
    final c = MarkdownEditingController(text: 'x' * (on - 1), theme: WriterTheme.presets[0]);
    expect(useWindowedEditor(c), isFalse);
    c.text = 'x' * on;
    expect(useWindowedEditor(c), isTrue);
    c.text = 'x' * (on - 100); // a little shorter: stays on
    expect(useWindowedEditor(c), isTrue);
    c.text = 'x' * (on ~/ 2);
    expect(useWindowedEditor(c), isFalse);
    // Plain controllers (other fields) never switch.
    expect(useWindowedEditor(TextEditingController(text: 'x' * on)), isFalse);
  });
}
