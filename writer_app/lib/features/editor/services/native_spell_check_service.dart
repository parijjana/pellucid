import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Red-underline spell checking through the OS spell checker: NSSpellChecker
/// on macOS (MainFlutterWindow.swift) and ISpellChecker on Windows
/// (windows/runner/spell_check_channel.cpp). Flutter has no desktop default.
///
/// EditableText reads its SpellCheckConfiguration once, in initState, and
/// only re-checks when the user types. So the editor is always given this one
/// [instance], the on/off setting lives in [enabled], and [refresh] brings a
/// live editor up to date the moment the setting changes.
class NativeSpellCheckService implements SpellCheckService {
  NativeSpellCheckService._();

  static final NativeSpellCheckService instance = NativeSpellCheckService._();

  /// Platforms with a native handler for [_channel].
  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  /// Mirrors SettingsProvider.spellCheckEnabled; off means no misspellings.
  bool enabled = true;

  static const _channel = MethodChannel('com.overengineeredhobbies.pellucid/spellcheck');

  @override
  Future<List<SuggestionSpan>> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (!isSupported || !enabled) return [];

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

  /// Re-check (or clear) the editor that owns [editorFocus] right away,
  /// without waiting for the next keystroke. EditableText only exposes its
  /// results as a public field, so set it and repaint the same way it does
  /// after its own check.
  Future<void> refresh(FocusNode editorFocus, TextEditingController controller) async {
    final editable = editorFocus.context?.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return;
    final text = controller.text;
    List<SuggestionSpan> spans = const [];
    if (enabled && text.isNotEmpty) {
      final locale = Localizations.maybeLocaleOf(editable.context) ?? const Locale('en', 'US');
      spans = await fetchSpellCheckSuggestions(locale, text);
    }
    if (!editable.mounted || controller.text != text) return;
    editable.spellCheckResults = SpellCheckResults(text, spans);
    editable.renderEditable.text = editable.buildTextSpan();
  }
}
