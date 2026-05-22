// @trace FEAT-20260516-120000-0001
// Description: A custom TextEditingController that styles Markdown in real-time and hides tags.

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class MarkdownEditingController extends TextEditingController {
  final WriterTheme theme;

  MarkdownEditingController({super.text, required this.theme});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> children = [];
    final lines = text.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLastLine = i == lines.length - 1;
      
      if (line.startsWith('# ')) {
        _addStyledBlock(children, line, r'^# ', 32.0, FontWeight.bold);
      } else if (line.startsWith('## ')) {
        _addStyledBlock(children, line, r'^## ', 24.0, FontWeight.bold);
      } else if (line.startsWith('- ')) {
        _addStyledBlock(children, line, r'^- ', 18.0, FontWeight.normal, isBullet: true);
      } else {
        _addInlineStyledText(children, line, style ?? const TextStyle());
      }

      if (!isLastLine) {
        children.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(style: style, children: children);
  }

  void _addStyledBlock(List<InlineSpan> children, String line, String pattern, double fontSize, FontWeight weight, {bool isBullet = false}) {
    final regex = RegExp(pattern);
    final match = regex.firstMatch(line);
    
    if (match != null) {
      // Hide the markdown tag
      children.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(color: Colors.transparent, fontSize: 1.0, letterSpacing: -1.0),
      ));
      
      // Add and style the content
      String content = line.substring(match.end);
      if (isBullet) content = '• $content';

      children.add(TextSpan(
        text: content,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: theme.foregroundColor,
        ),
      ));
    }
  }

  void _addInlineStyledText(List<InlineSpan> children, String line, TextStyle baseStyle) {
    // Scan for Bold (**) or Italic (*)
    final regex = RegExp(r'(\*\*.*?\*\*|\*.*?\*)');
    int lastMatchEnd = 0;
    
    final matches = regex.allMatches(line);
    
    for (final match in matches) {
      // Add text BEFORE the match
      if (match.start > lastMatchEnd) {
        children.add(TextSpan(text: line.substring(lastMatchEnd, match.start), style: baseStyle));
      }
      
      final matchText = match.group(0)!;
      if (matchText.startsWith('**') && matchText.length >= 4) {
        // Bold: Hide tags
        children.add(const TextSpan(text: '**', style: TextStyle(color: Colors.transparent, fontSize: 1.0, letterSpacing: -1.0)));
        children.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
        children.add(const TextSpan(text: '**', style: TextStyle(color: Colors.transparent, fontSize: 1.0, letterSpacing: -1.0)));
      } else if (matchText.startsWith('*') && matchText.length >= 2) {
        // Italic: Hide tags
        children.add(const TextSpan(text: '*', style: TextStyle(color: Colors.transparent, fontSize: 1.0, letterSpacing: -1.0)));
        children.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
        children.add(const TextSpan(text: '*', style: TextStyle(color: Colors.transparent, fontSize: 1.0, letterSpacing: -1.0)));
      } else {
        // Fallback for malformed matches
        children.add(TextSpan(text: matchText, style: baseStyle));
      }
      
      lastMatchEnd = match.end;
    }
    
    // Add remaining text after last match
    if (lastMatchEnd < line.length) {
      children.add(TextSpan(text: line.substring(lastMatchEnd), style: baseStyle));
    }
  }

  void toggleFormat(String tag) {
    final selection = this.selection;
    if (selection.isCollapsed && !tag.endsWith(' ')) {
      // For selection-based tags like ** or *, do nothing if no selection
      return;
    }

    final selectedText = text.substring(selection.start, selection.end);
    
    if (tag.endsWith(' ')) {
      // Line-based formatting (Title, Heading, Bullet)
      _toggleLineFormat(tag);
    } else {
      // Selection-based formatting (Bold, Italic)
      _toggleSelectionFormat(tag, selectedText);
    }
  }

  void _toggleSelectionFormat(String tag, String selectedText) {
    String newText;
    if (selectedText.startsWith(tag) && selectedText.endsWith(tag)) {
      // Remove format
      newText = selectedText.substring(tag.length, selectedText.length - tag.length);
    } else {
      // Add format
      newText = '$tag$selectedText$tag';
    }

    final selection = this.selection;
    value = value.copyWith(
      text: text.replaceRange(selection.start, selection.end, newText),
      selection: TextSelection.collapsed(offset: selection.start + newText.length),
    );
  }

  void _toggleLineFormat(String tag) {
    final selection = this.selection;
    // Find the start and end of the current line(s)
    int start = selection.start;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    
    int end = selection.end;
    while (end < text.length && text[end] != '\n') {
      end++;
    }

    final lineContent = text.substring(start, end);
    String newLineContent;

    if (tag == 'body') {
      // Remove any leading header or bullet tags
      newLineContent = lineContent.replaceFirst(RegExp(r'^(#+\s*|-\s*)'), '');
    } else if (lineContent.startsWith(tag)) {
      // Remove existing tag
      newLineContent = lineContent.substring(tag.length);
    } else {
      // Remove existing tag first if any, then add new tag
      final stripped = lineContent.replaceFirst(RegExp(r'^(#+\s*|-\s*)'), '');
      newLineContent = '$tag$stripped';
    }

    value = value.copyWith(
      text: text.replaceRange(start, end, newLineContent),
      selection: TextSelection.collapsed(offset: start + newLineContent.length),
    );
  }
}
