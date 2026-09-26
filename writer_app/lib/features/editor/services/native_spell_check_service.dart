import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Spell checking through the OS spell checker: NSSpellChecker on macOS
/// (MainFlutterWindow.swift) and ISpellChecker on Windows
/// (windows/runner/spell_check_channel.cpp). Flutter has no desktop default.
///
/// Not handed to EditableText: its built-in spell-check drawing replaces the
/// editor's markdown styling. EditorPaperArea drives this service itself and
/// MarkdownEditingController draws the underlines.
class NativeSpellCheckService implements SpellCheckService {
  const NativeSpellCheckService();

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
