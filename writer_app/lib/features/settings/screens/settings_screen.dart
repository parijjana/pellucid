// @trace FEAT-20260517-115000-0004
// Description: Unified Settings Dashboard (Setup, Projects, Statistics).

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import '../providers/settings_provider.dart';
import '../../editor/providers/editor_provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/widgets/integrated_header.dart';
import '../../sidebar/providers/notes_provider.dart';
import '../providers/history_provider.dart';
import '../widgets/project_card.dart';
import '../../editor/services/export_service.dart';
import '../../sync/providers/sync_provider.dart';
import '../../editor/widgets/shortcuts.dart';

enum ProjectSort { date, name }

class SettingsScreen extends StatefulWidget {
  final bool isFullscreen;
  const SettingsScreen({super.key, this.isFullscreen = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _exportService = ExportService();
  final _searchController = TextEditingController();
  ProjectSort _sortType = ProjectSort.date;
  bool _invertSort = false;

  bool _isSetupExpanded = true;
  bool _isProjectsExpanded = true;
  bool _isStatsExpanded = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleSyncLogin(SyncProvider sync) async {
    try {
      final success = await sync.login();
      if (success && mounted) {
        final settings = context.read<SettingsProvider>();
        final editor = context.read<EditorProvider>();
        final notes = context.read<NotesProvider>();
        
        if (settings.currentProjectName != null) {
          await sync.syncCurrentFile(
            projectName: settings.currentProjectName!,
            fileName: 'manuscript',
            content: editor.content,
          );
          final notesJson = jsonEncode(notes.cards.map((c) => c.toJson()).toList());
          await sync.syncNotes(projectName: settings.currentProjectName!, notesJson: notesJson);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connected and synced to Google Drive.'))
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cloud connection failed: $e')));
      }
    }
  }

  Future<void> _exportPdf(BuildContext context, String content, String projectName, String? projectPath) async {
    final FileSaveLocation? result = await getSaveLocation(
      suggestedName: '$projectName.pdf',
      initialDirectory: projectPath,
      acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
    );
    if (result == null) return;
    try {
      await _exportService.exportToPdf(content, result.path);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to ${result.path}')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _exportEpub(BuildContext context, String content, String projectName, String? projectPath) async {
    final FileSaveLocation? result = await getSaveLocation(
      suggestedName: '$projectName.epub',
      initialDirectory: projectPath,
      acceptedTypeGroups: [const XTypeGroup(label: 'EPUB', extensions: ['epub'])],
    );
    if (result == null) return;
    try {
      await _exportService.exportToEpub(
        markdown: content,
        title: projectName,
        author: 'Pellucid',
        filePath: result.path,
      );
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to ${result.path}')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  List<ProjectInfo> _getFilteredAndSortedProjects(List<ProjectInfo> projects) {
    final query = _searchController.text.toLowerCase();
    var filtered = projects.where((p) => p.name.toLowerCase().contains(query)).toList();

    filtered.sort((a, b) {
      int result;
      if (_sortType == ProjectSort.date) {
        result = projects.indexOf(b).compareTo(projects.indexOf(a));
      } else {
        result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _invertSort ? -result : result;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final settings = context.watch<SettingsProvider>();
    final editor = context.watch<EditorProvider>();
    final sync = context.watch<SyncProvider>();
    final history = context.watch<HistoryProvider>();

    final bool isMac = Platform.isMacOS;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.digit4, alt: !isMac, meta: isMac, control: isMac): const OpenSettingsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(onInvoke: (_) {
            Navigator.pop(context);
            return null;
          }),
        },
        child: Scaffold(
          backgroundColor: theme.backgroundColor,
          body: Column(
            children: [
              IntegratedHeader(
                theme: theme,
                showWindowControls: !widget.isFullscreen,
                actionButton: IconButton(
                  icon: Icon(Icons.arrow_back, size: 20, color: theme.foregroundColor.withValues(alpha: 0.4)),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Back',
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- PART 1: SETUP ---
                      _collapsibleHeader(
                        title: 'Setup',
                        theme: theme,
                        isExpanded: _isSetupExpanded,
                        onToggle: () => setState(() => _isSetupExpanded = !_isSetupExpanded),
                      ),
                      if (_isSetupExpanded) ...[
                        const SizedBox(height: 24),
                        _buildFolderPicker(settings, theme),
                        const SizedBox(height: 32),
                        _buildSyncTile(sync, theme, settings.masterDirectoryPath != null),
                        if (sync.lastSynced != null) ...[
                          const SizedBox(height: 8),
                          Text('Last synced: ${_formatDateTime(sync.lastSynced!)}',
                            style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.3), fontSize: 11, fontStyle: FontStyle.italic)),
                        ],
                        const SizedBox(height: 32),
                        _subHeader('Focus & Productivity', theme),
                        _buildFocusToggles(settings, theme),
                        const SizedBox(height: 32),
                        _subHeader('Appearance', theme),
                        const SizedBox(height: 16),
                        _buildThemeGrid(context, theme),
                      ],

                      const SizedBox(height: 60),

                      // --- PART 2: PROJECTS ---
                      _collapsibleHeader(
                        title: 'Projects',
                        theme: theme,
                        isExpanded: _isProjectsExpanded,
                        onToggle: () => setState(() => _isProjectsExpanded = !_isProjectsExpanded),
                      ),
                      if (_isProjectsExpanded) ...[
                        const SizedBox(height: 24),
                        if (settings.masterDirectoryPath != null) ...[
                          _buildProjectControls(theme),
                          const SizedBox(height: 16),
                          _buildProjectArea(settings, theme),
                          const SizedBox(height: 40),
                          _subHeader('Publish & Export', theme),
                          const SizedBox(height: 16),
                          _buildExportOptions(context, theme, editor.content, settings.currentProjectName ?? 'Untitled', settings.currentProjectPath),
                        ] else ...[
                          _buildPlaceholderTile('Please select a Master Storage Folder to view projects.', theme),
                        ],
                      ],

                      const SizedBox(height: 60),

                      // --- PART 3: STATISTICS ---
                      _collapsibleHeader(
                        title: 'Statistics',
                        theme: theme,
                        isExpanded: _isStatsExpanded,
                        onToggle: () => setState(() => _isStatsExpanded = !_isStatsExpanded),
                      ),
                      if (_isStatsExpanded) ...[
                        const SizedBox(height: 24),
                        _buildStatisticsArea(history, theme),
                      ],
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collapsibleHeader({required String title, required WriterTheme theme, required bool isExpanded, required VoidCallback onToggle}) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _sectionHeader(title, theme),
          Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: theme.foregroundColor.withValues(alpha: 0.3),
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, WriterTheme theme) {
    return Text(title.toUpperCase(),
      style: TextStyle(color: theme.foregroundColor, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 4));
  }

  Widget _subHeader(String title, WriterTheme theme) {
    return Text(title.toUpperCase(),
      style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5));
  }

  Widget _buildProjectControls(WriterTheme theme) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() {}),
            style: TextStyle(color: theme.foregroundColor, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search projects...',
              hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2)),
              prefixIcon: Icon(Icons.search, size: 16, color: theme.foregroundColor.withValues(alpha: 0.3)),
              filled: true,
              fillColor: theme.sidebarColor.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 16),
        _sortButton(theme),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(_invertSort ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
          color: theme.foregroundColor.withValues(alpha: 0.4),
          onPressed: () => setState(() => _invertSort = !_invertSort),
          tooltip: 'Invert Sort',
        ),
      ],
    );
  }

  Widget _sortButton(WriterTheme theme) {
    return PopupMenuButton<ProjectSort>(
      initialValue: _sortType,
      onSelected: (val) => setState(() => _sortType = val),
      color: theme.sidebarColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.sidebarColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(_sortType == ProjectSort.date ? 'Recent' : 'Name', 
              style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6), fontSize: 12)),
            const SizedBox(width: 4),
            Icon(Icons.sort, size: 14, color: theme.foregroundColor.withValues(alpha: 0.4)),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: ProjectSort.date, child: Text('Sort by Date')),
        const PopupMenuItem(value: ProjectSort.name, child: Text('Sort by Name')),
      ],
    );
  }

  Widget _buildProjectArea(SettingsProvider settings, WriterTheme theme) {
    final filtered = _getFilteredAndSortedProjects(settings.availableProjects);
    
    return Container(
      height: 320, // Generous height for ~2 rows
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.sidebarColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.05)),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
        ),
        itemCount: filtered.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return NewProjectCard(
              theme: theme,
              onTap: () => _showCreateProjectDialog(context, settings, theme),
            );
          }
          final project = filtered[index - 1];
          return ProjectCard(
            name: project.name,
            wordCount: project.stats.totalWordCount,
            timeSpent: project.stats.totalTimeSpent,
            isActive: settings.currentProjectName == project.name,
            theme: theme,
            onTap: () async {
              final editorProvider = context.read<EditorProvider>();
              final syncProvider = context.read<SyncProvider>();
              final notesProvider = context.read<NotesProvider>();
              final historyProvider = context.read<HistoryProvider>();

              await editorProvider.flushSync(
                syncProvider: syncProvider,
                projectName: settings.currentProjectName,
              );
              await settings.setCurrentProject(project.name);
              if (mounted) {
                final path = settings.currentProjectPath;
                await editorProvider.loadProject(path);
                await notesProvider.loadProject(path, projectName: project.name);
                await historyProvider.loadProjectStats(path);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildStatisticsArea(HistoryProvider history, WriterTheme theme) {
    final stats = history.history.take(7).toList().reversed.toList();
    if (stats.isEmpty) return _buildPlaceholderTile('No writing history recorded yet.', theme);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.sidebarColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBarChart(stats, theme),
          const SizedBox(height: 40),
          _subHeader('Key Metrics', theme),
          const SizedBox(height: 16),
          _buildStatRow('Words Written Today', '${history.todayStats?.wordCountDelta ?? 0}', theme),
          _buildStatRow('Cumulative Time Spent', _formatHours(history.currentProjectStats.totalTimeSpent), theme),
          _buildStatRow('Project Word Count', '${history.currentProjectStats.totalWordCount}', theme),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<DailyStats> stats, WriterTheme theme) {
    final maxSeconds = stats.map((s) => s.editorTime.inSeconds + s.notesTime.inSeconds).fold(1, max);
    final maxWords = stats.map((s) => s.wordCountDelta.abs()).fold(1, max);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: stats.map((s) => _buildBar(s, maxSeconds, maxWords, theme)).toList(),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem('Editor', Colors.blue, theme),
            const SizedBox(width: 16),
            _legendItem('Notes', Colors.green, theme),
            const SizedBox(width: 16),
            _legendItem('Words', Colors.orange, theme),
          ],
        ),
      ],
    );
  }

  Widget _buildBar(DailyStats s, int maxSeconds, int maxWords, WriterTheme theme) {
    const double maxHeight = 120.0;
    final totalSeconds = s.editorTime.inSeconds + s.notesTime.inSeconds;
    final editorHeight = totalSeconds == 0 ? 0.0 : (s.editorTime.inSeconds / maxSeconds) * maxHeight;
    final notesHeight = totalSeconds == 0 ? 0.0 : (s.notesTime.inSeconds / maxSeconds) * maxHeight;
    final wordDotPosition = (s.wordCountDelta.abs() / maxWords) * maxHeight;

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 20,
              height: editorHeight + notesHeight,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2)),
              child: Column(
                children: [
                  Container(height: notesHeight, width: 20, color: Colors.green.withValues(alpha: 0.4)),
                  Container(height: editorHeight, width: 20, color: Colors.blue.withValues(alpha: 0.4)),
                ],
              ),
            ),
            Positioned(
              bottom: wordDotPosition,
              child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(s.date.split('-').last, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4), fontSize: 9)),
      ],
    );
  }

  Widget _legendItem(String label, Color color, WriterTheme theme) {
    return Row(
      children: [
        Container(width: 8, height: 8, color: color.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.5), fontSize: 10)),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, WriterTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6), fontSize: 13)),
          Text(value, style: TextStyle(color: theme.foregroundColor, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatHours(Duration d) {
    final hours = d.inSeconds / 3600;
    return '${hours.toStringAsFixed(1)} hrs';
  }

  String _formatDateTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  // --- REUSED UI HELPERS ---
  Widget _buildSyncTile(SyncProvider sync, WriterTheme theme, bool isFolderSelected) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.sidebarColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(sync.isLoggedIn ? Icons.cloud_done : Icons.cloud_off, color: sync.isLoggedIn ? Colors.blue : theme.foregroundColor.withValues(alpha: 0.2)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sync.isLoggedIn ? 'Google Drive Connected' : 'Cloud Sync Off',
                  style: TextStyle(color: theme.foregroundColor, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(!isFolderSelected ? 'Select Master Folder first.' : 'Automated backups to Pellucid Vault.',
                  style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4), fontSize: 11)),
              ],
            ),
          ),
          if (!sync.isLoggedIn)
            ElevatedButton(
              onPressed: isFolderSelected ? () => _handleSyncLogin(sync) : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, elevation: 0),
              child: const Text('CONNECT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            )
          else
            TextButton(onPressed: sync.logout, child: Text('DISCONNECT', style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2), fontSize: 10))),
        ],
      ),
    );
  }

  Widget _buildFolderPicker(SettingsProvider settings, WriterTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subHeader('Master Storage Folder', theme),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: theme.sidebarColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                child: Text(settings.masterDirectoryPath ?? 'No folder selected',
                  style: TextStyle(color: theme.foregroundColor.withValues(alpha: settings.masterDirectoryPath == null ? 0.2 : 0.7), fontSize: 12, overflow: TextOverflow.ellipsis)),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: () async {
              final path = await getDirectoryPath();
              if (path != null) settings.setMasterDirectory(path);
            }, child: const Text('SELECT')),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeGrid(BuildContext context, WriterTheme current) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.5),
      itemCount: WriterTheme.presets.length,
      itemBuilder: (context, index) {
        final t = WriterTheme.presets[index];
        final isSelected = t.name == current.name;
        return GestureDetector(
          onTap: () => context.read<ThemeProvider>().setTheme(t),
          child: Container(
            decoration: BoxDecoration(
              color: t.backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? Colors.blue : t.foregroundColor.withValues(alpha: 0.1), width: isSelected ? 2 : 1),
            ),
            child: Center(child: Text(t.name, style: TextStyle(color: t.foregroundColor, fontSize: 10, fontWeight: FontWeight.w600))),
          ),
        );
      },
    );
  }

  Widget _buildFocusToggles(SettingsProvider settings, WriterTheme theme) {
    return Column(
      children: [
        _buildToggleRow(label: 'Display Clock', value: settings.clockEnabled, onChanged: settings.toggleClock, theme: theme),
        _buildToggleRow(label: 'Session Timer', value: settings.currentSessionEnabled, onChanged: settings.toggleCurrentSession, theme: theme),
        _buildToggleRow(label: 'Focus Timer', value: settings.focusTimerEnabled, onChanged: settings.toggleFocusTimer, theme: theme),
        _buildToggleRow(label: 'Battery Guard', value: settings.batteryGuardEnabled, onChanged: settings.toggleBatteryGuard, theme: theme),
        if (settings.batteryGuardEnabled) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildToggleRow(
              label: 'Show Battery Percentage',
              value: settings.showBatteryPercentage,
              onChanged: settings.toggleShowBatteryPercentage,
              theme: theme,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Battery Alert Threshold', style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6), fontSize: 13)),
                DropdownButton<int>(
                  value: settings.batteryAlertThreshold,
                  dropdownColor: theme.sidebarColor,
                  style: TextStyle(color: theme.foregroundColor, fontSize: 13),
                  underline: const SizedBox(),
                  onChanged: (int? value) {
                    if (value != null) {
                      settings.setBatteryAlertThreshold(value);
                    }
                  },
                  items: [10, 15, 20, 25, 30].map<DropdownMenuItem<int>>((int value) {
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value%'),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToggleRow({required String label, required bool value, required Function(bool) onChanged, required WriterTheme theme}) {
    return SwitchListTile(
      title: Text(label, style: TextStyle(color: theme.foregroundColor, fontSize: 13)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.blue,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildExportOptions(BuildContext context, WriterTheme theme, String content, String projectName, String? projectPath) {
    return Row(
      children: [
        _exportCard(title: 'PDF', icon: Icons.picture_as_pdf, theme: theme, onTap: () => _exportPdf(context, content, projectName, projectPath)),
        const SizedBox(width: 12),
        _exportCard(title: 'EPUB', icon: Icons.book, theme: theme, onTap: () => _exportEpub(context, content, projectName, projectPath)),
      ],
    );
  }

  Widget _exportCard({required String title, required IconData icon, required WriterTheme theme, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: theme.sidebarColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.05))),
          child: Column(
            children: [
              Icon(icon, color: theme.foregroundColor.withValues(alpha: 0.4), size: 20),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderTile(String label, WriterTheme theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: theme.sidebarColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.3), fontSize: 13, fontStyle: FontStyle.italic)),
    );
  }

  void _showCreateProjectDialog(BuildContext context, SettingsProvider settings, WriterTheme theme) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.sidebarColor,
        title: Text('New Project', style: TextStyle(color: theme.foregroundColor)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.foregroundColor),
          decoration: InputDecoration(hintText: 'Project Name', hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final editorProvider = context.read<EditorProvider>();
                final syncProvider = context.read<SyncProvider>();
                final notesProvider = context.read<NotesProvider>();
                final historyProvider = context.read<HistoryProvider>();
                final navigator = Navigator.of(context);

                await editorProvider.flushSync(
                  syncProvider: syncProvider,
                  projectName: settings.currentProjectName,
                );
                await settings.createProject(controller.text);
                if (mounted) {
                  final path = settings.currentProjectPath;
                  await editorProvider.loadProject(path);
                  await notesProvider.loadProject(path, projectName: controller.text);
                  await historyProvider.loadProjectStats(path);
                  navigator.pop();
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
