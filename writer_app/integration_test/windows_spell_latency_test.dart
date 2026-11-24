// Measures spell re-check latency: time from the last edit to the new misspelling being flagged, per
// document size (3 runs each). Prints EVID|latency lines; asserts only that every run completes.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pellucid/core/data_dir_override.dart';

import 'support/harness.dart';

String _textOfWords(int words) {
  final paras = fixture.text.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('-')).toList();
  final b = StringBuffer();
  int n = 0, i = 0;
  while (n < words) {
    final p = paras[i++ % paras.length];
    b.write('$p\n\n');
    n += p.split(RegExp(r'\s+')).length;
  }
  return b.toString();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  if (Platform.isWindows) applyDataDirOverride();

  for (final words in const [5000, 10000, 30000, 60000, 127000]) {
    testWidgets('spell re-check latency at $words words', (tester) async {
      final text = _textOfWords(words);
      final rig = await mount(tester, text: text, spell: true);
      final doc = rig.doc;
      final sw = Stopwatch()..start();
      // Initial whole-document check.
      int maxStall = 0;
      Future<int> waitFlag(bool Function() flagged, int limitMs) async {
        final t = Stopwatch()..start();
        int last = t.elapsedMilliseconds;
        while (!flagged() && t.elapsedMilliseconds < limitMs) {
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final now = t.elapsedMilliseconds;
          if (now - last > maxStall) maxStall = now - last;
          last = now;
        }
        return t.elapsedMilliseconds;
      }

      final initial = await waitFlag(() => doc.misspellings.isNotEmpty, 240000);
      // Let the first check settle (a second may follow once the window is laid out).
      await rig.wait(const Duration(milliseconds: 4000));
      maxStall = 0;
      final results = <int>[];
      final stalls = <int>[];
      for (final w in const ['recieve', 'definately', 'wierd']) {
        final base = doc.text;
        final start = base.length + 1;
        doc.value = TextEditingValue(text: '$base $w', selection: TextSelection.collapsed(offset: base.length + 1 + w.length));
        maxStall = 0;
        final ms = await waitFlag(() => doc.misspellings.any((m) => m.start == start), 180000);
        results.add(ms);
        stalls.add(maxStall);
        expect(doc.misspellings.any((m) => m.start == start), isTrue, reason: '$w flagged');
        await rig.wait(const Duration(milliseconds: 1500));
      }
      final sorted = [...results]..sort();
      // ignore: avoid_print
      print('EVID|latency|words=${rig.doc.text.split(RegExp(r"\s+")).length} chars=${doc.text.length} '
          'initialCheckMs=$initial runsMs=$results median=${sorted[1]} max=${sorted[2]} maxLoopStallMs=$stalls '
          'misspellings=${doc.misspellings.length} mode=${const bool.fromEnvironment("dart.vm.product") ? "release" : (const bool.fromEnvironment("dart.vm.profile") ? "profile" : "debug")}');
      await rig.dispose();
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
