import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Spell checking through the OS spell checker: NSSpellChecker on macOS
/// (MainFlutterWindow.swift), UITextChecker on iOS (ios/Runner/AppDelegate.swift)
/// and ISpellChecker on Windows (windows/runner/spell_check_channel.cpp).
///
/// Not handed to EditableText: its built-in spell-check drawing replaces the
/// editor's markdown styling. EditorPaperArea drives this service itself and
/// MarkdownEditingController draws the underlines.
///
/// [EditorSpellService] adds the two write actions of the editor context menu.
abstract class EditorSpellService implements SpellCheckService {
  /// Adds [word] to the user dictionary (permanent).
  Future<void> learnWord(String word, {Locale? locale});

  /// Stops flagging [word] for this session.
  Future<void> ignoreWord(String word, {Locale? locale});
}

class NativeSpellCheckService implements EditorSpellService {
  const NativeSpellCheckService();

  /// Platforms with a native handler for [_channel].
  static bool get isSupported => !kIsWeb && isSupportedOn(defaultTargetPlatform);

  /// Which platforms answer [_channel] natively. iOS is here because Flutter's
  /// own spell-check drawing there bypasses MarkdownEditingController.
  static bool isSupportedOn(TargetPlatform p) =>
      p == TargetPlatform.macOS || p == TargetPlatform.windows || p == TargetPlatform.iOS;

  static const _channel = MethodChannel('com.overengineeredhobbies.pellucid/spellcheck');

  @override
  Future<List<SuggestionSpan>> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (!isSupported) return [];

    try {
      final List<dynamic>? result = await _channel.invokeMethod(
        'checkSpelling',
        {
          'text': text,
          'language': locale.languageCode,
          // Windows spell checkers are keyed by full tags ("en-GB").
          'locale': locale.toLanguageTag(),
        },
      );

      if (result == null) return [];

      return result.map((item) {
        final map = Map<String, dynamic>.from(item);
        final start = map['start'] as int;
        final end = map['end'] as int;
        final suggestions = List<String>.from(map['suggestions'] as List);
        
        return SuggestionSpan(
          TextRange(start: start, end: end),
          suggestions,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> learnWord(String word, {Locale? locale}) => _wordAction('learnWord', word, locale);

  @override
  Future<void> ignoreWord(String word, {Locale? locale}) => _wordAction('ignoreWord', word, locale);

  /// Longest word Learn spelling / Ignore will pass to the OS (code points).
  static const int maxWordLength = 64;

  static final RegExp _blankOrControl = RegExp(r'[\s\p{Cc}]', unicode: true);

  /// Learn/Ignore take one word only: 1–[maxWordLength] code points, no
  /// whitespace or control characters. The native handlers apply the same
  /// rule, so a bad call from anywhere cannot write junk into the user's
  /// system-wide dictionary.
  static bool isLearnableWord(String word) =>
      word.isNotEmpty && word.runes.length <= maxWordLength && !_blankOrControl.hasMatch(word);

  Future<void> _wordAction(String method, String word, Locale? locale) async {
    if (!isSupported || !isLearnableWord(word)) return;
    try {
      await _channel.invokeMethod(method, {
        'word': word,
        'language': (locale ?? const Locale('en')).languageCode,
        'locale': (locale ?? const Locale('en', 'US')).toLanguageTag(),
      });
    } catch (_) {
      // The driver also remembers the word itself, so the underline still goes.
    }
  }
}
