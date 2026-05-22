// @trace FEAT-20260516-115000-0003
// Description: Minimal, gesture-based alignment bar for adjusting page width and position.

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class AlignmentBar extends StatefulWidget {
  final WriterTheme theme;
  final double pageWidth;
  final double horizontalPosition;
  final Function(double) onWidthChanged;
  final Function(double) onPositionChanged;

  const AlignmentBar({
    super.key,
    required this.theme,
    required this.pageWidth,
    required this.horizontalPosition,
    required this.onWidthChanged,
    required this.onPositionChanged,
  });

  @override
  State<AlignmentBar> createState() => _AlignmentBarState();
}

class _AlignmentBarState extends State<AlignmentBar> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        opacity: (_isHovered || _isDragging) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 40),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxTx = constraints.maxWidth - widget.pageWidth;
              final currentTx = widget.horizontalPosition * maxTx;

              return Stack(
                children: [
                  Positioned(
                    left: currentTx,
                    width: widget.pageWidth,
                    top: 15,
                    bottom: 15,
                    child: GestureDetector(
                      onHorizontalDragStart: (_) => setState(() => _isDragging = true),
                      onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
                      onHorizontalDragUpdate: (details) {
                        final delta = details.primaryDelta ?? 0;
                        final newPos = (currentTx + delta) / maxTx;
                        widget.onPositionChanged(newPos.clamp(0.0, 1.0));
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.theme.foregroundColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: -10, top: -5, bottom: -5,
                              child: _buildHandle(true),
                            ),
                            Positioned(
                              right: -10, top: -5, bottom: -5,
                              child: _buildHandle(false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(bool isLeft) {
    return _GlowHandle(
      theme: widget.theme,
      isDragging: _isDragging,
      onDragUpdate: (delta) {
        final newWidth = widget.pageWidth + (isLeft ? -delta * 2 : delta * 2);
        widget.onWidthChanged(newWidth);
      },
      onDragStart: () => setState(() => _isDragging = true),
      onDragEnd: () => setState(() => _isDragging = false),
    );
  }
}

class _GlowHandle extends StatefulWidget {
  final WriterTheme theme;
  final bool isDragging;
  final Function(double) onDragUpdate;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _GlowHandle({
    required this.theme,
    required this.isDragging,
    required this.onDragUpdate,
    required this.onDragStart,
    required this.onDragEnd,
  });

  @override
  State<_GlowHandle> createState() => _GlowHandleState();
}

class _GlowHandleState extends State<_GlowHandle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool active = _isHovered || widget.isDragging;
    
    return GestureDetector(
      onHorizontalDragStart: (_) => widget.onDragStart(),
      onHorizontalDragEnd: (_) => widget.onDragEnd(),
      onHorizontalDragUpdate: (details) => widget.onDragUpdate(details.primaryDelta ?? 0),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 20,
          decoration: BoxDecoration(
            color: active ? widget.theme.foregroundColor.withValues(alpha: 0.6) : widget.theme.foregroundColor.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            boxShadow: active ? [
              BoxShadow(
                color: widget.theme.foregroundColor.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ] : [],
          ),
          child: Center(
            child: Container(
              width: 2, height: 10,
              color: widget.theme.backgroundColor,
            ),
          ),
        ),
      ),
    );
  }
}
