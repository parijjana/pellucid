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
    _controller = TextEditingController();
    _focusNode = FocusNode();
    
    // Request focus on next frame to ensure widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    final searchProvider = context.read<SearchProvider>();
    _controller.text = searchProvider.query;
    _controller.addListener(() {
      searchProvider.setQuery(_controller.text);
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
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 80), // Centered near the top
            GestureDetector(
              onTap: () {}, // Intercept tap to prevent closing the popup when clicking inside the card
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
                            '$matchCount ${matchCount == 1 ? "match" : "matches"}',
                            style: TextStyle(
                              color: theme.foregroundColor.withValues(alpha: 0.3),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
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
            ),
          ],
        ),
      ),
    );
  }
}
