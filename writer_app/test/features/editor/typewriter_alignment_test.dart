// PEL-10 / MAC-4: the typewriter target must put the caret line at the viewport
// centre in the NORMAL (non-windowed) editor. Measures the real caret against
// typewriterTargetOffset.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/editor_font.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/editor_paper_area.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'package:pellucid/features/editor/widgets/typewriter_scroll.dart';

class _MockProvider extends Mock implements EditorProvider {}

void main() {
  Future<double> measure(WidgetTester tester, String text, int caret,
      {EditorFont font = EditorFont.defaultFont, double zoom = 1.0, bool typewriter = true}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = _MockProvider();
    when(() => provider.zoomLevel).thenReturn(zoom);
    when(() => provider.pageWidth).thenReturn(800.0);
    when(() => provider.horizontalPosition).thenReturn(0.5);
    when(() => provider.documentLoadFailed).thenReturn(false);
    final controller = MarkdownEditingController(
        text: text, theme: WriterTheme.presets.first);
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<EditorProvider>.value(
          value: provider,
          child: EditorPaperArea(
            theme: WriterTheme.presets.first,
            provider: provider,
            controller: controller,
            scrollController: scroll,
            focusNode: FocusNode(),
            codexEnabled: false,
            codexIndex: CodexIndex(),
            notes: const [],
            onOpenNote: (_) {},
            spellCheckEnabled: false,
            editorFont: font,
            typewriterEnabled: typewriter,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    controller.selection = TextSelection.collapsed(offset: caret);
    await tester.pump();

    final viewport = scroll.position.viewportDimension;
    final target = typewriterTargetOffset(
      text: text,
      caretOffset: caret,
      zoomLevel: zoom,
      pageWidth: 800,
      viewportHeight: viewport,
      font: font,
    ).clamp(0.0, scroll.position.maxScrollExtent);
    scroll.jumpTo(target);
    await tester.pump();

    final editable = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    // ignore: avoid_print
    print('editable top inside content: ${editable.localToGlobal(Offset.zero).dy - tester.getRect(find.byType(SingleChildScrollView)).top + scroll.offset}');
    final r = editable.getLocalRectForCaret(TextPosition(offset: caret));
    final globalY = editable.localToGlobal(r.center).dy;
    final scrollBox = tester.getRect(find.byType(SingleChildScrollView));
    final centre = scrollBox.top + viewport / 2;
    return globalY - centre; // 0 when perfectly centred
  }

  final plain = List.generate(80, (i) => 'Line $i of some prose that is long enough to be a paragraph.').join('\n');

  testWidgets('plain text: caret sits at the viewport centre', (tester) async {
    final off = await measure(tester, plain, plain.indexOf('Line 40 '));
    // ignore: avoid_print
    print('PLAIN offset from centre: $off');
    expect(off.abs(), lessThan(2));
  });

  testWidgets('last line of the document reaches the centre (MAC-4)', (tester) async {
    final off = await measure(tester, plain, plain.length);
    // ignore: avoid_print
    print('END-OF-DOC offset from centre: $off');
    expect(off.abs(), lessThan(2));
  });

  testWidgets('without typewriter slack the last line cannot centre (the bug)', (tester) async {
    final off = await measure(tester, plain, plain.length, typewriter: false);
    expect(off.abs(), greaterThan(100));
  });

  testWidgets('markdown with headings, bold, blank lines', (tester) async {
    final md = List.generate(40, (i) => '# Heading $i\n\nSome **bold** and *italic* text number $i.\n').join('\n');
    final off = await measure(tester, md, md.indexOf('Heading 30') + 12);
    // ignore: avoid_print
    print('MARKDOWN offset from centre: $off');
    expect(off.abs(), lessThan(2));
  });
}
