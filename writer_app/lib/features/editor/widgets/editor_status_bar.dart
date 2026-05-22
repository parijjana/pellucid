// @trace FEAT-20260516-115000-0003
// Description: Status bar with metrics and tools (Minimal Flat Style).

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/editor_provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../providers/shortcuts_provider.dart';

class EditorStatusBar extends StatefulWidget {
  final WriterTheme theme;
  final int wordCount;
  final bool isLeftSidebarOpen;
  final bool isRightSidebarOpen;
  final bool isFullscreen;
  final VoidCallback onToggleLeft;
  final VoidCallback onToggleRight;
  final VoidCallback onToggleToolbar;
  final VoidCallback onToggleFullscreen;

  const EditorStatusBar({
    super.key,
    required this.theme,
    required this.wordCount,
    required this.isLeftSidebarOpen,
    required this.isRightSidebarOpen,
    required this.isFullscreen,
    required this.onToggleLeft,
    required this.onToggleRight,
    required this.onToggleToolbar,
    required this.onToggleFullscreen,
  });

  @override
  State<EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<EditorStatusBar> {
  @override
  Widget build(BuildContext context) {
    final editorProvider = context.watch<EditorProvider>();
    final settings = context.watch<SettingsProvider>();
    final sync = context.watch<SyncProvider>();
    final shortcuts = context.watch<ShortcutsProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 48,
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor,
      ),
      child: Stack(
        children: [
          // Left Cluster: Word Count & Session Timer & Sync
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSyncPulse(sync, widget.theme),
                const SizedBox(width: 12),
                _LowContrastIconButton(
                  icon: widget.isLeftSidebarOpen ? Icons.menu_open : Icons.menu,
                  onPressed: widget.onToggleLeft,
                  theme: widget.theme,
                ),
                _LowContrastText(
                  label: '${widget.wordCount} words',
                  theme: widget.theme,
                ),
                if (settings.currentSessionEnabled) ...[
                  const SizedBox(width: 24),
                  _SessionTimerWidget(
                    theme: widget.theme,
                    current: settings.currentSessionTime,
                    target: settings.targetSessionTime,
                    showTarget: settings.targetSessionEnabled,
                    isPeeked: shortcuts.isSessionPeeked,
                  ),
                ],
              ],
            ),
          ),

          // Center: Clock
          if (settings.clockEnabled)
            Align(
              alignment: Alignment.center,
              child: _ClockWidget(theme: widget.theme, isPeeked: shortcuts.isClockPeeked),
            ),

          // Right Cluster: Pomodoro, Zoom, Formatting, Sidebars
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.focusTimerEnabled) ...[
                  _PomodoroWidget(
                    theme: widget.theme,
                    remaining: settings.pomodoroRemaining,
                    isActive: settings.isPomodoroActive,
                    onStart: settings.startPomodoro,
                    onPause: settings.pausePomodoro,
                    onReset: settings.resetPomodoro,
                  ),
                  const SizedBox(width: 16),
                ],
                _LowContrastIconButton(
                  icon: Icons.remove,
                  onPressed: editorProvider.zoomOut,
                  theme: widget.theme,
                  size: 14,
                ),
                _LowContrastText(
                  label: '${(editorProvider.zoomLevel * 100).toInt()}%',
                  theme: widget.theme,
                  fontSize: 10,
                ),
                _LowContrastIconButton(
                  icon: Icons.add,
                  onPressed: editorProvider.zoomIn,
                  theme: widget.theme,
                  size: 14,
                ),
                const SizedBox(width: 8),
                _LowContrastIconButton(
                  icon: Icons.format_paint,
                  onPressed: widget.onToggleToolbar,
                  theme: widget.theme,
                ),
                _LowContrastIconButton(
                  icon: widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  onPressed: widget.onToggleFullscreen,
                  theme: widget.theme,
                ),
                _LowContrastIconButton(
                  icon: widget.isRightSidebarOpen ? Icons.menu_open : Icons.menu,
                  flipX: true,
                  onPressed: widget.onToggleRight,
                  theme: widget.theme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncPulse(SyncProvider sync, WriterTheme theme) {
    Color dotColor;
    bool pulsing = false;

    if (!sync.isLoggedIn) {
      dotColor = theme.foregroundColor.withValues(alpha: 0.1);
    } else {
      switch (sync.status) {
        case SyncStatus.syncing:
          dotColor = Colors.blue;
          pulsing = true;
          break;
        case SyncStatus.success:
          dotColor = Colors.green;
          break;
        case SyncStatus.error:
          dotColor = Colors.red;
          break;
        case SyncStatus.idle:
        default:
          dotColor = theme.foregroundColor.withValues(alpha: 0.4);
          break;
      }
    }

    return _StatusDot(color: dotColor, isPulsing: pulsing);
  }
}

class _LowContrastIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final WriterTheme theme;
  final double size;
  final bool flipX;

  const _LowContrastIconButton({
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.size = 18,
    this.flipX = false,
  });

  @override
  State<_LowContrastIconButton> createState() => _LowContrastIconButtonState();
}

class _LowContrastIconButtonState extends State<_LowContrastIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isHovered ? 1.0 : 0.2,
        child: IconButton(
          icon: widget.flipX 
            ? Transform.flip(flipX: true, child: Icon(widget.icon, size: widget.size))
            : Icon(widget.icon, size: widget.size),
          onPressed: widget.onPressed,
          color: widget.theme.foregroundColor,
        ),
      ),
    );
  }
}

class _LowContrastText extends StatefulWidget {
  final String label;
  final WriterTheme theme;
  final double fontSize;

  const _LowContrastText({
    required this.label,
    required this.theme,
    this.fontSize = 11,
  });

  @override
  State<_LowContrastText> createState() => _LowContrastTextState();
}

class _LowContrastTextState extends State<_LowContrastText> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isHovered ? 1.0 : 0.25,
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.theme.foregroundColor,
            fontSize: widget.fontSize,
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool isPulsing;
  const _StatusDot({required this.color, this.isPulsing = false});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.isPulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isPulsing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: widget.isPulsing ? 0.3 + (_controller.value * 0.7) : 1.0),
            boxShadow: [
              if (widget.isPulsing || widget.color != Colors.grey)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.3),
                  blurRadius: 4,
                  spreadRadius: 2 * _controller.value,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ClockWidget extends StatefulWidget {
  final WriterTheme theme;
  final bool isPeeked;
  const _ClockWidget({required this.theme, this.isPeeked = false});

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> with SingleTickerProviderStateMixin {
  late AnimationController _bellController;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _bellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final time = DateTime.now();
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    if (settings.isAlarmTriggered) {
      if (!_bellController.isAnimating) _bellController.repeat(reverse: true);
    } else {
      if (_bellController.isAnimating) _bellController.stop();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          if (settings.isAlarmTriggered) {
            settings.dismissAlarm();
          } else {
            _pickAlarm(context, settings);
          }
        },
        child: AnimatedOpacity(
          opacity: _isHovered || widget.isPeeked || settings.isAlarmTriggered ? 1.0 : 0.2,
          duration: const Duration(milliseconds: 200),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.alarmTime != null || _isHovered || widget.isPeeked || settings.isAlarmTriggered)
                RotationTransition(
                  turns: _bellController.drive(Tween<double>(begin: -0.05, end: 0.05)),
                  child: Icon(
                    settings.isAlarmTriggered ? Icons.notifications_active : Icons.notifications_none,
                    size: 14,
                    color: settings.isAlarmTriggered ? Colors.red : (settings.alarmTime != null ? Colors.blue : widget.theme.foregroundColor),
                  ),
                ),
              if (settings.alarmTime != null || _isHovered || widget.isPeeked || settings.isAlarmTriggered)
                const SizedBox(width: 4),
              Text(
                '$hour:$minute',
                style: TextStyle(
                  color: settings.isAlarmTriggered ? Colors.red : widget.theme.foregroundColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAlarm(BuildContext context, SettingsProvider settings) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(settings.alarmTime ?? DateTime.now()),
    );
    if (picked != null) {
      final now = DateTime.now();
      final alarm = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      settings.setAlarm(alarm);
    }
  }
}

class _SessionTimerWidget extends StatefulWidget {
  final WriterTheme theme;
  final Duration current;
  final Duration target;
  final bool showTarget;
  final bool isPeeked;

  const _SessionTimerWidget({
    required this.theme,
    required this.current,
    required this.target,
    required this.showTarget,
    this.isPeeked = false,
  });

  @override
  State<_SessionTimerWidget> createState() => _SessionTimerWidgetState();
}

class _SessionTimerWidgetState extends State<_SessionTimerWidget> {
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

class _PomodoroWidget extends StatefulWidget {
  final WriterTheme theme;
  final Duration remaining;
  final bool isActive;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;

  const _PomodoroWidget({
    required this.theme,
    required this.remaining,
    required this.isActive,
    required this.onStart,
    required this.onPause,
    required this.onReset,
  });

  @override
  State<_PomodoroWidget> createState() => _PomodoroWidgetState();
}

class _PomodoroWidgetState extends State<_PomodoroWidget> {
  bool _isHovered = false;

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        opacity: _isHovered ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 200),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _format(widget.remaining),
              style: TextStyle(
                color: widget.theme.foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_isHovered) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(widget.isActive ? Icons.pause : Icons.play_arrow, size: 14),
                onPressed: widget.isActive ? widget.onPause : widget.onStart,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                color: widget.theme.foregroundColor,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 14),
                onPressed: widget.onReset,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 2),
                color: widget.theme.foregroundColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
