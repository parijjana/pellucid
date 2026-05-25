import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/shortcuts_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../widgets/revision_preview_dialog.dart';

class TimelineSidebar extends StatefulWidget {
  const TimelineSidebar({super.key});

  @override
  State<TimelineSidebar> createState() => _TimelineSidebarState();
}

class _TimelineSidebarState extends State<TimelineSidebar> {
  bool _wasOpen = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final sync = context.watch<SyncProvider>();
    final settings = context.watch<SettingsProvider>();
    final shortcuts = context.watch<ShortcutsProvider>();

    final isTimelineOpen = shortcuts.isTimelineOpen;
    if (isTimelineOpen && !_wasOpen) {
      _wasOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchHistory();
      });
    } else if (!isTimelineOpen) {
      _wasOpen = false;
    }

    return Container(
      color: theme.sidebarColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SNAPSHOTS',
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.2),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                if (sync.isLoggedIn)
                  _GhostIconButton(
                    icon: Icons.refresh,
                    onPressed: _fetchHistory,
                    theme: theme,
                  ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(sync, settings, theme),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchHistory() async {
    final sync = context.read<SyncProvider>();
    final settings = context.read<SettingsProvider>();
    if (sync.isLoggedIn && settings.currentProjectName != null) {
      setState(() => _isLoading = true);
      try {
        await sync.loadHistory(settings.currentProjectName!, 'manuscript.md');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildBody(SyncProvider sync, SettingsProvider settings, WriterTheme theme) {
    if (!sync.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 40, color: theme.foregroundColor.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(
                'Connect to Google Drive in settings to view manuscript snapshots.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.foregroundColor.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(theme.foregroundColor.withValues(alpha: 0.3)),
        ),
      );
    }

    final revisions = sync.history.reversed.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.backup, size: 16),
              label: const Text('Create Snapshot'),
              onPressed: () => _createSnapshot(sync, settings),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.foregroundColor.withValues(alpha: 0.05),
                foregroundColor: theme.foregroundColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.1)),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: revisions.isEmpty
              ? Center(
                  child: Text(
                    'No snapshots found.',
                    style: TextStyle(
                      color: theme.foregroundColor.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: revisions.length,
                  itemBuilder: (context, index) {
                    final rev = revisions[index];
                    final revIndex = revisions.length - index;
                    final displayTime = rev.modifiedTime != null
                        ? _formatTime(rev.modifiedTime!.toLocal())
                        : 'Unknown Time';

                    return Card(
                      color: theme.sidebarColor.withValues(alpha: 0.4),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.05)),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.history, size: 16, color: theme.foregroundColor.withValues(alpha: 0.4)),
                        title: Text(
                          'Snapshot #$revIndex',
                          style: TextStyle(
                            color: theme.foregroundColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          displayTime,
                          style: TextStyle(
                            color: theme.foregroundColor.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                        dense: true,
                        onTap: () => _previewRevision(rev.id, settings.currentProjectName, displayTime),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _createSnapshot(SyncProvider sync, SettingsProvider settings) async {
    if (settings.currentProjectName == null) return;
    setState(() => _isLoading = true);
    try {
      final editor = context.read<EditorProvider>();
      await sync.syncCurrentFile(
        projectName: settings.currentProjectName!,
        fileName: 'manuscript.md',
        content: editor.content,
      );
      await sync.loadHistory(settings.currentProjectName!, 'manuscript.md');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _previewRevision(String? revisionId, String? projectName, String displayTime) {
    if (revisionId == null || projectName == null) return;
    showDialog(
      context: context,
      builder: (context) => RevisionPreviewDialog(
        revisionId: revisionId,
        projectName: projectName,
        fileName: 'manuscript.md',
        displayTime: displayTime,
      ),
    );
  }
}

class _GhostIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final WriterTheme theme;

  const _GhostIconButton({required this.icon, required this.onPressed, required this.theme});

  @override
  State<_GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<_GhostIconButton> {
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
          icon: Icon(widget.icon, size: 16, color: widget.theme.foregroundColor),
          onPressed: widget.onPressed,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
