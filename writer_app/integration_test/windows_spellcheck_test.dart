// Windows: the REAL ISpellChecker channel (windows/runner/spell_check_channel.cpp).
//
//   flutter test integration_test/windows_spellcheck_test.dart -d windows ^
//     --dart-define=PELLUCID_DATA_DIR=D:\projects\.scratch\pellucid-data-spell
//
// Learn spelling writes %APPDATA%\Microsoft\Spelling (on C:), so it is skipped unless
// --dart-define=PELLUCID_TEST_ALLOW_LEARN=true is passed. Ignore is session-only and runs always.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/services/native_spell_check_service.dart';

import 'support/windows_support.dart';

const _ch = MethodChannel('com.overengineeredhobbies.pellucid/spellcheck');
const _svc = NativeSpellCheckService();

Future<List<Map<dynamic, dynamic>>> _check(String text) async {
  final r = await _ch.invokeMethod<List<dynamic>>(
      'checkSpelling', {'text': text, 'language': 'en', 'locale': 'en-US', 'withSuggestions': false});
  return [for (final m in r ?? const []) Map<dynamic, dynamic>.from(m as Map)];
}

Set<String> _flagged(String text, List<Map<dynamic, dynamic>> spans) =>
    {for (final s in spans) text.substring(s['start'] as int, s['end'] as int)};

Future<bool?> _raw(String method, String word) =>
    _ch.invokeMethod<bool>(method, {'word': word, 'language': 'en', 'locale': 'en-US'});

void main() {
  initWindowsTest();

  testWidgets('data dir override keeps app folders on D:', (tester) async {
    await expectDataOnD();
  });

  testWidgets('flags a misspelling and not correct words', (tester) async {
    const t = 'The quick brown fox jumpd over the lazy dog.';
    final spans = await _check(t);
    final bad = _flagged(t, spans);
    // ignore: avoid_print
    print('EVID|spell|flagged=$bad');
    expect(bad, contains('jumpd'));
    expect(bad, isNot(contains('quick')));
    expect(bad.length, 1);
  });

  testWidgets('apostrophe words and accented words', (tester) async {
    const t = "It's don't can't naïve café résumé wrongg.";
    final bad = _flagged(t, await _check(t));
    // ignore: avoid_print
    print('EVID|spell|apostrophe/accent flagged=$bad');
    expect(bad, contains('wrongg'));
    for (final w in ["It's", "don't", "can't"]) {
      expect(bad, isNot(contains(w)), reason: '$w is a valid contraction');
    }
    for (final w in ['naïve', 'café', 'résumé']) {
      expect(bad, isNot(contains(w)), reason: '$w');
    }
    // Offsets are UTF-16 code units: a flagged word after accents must still line up.
    const t2 = 'café qwertyx';
    expect(_flagged(t2, await _check(t2)), {'qwertyx'});
  });

  testWidgets('Ignore (session only) round trip', (tester) async {
    const word = 'zxqvbnmign';
    const t = 'Look at $word here.';
    expect(_flagged(t, await _check(t)), contains(word), reason: 'flagged before Ignore');
    await _svc.ignoreWord(word);
    expect(_flagged(t, await _check(t)), isNot(contains(word)), reason: 'not flagged after Ignore');
  });

  testWidgets('native word guard rejects non-words (nothing is written)', (tester) async {
    final cases = <String, String>{
      'empty': '',
      'space inside': 'two words',
      'leading space': ' word',
      'tab': 'a\tb',
      'newline': 'a\nb',
      'NUL': 'a\u0000b',
      'control U+0007': 'a\u0007b',
      'C1 control U+0085': 'a\u0085b',
      '65 code points': 'a' * 65,
    };
    for (final e in cases.entries) {
      // Only words the guard must reject are ever sent to learnWord, so nothing reaches the user dictionary.
      for (final m in ['ignoreWord', 'learnWord']) {
        expect(await _raw(m, e.value), isFalse, reason: '$m rejects ${e.key}');
      }
    }
    expect(await _raw('ignoreWord', 'a' * 64), isTrue, reason: '64 code points passes the guard');
    // Surrogate pairs count as one code point each: 65 of them are rejected.
    expect(await _raw('ignoreWord', '\u{1F600}' * 65), isFalse);
    expect(await _ch.invokeMethod<bool>('ignoreWord', <String, dynamic>{}), isFalse, reason: 'missing args');
  });

  testWidgets('suggestions appear for a misspelling (native suggest)', (tester) async {
    final viaChannel = List<String>.from(await _ch.invokeMethod<List<dynamic>>(
            'suggest', {'word': 'jumpd', 'language': 'en', 'locale': 'en-US'}) ??
        []);
    final viaService = await _svc.suggestionsFor('jumpd');
    // ignore: avoid_print
    print('EVID|spell|suggest("jumpd"): channel=$viaChannel service=$viaService');
    expect(viaChannel, isNotEmpty);
    expect(viaChannel.length, lessThanOrEqualTo(5));
    expect(viaChannel, contains('jumped'));
    expect(viaService, viaChannel);
    // The guard applies to suggest too.
    expect(await _ch.invokeMethod<List<dynamic>>('suggest', {'word': 'two words', 'language': 'en'}), isEmpty);
  });

  testWidgets('Learn spelling round trip (needs PELLUCID_TEST_ALLOW_LEARN=true)', (tester) async {
    const word = 'Zzpellucidtestword';
    const t = 'See $word now.';
    expect(_flagged(t, await _check(t)), contains(word));
    expect(await _raw('learnWord', word), isTrue);
    expect(_flagged(t, await _check(t)), isNot(contains(word)));
    // ignore: avoid_print
    print('EVID|spell|LEARNED $word -> remove from %APPDATA%\\Microsoft\\Spelling\\en-US\\default.dic');
  }, skip: !kAllowLearn);
}
