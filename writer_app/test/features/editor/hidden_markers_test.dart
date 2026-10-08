// Description: The hidden-marker map must agree with what
// MarkdownEditingController.buildTextSpan actually hides, and the caret rules
// built on it (backlog item 24).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/hidden_markers.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';

const fixtures = <String>[
  'plain text only',
  'a **bold** b *it* c <u>under</u> d ***both*** e',
  '**<u>nested</u>** and *x **y** z*',
  '# Title with **raw** stars',
  '## Heading',
  '### Sub',
  '- bullet *it*',
  '# Title with **raw** stars',
  '1. first **bold**',
  '12. twelfth',
  '    - nested *it*',
  '        7. deep ~~x~~',
  '- [ ] open **task**',
  '    - [x] done',
  '  3. two-space nested',
  '- [ ]no space',
  '10.no space',
  '    ',
  '-not a bullet **b**',
  '#not a heading',
  '**** empty bold',
  '** lone',
  '*a**b*',
  '***',
  'emoji 😀 **b😀d**',
  '<u></u>x<u>y',
  // Slice 6 formats.
  'a ~~gone~~ b ~~~~ c',
  '> quoted **b** ~~s~~',
  '>not a quote',
  '\u2003indented paragraph',
  '\u2003\u2003**bold** indented',
  '\u2003',
  '',
];

void main() {
  final theme = WriterTheme.presets[0];

  // Offsets of the transparent spans buildTextSpan emits.
  Future<List<TextRange>> renderedHidden(WidgetTester tester, String text) async {
    final c = MarkdownEditingController(text: text, theme: theme);
    late InlineSpan root;
    await tester.pumpWidget(Builder(builder: (context) {
      root = c.buildTextSpan(context: context, style: const TextStyle(), withComposing: false);
      return const SizedBox();
    }));
    final out = <TextRange>[];
    int offset = 0;
    bool afterMarker = false;
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      final t = span.text;
      if (t != null && t.isNotEmpty) {
        // A list marker is drawn as a glyph in place of the stored marker
        // (same length): it is a marker the caret must not land inside, so it
        // counts as hidden here. The renderer tags those spans.
        final isMarker = MarkdownEditingController.isListMarkerSpan(span);
        final hidden = isMarker || span.style?.color == Colors.transparent;
        if (hidden) {
          // Invisible filler right after a list glyph belongs to the same marker.
          if (!isMarker && afterMarker && out.isNotEmpty) {
            out[out.length - 1] = TextRange(start: out.last.start, end: offset + t.length);
          } else {
            out.add(TextRange(start: offset, end: offset + t.length));
          }
        }
        afterMarker = isMarker;
        offset += t.length;
      }
      span.children?.forEach(walk);
    }

    walk(root);
    expect(offset, text.length, reason: 'span walk lost track of offsets');
    return out;
  }

  List<TextRange> scannedHidden(String text) {
    final out = <TextRange>[];
    int ls = 0;
    while (true) {
      final le = lineEndOf(text, ls);
      out.addAll(scanLine(text, ls, le).hidden);
      if (le >= text.length) break;
      ls = le + 1;
    }
    return out;
  }

  testWidgets('scan matches what buildTextSpan hides', (tester) async {
    for (final f in fixtures) {
      expect(scannedHidden(f), await renderedHidden(tester, f), reason: f);
    }
    final all = fixtures.join('\n');
    expect(scannedHidden(all), await renderedHidden(tester, all));
  });

  group('canonicalOffset', () {
    //            0123456789012
    const t = 'a**bold** end';
    test('anywhere in an opening marker rests before it (outside the run)', () {
      for (final p in [1, 2, 3]) {
        expect(canonicalOffset(t, p), 1, reason: '$p');
      }
    });
    test('anywhere in a closing marker rests before it (inside the run)', () {
      for (final p in [7, 8, 9]) {
        expect(canonicalOffset(t, p), 7, reason: '$p');
      }
    });
    test('visible positions are left alone', () {
      for (final p in [0, 4, 5, 6, 10, 13]) {
        expect(canonicalOffset(t, p), p);
      }
    });
    test('a block prefix rests after it', () {
      const h = 'x\n# Head';
      expect(canonicalOffset(h, 2), 4);
      expect(canonicalOffset(h, 3), 4);
      expect(canonicalOffset(h, 4), 4);
    });
    test('touching markers form one cluster', () {
      //          0123456789012345
      const n = '**<u>ab</u>** z';
      for (final p in [0, 1, 2, 3, 4, 5]) {
        expect(canonicalOffset(n, p), 0, reason: '$p');
      }
      for (final p in [7, 8, 9, 10, 11, 12, 13]) {
        expect(canonicalOffset(n, p), 7, reason: '$p');
      }
    });
  });

  group('arrow steps skip hidden markers', () {
    const t = 'a**bold** end';
    test('right from before a run lands after its first visible letter', () {
      expect(stepRight(t, 1), 4);
    });
    test('right from the end of a run lands after the next visible letter', () {
      expect(stepRight(t, 7), 10);
    });
    test('left back into a run start rests outside the run', () {
      expect(stepLeft(t, 4), 1);
      expect(stepLeft(t, 10), 7);
    });
    test('left from after a block prefix goes to the previous line end', () {
      const h = 'ab\n# Head';
      expect(stepLeft(h, 5), 2);
      expect(stepRight(h, 2), 5);
    });
    test('surrogate pairs move as one', () {
      const e = 'a😀b';
      expect(stepRight(e, 1), 3);
      expect(stepLeft(e, 3), 1);
    });
  });

  test('visibleText drops hidden markers and draws bullets', () {
    // Block lines render inline styles too, so their stars are hidden.
    expect(visibleText('# T\n- a **b**\n<u>u</u> *i*'), 'T\n• a b\nu i');
  });
}
