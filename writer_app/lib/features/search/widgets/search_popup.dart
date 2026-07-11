import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../sidebar/providers/notes_provider.dart';
import '../providers/search_provider.dart';
import 'search_input_row.dart';
import 'search_replace_row.dart';

/// The Ctrl+F command palette: a single search row, optionally grown by a
/// second replace row (Phase 1 Search & Replace). Actually applying a replace
/// is owned by the host screen (`EditorScreen`, via [onReplaceOne] /
/// [onReplaceAll]) so this widget stays a dumb shell over [SearchProvider].
class SearchPopup extends StatefulWidget {
  final VoidCallback? onReplaceOne;
  final VoidCallback? onReplaceAll;

  const SearchPopup({super.key, this.onReplaceOne, this.onReplaceAll});

  @override
  State<SearchPopup> createState() => _SearchPopupState();
}

class _SearchPopupState extends State<SearchPopup> {
  late TextEditingController _controller;
  late TextEditingController _replaceController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final searchProvider = context.read<SearchProvider>();
    _controller = TextEditingController(text: searchProvider.query);
    _replaceController = TextEditingController(text: searchProvider.replaceQuery);
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

    _replaceController.addListener(() {
      searchProvider.setReplaceQuery(_replaceController.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _replaceController.dispose();
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
            // Each row (search field / replace field) is a fixed ~48px tall
            // (Material's minimum interactive height); the replace row adds
            // itself plus an 8px gap on top of the base single-row height.
            height: searchProvider.replaceMode ? 112 : 56,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SearchInputRow(
                  theme: theme,
                  searchProvider: searchProvider,
                  controller: _controller,
                  focusNode: _focusNode,
                  onSubmitted: () {
                    searchProvider.nextMatch();
                    _focusNode.requestFocus();
                  },
                  onToggleReplace: () => searchProvider.toggleReplaceMode(),
                ),
                if (searchProvider.replaceMode) ...[
                  const SizedBox(height: 8),
                  SearchReplaceRow(
                    theme: theme,
                    searchProvider: searchProvider,
                    controller: _replaceController,
                    onReplace: widget.onReplaceOne ?? () {},
                    onReplaceAll: widget.onReplaceAll ?? () {},
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
