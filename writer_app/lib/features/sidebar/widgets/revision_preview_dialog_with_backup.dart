import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../sync/providers/sync_provider.dart';

class RevisionPreviewDialogWithBackup extends StatefulWidget {
  final String revisionId;
  final String projectName;
  final String fileName;
  final String displayTime;

  const RevisionPreviewDialogWithBackup({
    super.key,
    required this.revisionId,
    required this.projectName,
    required this.fileName,
    required this.displayTime,
  });

  @override
  State<RevisionPreviewDialogWithBackup> createState() => _RevisionPreviewDialogWithBackupState();
}

class _RevisionPreviewDialogWithBackupState extends State<RevisionPreviewDialogWithBackup> {
  bool _isLoading = true;
  String _content = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRevisionContent();
  }

  Future<void> _loadRevisionContent() async {
    try {
      final sync = context.read<SyncProvider>();
      final text = await sync.getVersionContent(
        widget.revisionId,
        widget.projectName,
        widget.fileName,
      );
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

  int _calculateWordCount(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final editor = context.watch<EditorProvider>();
    final sync = context.watch<SyncProvider>();

    final currentWordCount = _calculateWordCount(editor.content);
    final revisionWordCount = _calculateWordCount(_content);
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
    showDialog(
      context: context,
      builder: (confirmContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        title: Text('Restore Snapshot?', style: TextStyle(color: theme.foregroundColor)),
        content: Text(
          'This will overwrite your current active manuscript. A backup snapshot of your current state will be automatically created first.',
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
                // 1. Create a backup snapshot of current editor content first
                await sync.syncCurrentFile(
                  projectName: widget.projectName,
                  fileName: widget.fileName,
                  content: editor.content,
                );
                
                // 2. Overwrite local and sync the restored content
                editor.updateContent(
                  _content,
                  syncProvider: sync,
                  projectName: widget.projectName,
                );
                
                // 3. Reload history so timeline lists the new backup & state
                await sync.loadHistory(widget.projectName, widget.fileName);
                
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
