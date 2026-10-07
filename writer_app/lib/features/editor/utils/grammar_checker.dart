// @trace BACKLOG-11
// Description: Basic English grammar hints. A short, closed list of rules, not
// a general grammar checker (any new rule is a new backlog item). Pure Dart:
// text in, issues out. Code, URLs and Markdown markers are never flagged.

import 'package:flutter/painting.dart' show TextRange;
import 'markdown_code_ranges.dart';

/// Stable ids of the four rules.
class GrammarRule {
  static const loneI = 'lone-i';
  static const aAn = 'a-an';
  static const repeatedWord = 'repeated-word';
  static const capitalAfterStop = 'capital-after-full-stop';
}

/// One hint: [range] is what gets underlined; applying the fix replaces
/// [fixRange] with [replacement] (they differ when only part of the underlined
/// text changes, e.g. the "i" of "i'm", or the duplicate and its leading space).
class GrammarIssue {
  final TextRange range;
  final TextRange fixRange;
  final String replacement;
  final String ruleId;
  final String message;

  const GrammarIssue({
    required this.range,
    required this.fixRange,
    required this.replacement,
    required this.ruleId,
    required this.message,
  });

  /// [text] with this issue's fix applied.
  String applyTo(String text) => text.replaceRange(fixRange.start, fixRange.end, replacement);

  @override
  bool operator ==(Object other) =>
      other is GrammarIssue &&
      other.range == range &&
      other.fixRange == fixRange &&
      other.replacement == replacement &&
      other.ruleId == ruleId;

  @override
  int get hashCode => Object.hash(range, fixRange, replacement, ruleId);

  @override
  String toString() => 'GrammarIssue($ruleId $range -> "$replacement")';
}

class GrammarChecker {
  const GrammarChecker._();

  static const _sentinel = '\u0001';

  static final _token = RegExp(r"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*", unicode: true);
  static final _lineMarkers = RegExp(
    r'^[ \t]*(?:(?:#{1,6}|>)[ \t]*)*(?:(?:[-*+]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?',
    multiLine: true,
  );
  static final _rule = RegExp(r'^[ \t]*(?:[-*_][ \t]*){3,}$', multiLine: true);
  static final _linkTarget = RegExp(r'\]\([^)\s]*\)');
  static final _bareUrl = RegExp(r'(?:https?://|www\.)\S+');
  static final _htmlTag = RegExp(r'</?[a-zA-Z][^>\n]*>');
  static final _inlineMarks = RegExp(r'\*+|~~|(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])|[\[\]]', unicode: true);
  static final _letters = RegExp(r'^[\p{L}]+', unicode: true);
  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _contraction = RegExp(r"^i['’](?:m|ll|ve|d)$");

  /// Abbreviations whose full stop does not end a sentence (lower case, no dot).
  static const abbreviations = {
    'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'mt', 'vs', 'etc', 'eg', 'ie', 'cf', 'no',
    'fig', 'figs', 'vol', 'vols', 'ch', 'sec', 'approx', 'dept', 'est', 'ed', 'eds', 'pp', 'al',
    'inc', 'ltd', 'co', 'corp', 'gen', 'col', 'capt', 'lt', 'sgt', 'rev', 'hon', 'gov', 'pres',
    'ave', 'blvd', 'rd',
  };

  /// Words that legitimately appear twice in a row.
  static const allowedRepeats = {
    'had', 'that', 'no', 'ha', 'bye', 'so', 'very', 'oh', 'yes', 'well', 'long', 'far',
  };

  /// Silent-h words: "an hour".
  static const _silentH = ['hour', 'honest', 'honor', 'honour', 'heir'];

  /// Vowel letter, consonant sound: "a university".
  static const _consonantSoundStems = [
    'univers', 'unif', 'unic', 'union', 'unit', 'uniq', 'unis', 'unil', 'unan',
    'use', 'usu', 'usa', 'uti', 'ute', 'uto', 'uku', 'uran', 'ubiq', 'ufo', 'uri', 'uro',
    'eu', 'ewe',
  ];
  static const _consonantSoundExact = {'one', 'ones', 'once', 'oneself'};

  /// Whether "an" (not "a") belongs before [word] (lower case, letters only).
  static bool needsAn(String word) {
    if (word.isEmpty) return false;
    for (final s in _silentH) {
      if (word.startsWith(s)) return true;
    }
    if (!'aeiou'.contains(word[0])) return false;
    if (_consonantSoundExact.contains(word)) return false;
    for (final s in _consonantSoundStems) {
      if (word.startsWith(s)) return false;
    }
    return true;
  }

  /// Same length as [text]: code and URLs become a sentinel (a hard break),
  /// Markdown markers become spaces.
  static String mask(String text) {
    final chars = text.split('');
    void blank(int start, int end, String fill) {
      for (int i = start; i < end && i < chars.length; i++) {
        if (chars[i] != '\n') chars[i] = fill;
      }
    }

    for (final r in markdownCodeRanges(text)) {
      blank(r.start, r.end, _sentinel);
    }
    for (final m in _linkTarget.allMatches(text)) {
      blank(m.start + 1, m.end, _sentinel);
    }
    for (final m in _bareUrl.allMatches(text)) {
      blank(m.start, m.end, _sentinel);
    }
    for (final m in _htmlTag.allMatches(text)) {
      blank(m.start, m.end, ' ');
    }
    for (final m in _rule.allMatches(text)) {
      blank(m.start, m.end, ' ');
    }
    for (final m in _lineMarkers.allMatches(text)) {
      blank(m.start, m.end, ' ');
    }
    final partial = chars.join();
    for (final m in _inlineMarks.allMatches(partial)) {
      // Leave sentinels (code) alone; marks inside them are already masked.
      blank(m.start, m.end, ' ');
    }
    return chars.join();
  }

  /// All hints in [text], sorted by position, never overlapping.
  static List<GrammarIssue> check(String text) {
    if (text.isEmpty) return const [];
    final masked = mask(text);
    final tokens = _token.allMatches(masked).toList();
    final issues = <GrammarIssue>[];

    _loneI(text, tokens, issues);
    _articles(text, masked, tokens, issues);
    _repeats(text, masked, tokens, issues);
    _capitals(masked, issues);

    issues.sort((a, b) => a.range.start.compareTo(b.range.start));
    final out = <GrammarIssue>[];
    for (final i in issues) {
      if (out.isNotEmpty && i.range.start < out.last.range.end) continue;
      out.add(i);
    }
    return out;
  }

  static String _at(String s, int i) => (i >= 0 && i < s.length) ? s[i] : '';

  static void _loneI(String text, List<RegExpMatch> tokens, List<GrammarIssue> out) {
    for (final t in tokens) {
      final w = t.group(0)!;
      if (w != 'i' && !_contraction.hasMatch(w)) continue;
      final prev = _at(text, t.start - 1);
      final next = _at(text, t.end);
      const pairs = {'*': '*', '_': '_', '~': '~', '`': '`', r'$': r'$', '(': ')', '[': ']'};
      if (pairs[prev] == next && prev.isNotEmpty) continue;
      if (prev == '.' || prev == '-' || prev == '/' || prev == r'\' || prev == r'$') continue;
      if (next == '.' && _letter.hasMatch(_at(text, t.end + 1))) continue; // i.e.
      if (w == 'i' && (next == '.' || next == ')')) {
        // Roman numeral list marker at the start of a line: "i. First".
        final lineStart = t.start == 0 ? 0 : text.lastIndexOf('\n', t.start - 1) + 1;
        if (text.substring(lineStart, t.start).trim().isEmpty) continue;
      }
      out.add(GrammarIssue(
        range: TextRange(start: t.start, end: t.end),
        fixRange: TextRange(start: t.start, end: t.start + 1),
        replacement: 'I',
        ruleId: GrammarRule.loneI,
        message: 'Use a capital "I".',
      ));
    }
  }

  static bool _sentenceStart(String masked, int index) {
    int i = index - 1;
    while (i >= 0) {
      final c = masked[i];
      if (c == ' ' || c == '\t' || c == '"' || c == '“' || c == '‘' || c == '(') {
        i--;
        continue;
      }
      return c == '\n' || c == '.' || c == '!' || c == '?';
    }
    return true;
  }

  static void _articles(String text, String masked, List<RegExpMatch> tokens, List<GrammarIssue> out) {
    for (int k = 0; k + 1 < tokens.length; k++) {
      final t = tokens[k];
      final w = t.group(0)!;
      final lower = w.toLowerCase();
      if (lower != 'a' && lower != 'an') continue;
      final n = tokens[k + 1];
      final gap = masked.substring(t.end, n.start);
      if (gap.isEmpty || gap.trim().isNotEmpty) continue;
      if (gap.contains('\n')) continue;
      final lead = _letters.firstMatch(n.group(0)!)?.group(0);
      if (lead == null || lead.length < 2) continue;
      // Acronyms ("an FBI agent", "a NASA probe"): the sound depends on spelling.
      if (lead == lead.toUpperCase()) continue;
      final word = lead.toLowerCase();
      final String? replacement;
      if (lower == 'a') {
        if (w == 'A' && !_sentenceStart(masked, t.start)) continue; // "Vitamin A is"
        if (w == 'a' || w == 'A') {
          replacement = needsAn(word) ? (w == 'A' ? 'An' : 'an') : null;
        } else {
          replacement = null;
        }
      } else {
        if (w == 'AN') continue;
        replacement = (!needsAn(word) && !word.startsWith('h')) ? (w == 'An' ? 'A' : 'a') : null;
      }
      if (replacement == null) continue;
      out.add(GrammarIssue(
        range: TextRange(start: t.start, end: t.end),
        fixRange: TextRange(start: t.start, end: t.end),
        replacement: replacement,
        ruleId: GrammarRule.aAn,
        message: 'Use "${replacement.toLowerCase()}" before "${n.group(0)}".',
      ));
    }
  }

  static void _repeats(String text, String masked, List<RegExpMatch> tokens, List<GrammarIssue> out) {
    for (int k = 0; k + 1 < tokens.length; k++) {
      final a = tokens[k];
      final b = tokens[k + 1];
      final wa = a.group(0)!.toLowerCase();
      if (wa != b.group(0)!.toLowerCase()) continue;
      if (allowedRepeats.contains(wa)) continue;
      if (RegExp(r'^\p{N}', unicode: true).hasMatch(wa)) continue;
      final gap = text.substring(a.end, b.start);
      if (gap.isEmpty || gap.replaceAll(RegExp(r'[ \t]'), '').isNotEmpty) continue;
      out.add(GrammarIssue(
        range: TextRange(start: b.start, end: b.end),
        fixRange: TextRange(start: a.end, end: b.end),
        replacement: '',
        ruleId: GrammarRule.repeatedWord,
        message: 'Repeated word: "${b.group(0)}".',
      ));
    }
  }

  static void _capitals(String masked, List<GrammarIssue> out) {
    for (final m in RegExp(r'\.(?=[ \t]+\p{Ll})', unicode: true).allMatches(masked)) {
      final d = m.start;
      final before = _at(masked, d - 1);
      if (before == '.' || before == '…' || before.isEmpty) continue;
      int s = d;
      while (s > 0 && (_letter.hasMatch(masked[s - 1]) || masked[s - 1] == '.')) {
        s--;
      }
      final w = masked.substring(s, d);
      if (w.isEmpty) continue;
      if (w.contains('.')) continue; // e.g. i.e. U.S. a.m.
      if (w.length == 1) continue; // initials
      if (abbreviations.contains(w.toLowerCase())) continue;
      int p = d + 1;
      while (masked[p] == ' ' || masked[p] == '\t') {
        p++;
      }
      out.add(GrammarIssue(
        range: TextRange(start: p, end: p + 1),
        fixRange: TextRange(start: p, end: p + 1),
        replacement: masked[p].toUpperCase(),
        ruleId: GrammarRule.capitalAfterStop,
        message: 'Start a sentence with a capital letter.',
      ));
    }
  }
}
