import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'features/editor/providers/editor_provider.dart';
import 'features/editor/providers/theme_provider.dart';
import 'features/editor/screens/editor_screen.dart';
import 'features/sidebar/providers/notes_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/settings/providers/history_provider.dart';
import 'features/sync/providers/sync_provider.dart';
import 'package:flutter/services.dart';
import 'features/editor/providers/shortcuts_provider.dart';
import 'features/editor/widgets/shortcuts.dart';
import 'features/settings/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  await windowManager.ensureInitialized();

  final editorProvider = EditorProvider();
  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  final historyProvider = HistoryProvider();
  final notesProvider = NotesProvider(); 
  final syncProvider = SyncProvider();

  await themeProvider.loadSettings();
  await editorProvider.loadSettings();
  await settingsProvider.loadSettings();
  await editorProvider.loadProject(settingsProvider.currentProjectPath);
  await notesProvider.loadProject(settingsProvider.currentProjectPath);

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: editorProvider),
        ChangeNotifierProvider.value(value: notesProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: historyProvider),
        ChangeNotifierProvider.value(value: syncProvider),
        ChangeNotifierProvider(create: (_) => ShortcutsProvider()),
      ],
      child: const WriterApp(),
    ),
  );
}

class WriterApp extends StatelessWidget {
  const WriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMac = Platform.isMacOS;
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Global Toggles
        SingleActivator(LogicalKeyboardKey.digit1, alt: !isMac, meta: isMac, control: isMac): const ToggleToCIntent(),
        SingleActivator(LogicalKeyboardKey.digit2, alt: !isMac, meta: isMac, control: isMac): const ToggleNotesIntent(),
        SingleActivator(LogicalKeyboardKey.digit3, alt: !isMac, meta: isMac, control: isMac): const ToggleToolbarIntent(),
        SingleActivator(LogicalKeyboardKey.digit4, alt: !isMac, meta: isMac, control: isMac): const OpenSettingsIntent(),
        const SingleActivator(LogicalKeyboardKey.f11): const ToggleFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.enter, alt: !isMac, meta: isMac, control: isMac): const ToggleFullscreenIntent(),
        
        // Status Bar Peeks
        SingleActivator(LogicalKeyboardKey.keyC, alt: !isMac, meta: isMac, control: isMac): const PeekClockIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, alt: !isMac, meta: isMac, control: isMac): const PeekSessionIntent(),
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
            return null;
          }),
          PeekSessionIntent: CallbackAction<PeekSessionIntent>(onInvoke: (intent) {
            context.read<ShortcutsProvider>().peekSession();
            return null;
          }),
          ToggleFullscreenIntent: CallbackAction<ToggleFullscreenIntent>(onInvoke: (intent) async {
            final provider = context.read<ShortcutsProvider>();
            final newValue = !provider.isFullscreen;
            await windowManager.setFullScreen(newValue);
            provider.setFullscreen(newValue);
            return null;
          }),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(onInvoke: (intent) {
            final state = navKey.currentState;
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
              state.push(MaterialPageRoute(
                settings: const RouteSettings(name: '/settings'),
                builder: (context) => SettingsScreen(isFullscreen: uiState.isFullscreen),
              ));
            }
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // SILENCE THE BELL: 
            // Return 'handled' for any Alt/Meta combo, but ONLY if it's NOT a standard 
            // text editing command (like Ctrl+C/V) or a character-producing key.
            // Flutter's Shortcut widget will have already processed the Intent 
            // because it is a parent of this Focus widget in the hierarchy I've built.
            if (event is KeyDownEvent && (event.logicalKey.keyLabel.length == 1 || event.logicalKey == LogicalKeyboardKey.enter)) {
              if (HardwareKeyboard.instance.isAltPressed || (isMac && HardwareKeyboard.instance.isMetaPressed)) {
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: MaterialApp(
            navigatorKey: navKey,
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
          ),
        ),
      ),
    );
  }
}
