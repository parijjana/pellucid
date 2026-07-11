import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../editor/providers/storage_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import 'local_snapshot_list.dart';
import 'revision_preview_dialog.dart';
import 'snapshot_tab.dart';
import 'snapshot_tab_toggle.dart';
import 'snapshot_text_utils.dart';

class SnapshotManagementDialog extends StatefulWidget {
  final String projectName;

  const SnapshotManagementDialog({
    super.key,
    required this.projectName,
  });

  @override
  State<SnapshotManagementDialog> createState() => _SnapshotManagementDialogState();
}

class _SnapshotManagementDialogState extends State<SnapshotManagementDialog> {
  bool _isLoading = false;
  SnapshotTab _tab = SnapshotTab.cloud;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sync = context.read<SyncProvider>();
      if (!sync.isLoggedIn) {
        setState(() => _tab = SnapshotTab.local);
      }
      _fetchHistory();
    });
  }

  Future<void> _fetchHistory() async {
    final sync = context.read<SyncProvider>();
    if (sync.isLoggedIn) {
      setState(() => _isLoading = true);
      try {
        await sync.loadHistory(widget.projectName, 'manuscript.md');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final sync = context.watch<SyncProvider>();
    final settings = context.watch<SettingsProvider>();

    return Dialog(
      backgroundColor: theme.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.1)),
      ),
      child: Container(
        width: 450,
        height: 550,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manuscript Snapshots',
                        style: TextStyle(
                          color: theme.foregroundColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.projectName,
                        style: TextStyle(
                          color: theme.foregroundColor.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_tab == SnapshotTab.cloud && sync.isLoggedIn)
                  IconButton(
                    icon: Icon(Icons.refresh, color: theme.foregroundColor.withValues(alpha: 0.5), size: 20),
                    onPressed: _fetchHistory,
                  ),
                IconButton(
                  icon: Icon(Icons.close, color: theme.foregroundColor.withValues(alpha: 0.5), size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SnapshotTabToggle(
              activeTab: _tab,
              theme: theme,
              onChanged: (tab) => setState(() => _tab = tab),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _tab == SnapshotTab.cloud
                  ? _buildCloudBody(sync, settings, theme)
                  : LocalSnapshotList(
                      projectPath: settings.masterDirectoryPath != null
                          ? '${settings.masterDirectoryPath}/${widget.projectName}'
                          : null,
                      projectName: widget.projectName,
                      theme: theme,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudBody(SyncProvider sync, SettingsProvider settings, WriterTheme theme) {
    if (!sync.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 40, color: theme.foregroundColor.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'Connect to Google Drive in settings to view cloud snapshots.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.foregroundColor.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
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
        SizedBox(
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
        const SizedBox(height: 12),
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
                  itemCount: revisions.length,
                  itemBuilder: (context, index) {
                    final rev = revisions[index];
                    final revIndex = revisions.length - index;
                    final displayTime = rev.modifiedTime != null
                        ? formatSnapshotTime(rev.modifiedTime!.toLocal())
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
                        onTap: () => _previewRevision(rev.id, displayTime),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _createSnapshot(SyncProvider sync, SettingsProvider settings) async {
    setState(() => _isLoading = true);
    try {
      String content = '';
      if (widget.projectName == settings.currentProjectName) {
        final editor = context.read<EditorProvider>();
        content = editor.content;
      } else if (settings.masterDirectoryPath != null) {
        final path = '${settings.masterDirectoryPath}/${widget.projectName}';
        content = await StorageService().readDocument(path);
      }
      
      await sync.syncCurrentFile(
        projectName: widget.projectName,
        fileName: 'manuscript.md',
        content: content,
      );
      await sync.loadHistory(widget.projectName, 'manuscript.md');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _previewRevision(String? revisionId, String displayTime) {
    if (revisionId == null) return;
    showDialog(
      context: context,
      builder: (context) => RevisionPreviewDialog(
        revisionId: revisionId,
        projectName: widget.projectName,
        fileName: 'manuscript.md',
        displayTime: displayTime,
      ),
    );
  }
}
