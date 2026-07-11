import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pellucid/main.dart'; // Import the global navigatorKey
import '../providers/editor_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/shortcuts_provider.dart';
import '../widgets/shortcuts.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/providers/history_provider.dart';
import '../../sidebar/providers/notes_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../services/export_service.dart';

class SettingsMenuBarState {
  final String? currentProjectName;
  final List<String> projectNames;
  final String? masterDirectoryPath;
  final bool clockEnabled;
  final bool currentSessionEnabled;
  final bool focusTimerEnabled;
  final bool batteryGuardEnabled;
  final String? googleClientId;
  final String? googleClientSecret;
  final bool typewriterScrolling;

  SettingsMenuBarState({
    required this.currentProjectName,
    required this.projectNames,
    required this.masterDirectoryPath,
    required this.clockEnabled,
    required this.currentSessionEnabled,
    required this.focusTimerEnabled,
    required this.batteryGuardEnabled,
    required this.googleClientId,
    required this.googleClientSecret,
    required this.typewriterScrolling,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsMenuBarState &&
        other.currentProjectName == currentProjectName &&
        _listEquals(other.projectNames, projectNames) &&
        other.masterDirectoryPath == masterDirectoryPath &&
        other.clockEnabled == clockEnabled &&
        other.currentSessionEnabled == currentSessionEnabled &&
        other.focusTimerEnabled == focusTimerEnabled &&
        other.batteryGuardEnabled == batteryGuardEnabled &&
        other.googleClientId == googleClientId &&
        other.googleClientSecret == googleClientSecret &&
        other.typewriterScrolling == typewriterScrolling;
  }

  @override
  int get hashCode => Object.hash(
        currentProjectName,
        Object.hashAll(projectNames),
        masterDirectoryPath,
        clockEnabled,
        currentSessionEnabled,
        focusTimerEnabled,
        batteryGuardEnabled,
        googleClientId,
        googleClientSecret,
        typewriterScrolling,
      );

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class MacMenuBarWrapper extends StatelessWidget {
  final Widget child;
  const MacMenuBarWrapper({super.key, required this.child});

  BuildContext _getBestContext(BuildContext context) {
    return navigatorKey.currentContext ?? context;
  }

  Future<void> _switchProject(BuildContext context, SettingsProvider settings, String name) async {
    final editorProvider = context.read<EditorProvider>();
    final syncProvider = context.read<SyncProvider>();
    final notesProvider = context.read<NotesProvider>();
    final historyProvider = context.read<HistoryProvider>();

    // 1. Flush/save current project stats and sync
    await historyProvider.saveStatsNow();
    await editorProvider.flushSync(
      syncProvider: syncProvider,
      projectName: settings.currentProjectName,
    );

    // 2. Change the current project setting
    await settings.setCurrentProject(name);

    // 3. Load the new project data
    final path = settings.currentProjectPath;
    await editorProvider.loadProject(path);
    await notesProvider.loadProject(path, projectName: name);
    await historyProvider.loadProjectStats(path);
    await settings.refreshProjects();
  }

  Future<void> _handleNewProjectCreation(BuildContext context, SettingsProvider settings, String name) async {
    final editorProvider = context.read<EditorProvider>();
    final syncProvider = context.read<SyncProvider>();
    final notesProvider = context.read<NotesProvider>();
    final historyProvider = context.read<HistoryProvider>();

    // 1. Flush/save current project stats and sync
    await historyProvider.saveStatsNow();
    await editorProvider.flushSync(
      syncProvider: syncProvider,
      projectName: settings.currentProjectName,
    );

    // 2. Create the new project
    await settings.createProject(name);

    // 3. Load the new project data
    final path = settings.currentProjectPath;
    await editorProvider.loadProject(path);
    await notesProvider.loadProject(path, projectName: name);
    await historyProvider.loadProjectStats(path);
  }

  Future<void> _handleRenameProject(BuildContext context, SettingsProvider settings, String currentProject, String newName) async {
    final editorProvider = context.read<EditorProvider>();
    final notesProvider = context.read<NotesProvider>();
    final historyProvider = context.read<HistoryProvider>();

    final success = await settings.renameProject(currentProject, newName);
    if (success && context.mounted) {
      final path = settings.currentProjectPath;
      await editorProvider.loadProject(path);
      await notesProvider.loadProject(path, projectName: newName);
      await historyProvider.loadProjectStats(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!Platform.isMacOS || isTest) return child;

    final themeProvider = context.watch<ThemeProvider>();
    final syncProvider = context.watch<SyncProvider>();

    return Selector<SettingsProvider, SettingsMenuBarState>(
      selector: (context, settings) => SettingsMenuBarState(
        currentProjectName: settings.currentProjectName,
        projectNames: settings.availableProjects.map((p) => p.name).toList(),
        masterDirectoryPath: settings.masterDirectoryPath,
        clockEnabled: settings.clockEnabled,
        currentSessionEnabled: settings.currentSessionEnabled,
        focusTimerEnabled: settings.focusTimerEnabled,
        batteryGuardEnabled: settings.batteryGuardEnabled,
        googleClientId: settings.googleClientId,
        googleClientSecret: settings.googleClientSecret,
        typewriterScrolling: settings.typewriterScrolling,
      ),
      builder: (context, settingsState, _) {
        final settings = context.read<SettingsProvider>();

        return PlatformMenuBar(
          menus: [
            PlatformMenu(
              label: 'Pellucid',
              menus: [
                PlatformMenuItem(
                  label: 'About Pellucid',
                  onSelected: () => _showAboutDialog(_getBestContext(context)),
                ),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
              ],
            ),
            PlatformMenu(
              label: 'File',
              menus: [
                PlatformMenuItem(
                  label: 'Select Master Storage Folder...',
                  onSelected: () async {
                    final path = await getDirectoryPath();
                    if (path != null) {
                      await settings.setMasterDirectory(path);
                    }
                  },
                ),
                const PlatformMenuItemGroup(members: []),
                PlatformMenu(
                  label: 'Export Manuscript',
                  menus: [
                    PlatformMenuItem(
                      label: 'As PDF...',
                      onSelected: () => _exportPdf(_getBestContext(context)),
                    ),
                    PlatformMenuItem(
                      label: 'As EPUB...',
                      onSelected: () => _exportEpub(_getBestContext(context)),
                    ),
                  ],
                ),
              ],
            ),
            PlatformMenu(
              label: 'Edit',
              menus: [
                PlatformMenuItem(
                  label: 'Undo',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const UndoTextIntent(SelectionChangedCause.keyboard));
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Redo',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const RedoTextIntent(SelectionChangedCause.keyboard));
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Cut',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard));
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Copy',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, CopySelectionTextIntent.copy);
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Paste',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const PasteTextIntent(SelectionChangedCause.keyboard));
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Select All',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const SelectAllTextIntent(SelectionChangedCause.keyboard));
                    }
                  },
                ),
                const PlatformMenuItemGroup(members: []),
                PlatformMenuItem(
                  label: 'Find...',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ToggleSearchIntent());
                    }
                  },
                ),
              ],
            ),
            PlatformMenu(
              label: 'Projects',
              menus: [
                PlatformMenuItem(
                  label: 'New Project...',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
                  onSelected: () => _showNewProjectPrompt(_getBestContext(context), settings),
                ),
                PlatformMenuItem(
                  label: 'Rename Current Project...',
                  onSelected: (settingsState.currentProjectName == null || settingsState.currentProjectName == 'User Manual')
                      ? null
                      : () => _showRenameProjectPrompt(_getBestContext(context), settings),
                ),
                const PlatformMenuItemGroup(members: []),
                PlatformMenu(
                  label: 'Load Project',
                  menus: settingsState.projectNames.map((name) {
                    final isCurrent = name == settingsState.currentProjectName;
                    return PlatformMenuItem(
                      label: isCurrent ? '✓ $name' : '   $name',
                      onSelected: () => _switchProject(_getBestContext(context), settings, name),
                    );
                  }).toList(),
                ),
              ],
            ),
            PlatformMenu(
              label: 'Sync',
              menus: [
                if (!syncProvider.isLoggedIn)
                  PlatformMenuItem(
                    label: 'Connect Google Drive...',
                    onSelected: settingsState.masterDirectoryPath == null
                        ? null
                        : () => _handleSyncLogin(_getBestContext(context), syncProvider, settingsState),
                  ),
                if (syncProvider.isLoggedIn)
                  PlatformMenuItem(
                    label: 'Disconnect Google Drive',
                    onSelected: () => syncProvider.logout(),
                  ),
                PlatformMenuItem(
                  label: 'Configure Credentials...',
                  onSelected: () => _showCredentialsPrompt(_getBestContext(context), settings),
                ),
                const PlatformMenuItemGroup(members: []),
                PlatformMenuItem(
                  label: 'Sync Now',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
                  onSelected: (settingsState.currentProjectName == null || !syncProvider.isLoggedIn)
                      ? null
                      : () => _triggerManualSync(_getBestContext(context), syncProvider, settingsState),
                ),
              ],
            ),
            PlatformMenu(
              label: 'Themes',
              menus: [
                ...WriterTheme.presets.map((theme) {
                  final isCurrent = theme.name == themeProvider.currentTheme.name;
                  return PlatformMenuItem(
                    label: isCurrent ? '✓ ${theme.name}' : '   ${theme.name}',
                    onSelected: () => themeProvider.setTheme(theme),
                  );
                }),
                const PlatformMenuItemGroup(members: []),
                PlatformMenu(
                  label: 'Mac-Matched Themes',
                  menus: [
                    if (themeProvider.macMatchedTheme != null) ...[
                      PlatformMenuItem(
                        label: themeProvider.currentTheme.name == themeProvider.macMatchedTheme!.name
                            ? '✓ Match My Mac (Detected: ${themeProvider.macColorName})'
                            : '   Match My Mac (Detected: ${themeProvider.macColorName})',
                        onSelected: () => themeProvider.setTheme(themeProvider.macMatchedTheme!),
                      ),
                      const PlatformMenuItemGroup(members: []),
                    ],
                    ...WriterTheme.macMatchedPresets.map((theme) {
                      final isCurrent = theme.name == themeProvider.currentTheme.name;
                      return PlatformMenuItem(
                        label: isCurrent ? '✓ ${theme.name}' : '   ${theme.name}',
                        onSelected: () => themeProvider.setTheme(theme),
                      );
                    }),
                  ],
                ),
              ],
            ),
            PlatformMenu(
              label: 'View',
              menus: [
                PlatformMenuItem(
                  label: 'Toggle Table of Contents (Left Sidebar)',
                  shortcut: const SingleActivator(LogicalKeyboardKey.digit1, alt: true, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ToggleToCIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Toggle Research Notes (Right Sidebar)',
                  shortcut: const SingleActivator(LogicalKeyboardKey.digit2, alt: true, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ToggleNotesIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Toggle Formatting Toolbar',
                  shortcut: const SingleActivator(LogicalKeyboardKey.digit3, alt: true, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ToggleToolbarIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: settingsState.typewriterScrolling ? '✓ Typewriter Scrolling' : '   Typewriter Scrolling',
                  shortcut: const SingleActivator(LogicalKeyboardKey.digit5, alt: true, meta: true),
                  onSelected: () => settings.toggleTypewriterScrolling(!settingsState.typewriterScrolling),
                ),
                const PlatformMenuItemGroup(members: []),
                PlatformMenuItem(
                  label: 'Toggle Full Screen',
                  shortcut: const SingleActivator(LogicalKeyboardKey.enter, alt: true, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ToggleFullscreenIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Zoom In',
                  shortcut: const SingleActivator(LogicalKeyboardKey.equal, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ZoomInIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Zoom Out',
                  shortcut: const SingleActivator(LogicalKeyboardKey.minus, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ZoomOutIntent());
                    }
                  },
                ),
              ],
            ),
            PlatformMenu(
              label: 'Tools',
              menus: [
                PlatformMenuItem(
                  label: 'Show Writing Statistics...',
                  onSelected: () => _showStatsOverlay(_getBestContext(context)),
                ),
                const PlatformMenuItemGroup(members: []),
                PlatformMenu(
                  label: 'Status Bar Features',
                  menus: [
                    PlatformMenuItem(
                      label: settingsState.clockEnabled ? '✓ Show Clock' : '   Show Clock',
                      onSelected: () => settings.toggleClock(!settingsState.clockEnabled),
                    ),
                    PlatformMenuItem(
                      label: settingsState.currentSessionEnabled ? '✓ Show Session Timer' : '   Show Session Timer',
                      onSelected: () => settings.toggleCurrentSession(!settingsState.currentSessionEnabled),
                    ),
                    PlatformMenuItem(
                      label: settingsState.focusTimerEnabled ? '✓ Show Focus Timer' : '   Show Focus Timer',
                      onSelected: () => settings.toggleFocusTimer(!settingsState.focusTimerEnabled),
                    ),
                    PlatformMenuItem(
                      label: settingsState.batteryGuardEnabled ? '✓ Show Battery Guard' : '   Show Battery Guard',
                      onSelected: () => settings.toggleBatteryGuard(!settingsState.batteryGuardEnabled),
                    ),
                  ],
                ),
                const PlatformMenuItemGroup(members: []),
                PlatformMenuItem(
                  label: 'Peek Clock',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyC, alt: true, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const PeekClockIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Set Alarm...',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyA, alt: true, meta: true, shift: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const SetAlarmIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Peek Session Stats',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyS, alt: true, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const PeekSessionIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Start/Pause Pomodoro Timer',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyP, alt: true, meta: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const TogglePomodoroIntent());
                    }
                  },
                ),
                PlatformMenuItem(
                  label: 'Reset Pomodoro Timer',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyP, alt: true, meta: true, shift: true),
                  onSelected: () {
                    final contextNode = FocusManager.instance.primaryFocus?.context;
                    if (contextNode != null) {
                      Actions.maybeInvoke(contextNode, const ResetPomodoroIntent());
                    }
                  },
                ),
              ],
            ),
          ],
          child: child,
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Pellucid',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 Pellucid. All rights reserved.',
      applicationIcon: const FlutterLogo(size: 32),
    );
  }

  void _exportPdf(BuildContext context) async {
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    final projectName = settings.currentProjectName ?? 'manuscript';
    final projectPath = settings.currentProjectPath;
    final content = editor.content;

    final FileSaveLocation? result = await getSaveLocation(
      suggestedName: '$projectName.pdf',
      initialDirectory: projectPath,
      acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
    );
    if (result == null) return;
    try {
      await ExportService().exportToPdf(content, result.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to ${result.path}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _exportEpub(BuildContext context) async {
    final editor = context.read<EditorProvider>();
    final settings = context.read<SettingsProvider>();
    final projectName = settings.currentProjectName ?? 'manuscript';
    final projectPath = settings.currentProjectPath;
    final content = editor.content;

    final FileSaveLocation? result = await getSaveLocation(
      suggestedName: '$projectName.epub',
      initialDirectory: projectPath,
      acceptedTypeGroups: [const XTypeGroup(label: 'EPUB', extensions: ['epub'])],
    );
    if (result == null) return;
    try {
      await ExportService().exportToEpub(
        markdown: content,
        title: projectName,
        author: 'Pellucid',
        filePath: result.path,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to ${result.path}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _showNewProjectPrompt(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        final theme = context.read<ThemeProvider>().currentTheme;
        return AlertDialog(
          backgroundColor: theme.backgroundColor,
          title: Text('New Project', style: TextStyle(color: theme.foregroundColor)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: theme.foregroundColor),
            decoration: InputDecoration(
              hintText: 'Project Name',
              hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.3))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6))),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  await _handleNewProjectCreation(context, settings, name);
                }
              },
              child: Text('Create', style: TextStyle(color: theme.foregroundColor)),
            ),
          ],
        );
      },
    );
  }

  void _showRenameProjectPrompt(BuildContext context, SettingsProvider settings) {
    final currentProject = settings.currentProjectName;
    if (currentProject == null || currentProject == 'User Manual') return;
    final controller = TextEditingController(text: currentProject);
    showDialog(
      context: context,
      builder: (context) {
        final theme = context.read<ThemeProvider>().currentTheme;
        return AlertDialog(
          backgroundColor: theme.backgroundColor,
          title: Text('Rename Project', style: TextStyle(color: theme.foregroundColor)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: theme.foregroundColor),
            decoration: InputDecoration(
              hintText: 'New Project Name',
              hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.3))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6))),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty && name != currentProject) {
                  Navigator.pop(context);
                  await _handleRenameProject(context, settings, currentProject, name);
                }
              },
              child: Text('Rename', style: TextStyle(color: theme.foregroundColor)),
            ),
          ],
        );
      },
    );
  }

  void _showCredentialsPrompt(BuildContext context, SettingsProvider settings) {
    final clientController = TextEditingController(text: settings.googleClientId ?? '');
    final secretController = TextEditingController(text: settings.googleClientSecret ?? '');
    showDialog(
      context: context,
      builder: (context) {
        final theme = context.read<ThemeProvider>().currentTheme;
        return AlertDialog(
          backgroundColor: theme.backgroundColor,
          title: Text('Google Drive Credentials', style: TextStyle(color: theme.foregroundColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: clientController,
                style: TextStyle(color: theme.foregroundColor),
                decoration: InputDecoration(
                  labelText: 'Client ID',
                  labelStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6)),
                  hintText: 'Enter Client ID',
                  hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.3))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: secretController,
                style: TextStyle(color: theme.foregroundColor),
                decoration: InputDecoration(
                  labelText: 'Client Secret',
                  labelStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6)),
                  hintText: 'Enter Client Secret',
                  hintStyle: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.3))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.foregroundColor)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.6))),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final cId = clientController.text.trim();
                final cSec = secretController.text.trim();
                await settings.setGoogleCredentials(
                  cId.isEmpty ? null : cId,
                  cSec.isEmpty ? null : cSec,
                );
              },
              child: Text('Save', style: TextStyle(color: theme.foregroundColor)),
            ),
          ],
        );
      },
    );
  }

  void _showStatsOverlay(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = context.read<ThemeProvider>().currentTheme;
        return AlertDialog(
          backgroundColor: theme.backgroundColor,
          title: Text('Writing Statistics', style: TextStyle(color: theme.foregroundColor)),
          content: Consumer<HistoryProvider>(
            builder: (context, history, child) {
              final stats = history.currentProjectStats;
              final wordsWrittenToday = history.todayStats?.wordCountDelta ?? 0;
              final cumulativeTimeSpent = _formatHours(stats.totalTimeSpent);
              final projectWordCount = stats.totalWordCount;
              
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Words Written Today: $wordsWrittenToday', style: TextStyle(color: theme.foregroundColor, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('Project Word Count: $projectWordCount', style: TextStyle(color: theme.foregroundColor, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('Cumulative Time Spent: $cumulativeTimeSpent', style: TextStyle(color: theme.foregroundColor, fontSize: 14)),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: theme.foregroundColor)),
            ),
          ],
        );
      },
    );
  }

  String _formatHours(Duration d) {
    if (d.inHours < 1) {
      return '${d.inMinutes}m';
    } else {
      final hours = d.inHours.toString().padLeft(2, '0');
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '$hours:$minutes';
    }
  }

  Future<void> _handleSyncLogin(BuildContext context, SyncProvider sync, SettingsMenuBarState settingsState) async {
    try {
      final success = await sync.login(
        clientId: settingsState.googleClientId,
        clientSecret: settingsState.googleClientSecret,
      );
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to Google Drive.'))
        );
        _triggerManualSync(context, sync, settingsState);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud connection failed: $e'))
        );
      }
    }
  }

  Future<void> _triggerManualSync(BuildContext context, SyncProvider sync, SettingsMenuBarState settingsState) async {
    if (settingsState.currentProjectName == null) return;
    try {
      final editor = context.read<EditorProvider>();
      final notes = context.read<NotesProvider>();
      
      await sync.syncCurrentFile(
        projectName: settingsState.currentProjectName!,
        fileName: 'manuscript',
        content: editor.content,
      );
      
      final notesJson = jsonEncode(notes.cards.map((c) => c.toJson()).toList());
      await sync.syncNotes(projectName: settingsState.currentProjectName!, notesJson: notesJson);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced to Google Drive.'))
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'))
        );
      }
    }
  }
}
