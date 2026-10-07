// Description: Learn spelling / Ignore only ever send one word to the OS
// (security pass, slice 12 finding 3). The native handlers in
// MainFlutterWindow.swift and spell_check_channel.cpp apply the same rule.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/services/native_spell_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.overengineeredhobbies.pellucid/spellcheck');

  group('isLearnableWord', () {
    test('accepts ordinary words, apostrophes, hyphens, accents, emoji', () {
      for (final w in ['Ravenscar', "O'Neil", 'well-known', 'café', 'naïve', 'x', '😀']) {
        expect(NativeSpellCheckService.isLearnableWord(w), isTrue, reason: w);
      }
      expect(NativeSpellCheckService.isLearnableWord('a' * 64), isTrue);
      expect(NativeSpellCheckService.isLearnableWord('😀' * 64), isTrue, reason: '64 code points');
    });

    test('rejects empty, too long, whitespace and control characters', () {
      for (final w in [
        '',
        'a' * 65,
        '😀' * 65,
        'two words',
        ' lead',
        'trail ',
        'tab\there',
        'line\nbreak',
        'nbsp x',
        'nul\u0000x',
        'esc\u001bx',
        'ls x',
      ]) {
        expect(NativeSpellCheckService.isLearnableWord(w), isFalse, reason: w.codeUnits.toString());
      }
    });
  });

  group('learnWord / ignoreWord', () {
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call);
        return true;
      });
    });
    tearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('a valid word reaches the native side', () async {
      if (!NativeSpellCheckService.isSupported) return;
      const s = NativeSpellCheckService();
      await s.learnWord('Ravenscar');
      await s.ignoreWord('Mira');
      expect(calls.map((c) => c.method), ['learnWord', 'ignoreWord']);
      expect((calls.first.arguments as Map)['word'], 'Ravenscar');
    });

    test('anything else never reaches the native side', () async {
      if (!NativeSpellCheckService.isSupported) return;
      const s = NativeSpellCheckService();
      await s.learnWord('two words');
      await s.learnWord('a' * 65);
      await s.ignoreWord('x\ny');
      await s.ignoreWord('');
      expect(calls, isEmpty);
    });
  });
}
