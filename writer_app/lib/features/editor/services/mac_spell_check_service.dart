import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';

class MacSpellCheckService implements SpellCheckService {
  static const _channel = MethodChannel('com.overengineeredhobbies.pellucid/spellcheck');

  @override
  Future<List<SuggestionSpan>> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (!Platform.isMacOS) return [];

    try {
      final List<dynamic>? result = await _channel.invokeMethod(
        'checkSpelling',
        {
          'text': text,
          'language': locale.languageCode,
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
