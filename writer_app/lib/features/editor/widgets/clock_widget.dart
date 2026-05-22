import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';

class ClockWidget extends StatefulWidget {
  final WriterTheme theme;
  final bool isPeeked;
  const ClockWidget({super.key, required this.theme, this.isPeeked = false});

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> with SingleTickerProviderStateMixin {
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
