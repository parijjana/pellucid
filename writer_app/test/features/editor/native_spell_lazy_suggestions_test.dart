// The whole-manuscript spell check must not ask for suggestions: NSSpellChecker
// guesses cost ~15 ms a word, which froze the UI thread for ~20 s on a 127k-word
// manuscript. Suggestions are fetched for the one word the writer right-clicks.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/services/native_spell_check_service.dart';

void main() {
  testWidgets('checkSpelling skips suggestions; suggestionsFor asks per word', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('com.overengineeredhobbies.pellucid/spellcheck');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'checkSpelling') {
        return [
          {'start': 0, 'end': 4, 'suggestions': <String>[]}
        ];
      }
      return ['Darcy'];
    });
    const service = NativeSpellCheckService();
    final spans = await service.fetchSpellCheckSuggestions(const Locale('en', 'US'), 'Darci said');
    expect(spans, hasLength(1));
    expect((calls.single.arguments as Map)['withSuggestions'], isFalse);
    expect(await service.suggestionsFor('Darci'), ['Darcy']);
    expect(calls.last.method, 'suggest');
    debugDefaultTargetPlatformOverride = null;
  });
}
