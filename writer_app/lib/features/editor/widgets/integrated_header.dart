// @trace FEAT-20260517-115000-0004
// Description: A unified header that handles window dragging and project info (Minimal Flat Style).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/theme_provider.dart';

class IntegratedHeader extends StatefulWidget {
  final WriterTheme theme;
  final Widget actionButton;
  final bool showWindowControls;
  final String? projectName;

  const IntegratedHeader({
    super.key,
    required this.theme,
    required this.actionButton,
    this.showWindowControls = true,
    this.projectName,
  });

  @override
  State<IntegratedHeader> createState() => _IntegratedHeaderState();
}

class _IntegratedHeaderState extends State<IntegratedHeader> {
  bool _isActionHovered = false;
  bool _isTitleHovered = false;

  @override
  Widget build(BuildContext context) {
    final double leftPadding = Platform.isMacOS ? 80.0 : 8.0;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor,
      ),
      child: Stack(
        children: [
          if (widget.showWindowControls)
            WindowCaption(
              brightness: widget.theme.backgroundColor.computeLuminance() > 0.5 
                  ? Brightness.light 
                  : Brightness.dark,
              backgroundColor: Colors.transparent,
            )
          else
            const DragToMoveArea(child: SizedBox.expand()),
          
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
        ],
      ),
    );
  }
}
