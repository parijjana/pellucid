// Description: Backlog item 23 (speed target). Times buildTextSpan on large
// manuscripts with spell-check underlines and Codex links on. Before the
// range lookups were made binary-search, both layers rescanned every range
// for every text segment: 640 ms for 100k words in this test, 2.4 s for 200k.
// The bound is loose (debug JIT, shared CI machines); it catches a return to
// quadratic behaviour, not a few milliseconds.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/codex_index.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/markdown_controller.dart';
import 'large_document_fixture.dart';

void main() {
  for (final words in [50000, 100000, 200000]) {
  testWidgets('buildTextSpan stays linear: $words words', (tester) async {
    final text = generateManuscript(words);
    final miss = [for (final m in RegExp(r'\b(Teh|recieved)\b').allMatches(text)) TextRange(start: m.start, end: m.end)];
    Future<int> time(MarkdownEditingController c) async {
      int best = 1 << 30;
      await tester.pumpWidget(Builder(builder: (context) {
        for (int i = 0; i < 5; i++) {
          final sw = Stopwatch()..start();
          c.buildTextSpan(context: context, style: const TextStyle(), withComposing: false);
          if (sw.elapsedMicroseconds < best) best = sw.elapsedMicroseconds;
        }
        return const SizedBox();
      }));
      return best ~/ 1000;
    }
    final c = MarkdownEditingController(text: text, theme: WriterTheme.presets[0]);
    final plain = await time(c);
    c.setMisspellings(miss);
    final spell = await time(c);
    c.codexTitles = const [CodexTitle(id: 'n1', title: 'Mira'), CodexTitle(id: 'n2', title: 'Ostrava')];
    c.codexLinkingEnabled = true;
    final codex = await time(c);
    // ignore: avoid_print
    print('BENCH words=$words chars=${text.length} misspellings=${miss.length} plain=${plain}ms +spell=${spell}ms +codex=${codex}ms');
    expect(codex, lessThan(words ~/ 1000 * 2 + 50), reason: 'all layers on, $words words');
  });
  }
}
