import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'features/editor/providers/editor_provider.dart';
import 'features/editor/providers/theme_provider.dart';
import 'features/editor/screens/editor_screen.dart';
import 'features/sidebar/providers/notes_provider.dart';
import 'features/sidebar/providers/note_card.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/settings/providers/history_provider.dart';
import 'features/editor/providers/storage_service.dart';
import 'features/editor/providers/sprint_controller.dart';
import 'features/sync/providers/sync_provider.dart';
import 'package:flutter/services.dart';
import 'features/editor/providers/shortcuts_provider.dart';
import 'features/editor/widgets/shortcuts.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/editor/widgets/glowing_border.dart';
import 'features/sidebar/widgets/note_editor_dialog.dart';
import 'features/editor/widgets/alarm_setter_dialog.dart';
import 'features/search/providers/search_provider.dart';
import 'features/editor/widgets/mac_menu_bar_wrapper.dart';
import 'core/platform_context.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  final editorProvider = EditorProvider();
  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  final syncProvider = SyncProvider();
  final historyProvider = HistoryProvider(syncProvider: syncProvider);
  final notesProvider = NotesProvider();
  final searchProvider = SearchProvider();
  final sprintController = SprintController();

  if (!kIsWeb) {
    await themeProvider.loadSettings();
    await editorProvider.loadSettings();
    await settingsProvider.loadSettings();
    await editorProvider.loadProject(settingsProvider.currentProjectPath);
    await notesProvider.loadProject(settingsProvider.currentProjectPath);
    await historyProvider.loadProjectStats(settingsProvider.currentProjectPath);
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: editorProvider),
        ChangeNotifierProvider.value(value: notesProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: historyProvider),
        ChangeNotifierProvider.value(value: syncProvider),
        ChangeNotifierProvider.value(value: searchProvider),
        ChangeNotifierProvider.value(value: sprintController),
        ChangeNotifierProvider(create: (_) => ShortcutsProvider()),
        ChangeNotifierProvider(create: (_) => PointerTypeNotifier()),
      ],
      child: const WriterApp(),
    ),
  );

  // Full-library backup sweep: runs once at startup (if due) and then hourly so
  // a long-running session eventually backs up once 24h elapses. Fire-and-forget
  // so it never blocks or freezes startup/UI. One-way local -> Drive only.
  if (!kIsWeb) {
    _scheduleFullBackups(syncProvider, settingsProvider);

    // One-time, data-preserving Drive-side manuscript filename migration
    // (docs/two-way-sync-design.md §1). Fire-and-forget: it only touches
    // Drive, never local disk, and is idempotent/interruption-safe (see
    // SyncProvider.runManuscriptMigrationIfNeeded). Already-migrated vaults
    // resolve to a single cheap Drive listing per app start.
    unawaited(syncProvider.runManuscriptMigrationIfNeeded());
  }
}

/// Kicks off the periodic full-backup sweep. Each invocation is a no-op unless
/// logged in, a master directory is set, and 24h has elapsed since the last
/// sweep, so calling it hourly is cheap and safe.
void _scheduleFullBackups(SyncProvider sync, SettingsProvider settings) {
  Future<void> run() async {
    final masterPath = settings.masterDirectoryPath;
    if (masterPath == null) return;
    await sync.runFullBackupIfDue(
      masterPath: masterPath,
      storageService: StorageService(),
    );
  }

  // Initial (background) run.
  unawaited(run());
  // Periodic re-check so a due sweep eventually fires within a long session.
  Timer.periodic(const Duration(hours: 1), (_) => unawaited(run()));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class WriterApp extends StatelessWidget {
  const WriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    // "Uses Command as the primary shortcut modifier" — true on macOS AND
    // iOS/iPadOS (relevant for iPad + hardware keyboard users). Everywhere
    // else (Windows, Linux, Android, web) uses Ctrl/Alt. See
    // usesCommandModifier in core/platform_context.dart for the full
    // rationale (imported as `usesCommandModifier`, used directly below).
    //
    // macOS-*specifically* (not iOS) — reserved for the one shortcut below
    // that has no iOS equivalent.
    final bool isMacOS = !kIsWeb && Platform.isMacOS;

    // Latches PointerTypeNotifier.hasPointer the first time a mouse/trackpad
    // hover is observed anywhere in the app. Listener is non-opaque (it only
    // participates in hit-testing if a child does), so this adds pointer
    // observation without changing hit-testing or visuals anywhere below it.
    return Listener(
      onPointerHover: (event) => context.read<PointerTypeNotifier>().onPointerHover(event),
      child: Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.digit1, alt: true, meta: usesCommandModifier): const ToggleToCIntent(),
        SingleActivator(LogicalKeyboardKey.digit2, alt: true, meta: usesCommandModifier): const ToggleNotesIntent(),
        SingleActivator(LogicalKeyboardKey.digit3, alt: true, meta: usesCommandModifier): const ToggleToolbarIntent(),
        SingleActivator(LogicalKeyboardKey.digit4, alt: true, meta: usesCommandModifier): const OpenSettingsIntent(),
        SingleActivator(LogicalKeyboardKey.comma, meta: usesCommandModifier, control: !usesCommandModifier): const OpenSettingsIntent(),
        SingleActivator(LogicalKeyboardKey.digit5, alt: true, meta: usesCommandModifier): const ToggleTypewriterIntent(),
        SingleActivator(LogicalKeyboardKey.digit6, alt: true, meta: usesCommandModifier): const ToggleParagraphFocusIntent(),
        const SingleActivator(LogicalKeyboardKey.f11): const ToggleFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.enter, alt: true, meta: usesCommandModifier): const ToggleFullscreenIntent(),
        // macOS-only: standard Cmd+Ctrl+F fullscreen convention. Gated to
        // isMacOS specifically (not usesCommandModifier / iOS) because on
        // Windows/Linux this activator (control: true, meta: false)
        // would otherwise be structurally identical to the Ctrl+F search
        // shortcut below and silently overwrite it as a map key. iOS has no
        // equivalent native fullscreen convention, so it is deliberately
        // excluded too.
        if (isMacOS) const SingleActivator(LogicalKeyboardKey.keyF, control: true, meta: true): const ToggleFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, alt: true, meta: usesCommandModifier): const PeekClockIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, alt: true, meta: usesCommandModifier, shift: true): const SetAlarmIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, alt: true, meta: usesCommandModifier): const PeekSessionIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, alt: true, meta: usesCommandModifier): const AddNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, alt: true, meta: usesCommandModifier): const OpenAttributionIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, alt: true, meta: usesCommandModifier): const TogglePomodoroIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, alt: true, meta: usesCommandModifier, shift: true): const ResetPomodoroIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, alt: true, meta: usesCommandModifier, shift: true): const ToggleSprintIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: !usesCommandModifier, meta: usesCommandModifier): const ToggleSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ToggleToCIntent: CallbackAction<ToggleToCIntent>(onInvoke: (intent) {
            context.read<ShortcutsProvider>().toggleLeftSidebar();
            return null;
          }),
          ToggleNotesIntent: CallbackAction<ToggleNotesIntent>(onInvoke: (intent) {
            context.read<ShortcutsProvider>().toggleRightSidebar();
            return null;
          }),
          ToggleToolbarIntent: CallbackAction<ToggleToolbarIntent>(onInvoke: (intent) {
            context.read<ShortcutsProvider>().toggleToolbar();
            return null;
          }),
          PeekClockIntent: CallbackAction<PeekClockIntent>(onInvoke: (intent) {
            context.read<ShortcutsProvider>().peekClock();
            final settings = context.read<SettingsProvider>();
            if (settings.isAlarmTriggered) {
              settings.dismissAlarm();
            }
            return null;
          }),
          PeekSessionIntent: CallbackAction<PeekSessionIntent>(onInvoke: (intent) {
            context.read<ShortcutsProvider>().peekSession();
            return null;
          }),
          TogglePomodoroIntent: CallbackAction<TogglePomodoroIntent>(onInvoke: (intent) {
            final settings = context.read<SettingsProvider>();
            if (settings.isPomodoroActive) {
              settings.pausePomodoro();
            } else {
              settings.startPomodoro();
            }
            return null;
          }),
          ResetPomodoroIntent: CallbackAction<ResetPomodoroIntent>(onInvoke: (intent) {
            context.read<SettingsProvider>().resetPomodoro();
            return null;
          }),
          ToggleSprintIntent: CallbackAction<ToggleSprintIntent>(onInvoke: (intent) {
            final sprint = context.read<SprintController>();
            if (sprint.isActive) {
              sprint.stop();
            } else {
              final history = context.read<HistoryProvider>();
              sprint.start(currentWords: () => history.todayStats?.wordCountDelta ?? 0);
            }
            return null;
          }),
          AddNoteIntent: CallbackAction<AddNoteIntent>(onInvoke: (intent) {
            final ctx = navigatorKey.currentContext;
            if (ctx != null) {
              final notesProvider = ctx.read<NotesProvider>();
              final sync = ctx.read<SyncProvider>();
              notesProvider.addCard(category: 'general', syncProvider: sync);
              final newNoteId = notesProvider.cards.last.id;
              showDialog(
                context: ctx,
                builder: (context) => NoteEditorDialog(noteId: newNoteId),
              );
            }
            return null;
          }),
          OpenAttributionIntent: CallbackAction<OpenAttributionIntent>(onInvoke: (intent) {
            final ctx = navigatorKey.currentContext;
            if (ctx != null) {
              final notesProvider = ctx.read<NotesProvider>();
              final attributionCard = notesProvider.cards.cast<NoteCard?>().firstWhere(
                (c) => c!.isAttribution,
                orElse: () => null,
              );
              if (attributionCard == null) {
                final sync = ctx.read<SyncProvider>();
                notesProvider.addAttributionCard(syncProvider: sync);
                final newAttributionCard = notesProvider.cards.cast<NoteCard?>().firstWhere(
                  (c) => c!.isAttribution,
                  orElse: () => null,
                );

                if (newAttributionCard != null) {
                  // Sync to manuscript
                  final editor = ctx.read<EditorProvider>();
                  final settings = ctx.read<SettingsProvider>();
                  editor.syncAttributions(newAttributionCard, syncProvider: sync, projectName: settings.currentProjectName);

                  showDialog(
                    context: ctx,
                    builder: (context) => NoteEditorDialog(noteId: newAttributionCard.id),
                  );
                }
              } else {
                showDialog(
                  context: ctx,
                  builder: (context) => NoteEditorDialog(noteId: attributionCard.id),
                );
              }
            }
            return null;
          }),
          SetAlarmIntent: CallbackAction<SetAlarmIntent>(onInvoke: (intent) {
            final ctx = navigatorKey.currentContext;
            if (ctx != null) {
              showDialog(
                context: ctx,
                builder: (context) => const AlarmSetterDialog(),
              );
            }
            return null;
          }),
          ToggleFullscreenIntent: CallbackAction<ToggleFullscreenIntent>(onInvoke: (intent) async {
            final provider = context.read<ShortcutsProvider>();
            final newValue = !provider.isFullscreen;
            if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
              await windowManager.setFullScreen(newValue);
            }
            provider.setFullscreen(newValue);
            return null;
          }),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(onInvoke: (intent) {
            final state = navigatorKey.currentState;
            if (state == null) return null;

            bool isSettingsOpen = false;
            state.popUntil((route) {
              if (route.settings.name == '/settings') isSettingsOpen = true;
              return true;
            });

            if (isSettingsOpen) {
              state.pop();
            } else {
              final uiState = context.read<ShortcutsProvider>();
              // Flush stats in the background; do NOT block navigation on the Drive sync.
              unawaited(context.read<HistoryProvider>().saveStatsNow());
              state.push(MaterialPageRoute(
                settings: const RouteSettings(name: '/settings'),
                builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
              ));
            }
            return null;
          }),
          ToggleSearchIntent: CallbackAction<ToggleSearchIntent>(onInvoke: (intent) {
            navigatorKey.currentContext?.read<SearchProvider>().toggleSearch();
            return null;
          }),
          ToggleTypewriterIntent: CallbackAction<ToggleTypewriterIntent>(onInvoke: (intent) {
            final settings = context.read<SettingsProvider>();
            settings.toggleTypewriter(!settings.typewriterEnabled);
            return null;
          }),
          ToggleParagraphFocusIntent: CallbackAction<ToggleParagraphFocusIntent>(onInvoke: (intent) {
            final settings = context.read<SettingsProvider>();
            settings.toggleParagraphFocus(!settings.paragraphFocusEnabled);
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && (event.logicalKey.keyLabel.length == 1 || event.logicalKey == LogicalKeyboardKey.enter)) {
              final bypassedKeys = {
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
                LogicalKeyboardKey.digit5,
                LogicalKeyboardKey.digit6,
                LogicalKeyboardKey.enter,
                LogicalKeyboardKey.keyC,
                LogicalKeyboardKey.keyA,
                LogicalKeyboardKey.keyS,
                LogicalKeyboardKey.keyN,
                LogicalKeyboardKey.keyP,
                LogicalKeyboardKey.keyF,
              };
              if (bypassedKeys.contains(event.logicalKey)) {
                return KeyEventResult.ignored;
              }
              // Only swallow Alt-modified combos here (Win/Linux Alt shortcuts,
              // and macOS Cmd+Opt combos which also carry isAltPressed).
              // Plain macOS Cmd+<key> (meta without alt) is left ignored so
              // native menu items (Quit/Close/Minimize/Hide/Preferences, i.e.
              // Cmd+Q/W/M/H/,) can still be handled by AppKit's main menu.
              if (HardwareKeyboard.instance.isAltPressed) {
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: MacMenuBarWrapper(
            child: MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Pellucid',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blueGrey,
                  brightness: Brightness.light,
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blueGrey,
                  brightness: Brightness.dark,
                ),
              ),
              home: const EditorScreen(),
              builder: (context, child) {
                final bool isMobilePhone = isPhoneLayout(context);
                return Consumer<SettingsProvider>(
                  builder: (context, settings, _) {
                    return GlowingBorder(
                      isActive: !isMobilePhone && settings.isAlarmTriggered,
                      borderThickness: isMobilePhone ? 0.0 : 20.0,
                      color: Colors.red,
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
      ),
    );
  }
}
