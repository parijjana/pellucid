import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../editor/providers/storage_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../../sync/providers/sync_provider.dart';
import 'snapshot_text_utils.dart';

/// Previews a single manuscript snapshot and offers a restore flow. Sourced from
/// either a Google Drive revision (pass [revisionId]) or a local on-device
/// snapshot file (pass [localFilePath]) — exactly one must be provided.
class RevisionPreviewDialog extends StatefulWidget {
  final String projectName;
  final String fileName;
  final String displayTime;
  final String? revisionId;
  final String? localFilePath;
  final StorageService? storageService;

  const RevisionPreviewDialog({
    super.key,
    required this.projectName,
    required this.fileName,
    required this.displayTime,
    this.revisionId,
    this.localFilePath,
    this.storageService,
  }) : assert(revisionId != null || localFilePath != null);

  bool get isLocal => localFilePath != null;

  @override
  State<RevisionPreviewDialog> createState() => _RevisionPreviewDialogState();
}

class _RevisionPreviewDialogState extends State<RevisionPreviewDialog> {
  bool _isLoading = true;
  String _content = '';
  String? _error;

  StorageService get _storage => widget.storageService ?? StorageService();

  @override
  void initState() {
    super.initState();
    _loadRevisionContent();
  }

  Future<void> _loadRevisionContent() async {
    try {
      final String text;
      if (widget.isLocal) {
        text = await _storage.readLocalSnapshot(widget.localFilePath!);
      } else {
        final sync = context.read<SyncProvider>();
        text = await sync.getVersionContent(
          widget.revisionId!,
          widget.projectName,
          widget.fileName,
        );
      }
      if (mounted) {
        setState(() {
          _content = text;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final editor = context.watch<EditorProvider>();
    final sync = context.watch<SyncProvider>();

    final currentWordCount = countSnapshotWords(editor.content);
    final revisionWordCount = countSnapshotWords(_content);
    final wordDelta = revisionWordCount - currentWordCount;

    return Dialog(
      backgroundColor: theme.backgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.1)),
      ),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(theme.foregroundColor.withValues(alpha: 0.3)),
                ),
              )
            : _error != null
                ? Center(
                    child: Text(
                      'Failed to load snapshot content: $_error',
                      style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6)),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preview Snapshot - ${widget.displayTime}',
                                style: TextStyle(
                                  color: theme.foregroundColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$revisionWordCount words (${wordDelta >= 0 ? '+' : ''}$wordDelta relative to current)',
                                style: TextStyle(
                                  color: theme.foregroundColor.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: theme.foregroundColor.withValues(alpha: 0.5)),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.sidebarColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.05)),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _content,
                              style: TextStyle(
                                color: theme.foregroundColor,
                                fontSize: 14,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => _confirmRestore(context, theme, editor, sync),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.withValues(alpha: 0.1),
                              foregroundColor: Colors.blue,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Restore Version'),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  void _confirmRestore(
    BuildContext context,
    WriterTheme theme,
    EditorProvider editor,
    SyncProvider sync,
  ) {
    final settings = context.read<SettingsProvider>();
    final isCurrentProject = widget.projectName == settings.currentProjectName;

    showDialog(
      context: context,
      builder: (confirmContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        title: Text('Restore Snapshot?', style: TextStyle(color: theme.foregroundColor)),
        content: Text(
          isCurrentProject
              ? 'This will overwrite your current active manuscript.'
              : 'This will overwrite the manuscript for project "${widget.projectName}".',
          style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(),
            child: Text('Cancel', style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(confirmContext).pop();
              setState(() => _isLoading = true);
              
              try {
                if (isCurrentProject) {
                  editor.updateContent(
                    _content,
                    syncProvider: sync,
                    projectName: widget.projectName,
                  );
                } else if (settings.masterDirectoryPath != null) {
                  final path = '${settings.masterDirectoryPath}/${widget.projectName}';
                  await _storage.saveDocument(path, _content);
                  if (!widget.isLocal) {
                    await sync.syncCurrentFile(
                      projectName: widget.projectName,
                      fileName: widget.fileName,
                      content: _content,
                    );
                  }
                }

                if (!widget.isLocal) {
                  await sync.loadHistory(widget.projectName, widget.fileName);
                }

                if (mounted) {
                  Navigator.of(context).pop();
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _error = 'Restore failed: $e';
                    _isLoading = false;
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.1),
              foregroundColor: Colors.red,
              elevation: 0,
            ),
            child: const Text('Confirm Restore'),
          ),
        ],
      ),
    );
  }
}
