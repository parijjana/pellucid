// @trace FEAT-20260516-115000-0003
// Description: Status bar with metrics and tools (Decomposed Flat Style).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/editor_provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../providers/shortcuts_provider.dart';
import 'low_contrast_widgets.dart';
import 'sync_status_cloud.dart';
import 'clock_widget.dart';
import 'session_timer_widget.dart';
import 'pomodoro_widget.dart';
import 'battery_widget.dart';

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
                LowContrastIconButton(
                  icon: widget.isLeftSidebarOpen ? Icons.menu_open : Icons.menu,
                  onPressed: widget.onToggleLeft,
                  theme: widget.theme,
                ),
                const SizedBox(width: 12),
                _buildSyncPulse(sync, widget.theme),
                const SizedBox(width: 12),
                LowContrastText(
                  label: '${widget.wordCount} words',
                  theme: widget.theme,
                ),
                if (settings.currentSessionEnabled) ...[
                  const SizedBox(width: 24),
                  SessionTimerWidget(
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
              child: ClockWidget(theme: widget.theme, isPeeked: shortcuts.isClockPeeked),
            ),

          // Right Cluster: Pomodoro, Battery, Zoom, Formatting, Sidebars
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.focusTimerEnabled) ...[
                  PomodoroWidget(
                    theme: widget.theme,
                    remaining: settings.pomodoroRemaining,
                    isActive: settings.isPomodoroActive,
                    onStart: settings.startPomodoro,
                    onPause: settings.pausePomodoro,
                    onReset: settings.resetPomodoro,
                  ),
                  const SizedBox(width: 16),
                ],
                if (settings.batteryGuardEnabled) ...[
                  BatteryWidget(theme: widget.theme),
                  const SizedBox(width: 16),
                ],
                LowContrastIconButton(
                  icon: Icons.remove,
                  onPressed: editorProvider.zoomOut,
                  theme: widget.theme,
                  size: 14,
                ),
                LowContrastText(
                  label: '${(editorProvider.zoomLevel * 100).toInt()}%',
                  theme: widget.theme,
                  fontSize: 10,
                ),
                LowContrastIconButton(
                  icon: Icons.add,
                  onPressed: editorProvider.zoomIn,
                  theme: widget.theme,
                  size: 14,
                ),
                const SizedBox(width: 8),
                LowContrastIconButton(
                  icon: Icons.format_paint,
                  onPressed: widget.onToggleToolbar,
                  theme: widget.theme,
                ),
                LowContrastIconButton(
                  icon: widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  onPressed: widget.onToggleFullscreen,
                  theme: widget.theme,
                ),
                LowContrastIconButton(
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
    return SyncStatusCloud(
      isLoggedIn: sync.isLoggedIn,
      status: sync.status,
      theme: theme,
    );
  }
}
