// @trace FEAT-20260516-120000-0001
// Description: Refactored EditorScreen (Flat Paper Aesthetic with Sidebars & Navigation).

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/editor_provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/screens/settings_screen.dart';
import '../../sidebar/screens/notes_sidebar.dart';
import '../../sidebar/providers/notes_provider.dart';
import '../widgets/editor_status_bar.dart';
import '../widgets/markdown_controller.dart';
import '../widgets/alignment_bar.dart';
import '../widgets/noise_overlay.dart';
import '../widgets/formatting_toolbar.dart';
import '../widgets/glowing_border.dart';
import '../widgets/integrated_header.dart';
import '../../sync/providers/sync_provider.dart';
import 'package:flutter/services.dart';
import '../widgets/shortcuts.dart';
import '../providers/shortcuts_provider.dart';
import 'dart:io';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late MarkdownEditingController _editorController;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final editorProvider = context.read<EditorProvider>();
    final themeProvider = context.read<ThemeProvider>();
    
    _editorController = MarkdownEditingController(
      text: editorProvider.content,
      theme: themeProvider.currentTheme,
    );
  }

  @override
  void dispose() {
    _editorController.dispose();
    _scrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _jumpToHeader(int lineIndex) {
    final double estimatedPosition = lineIndex * 28.8 + 100;
    _scrollController.animateTo(
      estimatedPosition,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  List<({String title, int line, int level})> _parseHeaders(String text) {
    final List<({String title, int line, int level})> headers = [];
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#')) {
        final match = RegExp(r'^(#+)\s+(.*)$').firstMatch(line);
        if (match != null) {
          headers.add((title: match.group(2)!, line: i, level: match.group(1)!.length));
        }
      }
    }
    return headers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final editorProvider = context.watch<EditorProvider>();
    final settings = context.watch<SettingsProvider>();
    final sync = context.watch<SyncProvider>();
    final uiState = context.watch<ShortcutsProvider>();
    
    if (_editorController.text != editorProvider.content) {
      _editorController.text = editorProvider.content;
    }

    final headers = _parseHeaders(editorProvider.content);
    final bool isMac = Platform.isMacOS;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Formatting (Still local to editor for context)
        SingleActivator(LogicalKeyboardKey.keyT, alt: !isMac, meta: isMac, control: isMac): const SetTitleIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, alt: !isMac, meta: isMac, control: isMac): const SetHeaderIntent(),
        SingleActivator(LogicalKeyboardKey.keyG, alt: !isMac, meta: isMac, control: isMac): const SetBodyIntent(),
        SingleActivator(LogicalKeyboardKey.keyL, alt: !isMac, meta: isMac, control: isMac): const SetBulletIntent(),

        // Alignment
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: !isMac, meta: isMac, control: isMac): const IncreaseWidthIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: !isMac, meta: isMac, control: isMac): const DecreaseWidthIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: !isMac, meta: isMac, control: isMac, shift: true): const ShiftPaperRightIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: !isMac, meta: isMac, control: isMac, shift: true): const ShiftPaperLeftIntent(),

        // Zoom (Ctrl/Cmd)
        SingleActivator(LogicalKeyboardKey.equal, control: !isMac, meta: isMac): const ZoomInIntent(),
        SingleActivator(LogicalKeyboardKey.minus, control: !isMac, meta: isMac): const ZoomOutIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(onInvoke: (_) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen)));
            return null;
          }),
          SetTitleIntent: CallbackAction<SetTitleIntent>(onInvoke: (_) => _applyFormat('# ')),
          SetHeaderIntent: CallbackAction<SetHeaderIntent>(onInvoke: (_) => _applyFormat('## ')),
          SetBodyIntent: CallbackAction<SetBodyIntent>(onInvoke: (_) => _applyFormat('body')),
          SetBulletIntent: CallbackAction<SetBulletIntent>(onInvoke: (_) => _applyFormat('- ')),
          ZoomInIntent: CallbackAction<ZoomInIntent>(onInvoke: (_) => editorProvider.zoomIn()),
          ZoomOutIntent: CallbackAction<ZoomOutIntent>(onInvoke: (_) => editorProvider.zoomOut()),
          IncreaseWidthIntent: CallbackAction<IncreaseWidthIntent>(onInvoke: (_) => editorProvider.setPageWidth(editorProvider.pageWidth + 50)),
          DecreaseWidthIntent: CallbackAction<DecreaseWidthIntent>(onInvoke: (_) => editorProvider.setPageWidth(editorProvider.pageWidth - 50)),
          ShiftPaperRightIntent: CallbackAction<ShiftPaperRightIntent>(onInvoke: (_) => editorProvider.setHorizontalPosition((editorProvider.horizontalPosition + 0.1).clamp(0.0, 1.0))),
          ShiftPaperLeftIntent: CallbackAction<ShiftPaperLeftIntent>(onInvoke: (_) => editorProvider.setHorizontalPosition((editorProvider.horizontalPosition - 0.1).clamp(0.0, 1.0))),
        },
        child: Scaffold(
          backgroundColor: theme.backgroundColor,
          body: Stack(
            children: [
              Column(
                children: [
                  IntegratedHeader(
                    theme: theme,
                    projectName: settings.currentProjectName,
                    showWindowControls: !uiState.isFullscreen,
                    actionButton: IconButton(
                      icon: const Icon(Icons.settings, size: 20),
                      onPressed: () => Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen))
                      ),
                      tooltip: 'Settings',
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: NoiseOverlay(
                            child: GlowingBorder(
                              isActive: syncStatusToActive(sync.status) || settings.isAlarmTriggered,
                              color: settings.isAlarmTriggered ? Colors.red : Colors.blue,
                              child: Stack(
                                children: [
                                  _buildPaperArea(theme, editorProvider),
                                  if (uiState.isToolbarOpen)
                                    Positioned(
                                      top: 20, left: 0, right: 0,
                                      child: Center(
                                        child: FormattingToolbar(
                                          theme: theme,
                                          onApplyFormat: (format) => _applyFormat(format),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          left: uiState.isLeftSidebarOpen ? 0 : -250,
                          top: 0, bottom: 0, width: 250,
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme.sidebarColor.withValues(alpha: 0.8),
                                  border: Border(right: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.05))),
                                ),
                                child: _buildNavigationSidebar(theme, headers),
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          right: uiState.isRightSidebarOpen ? 0 : -300,
                          top: 0, bottom: 0, width: 300,
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme.sidebarColor.withValues(alpha: 0.8),
                                  border: Border(left: BorderSide(color: theme.foregroundColor.withValues(alpha: 0.05))),
                                ),
                                child: const NotesSidebar(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  EditorStatusBar(
                    theme: theme,
                    wordCount: _calculateWordCount(editorProvider.content),
                    isLeftSidebarOpen: uiState.isLeftSidebarOpen,
                    isRightSidebarOpen: uiState.isRightSidebarOpen,
                    isFullscreen: uiState.isFullscreen,
                    onToggleLeft: uiState.toggleLeftSidebar,
                    onToggleRight: uiState.toggleRightSidebar,
                    onToggleToolbar: uiState.toggleToolbar,
                    onToggleFullscreen: () async {
                      final newValue = !uiState.isFullscreen;
                      await windowManager.setFullScreen(newValue);
                      uiState.setFullscreen(newValue);
                    },
                  ),
                ],
              ),
              Positioned(
                left: 20, right: 20, bottom: 60,
                child: AlignmentBar(
                  theme: theme,
                  pageWidth: editorProvider.pageWidth,
                  horizontalPosition: editorProvider.horizontalPosition,
                  onWidthChanged: editorProvider.setPageWidth,
                  onPositionChanged: editorProvider.setHorizontalPosition,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyFormat(String format) {
    _editorController.toggleFormat(format);
    final settings = context.read<SettingsProvider>();
    context.read<EditorProvider>().updateContent(
      _editorController.text,
      syncProvider: context.read<SyncProvider>(),
      projectName: settings.currentProjectName,
    );
    setState(() {});
  }
  
  bool syncStatusToActive(SyncStatus status) => status == SyncStatus.syncing;

  Widget _buildPaperArea(WriterTheme theme, EditorProvider provider) {
    final zoomLevel = provider.zoomLevel;
    final pageWidth = provider.pageWidth;
    final horizontalPos = provider.horizontalPosition;

    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment(horizontalPos * 2 - 1, 0),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 100),
        child: Container(
          width: pageWidth * zoomLevel,
          constraints: const BoxConstraints(minHeight: 1000),
          decoration: BoxDecoration(
            color: theme.backgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(60),
          child: TextField(
            controller: _editorController,
            focusNode: _editorFocusNode,
            maxLines: null,
            cursorColor: theme.foregroundColor.withValues(alpha: 0.3),
            style: TextStyle(
              color: theme.foregroundColor,
              fontSize: 16 * zoomLevel,
              height: 1.8,
              fontFamily: 'Georgia',
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
            onChanged: (val) {
              final settings = context.read<SettingsProvider>();
              final sync = context.read<SyncProvider>();
              context.read<EditorProvider>().updateContent(
                val,
                syncProvider: sync,
                projectName: settings.currentProjectName,
              );
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationSidebar(WriterTheme theme, List<({String title, int line, int level})> headers) {
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text('TABLE OF CONTENTS', style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2), fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)),
          ),
          Expanded(
            child: headers.isEmpty 
              ? Center(
                  child: Text(
                    'No headers found',
                    style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2), fontSize: 12),
                  ),
                )
              : ListView.builder(
                  itemCount: headers.length,
                  itemBuilder: (context, index) {
                    final h = headers[index];
                    return _sidebarItem(h.title, theme, false, level: h.level, onTap: () => _jumpToHeader(h.line));
                  },
                ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sidebarItem(String label, WriterTheme theme, bool isActive, {int level = 1, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(left: 20.0 * level, right: 20, top: 12, bottom: 12),
        color: isActive ? theme.foregroundColor.withValues(alpha: 0.03) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? theme.foregroundColor : theme.foregroundColor.withValues(alpha: 0.4),
            fontSize: 13 - (level - 1) * 1.0,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  int _calculateWordCount(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }
}
