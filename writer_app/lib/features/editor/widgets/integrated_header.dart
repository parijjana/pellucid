import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/theme_provider.dart';
import '../screenshot_mode.dart';
import '../../../core/platform_context.dart';

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
    final double leftPadding = (!kIsWeb && Platform.isMacOS) ? 80.0 : 8.0;

    Color dragAreaColor = Colors.transparent;

    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool isCompactLayout = usesCompactLayout(context);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor,
      ),
      child: Stack(
        children: [
          // Background Drag Area: Handles dragging on any empty space of the header
          if (isDesktop)
            Positioned.fill(
              child: DragToMoveArea(
                child: Container(
                  color: dragAreaColor,
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: Colors.transparent,
              ),
            ),
          if (isDesktop && widget.showWindowControls && !Platform.isMacOS && !kScreenshotCaptureMode)
            WindowCaption(
              brightness: widget.theme.backgroundColor.computeLuminance() > 0.5
                  ? Brightness.light
                  : Brightness.dark,
              backgroundColor: Colors.transparent,
            ),
          // Screenshot harness only: the real native macOS traffic lights are drawn
          // by the OS window and never composited into the off-screen raster, so the
          // Mac App Store set would otherwise be missing them. Draw synthetic ones for
          // the macOS target, and nothing for every other store (keeps Apple controls
          // out of the Windows/iOS/Android shots). Inert when not capturing.
          if (kScreenshotCaptureMode && kScreenshotWindowControls == ScreenshotWindowControls.macOS)
            const Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(child: _CaptureTrafficLights()),
            ),

          // Action Button (Left)
          if (!isCompactLayout)
            Positioned(
              left: leftPadding,
              top: 0,
              bottom: 0,
              child: MouseRegion(
                onEnter: (_) => setState(() => _isActionHovered = true),
                onExit: (_) => setState(() => _isActionHovered = false),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: (_isActionHovered || kScreenshotCaptureMode) ? 1.0 : 0.2,
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
                          opacity: (_isTitleHovered || kScreenshotCaptureMode) ? 1.0 : 0.15,
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

/// Screenshot-harness-only synthetic macOS traffic lights (close/minimize/zoom).
/// Never used by the shipped app — only composited into the Mac App Store shots,
/// where the real OS-drawn controls fall outside the off-screen raster.
class _CaptureTrafficLights extends StatelessWidget {
  const _CaptureTrafficLights();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _TrafficDot(Color(0xFFFF5F57)),
        SizedBox(width: 8),
        _TrafficDot(Color(0xFFFEBC2E)),
        SizedBox(width: 8),
        _TrafficDot(Color(0xFF28C840)),
      ],
    );
  }
}

class _TrafficDot extends StatelessWidget {
  final Color color;
  const _TrafficDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
