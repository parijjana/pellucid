import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../sidebar/providers/notes_provider.dart';
import '../providers/search_provider.dart';

class SearchPopup extends StatefulWidget {
  const SearchPopup({super.key});

  @override
  State<SearchPopup> createState() => _SearchPopupState();
}

class _SearchPopupState extends State<SearchPopup> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final searchProvider = context.read<SearchProvider>();
    _controller = TextEditingController(text: searchProvider.query);
    _focusNode = FocusNode();
    
    // Request focus and run initial search update on next frame to ensure widget is mounted
    // and to avoid triggering setState() or notifyListeners() during build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        if (searchProvider.query.isNotEmpty) {
          final content = context.read<EditorProvider>().content;
          searchProvider.updateMatchOffsets(content);
        }
      }
    });
    
    _controller.addListener(() {
      final query = _controller.text;
      searchProvider.setQuery(query);
      if (mounted) {
        final content = context.read<EditorProvider>().content;
        searchProvider.updateMatchOffsets(content);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int _countMatches(String text, String query) {
    if (query.isEmpty) return 0;
    final escaped = RegExp.escape(query);
    return RegExp(escaped, caseSensitive: false).allMatches(text).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final searchProvider = context.watch<SearchProvider>();
    final editorProvider = context.watch<EditorProvider>();
    final notesProvider = context.watch<NotesProvider>();

    // Calculate total matches dynamically
    int matchCount = 0;
    if (searchProvider.query.isNotEmpty) {
      matchCount += _countMatches(editorProvider.content, searchProvider.query);
      for (final card in notesProvider.cards) {
        matchCount += _countMatches(card.title, searchProvider.query);
        matchCount += _countMatches(card.isAttribution ? card.getAttributionMarkdown() : card.content, searchProvider.query);
      }
    }

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          searchProvider.toggleSearch(isOpen: false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 500,
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.sidebarColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.foregroundColor.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: 20,
                  color: theme.foregroundColor.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onSubmitted: (value) {
                      searchProvider.nextMatch();
                      _focusNode.requestFocus();
                    },
                    style: TextStyle(
                      color: theme.foregroundColor,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search manuscript, notes, and chapters...',
                      hintStyle: TextStyle(
                        color: theme.foregroundColor.withValues(alpha: 0.25),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (searchProvider.query.isNotEmpty) ...[
                  Text(
                    '${searchProvider.matchOffsets.isEmpty ? 0 : searchProvider.currentMatchIndex + 1} of ${searchProvider.matchOffsets.length}',
                    style: TextStyle(
                      color: theme.foregroundColor.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_up,
                      size: 18,
                      color: theme.foregroundColor.withValues(alpha: 0.5),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      searchProvider.previousMatch();
                    },
                    tooltip: 'Previous Match',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: theme.foregroundColor.withValues(alpha: 0.5),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      searchProvider.nextMatch();
                    },
                    tooltip: 'Next Match',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.foregroundColor.withValues(alpha: 0.4),
                    ),
                    onPressed: () {
                      _controller.clear();
                    },
                  ),
                ] else
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.foregroundColor.withValues(alpha: 0.4),
                    ),
                    onPressed: () {
                      searchProvider.toggleSearch(isOpen: false);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
