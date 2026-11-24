// Measures spell re-check latency: time from the last edit to the new misspelling being flagged, per
// document size (3 runs each). Prints EVID|latency lines; asserts only that every run completes.
import 'dart:async';
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
    // Unique paragraphs (a real manuscript does not repeat): the per-paragraph cache must not flatter the numbers.
    final p = '${i + 1}. ${paras[i++ % paras.length]}';
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
      // Event-loop gap monitor from before the mount: the longest time the app did not run (UI frozen).
      int gapMax = 0;
      final gapClock = Stopwatch()..start();
      int gapLast = 0;
      final gapTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final n = gapClock.elapsedMilliseconds;
        if (n - gapLast > gapMax) gapMax = n - gapLast;
        gapLast = n;
      });
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
      // First full check: wait until the number of flagged words stops changing for 5 s.
      int lastCount = -1;
      final settle = Stopwatch()..start();
      int lastChangeMs = 0;
      while (settle.elapsedMilliseconds - lastChangeMs < 5000 && settle.elapsedMilliseconds < 200000) {
        await waitFlag(() => false, 250);
        if (doc.misspellings.length != lastCount) {
          lastCount = doc.misspellings.length;
          lastChangeMs = settle.elapsedMilliseconds;
        }
      }
      final firstCheckMs = initial + lastChangeMs;
      final firstCheckStall = maxStall;
      final mountAndFirstCheckGap = gapMax;
      gapMax = 0;
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
          'firstFlagMs=$initial firstFullCheckMs~$firstCheckMs firstCheckMaxStallMs=$firstCheckStall mountPlusFirstCheckMaxGapMs=$mountAndFirstCheckGap runsMs=$results median=${sorted[1]} max=${sorted[2]} maxLoopStallMs=$stalls '
          'misspellings=${doc.misspellings.length} mode=${const bool.fromEnvironment("dart.vm.product") ? "release" : (const bool.fromEnvironment("dart.vm.profile") ? "profile" : "debug")}');
      gapTimer.cancel();
      await rig.dispose();
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
