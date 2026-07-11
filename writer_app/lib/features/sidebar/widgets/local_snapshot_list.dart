// Description: Browsable list of on-device manuscript snapshots (Local Snapshot
// Safety Net). Works regardless of Google Drive login state.

import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/storage_service.dart';
import '../../editor/providers/local_snapshot_store.dart';
import 'revision_preview_dialog.dart';
import 'snapshot_text_utils.dart';

class _LocalSnapshotEntry {
  final LocalSnapshotRecord record;
  final int wordCount;
  const _LocalSnapshotEntry({required this.record, required this.wordCount});
}

class LocalSnapshotList extends StatefulWidget {
  final String? projectPath;
  final String projectName;
  final WriterTheme theme;
  final StorageService? storageService;

  const LocalSnapshotList({
    super.key,
    required this.projectPath,
    required this.projectName,
    required this.theme,
    this.storageService,
  });

  @override
  State<LocalSnapshotList> createState() => _LocalSnapshotListState();
}

class _LocalSnapshotListState extends State<LocalSnapshotList> {
  bool _isLoading = true;
  List<_LocalSnapshotEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final projectPath = widget.projectPath;
    if (projectPath == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);

    final storage = widget.storageService ?? StorageService();
    final records = await storage.listLocalSnapshots(projectPath);
    final entries = <_LocalSnapshotEntry>[];
    for (final record in records) {
      final content = await storage.readLocalSnapshot(record.filePath);
      entries.add(_LocalSnapshotEntry(record: record, wordCount: countSnapshotWords(content)));
    }

    if (mounted) setState(() { _entries = entries; _isLoading = false; });
  }

  void _openPreview(_LocalSnapshotEntry entry) {
    showDialog(
      context: context,
      builder: (context) => RevisionPreviewDialog(
        projectName: widget.projectName,
        fileName: 'manuscript.md',
        displayTime: formatSnapshotTime(entry.record.timestamp),
        localFilePath: entry.record.filePath,
        storageService: widget.storageService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(theme.foregroundColor.withValues(alpha: 0.3)),
        ),
      );
    }

    if (widget.projectPath == null) {
      return _EmptyState(
        theme: theme,
        message: 'Set a Master Storage Directory to enable local snapshots.',
      );
    }

    if (_entries.isEmpty) {
      return _EmptyState(
        theme: theme,
        message: 'No local snapshots yet. Pellucid saves one automatically every\n10 minutes while you write, and whenever you switch projects.',
      );
    }

    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) => _LocalSnapshotRow(
        entry: _entries[index],
        theme: theme,
        onTap: () => _openPreview(_entries[index]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final WriterTheme theme;
  final String message;
  const _EmptyState({required this.theme, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 40, color: theme.foregroundColor.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LocalSnapshotRow extends StatelessWidget {
  final _LocalSnapshotEntry entry;
  final WriterTheme theme;
  final VoidCallback onTap;

  const _LocalSnapshotRow({required this.entry, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.sidebarColor.withValues(alpha: 0.4),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        leading: Icon(Icons.save_outlined, size: 16, color: theme.foregroundColor.withValues(alpha: 0.4)),
        title: Text(
          formatSnapshotTime(entry.record.timestamp),
          style: TextStyle(color: theme.foregroundColor, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${entry.wordCount} words',
          style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4), fontSize: 11),
        ),
        dense: true,
        onTap: onTap,
      ),
    );
  }
}
