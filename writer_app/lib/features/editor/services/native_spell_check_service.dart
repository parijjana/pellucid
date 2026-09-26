import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';

/// Red-underline spell checking through the OS spell checker: NSSpellChecker
/// on macOS (MainFlutterWindow.swift) and ISpellChecker on Windows
/// (windows/runner/spell_check_channel.cpp). Flutter has no desktop default.
class NativeSpellCheckService implements SpellCheckService {
  /// Platforms with a native handler for [_channel].
  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

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
}
