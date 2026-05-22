import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../providers/editor_provider.dart';

class EditorPaperArea extends StatelessWidget {
  final WriterTheme theme;
  final EditorProvider provider;
  final TextEditingController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const EditorPaperArea({
    super.key,
    required this.theme,
    required this.provider,
    required this.controller,
    required this.scrollController,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final zoomLevel = provider.zoomLevel;
    final pageWidth = provider.pageWidth;
    final horizontalPos = provider.horizontalPosition;

    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment(horizontalPos * 2 - 1, 0),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 100),
        child: Container(
          width: pageWidth * zoomLevel,
          constraints: const BoxConstraints(minHeight: 1000),
          decoration: BoxDecoration(
            color: theme.backgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(60),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: null,
            cursorColor: theme.foregroundColor.withValues(alpha: 0.3),
            style: TextStyle(
              color: theme.foregroundColor,
              fontSize: 16 * zoomLevel,
              height: 1.8,
              fontFamily: 'Georgia',
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
