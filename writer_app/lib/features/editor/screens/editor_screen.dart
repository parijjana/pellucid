import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/editor_provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/screens/settings_screen.dart';
import '../../sidebar/screens/notes_sidebar.dart';
import '../widgets/editor_status_bar.dart';
import '../widgets/markdown_controller.dart';
import '../widgets/alignment_bar.dart';
import '../widgets/noise_overlay.dart';
import '../widgets/formatting_toolbar.dart';
import '../widgets/integrated_header.dart';
import '../../sync/providers/sync_provider.dart';
import 'package:flutter/services.dart';
import '../widgets/shortcuts.dart';
import '../providers/shortcuts_provider.dart';
import '../widgets/editor_navigation_sidebar.dart';
import '../widgets/editor_paper_area.dart';
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
  DateTime? _lastAltReleaseTime;
  OverlayEntry? _cheatsheetOverlayEntry;
  Timer? _cheatsheetTimer;

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.altLeft || event.logicalKey == LogicalKeyboardKey.altRight) {
        final now = DateTime.now();
        if (_lastAltReleaseTime != null && now.difference(_lastAltReleaseTime!) < const Duration(milliseconds: 350)) {
          _showCheatsheetOverlay();
          _lastAltReleaseTime = null;
        } else {
          _lastAltReleaseTime = now;
        }
      } else {
        _lastAltReleaseTime = null;
      }
    } else if (event is KeyDownEvent) {
      if (event.logicalKey != LogicalKeyboardKey.altLeft && event.logicalKey != LogicalKeyboardKey.altRight) {
        _lastAltReleaseTime = null;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    final editorProvider = context.read<EditorProvider>();
    final themeProvider = context.read<ThemeProvider>();
    
    _editorController = MarkdownEditingController(
      text: editorProvider.content,
      theme: themeProvider.currentTheme,
    );
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _editorController.dispose();
    _scrollController.dispose();
    _editorFocusNode.dispose();
    _cheatsheetOverlayEntry?.remove();
    _cheatsheetTimer?.cancel();
    super.dispose();
  }

  void _showCheatsheetOverlay() {
    _cheatsheetOverlayEntry?.remove();
    _cheatsheetTimer?.cancel();

    _cheatsheetOverlayEntry = OverlayEntry(
      builder: (context) {
        final theme = Provider.of<ThemeProvider>(context).currentTheme;
        return Positioned(
          bottom: 80,
          left: 20,
          right: 20,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: theme.sidebarColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.1)),
                      boxShadow: theme.sidebarShadows,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'KEYBOARD SHORTCUTS CHEATSHEET',
                          style: TextStyle(
                            color: theme.foregroundColor.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildCheatsheetItem(theme, 'Alt + 1', 'Toggle ToC'),
                            _buildCheatsheetItem(theme, 'Alt + 2', 'Toggle Notes'),
                            _buildCheatsheetItem(theme, 'Alt + 3', 'Toggle Toolbar'),
                            _buildCheatsheetItem(theme, 'Alt + 4', 'Toggle Settings'),
                            _buildCheatsheetItem(theme, 'Alt + Enter', 'Toggle Fullscreen'),
                            _buildCheatsheetItem(theme, 'Alt + A', 'Attributions'),
                            _buildCheatsheetItem(theme, 'Alt + Shift + A', 'Set Alarm'),
                            _buildCheatsheetItem(theme, 'Alt + C', 'Peek Clock / Dismiss Alarm'),
                            _buildCheatsheetItem(theme, 'Alt + S', 'Peek Session'),
                            _buildCheatsheetItem(theme, 'Alt + P', 'Toggle Pomodoro'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_cheatsheetOverlayEntry!);

    _cheatsheetTimer = Timer(const Duration(seconds: 3), () {
      _cheatsheetOverlayEntry?.remove();
      _cheatsheetOverlayEntry = null;
    });
  }

  Widget _buildCheatsheetItem(WriterTheme theme, String keys, String description) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: theme.foregroundColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            keys,
            style: TextStyle(
              color: theme.foregroundColor,
              fontSize: 10,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          description,
          style: TextStyle(
            color: theme.foregroundColor.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _jumpToHeader(int lineIndex) {
    final text = _editorController.text;
    final lines = text.split('\n');
    int charOffset = 0;
    for (int i = 0; i < lineIndex && i < lines.length; i++) {
      charOffset += lines[i].length + 1;
    }

    final zoomLevel = context.read<EditorProvider>().zoomLevel;
    final pageWidth = context.read<EditorProvider>().pageWidth;
    final textWidth = pageWidth * zoomLevel - 120.0;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 16.0 * zoomLevel,
          height: 1.8,
          fontFamily: 'Georgia',
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: textWidth);
    final offset = textPainter.getOffsetForCaret(
      TextPosition(offset: charOffset),
      Rect.zero,
    );

    final targetScrollOffset = offset.dy + 100.0;

    _scrollController.animateTo(
      targetScrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
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
            Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: '/settings'),
                builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
              ),
            );
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
                      projectName: settings.currentProjectName ?? 'User Manual',
                      showWindowControls: !uiState.isFullscreen,
                      actionButton: IconButton(
                        icon: const Icon(Icons.settings, size: 20),
                        onPressed: () => Navigator.push(
                          context, 
                          MaterialPageRoute(
                            settings: const RouteSettings(name: '/settings'),
                            builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
                          ),
                        ),
                        tooltip: 'Settings',
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: NoiseOverlay(
                              child: Stack(
                                children: [
                                  EditorPaperArea(
                                    theme: theme,
                                    provider: editorProvider,
                                    controller: _editorController,
                                    scrollController: _scrollController,
                                    focusNode: _editorFocusNode,
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
                                  if (uiState.isToolbarOpen)
                                    Positioned(
                                      top: 0, left: 0, right: 0,
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
                                   child: EditorNavigationSidebar(
                                     theme: theme,
                                     headers: headers,
                                     onHeaderTap: _jumpToHeader,
                                   ),
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
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  left: uiState.isLeftSidebarOpen ? 270 : 20,
                  right: uiState.isRightSidebarOpen ? 320 : 20,
                  bottom: 60,
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
    

  int _calculateWordCount(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }
}
