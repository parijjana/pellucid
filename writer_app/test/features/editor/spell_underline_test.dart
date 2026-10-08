// Description: Spell-check underlines drawn by MarkdownEditingController.
// EditableText's own spell-check drawing replaced buildTextSpan wholesale,
// so a heading with a misspelling showed its raw "# " markdown.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/services/native_spell_check_service.dart';
import 'package:pellucid/features/editor/widgets/editor_paper_area.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

List<TextSpan> _flatten(InlineSpan root) {
  final List<TextSpan> out = [];
  void collect(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.isNotEmpty) out.add(span);
      span.children?.forEach(collect);
    }
  }
  collect(root);
  return out;
}

bool _isWavy(TextSpan s) => s.style?.decorationStyle == TextDecorationStyle.wavy;

void main() {
  final theme = WriterTheme.presets[0];

  Future<List<TextSpan>> spansFor(WidgetTester tester, MarkdownEditingController c) async {
    late List<TextSpan> spans;
    await tester.pumpWidget(Builder(builder: (context) {
      spans = _flatten(c.buildTextSpan(context: context, style: const TextStyle(), withComposing: false));
      return const SizedBox();
    }));
    return spans;
  }

  testWidgets('a misspelled heading keeps its markdown styling', (tester) async {
    //                                        0123456789
    final c = MarkdownEditingController(text: '# Teh Title\nplain', theme: theme);
    c.setMisspellings([const TextRange(start: 2, end: 5)]);
    final spans = await spansFor(tester, c);

    // The "# " marker is still hidden, the heading still big and bold.
    final marker = spans.firstWhere((s) => s.text == '# ');
    expect(marker.style!.color, Colors.transparent);
    final teh = spans.firstWhere((s) => s.text == 'Teh');
    expect(_isWavy(teh), isTrue);
    expect(teh.style!.fontSize, 32.0);
    expect(teh.style!.fontWeight, FontWeight.bold);
    final title = spans.firstWhere((s) => s.text == ' Title');
    expect(_isWavy(title), isFalse);
    expect(title.style!.fontSize, 32.0);
  });

  testWidgets('underline covers exactly the range, inside bold text too', (tester) async {
    //                                        0         1
    //                                        0123456789012345
    final c = MarkdownEditingController(text: 'a **bold wrod** b', theme: theme);
    c.setMisspellings([const TextRange(start: 9, end: 13)]);
    final spans = await spansFor(tester, c);

    final wavy = spans.where(_isWavy).toList();
    expect(wavy.map((s) => s.text), ['wrod']);
    expect(wavy.single.style!.fontWeight, FontWeight.bold);
    expect(spans.map((s) => s.text).join(), c.text, reason: 'no text lost or duplicated');
  });

  testWidgets('underline is thick and bright enough on a dark theme', (tester) async {
    final cyberpunk = WriterTheme.presets.firstWhere((t) => t.name == 'Cyberpunk');
    final c = MarkdownEditingController(text: 'teh', theme: cyberpunk);
    c.setMisspellings([const TextRange(start: 0, end: 3)]);
    final teh = (await spansFor(tester, c)).single;
    expect(teh.style!.decorationThickness, 2.0);
    expect(teh.style!.decorationColor!.a, 1.0);
    expect(teh.style!.decorationColor!.computeLuminance(), greaterThan(0.2));
  });

  testWidgets('underline contrasts with the page on every theme', (tester) async {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    for (final t in WriterTheme.presets) {
      final c = MarkdownEditingController(text: 'teh', theme: t);
      c.setMisspellings([const TextRange(start: 0, end: 3)]);
      final style = (await spansFor(tester, c)).single.style!;
      expect(style.decorationColor, isNotNull, reason: t.name);
      expect(contrast(style.decorationColor!, t.backgroundColor), greaterThan(3.0), reason: t.name);
    }
  });

  testWidgets('no misspellings leaves the spans untouched', (tester) async {
    final c = MarkdownEditingController(text: '# Title\nbody', theme: theme);
    expect((await spansFor(tester, c)).where(_isWavy), isEmpty);
  });

  test('ranges shift with edits before them and drop when edited', () {
    final c = MarkdownEditingController(text: 'teh cat and teh dog', theme: theme);
    c.setMisspellings([const TextRange(start: 0, end: 3), const TextRange(start: 12, end: 15)]);

    // Insert before the second word: it moves, the first stays.
    c.value = c.value.copyWith(text: 'teh big cat and teh dog');
    expect(c.misspellings, [const TextRange(start: 0, end: 3), const TextRange(start: 16, end: 19)]);

    // Fix the first word: its range goes, the other stays.
    c.value = c.value.copyWith(text: 'the big cat and teh dog');
    expect(c.misspellings, [const TextRange(start: 16, end: 19)]);
  });

  group('iOS uses the controller path, not Flutter spell check', () {

    testWidgets('EditableText spell check is off on iOS, macOS and Windows', (tester) async {
      for (final p in [TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = p;
        expect(NativeSpellCheckService.isSupported, isTrue, reason: p.name);
        final c = editableSpellCheckConfiguration(true, inTest: false);
        expect(c.spellCheckEnabled, isFalse, reason: p.name);
        expect(c.spellCheckService, isNull, reason: p.name);
      }
      // Android keeps Flutter's own checker.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(editableSpellCheckConfiguration(true, inTest: false).spellCheckEnabled, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on iOS a misspelling leaves heading and bold markers hidden', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(editableSpellCheckConfiguration(true, inTest: false).spellCheckEnabled, isFalse);
      //                                        0         1         2
      //                                        0123456789012345678901234
      final c = MarkdownEditingController(text: '# Teh Title\nsome **bolt** x', theme: theme);
      c.setMisspellings([const TextRange(start: 2, end: 5), const TextRange(start: 19, end: 23)]);
      final spans = await spansFor(tester, c);
      expect(spans.firstWhere((s) => s.text == '# ').style!.color, Colors.transparent);
      final stars = spans.where((s) => s.text == '**').toList();
      expect(stars, isNotEmpty);
      for (final s in stars) {
        expect(s.style!.color, Colors.transparent);
      }
      expect(spans.where(_isWavy).map((s) => s.text), ['Teh', 'bolt']);
      expect(spans.map((s) => s.text).join(), c.text);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
