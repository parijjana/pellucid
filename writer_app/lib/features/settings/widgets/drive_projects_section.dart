// Description: The library's Drive -> local half. Until this existed, nothing
// in the app enumerated the Drive vault, so a project written on the Mac was
// invisible on a fresh iPad even while signed in to the same account: sync
// was upload-only in both directions of the UI as well as the code.
//
// Deliberately not automatic. A pull writes a project onto this device, and
// silently materialising folders behind the user's back is the kind of thing
// that turns a sync bug into a support thread. Discovery is a button; each
// pull is a button.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../editor/providers/storage_service.dart';
import '../../editor/providers/theme_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../../sync/services/project_pull.dart';
import '../providers/settings_provider.dart';

class DriveProjectsSection extends StatefulWidget {
  final WriterTheme theme;

  /// Injectable for tests; defaults to the real local filesystem.
  final StorageService? storageService;

  const DriveProjectsSection({
    super.key,
    required this.theme,
    this.storageService,
  });

  @override
  State<DriveProjectsSection> createState() => _DriveProjectsSectionState();
}

class _DriveProjectsSectionState extends State<DriveProjectsSection> {
  late final StorageService _storage = widget.storageService ?? StorageService();

  List<RemoteProject>? _remote;
  bool _isLoading = false;
  String? _pullingProject;

  Future<void> _refresh() async {
    final settings = context.read<SettingsProvider>();
    final sync = context.read<SyncProvider>();
    final masterPath = settings.masterDirectoryPath;
    if (masterPath == null) return;

    setState(() => _isLoading = true);
    final remote = await sync.listRemoteProjects(
      masterPath: masterPath,
      storageService: _storage,
    );
    if (!mounted) return;
    setState(() {
      _remote = remote;
      _isLoading = false;
    });
  }

  Future<void> _pull(String projectName) async {
    final settings = context.read<SettingsProvider>();
    final sync = context.read<SyncProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final masterPath = settings.masterDirectoryPath;
    if (masterPath == null) return;

    setState(() => _pullingProject = projectName);
    final result = await sync.pullProject(
      projectName: projectName,
      masterPath: masterPath,
      storageService: _storage,
    );
    if (result.succeeded) {
      // The project came FROM Drive, so another device owns it. Recording that
      // is what makes the first edit fork instead of writing in place.
      await settings.markProjectMirrored(result.projectName);
    }
    // The local library changed underneath the grid above, and the pulled
    // project must stop being offered as a pull.
    await settings.refreshProjects();
    if (!mounted) return;
    setState(() => _pullingProject = null);

    messenger.showSnackBar(SnackBar(content: Text(_messageFor(result))));
    await _refresh();
  }

  /// Every outcome says something specific. "Something went wrong" on a path
  /// that touches a user's only copy of a manuscript is not good enough.
  String _messageFor(PullResult result) {
    switch (result.outcome) {
      case PullOutcome.pulled:
        final skipped = result.filesSkipped;
        if (skipped.isEmpty) {
          return 'Copied "${result.projectName}" from Drive. It tracks Drive — '
            'your first edit makes an editable copy.';
        }
        final names = skipped.map((f) => f.name).join(' and ');
        return 'Copied "${result.projectName}", but its $names could not be read '
            'and were left in Drive.';
      case PullOutcome.alreadyExistsLocally:
        return '"${result.projectName}" is already on this device. It was not '
            'touched.';
      case PullOutcome.notLoggedIn:
        return 'Sign in to Google Drive first.';
      case PullOutcome.noManuscript:
        return '"${result.projectName}" has no manuscript in Drive yet.';
      case PullOutcome.ambiguousManuscript:
        return '"${result.projectName}" has two manuscript files in Drive and '
            'neither can be dated. Open it on the desktop first.';
      case PullOutcome.failed:
        return 'Could not copy "${result.projectName}": ${result.error}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final sync = context.watch<SyncProvider>();
    final fg = theme.foregroundColor;

    if (!sync.isLoggedIn) {
      return Text(
        'Sign in to Google Drive to see projects saved from your other devices.',
        style: TextStyle(color: fg.withValues(alpha: 0.5), fontSize: 13),
      );
    }

    final remote = _remote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                remote == null
                    ? 'Projects saved to Drive from your other devices.'
                    : remote.isEmpty
                        ? 'No projects found in your Drive vault.'
                        : '${remote.where((p) => p.isPullable).length} of '
                            '${remote.length} not on this device.',
                style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: _isLoading ? null : _refresh,
              icon: _isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  : Icon(Icons.cloud_download_outlined, size: 16, color: fg),
              label: Text(
                remote == null ? 'Check Drive' : 'Refresh',
                style: TextStyle(color: fg),
              ),
            ),
          ],
        ),
        if (remote != null && remote.isNotEmpty)
          ...remote.map((project) => _row(project, theme)),
      ],
    );
  }

  Widget _row(RemoteProject project, WriterTheme theme) {
    final fg = theme.foregroundColor;
    final isPulling = _pullingProject == project.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            project.isPullable ? Icons.cloud_outlined : Icons.check,
            size: 16,
            color: fg.withValues(alpha: project.isPullable ? 0.7 : 0.35),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              project.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg.withValues(alpha: project.isPullable ? 0.9 : 0.45),
                fontSize: 14,
              ),
            ),
          ),
          if (project.isPullable)
            TextButton(
              onPressed: isPulling ? null : () => _pull(project.name),
              child: Text(
                isPulling ? 'Copying…' : 'Copy here',
                style: TextStyle(color: fg),
              ),
            )
          else
            Text(
              'On this device',
              style: TextStyle(color: fg.withValues(alpha: 0.4), fontSize: 12),
            ),
        ],
      ),
    );
  }
}
