// @trace FEAT-20260517-115000-0004
// Description: Card widgets for project selection and creation.

import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';
import '../../sidebar/widgets/snapshot_management_dialog.dart';
import '../screens/stats_screen.dart';

class ProjectCard extends StatelessWidget {
  final String name;
  final int wordCount;
  final Duration timeSpent;
  final bool isActive;
  final WriterTheme theme;
  final VoidCallback onTap;
  final VoidCallback onLaunch;

  const ProjectCard({
    super.key,
    required this.name,
    required this.wordCount,
    required this.timeSpent,
    required this.isActive,
    required this.theme,
    required this.onTap,
    required this.onLaunch,
  });

  String _formatTime(Duration d) {
    if (d.inHours < 1) {
      return '${d.inMinutes}m';
    } else {
      final hours = d.inHours.toString().padLeft(2, '0');
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '$hours:$minutes';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.sidebarColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.blue : theme.foregroundColor.withValues(alpha: 0.1),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: theme.foregroundColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  const Icon(Icons.check_circle, color: Colors.blue, size: 16),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statText('$wordCount words', theme),
                    const SizedBox(height: 4),
                    _statText(_formatTime(timeSpent), theme),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: onLaunch,
                      child: _LaunchButton(theme: theme),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => SnapshotManagementDialog(projectName: name),
                        );
                      },
                      child: _SnapshotsButton(theme: theme),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              settings: const RouteSettings(name: '/stats'),
                              builder: (context) => const StatsScreen(),
                            ),
                          );
                        },
                        child: _HistoryButton(theme: theme),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statText(String text, WriterTheme theme) {
    return Text(
      text,
      style: TextStyle(
        color: theme.foregroundColor.withValues(alpha: 0.5),
        fontSize: 11,
      ),
    );
  }
}

class _SnapshotsButton extends StatelessWidget {
  final WriterTheme theme;
  const _SnapshotsButton({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.foregroundColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.cloud_sync,
        size: 14,
        color: theme.foregroundColor.withValues(alpha: 0.4),
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final WriterTheme theme;
  const _HistoryButton({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.foregroundColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.history,
        size: 14,
        color: theme.foregroundColor.withValues(alpha: 0.4),
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  final WriterTheme theme;
  const _LaunchButton({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.foregroundColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.open_in_new,
        size: 14,
        color: theme.foregroundColor.withValues(alpha: 0.4),
      ),
    );
  }
}
