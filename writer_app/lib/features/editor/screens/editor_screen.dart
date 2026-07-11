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
import '../../settings/providers/history_provider.dart';
import '../../sidebar/providers/notes_provider.dart';
import 'dart:io';
import '../../search/providers/search_provider.dart';
import '../../search/widgets/search_popup.dart';
import '../widgets/sidebar_pulltab.dart';
import '../widgets/mobile_persistent_toolbar.dart';
import '../widgets/cheatsheet_overlay.dart';

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
  bool _isDeactivated = false;
  late SearchProvider _searchProvider;
  late EditorProvider _editorProvider;
  int _currentWordCount = 0;
  String _lastProcessedText = '';
  double _initialScaleZoom = 1.0;

  @override
  void deactivate() {
    _isDeactivated = true;
    super.deactivate();
  }

  @override
  void activate() {
    _isDeactivated = false;
    super.activate();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (_isDeactivated || !mounted) return false;
    try {
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) {
        return false;
      }
    } catch (_) {
      return false;
    }

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

  void _onEditorFocusChange() {
    if (mounted) {
      try {
        final history = Provider.of<HistoryProvider>(context, listen: false);
        history.setEditorFocus(_editorFocusNode.hasFocus);
      } catch (_) {
        // HistoryProvider not in tree
      }
    }
  }

  void _onEditorTextChanged() {
    if (!mounted) return;
    final currentText = _editorController.text;
    if (currentText == _lastProcessedText) {
      return;
    }
    _lastProcessedText = currentText;

    final count = _calculateWordCount(currentText);
    if (_currentWordCount != count) {
      setState(() {
        _currentWordCount = count;
      });
    }
    try {
      final history = Provider.of<HistoryProvider>(context, listen: false);
      history.updateWordCount(count);
    } catch (_) {
      // HistoryProvider not in tree
    }

    if (_searchProvider.isSearchOpen && _searchProvider.query.isNotEmpty) {
      _searchProvider.updateMatchOffsets(currentText);
    }
  }

  void _onTypewriterScroll() {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    if (settings.typewriterScrolling != true) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _editorController;
      final selection = controller.selection;
      if (selection.isValid && selection.isCollapsed) {
        final charOffset = selection.baseOffset;
        final text = controller.text;

        final zoomLevel = context.read<EditorProvider>().zoomLevel;
        final pageWidth = context.read<EditorProvider>().pageWidth;
        final textWidth = pageWidth - 120.0;

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
        final caretOffset = textPainter.getOffsetForCaret(
          TextPosition(offset: charOffset),
          Rect.zero,
        );

        if (_scrollController.hasClients) {
          final double viewportHeight = _scrollController.position.viewportDimension;
          final double absoluteCaretY = 160.0 + caretOffset.dy;
          final double targetScrollOffset = absoluteCaretY - (viewportHeight / 2);

          _scrollController.jumpTo(
            targetScrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      }
    });
  }

  void _onSearchChanged() {
    if (!mounted) return;
    final activeIndex = _searchProvider.currentMatchIndex;
    
    // Update active offset on the controller
    int newOffset = -1;
    if (activeIndex >= 0 && activeIndex < _searchProvider.matchOffsets.length) {
      newOffset = _searchProvider.matchOffsets[activeIndex];
    }
    
    if (_editorController.activeMatchOffset != newOffset) {
      _editorController.activeMatchOffset = newOffset;
      // Scroll the editor to the new match offset if editor does not have focus
      if (newOffset != -1 && !_editorFocusNode.hasFocus) {
        _jumpToCharacterOffset(newOffset);
      }
    }
  }

  void _onEditorProviderChanged() {
    if (!mounted) return;
    final newContent = _editorProvider.content;
    if (_editorController.text != newContent) {
      // Temporarily remove listener to avoid triggering word count updates/setState during build
      _editorController.removeListener(_onEditorTextChanged);
      _editorController.text = newContent;
      _editorController.addListener(_onEditorTextChanged);
      _lastProcessedText = newContent;
      
      final count = _calculateWordCount(newContent);
      if (_currentWordCount != count) {
        setState(() {
          _currentWordCount = count;
        });
      }
    }
  }

  void _jumpToCharacterOffset(int charOffset) {
    if (charOffset < 0 || charOffset >= _editorController.text.length) return;
    
    final text = _editorController.text;
    final zoomLevel = context.read<EditorProvider>().zoomLevel;
    final pageWidth = context.read<EditorProvider>().pageWidth;
    final textWidth = pageWidth - 120.0;

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

    final double viewportHeight = _scrollController.hasClients 
        ? _scrollController.position.viewportDimension 
        : 600.0;
    final targetScrollOffset = offset.dy - (viewportHeight / 3);

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        targetScrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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
    _currentWordCount = _calculateWordCount(editorProvider.content);
    _lastProcessedText = editorProvider.content;
    _editorFocusNode.addListener(_onEditorFocusChange);
    _editorController.addListener(_onEditorTextChanged);
    _editorController.addListener(_onTypewriterScroll);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);

    _editorProvider = context.read<EditorProvider>();
    _editorProvider.addListener(_onEditorProviderChanged);

    _searchProvider = context.read<SearchProvider>();
    _searchProvider.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onEditorTextChanged();
      }
    });
  }

  @override
  void dispose() {
    _editorFocusNode.removeListener(_onEditorFocusChange);
    _editorController.removeListener(_onEditorTextChanged);
    _editorController.removeListener(_onTypewriterScroll);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _editorProvider.removeListener(_onEditorProviderChanged);
    _searchProvider.removeListener(_onSearchChanged);
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
            child: CheatsheetOverlayContent(theme: theme),
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

  void _jumpToHeader(int lineIndex) {
    final text = _editorController.text;
    final lines = text.split('\n');
    int charOffset = 0;
    for (int i = 0; i < lineIndex && i < lines.length; i++) {
      charOffset += lines[i].length + 1;
    }

    final zoomLevel = context.read<EditorProvider>().zoomLevel;
    final pageWidth = context.read<EditorProvider>().pageWidth;
    final textWidth = pageWidth - 120.0;

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
    final searchProvider = context.watch<SearchProvider>();
    
    _editorController.theme = theme;
    _editorController.searchQuery = searchProvider.query;


    final headers = _parseHeaders(editorProvider.content);
    final bool isMac = Platform.isMacOS;
    final bool isMobilePhone = (Platform.isAndroid || Platform.isIOS) && MediaQuery.of(context).size.shortestSide < 600;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Formatting (Still local to editor for context)
        SingleActivator(LogicalKeyboardKey.keyT, alt: true, meta: isMac): const SetTitleIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, alt: true, meta: isMac): const SetHeaderIntent(),
        SingleActivator(LogicalKeyboardKey.keyG, alt: true, meta: isMac): const SetBodyIntent(),
        SingleActivator(LogicalKeyboardKey.keyL, alt: true, meta: isMac): const SetBulletIntent(),

        // Alignment
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, meta: isMac): const IncreaseWidthIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, meta: isMac): const DecreaseWidthIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, meta: isMac, shift: true): const ShiftPaperRightIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, meta: isMac, shift: true): const ShiftPaperLeftIntent(),

        // Zoom (Ctrl/Cmd)
        SingleActivator(LogicalKeyboardKey.equal, control: !isMac, meta: isMac): const ZoomInIntent(),
        SingleActivator(LogicalKeyboardKey.minus, control: !isMac, meta: isMac): const ZoomOutIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(onInvoke: (_) {
            if (Platform.isMacOS) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings are located in the top macOS System Menu Bar.'))
              );
              return null;
            }
            context.read<HistoryProvider>().saveStatsNow().then((_) {
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '/settings'),
                    builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
                  ),
                );
              }
            });
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
                      showWindowControls: !isMobilePhone && !uiState.isFullscreen,
                      onRename: (newName) async {
                        final success = await settings.renameProject(settings.currentProjectName!, newName);
                        if (success && mounted) {
                          final path = settings.currentProjectPath;
                          await context.read<EditorProvider>().loadProject(path);
                          await context.read<NotesProvider>().loadProject(path, projectName: newName);
                          await context.read<HistoryProvider>().loadProjectStats(path);
                        }
                      },
                      actionButton: const SizedBox.shrink(),
                    ),
                    if (isMobilePhone)
                      MobilePersistentToolbar(
                        theme: theme,
                        onApplyFormat: _applyFormat,
                        onSettingsTap: () {
                          context.read<HistoryProvider>().saveStatsNow().then((_) {
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  settings: const RouteSettings(name: '/settings'),
                                  builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
                                ),
                              );
                            }
                          });
                        },
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: NoiseOverlay(
                              child: Stack(
                                children: [
                                  Builder(
                                    builder: (context) {
                                      Widget paperArea = EditorPaperArea(
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
                                            syncInterval: Duration(minutes: settings.syncIntervalMinutes),
                                          );
                                          setState(() {});
                                        },
                                      );

                                      if (isMobilePhone) {
                                        paperArea = GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTapDown: (_) {
                                            final state = context.read<ShortcutsProvider>();
                                            if (state.isLeftSidebarOpen || state.isRightSidebarOpen) {
                                              if (state.isLeftSidebarOpen) {
                                                state.toggleLeftSidebar();
                                              }
                                              if (state.isRightSidebarOpen) {
                                                state.toggleRightSidebar();
                                              }
                                            }
                                          },
                                          onScaleStart: _onScaleStart,
                                          onScaleUpdate: _onScaleUpdate,
                                          child: paperArea,
                                        );
                                      }
                                      return paperArea;
                                    },
                                  ),
                                  if (!isMobilePhone && uiState.isToolbarOpen)
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
                      wordCount: _currentWordCount,
                      isLeftSidebarOpen: uiState.isLeftSidebarOpen,
                      isRightSidebarOpen: uiState.isRightSidebarOpen,
                      isFullscreen: uiState.isFullscreen,
                      onToggleLeft: uiState.toggleLeftSidebar,
                      onToggleRight: uiState.toggleRightSidebar,
                      onToggleToolbar: uiState.toggleToolbar,
                      onToggleFullscreen: () async {
                        final newValue = !uiState.isFullscreen;
                        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
                          await windowManager.setFullScreen(newValue);
                        }
                        uiState.setFullscreen(newValue);
                      },
                      onOpenSettings: () {
                        context.read<HistoryProvider>().saveStatsNow().then((_) {
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                settings: const RouteSettings(name: '/settings'),
                                builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
                              ),
                            );
                          }
                        });
                      },
                    ),
                  ],
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  left: uiState.isLeftSidebarOpen ? 270 : 20,
                  right: uiState.isRightSidebarOpen ? 320 : 20,
                  bottom: searchProvider.isSearchOpen ? -100 : 60,
                  child: AlignmentBar(
                    theme: theme,
                    pageWidth: editorProvider.pageWidth,
                    horizontalPosition: editorProvider.horizontalPosition,
                    onWidthChanged: editorProvider.setPageWidth,
                    onPositionChanged: editorProvider.setHorizontalPosition,
                  ),
                ),
                if (searchProvider.isSearchOpen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 80,
                    child: const Center(
                      child: SearchPopup(),
                    ),
                  ),
                if (isMobilePhone) ...[
                  SidebarPulltab(
                    theme: theme,
                    direction: AxisDirection.left,
                    isOpen: uiState.isLeftSidebarOpen,
                    onTap: uiState.toggleLeftSidebar,
                  ),
                  SidebarPulltab(
                    theme: theme,
                    direction: AxisDirection.right,
                    isOpen: uiState.isRightSidebarOpen,
                    onTap: uiState.toggleRightSidebar,
                  ),
                ],
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
      syncInterval: Duration(minutes: settings.syncIntervalMinutes),
    );
    setState(() {});
  }
    

  int _calculateWordCount(String text) {
    int count = 0;
    bool inWord = false;
    final length = text.length;
    for (int i = 0; i < length; i++) {
      final codeUnit = text.codeUnitAt(i);
      final isWhitespace = codeUnit == 32 || codeUnit == 10 || codeUnit == 13 || codeUnit == 9;
      if (isWhitespace) {
        if (inWord) {
          count++;
          inWord = false;
        }
      } else {
        inWord = true;
      }
    }
    if (inWord) {
      count++;
    }
    return count;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _initialScaleZoom = context.read<EditorProvider>().zoomLevel;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 && details.scale != 1.0) {
      context.read<EditorProvider>().setZoomLevel(_initialScaleZoom * details.scale);
    }
  }
}
