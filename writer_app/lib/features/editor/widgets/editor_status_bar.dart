// @trace FEAT-20260516-115000-0003
// Description: Status bar with metrics and tools (Decomposed Flat Style).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/editor_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/sprint_controller.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../providers/shortcuts_provider.dart';
import 'low_contrast_widgets.dart';
import 'sync_status_cloud.dart';
import 'clock_widget.dart';
import 'session_timer_widget.dart';
import 'pomodoro_widget.dart';
import 'sprint_widget.dart';
import 'battery_widget.dart';
import '../../../core/platform_context.dart';

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
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenVersionHistory;

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
    required this.onOpenSettings,
    required this.onOpenVersionHistory,
  });

  @override
  State<EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<EditorStatusBar> {
  // Whether the touch "action dock" (settings/zoom/theme/fullscreen) is
  // currently slid into view. Touch-only state — desktop never sets this.
  bool _isDockOpen = false;

  // Base height of the persistent (always-visible) touch status bar, before
  // the bottom safe-area inset is added. Matches the desktop bar's height so
  // the two feel like the same control at a glance.
  static const double _touchBarHeight = 48.0;
  // Height of the slide-up dock strip holding the action controls. Tall
  // enough that every control inside clears the 44x44 touch-target minimum.
  static const double _dockHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final bool isMobilePhone = isPhoneLayout(context);

    // Touch platforms (iPhone AND iPad) get the FAB-dock status bar instead
    // of the full desktop bar. Rationale for including iPhone, not just
    // keyboard-less iPad: both are "quick updates when inspiration strikes"
    // contexts per the app's own framing, and unifying the two touch bars
    // means one code path to maintain and test instead of a third bespoke
    // layout. iPhone's tighter width is handled by making the dock
    // horizontally scrollable rather than by omitting it.
    if (isTouchPlatform) {
      return _buildTouchBar(context);
    }

    if (isMobilePhone) {
      // Unreachable in real builds (isPhoneLayout implies isTouchPlatform on
      // every real platform), but the store-screenshot capture harness can
      // force this layout on a desktop host via kScreenshotCaptureMode, so
      // this legacy minimal bar is kept as-is for that harness only.
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: widget.theme.backgroundColor,
        ),
        child: Center(
          child: LowContrastText(
            label: '${widget.wordCount} words',
            theme: widget.theme,
          ),
        ),
      );
    }

    return _buildDesktopBar(context);
  }

  /// The full status bar, unchanged from before this feature: every control
  /// always visible, sidebar toggle buttons included. Desktop/mouse-driven
  /// platforms only.
  Widget _buildDesktopBar(BuildContext context) {
    final editorProvider = context.watch<EditorProvider>();
    final settings = context.watch<SettingsProvider>();
    final sync = context.watch<SyncProvider>();
    final shortcuts = context.watch<ShortcutsProvider>();
    final sprint = context.watch<SprintController>();

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
                LowContrastIconButton(
                  icon: Icons.settings,
                  onPressed: widget.onOpenSettings,
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
                if (sprint.isActive || sprint.lastSprintWords != null) ...[
                  SprintWidget(
                    theme: widget.theme,
                    isActive: sprint.isActive,
                    remaining: sprint.remaining,
                    lastWords: sprint.lastSprintWords,
                    onDismiss: sprint.clearResult,
                  ),
                  const SizedBox(width: 16),
                ],
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
                  isSelected: widget.isRightSidebarOpen,
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

  /// Touch (iPhone + iPad) status bar: a persistent, always-glanceable strip
  /// (word count + sync pulse) with a FAB that slides a second "dock" strip
  /// of action controls (settings/zoom/theme/fullscreen) in and out above
  /// it. Sidebar toggles are intentionally absent here — [SidebarPulltab]
  /// covers that job on touch, so the icon-button duplicates were removed.
  ///
  /// Respects the bottom safe area via `MediaQuery.viewPadding`/`padding` so
  /// nothing sits under the iPad/iPhone home-indicator gesture strip.
  Widget _buildTouchBar(BuildContext context) {
    final editorProvider = context.watch<EditorProvider>();
    final sync = context.watch<SyncProvider>();
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double barTotalHeight = _touchBarHeight + bottomInset;

    return Stack(
      // The dock strip is painted above this widget's own box (Positioned
      // with `bottom` >= this box's height). Clip.none lets that overflow
      // paint instead of being clipped, and because this widget is the last
      // child of the enclosing Column, it paints on top of the paper area
      // above it wherever the two overlap — the same "layer on top via
      // paint order" trick already used for the search popup/cheatsheet
      // overlays elsewhere in this screen.
      clipBehavior: Clip.none,
      children: [
        Container(
          height: barTotalHeight,
          padding: EdgeInsets.only(bottom: bottomInset, left: 16, right: 16),
          decoration: BoxDecoration(color: widget.theme.backgroundColor),
          child: Row(
            children: [
              _buildSyncPulse(sync, widget.theme),
              const SizedBox(width: 12),
              LowContrastText(
                label: '${widget.wordCount} words',
                theme: widget.theme,
              ),
              const Spacer(),
              _buildDockFab(),
            ],
          ),
        ),
        if (_isDockOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: barTotalHeight,
            child: Container(
              height: _dockHeight,
              color: widget.theme.backgroundColor,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDockAction(
                      icon: Icons.settings,
                      onPressed: widget.onOpenSettings,
                    ),
                    const SizedBox(width: 20),
                    _buildDockAction(
                      icon: Icons.remove,
                      onPressed: editorProvider.zoomOut,
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: LowContrastText(
                          label: '${(editorProvider.zoomLevel * 100).toInt()}%',
                          theme: widget.theme,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    _buildDockAction(
                      icon: Icons.add,
                      onPressed: editorProvider.zoomIn,
                    ),
                    const SizedBox(width: 20),
                    _buildDockAction(
                      icon: Icons.format_paint,
                      onPressed: widget.onToggleToolbar,
                    ),
                    const SizedBox(width: 20),
                    _buildDockAction(
                      icon: widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      onPressed: widget.onToggleFullscreen,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The FAB that toggles the touch action dock open/closed. 44x44 minimum
  /// touch target, positioned inside the persistent bar's row (not
  /// floating over the paper) so it never fights the [AlignmentBar] — which
  /// itself no longer renders on touch-only devices (see
  /// `hasPointerOrDefault` gating in alignment_bar.dart) — or the home
  /// indicator, since it lives inside the safe-area-padded row.
  Widget _buildDockFab() {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: widget.theme.foregroundColor.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _isDockOpen = !_isDockOpen),
          child: Icon(
            _isDockOpen ? Icons.close : Icons.tune,
            size: 20,
            color: widget.theme.foregroundColor,
          ),
        ),
      ),
    );
  }

  Widget _buildDockAction({required IconData icon, required VoidCallback onPressed}) {
    return SizedBox(
      width: 44,
      height: 44,
      child: LowContrastIconButton(
        icon: icon,
        onPressed: onPressed,
        theme: widget.theme,
        size: 20,
      ),
    );
  }

  /// The sync cloud, doubling as the main page's entry point to version
  /// history. Reusing this glyph rather than adding a button was deliberate:
  /// it already appears in both the desktop and touch bars, so one control
  /// covers every layout, and an app built on near-invisible chrome cannot
  /// afford another icon competing for the same eye.
  ///
  /// The cloud keeps all four of its sync states — the arc is additive, never
  /// a replacement. Losing the signed-out slash or the sync-error cross to
  /// make room for a history glyph would have traded away the only indication
  /// on this screen that a writer's work is not reaching Drive.
  Widget _buildSyncPulse(SyncProvider sync, WriterTheme theme) {
    final Widget cloud = SyncStatusCloud(
      isLoggedIn: sync.isLoggedIn,
      status: sync.status,
      theme: theme,
      showHistoryAffordance: true,
    );

    // Touch needs the 44x44 minimum; the glyph itself is 24 wide, so the
    // padding is what makes the target, not a bigger drawing.
    final Widget target = isTouchPlatform
        ? SizedBox(width: 44, height: 44, child: Center(child: cloud))
        : cloud;

    return Tooltip(
      message: 'Version History',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenVersionHistory,
          child: target,
        ),
      ),
    );
  }
}
