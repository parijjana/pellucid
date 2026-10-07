// Item 15: strikethrough (`~~text~~`) and block quotes (`> `).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/formatting_toolbar.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

void main() {
  final theme = WriterTheme.presets.first;

  MarkdownEditingController make(String text, TextSelection sel) =>
      MarkdownEditingController(text: text, theme: theme)..selection = sel;

  group('strikethrough toggle', () {
    test('wraps the selection in ~~ and removes it again', () {
      final c = make('Hello world', const TextSelection(baseOffset: 6, extentOffset: 11))
        ..toggleFormat('~~');
      expect(c.text, 'Hello ~~world~~');
      c.toggleFormat('~~');
      expect(c.text, 'Hello world');
    });

    // Same rule as bold/italic (item 24): a bare caret opens an empty,
    // hidden run so the next keystroke is struck.
    test('collapsed caret opens a hidden empty run', () {
      final c = make('Hello', const TextSelection.collapsed(offset: 2))..toggleFormat('~~');
      expect(c.text, 'He~~~~llo');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });
  });

  group('block quote toggle', () {
    test('adds, removes and replaces other line styles', () {
      final c = make('Hello', const TextSelection.collapsed(offset: 2))..toggleFormat('> ');
      expect(c.text, '> Hello');
      c.toggleFormat('> ');
      expect(c.text, 'Hello');
      c.toggleFormat('- ');
      c.toggleFormat('> ');
      expect(c.text, '> Hello');
      c.toggleFormat('body');
      expect(c.text, 'Hello');
    });
  });

  testWidgets('strikethrough renders struck text with hidden markers', (tester) async {
    final c = make('a ~~gone~~ b', const TextSelection.collapsed(offset: 0));
    late TextSpan span;
    await tester.pumpWidget(Builder(builder: (ctx) {
      span = c.buildTextSpan(context: ctx, withComposing: false);
      return const SizedBox();
    }));
    final l = <TextSpan>[];
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) l.add(s);
      return true;
    });
    final marker = l.where((s) => s.text == '~~').toList();
    expect(marker.length, 2);
    expect(marker.every((s) => s.style!.color == Colors.transparent), isTrue);
    final struck = l.singleWhere((s) => s.text == 'gone');
    expect(struck.style!.decoration!.contains(TextDecoration.lineThrough), isTrue);
    expect(l.map((s) => s.text).join(), 'a ~~gone~~ b');
  });

  testWidgets('block quote renders italic with hidden marker and keeps offsets', (tester) async {
    final c = make('> **bold** quote', const TextSelection.collapsed(offset: 0));
    late TextSpan span;
    await tester.pumpWidget(Builder(builder: (ctx) {
      span = c.buildTextSpan(context: ctx, withComposing: false);
      return const SizedBox();
    }));
    final l = <TextSpan>[];
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) l.add(s);
      return true;
    });
    expect(l.first.text, '> ');
    expect(l.first.style!.color, Colors.transparent);
    final bold = l.singleWhere((s) => s.text == 'bold');
    expect(bold.style!.fontStyle, FontStyle.italic);
    expect(bold.style!.fontWeight, FontWeight.bold);
    expect(l.map((s) => s.text).join(), '> **bold** quote');
  });

  testWidgets('toolbar has QUOTE and STRIKE buttons', (tester) async {
    final applied = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FormattingToolbar(theme: theme, onApplyFormat: applied.add)),
    ));
    await tester.tap(find.text('QUOTE'));
    await tester.tap(find.text('STRIKE'));
    expect(applied, ['> ', '~~']);
  });
}
