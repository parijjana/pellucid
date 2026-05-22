import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';

class SessionTimerWidget extends StatefulWidget {
  final WriterTheme theme;
  final Duration current;
  final Duration target;
  final bool showTarget;
  final bool isPeeked;

  const SessionTimerWidget({
    super.key,
    required this.theme,
    required this.current,
    required this.target,
    required this.showTarget,
    this.isPeeked = false,
  });

  @override
  State<SessionTimerWidget> createState() => _SessionTimerWidgetState();
}

class _SessionTimerWidgetState extends State<SessionTimerWidget> {
  bool _isHovered = false;

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => _pickTargetTime(context, settings),
        child: AnimatedOpacity(
          opacity: _isHovered || widget.isPeeked ? 1.0 : 0.3,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              widget.showTarget ? '${_format(widget.current)} / ${_format(widget.target)}' : _format(widget.current),
              style: TextStyle(
                color: widget.theme.foregroundColor,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _pickTargetTime(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned(
            bottom: 60,
            left: 60,
            child: Material(
              color: widget.theme.sidebarColor,
              borderRadius: BorderRadius.circular(8),
              elevation: 8,
              child: SizedBox(
                width: 250,
                height: 250,
                child: Column(
                  children: [
                    Expanded(
                      child: CupertinoTheme(
                        data: CupertinoThemeData(
                          brightness: widget.theme.backgroundColor.computeLuminance() > 0.5 
                            ? Brightness.light 
                            : Brightness.dark,
                        ),
                        child: CupertinoTimerPicker(
                          mode: CupertinoTimerPickerMode.hm,
                          initialTimerDuration: settings.targetSessionTime,
                          onTimerDurationChanged: (Duration duration) {
                            settings.setTargetSessionTime(duration);
                          },
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context), 
                      child: Text('OK', style: TextStyle(color: widget.theme.foregroundColor))
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
