// @trace FEAT-20260517-115000-0004
// Description: A unified header that handles window dragging, project info, and project renaming.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/theme_provider.dart';

class IntegratedHeader extends StatefulWidget {
  final WriterTheme theme;
  final Widget actionButton;
  final bool showWindowControls;
  final String? projectName;
  final ValueChanged<String>? onRename;

  const IntegratedHeader({
    super.key,
    required this.theme,
    required this.actionButton,
    this.showWindowControls = true,
    this.projectName,
    this.onRename,
  });

  @override
  State<IntegratedHeader> createState() => _IntegratedHeaderState();
}

class _IntegratedHeaderState extends State<IntegratedHeader> {
  bool _isActionHovered = false;
  bool _isTitleHovered = false;
  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.projectName);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IntegratedHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectName != widget.projectName && !_isEditing) {
      _textController.text = widget.projectName ?? '';
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _submitRename(_textController.text);
    }
  }

  void _submitRename(String val) {
    if (!_isEditing) return;
    setState(() {
      _isEditing = false;
    });
    final cleanName = val.trim();
    if (cleanName.isNotEmpty && cleanName != widget.projectName) {
      widget.onRename?.call(cleanName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double leftPadding = Platform.isMacOS ? 80.0 : 8.0;

    Color dragAreaColor = Colors.transparent;
    if (widget.showWindowControls) {
      final baseColor = widget.theme.backgroundColor;
      final isDark = baseColor.computeLuminance() < 0.5;
      if (baseColor == Colors.black || (isDark && baseColor.red == 0 && baseColor.green == 0 && baseColor.blue == 0)) {
        dragAreaColor = const Color(0xFF161616);
      } else {
        final hsl = HSLColor.fromColor(baseColor);
        dragAreaColor = hsl.withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0)).toColor();
      }
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor,
      ),
      child: Stack(
        children: [
          // Background Drag Area: Handles dragging on any empty space of the header
          Positioned.fill(
            child: DragToMoveArea(
              child: Container(
                color: dragAreaColor,
              ),
            ),
          ),
          if (widget.showWindowControls)
            WindowCaption(
              brightness: widget.theme.backgroundColor.computeLuminance() > 0.5 
                  ? Brightness.light 
                  : Brightness.dark,
              backgroundColor: Colors.transparent,
            ),
          
          // Action Button (Left)
          Positioned(
            left: leftPadding,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => setState(() => _isActionHovered = true),
              onExit: (_) => setState(() => _isActionHovered = false),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isActionHovered ? 1.0 : 0.2,
                child: widget.actionButton,
              ),
            ),
          ),

          // Project Name (Center)
          if (widget.projectName != null)
            Align(
              alignment: Alignment.center,
              child: _isEditing
                  ? SizedBox(
                      width: 250,
                      height: 30,
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.theme.foregroundColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3.0,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: _submitRename,
                      ),
                    )
                  : GestureDetector(
                      onDoubleTap: () {
                        if (widget.projectName == 'User Manual' || widget.onRename == null) return;
                        setState(() {
                          _isEditing = true;
                          _textController.text = widget.projectName ?? '';
                          _focusNode.requestFocus();
                        });
                      },
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _isTitleHovered = true),
                        onExit: (_) => setState(() => _isTitleHovered = false),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isTitleHovered ? 1.0 : 0.15,
                          child: Text(
                            widget.projectName!.toUpperCase(),
                            style: TextStyle(
                              color: widget.theme.foregroundColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3.0,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
