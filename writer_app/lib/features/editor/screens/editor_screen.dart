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
import '../../sidebar/widgets/note_editor_dialog.dart';
import '../providers/codex_index.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../search/providers/search_provider.dart';
import '../../search/widgets/search_popup.dart';
import '../widgets/sidebar_pulltab.dart';
import '../widgets/mobile_persistent_toolbar.dart';
import '../widgets/cheatsheet_overlay.dart';
import '../widgets/typewriter_scroll.dart';
import '../utils/toc_parser.dart';
import '../../../core/platform_context.dart';

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
  // Cached TOC headers + per-chapter rolled-up word counts, recomputed only when
  // the editor text changes (never inside build()).
  List<TocHeader> _tocHeaders = const [];
  double _initialScaleZoom = 1.0;
  int _typewriterCaretLine = -1;
  String _typewriterText = '';

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
    final headers = parseTocHeaders(currentText);
    if (_currentWordCount != count || !_sameHeaders(headers, _tocHeaders)) {
      setState(() {
        _currentWordCount = count;
        _tocHeaders = headers;
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
      final headers = parseTocHeaders(newContent);
      if (_currentWordCount != count || !_sameHeaders(headers, _tocHeaders)) {
        setState(() {
          _currentWordCount = count;
          _tocHeaders = headers;
        });
      }
    }
  }

  bool _sameHeaders(List<TocHeader> a, List<TocHeader> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onTypewriterUpdate() {
    // Reacts only to controller (text/selection) changes while the editor is
    // focused — never to scroll events, so manual scrolling is not fought.
    // Search navigation scrolls while the editor is unfocused, so the two
    // mechanisms cannot conflict.
    if (!mounted || _isDeactivated) return;
    if (!_editorFocusNode.hasFocus) return;
    bool enabled;
    try {
      enabled = context.read<SettingsProvider>().typewriterEnabled;
    } catch (_) {
      return;
    }
    if (!enabled) return;

    final selection = _editorController.selection;
    if (!selection.isValid || !_scrollController.hasClients) return;

    final text = _editorController.text;
    final caret = selection.extentOffset;
    int caretLine = 0;
    final limit = caret < text.length ? caret : text.length;
    for (int i = 0; i < limit; i++) {
      if (text.codeUnitAt(i) == 10) caretLine++;
    }
    final bool textChanged = text != _typewriterText;
    if (caretLine == _typewriterCaretLine && !textChanged) return;
    _typewriterCaretLine = caretLine;
    _typewriterText = text;

    final target = typewriterTargetOffset(
      text: text,
      caretOffset: caret,
      zoomLevel: _editorProvider.zoomLevel,
      pageWidth: _editorProvider.pageWidth,
      viewportHeight: _scrollController.position.viewportDimension,
    ).clamp(0.0, _scrollController.position.maxScrollExtent);

    if ((target - _scrollController.offset).abs() < 1.0) return;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
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
    _tocHeaders = parseTocHeaders(editorProvider.content);
    _lastProcessedText = editorProvider.content;
    _editorFocusNode.addListener(_onEditorFocusChange);
    _editorController.addListener(_onEditorTextChanged);
    _editorController.addListener(_onTypewriterUpdate);
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
    _editorController.removeListener(_onTypewriterUpdate);
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

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final editorProvider = context.watch<EditorProvider>();
    final settings = context.watch<SettingsProvider>();
    final uiState = context.watch<ShortcutsProvider>();
    final searchProvider = context.watch<SearchProvider>();
    final notesProvider = context.watch<NotesProvider>();

    _editorController.theme = theme;
    _editorController.searchQuery = searchProvider.query;
    _editorController.paragraphFocusEnabled = settings.paragraphFocusEnabled;
    _editorController.codexLinkingEnabled = settings.codexLinkingEnabled;
    _editorController.codexTitles = [
      for (final c in notesProvider.cards)
        if (!c.isAttribution) CodexTitle(id: c.id, title: c.title),
    ];


    final headers = _tocHeaders;
    // "Uses Command as the primary shortcut modifier" — true on macOS AND
    // iOS/iPadOS. See usesCommandModifier in core/platform_context.dart.
    final bool isMobilePhone = isPhoneLayout(context);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Formatting (Still local to editor for context)
        SingleActivator(LogicalKeyboardKey.keyT, alt: true, meta: usesCommandModifier): const SetTitleIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, alt: true, meta: usesCommandModifier): const SetHeaderIntent(),
        SingleActivator(LogicalKeyboardKey.keyG, alt: true, meta: usesCommandModifier): const SetBodyIntent(),
        SingleActivator(LogicalKeyboardKey.keyL, alt: true, meta: usesCommandModifier): const SetBulletIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, control: !usesCommandModifier, meta: usesCommandModifier): const ToggleBoldIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, control: !usesCommandModifier, meta: usesCommandModifier): const ToggleItalicIntent(),
        SingleActivator(LogicalKeyboardKey.keyU, control: !usesCommandModifier, meta: usesCommandModifier): const ToggleUnderlineIntent(),

        // Alignment
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, meta: usesCommandModifier): const IncreaseWidthIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, meta: usesCommandModifier): const DecreaseWidthIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, meta: usesCommandModifier, shift: true): const ShiftPaperRightIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, meta: usesCommandModifier, shift: true): const ShiftPaperLeftIntent(),

        // Zoom (Ctrl/Cmd)
        SingleActivator(LogicalKeyboardKey.equal, control: !usesCommandModifier, meta: usesCommandModifier): const ZoomInIntent(),
        SingleActivator(LogicalKeyboardKey.minus, control: !usesCommandModifier, meta: usesCommandModifier): const ZoomOutIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(onInvoke: (_) {
            // Flush stats in the background; do NOT block navigation on the Drive sync.
            unawaited(context.read<HistoryProvider>().saveStatsNow());
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
          ToggleBoldIntent: CallbackAction<ToggleBoldIntent>(onInvoke: (_) => _applyFormat('**')),
          ToggleItalicIntent: CallbackAction<ToggleItalicIntent>(onInvoke: (_) => _applyFormat('*')),
          ToggleUnderlineIntent: CallbackAction<ToggleUnderlineIntent>(onInvoke: (_) => _applyFormat('<u>')),
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
                          // Flush stats in the background; do NOT block navigation on the Drive sync.
                          unawaited(context.read<HistoryProvider>().saveStatsNow());
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              settings: const RouteSettings(name: '/settings'),
                              builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
                            ),
                          );
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
                                        codexEnabled: settings.codexLinkingEnabled && !isMobilePhone,
                                        codexIndex: _editorController.codexIndex,
                                        notes: notesProvider.cards,
                                        onOpenNote: _openNote,
                                        spellCheckEnabled: settings.spellCheckEnabled == true,
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
                                     showWordCounts: settings.tocWordCountsEnabled,
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
                        if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
                          await windowManager.setFullScreen(newValue);
                        }
                        uiState.setFullscreen(newValue);
                      },
                      onOpenSettings: () {
                        // Flush stats in the background; do NOT block navigation on the Drive sync.
                        unawaited(context.read<HistoryProvider>().saveStatsNow());
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            settings: const RouteSettings(name: '/settings'),
                            builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
                          ),
                        );
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
                    child: Center(
                      child: SearchPopup(
                        onReplaceOne: _applyReplaceOne,
                        onReplaceAll: _applyReplaceAll,
                      ),
                    ),
                  ),
                if (isTouchPlatform) ...[
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

  void _openNote(String noteId) {
    showDialog(
      context: context,
      builder: (_) => NoteEditorDialog(noteId: noteId),
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

  // Search & Replace (Phase 1). Follows the exact `_applyFormat` pattern above:
  // mutate the controller's `value` first, then push the resulting text
  // through `EditorProvider.updateContent`. Because the controller and the
  // provider already agree on the text by the time `updateContent` notifies,
  // `_onEditorProviderChanged` no-ops instead of reassigning
  // `_editorController.text` — which is what keeps the native undo stack
  // (and thus a single Ctrl+Z) intact for both Replace-one and Replace-All.
  void _applyReplaceOne() {
    final query = _searchProvider.query;
    final offsets = _searchProvider.matchOffsets;
    final idx = _searchProvider.currentMatchIndex;
    if (query.isEmpty || idx < 0 || idx >= offsets.length) return;

    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final result = _editorController.replaceMatches(
      pattern,
      _searchProvider.replaceQuery,
      matchStart: offsets[idx],
    );
    if (result.count == 0) return;
    _commitReplace();
  }

  void _applyReplaceAll() {
    final query = _searchProvider.query;
    if (query.isEmpty) return;

    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final result = _editorController.replaceMatches(pattern, _searchProvider.replaceQuery);
    if (result.count == 0) return;
    _commitReplace();
  }

  void _commitReplace() {
    final settings = context.read<SettingsProvider>();
    context.read<EditorProvider>().updateContent(
      _editorController.text,
      syncProvider: context.read<SyncProvider>(),
      projectName: settings.currentProjectName,
      syncInterval: Duration(minutes: settings.syncIntervalMinutes),
    );
    setState(() {});
    _searchProvider.updateMatchOffsets(_editorController.text);
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
