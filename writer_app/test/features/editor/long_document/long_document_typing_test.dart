import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/widgets/editor_selection_actions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/shortcuts_provider.dart';
import 'package:pellucid/features/editor/providers/sprint_controller.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/screens/editor_screen.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';
import 'package:pellucid/features/settings/providers/history_provider.dart';
import 'package:pellucid/features/settings/providers/project_stats.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/sidebar/providers/notes_provider.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/token_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Db extends Mock implements SettingsDatabase {
  @override
  Future<void> updateSetting(String key, dynamic value) async {}
}
class _Storage extends Mock implements StorageService {}
class _Secrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}
class _Sync extends Mock implements SyncProvider {}
class _Hist extends Mock implements HistoryProvider {}
class _Notes extends Mock implements NotesProvider {}


String _manuscript() {
  final sb = StringBuffer();
  for (var c = 0; c < 20; c++) {
    sb.writeln('## Chapter ${c + 1}\n');
    for (var p = 0; p < 40; p++) {
      sb.writeln('It is a truth universally acknowledged, that a single man in possession of a good fortune, '
          'must be in want of a wife. However little known the feelings or views of such a man may be.\n');
    }
  }
  return sb.toString();
}

Future<EditorProvider> _mount(WidgetTester tester, String initial, String clipboard) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final editor = EditorProvider(storageService: _Storage(), settingsDatabase: _Db())..updateContent(initial);
  final sync = _Sync();
  when(() => sync.status).thenReturn(SyncStatus.idle);
  when(() => sync.isLoggedIn).thenReturn(false);
  when(() => sync.lastSynced).thenReturn(null);
  final hist = _Hist();
  when(() => hist.history).thenReturn([]);
  when(() => hist.currentProjectStats).thenReturn(ProjectStats());
  final notes = _Notes();
  when(() => notes.cards).thenReturn([]);
  final settings = SettingsProvider(
    settingsDatabase: _Db(),
    storageService: _Storage(),
    tokenStore: TokenStore(secrets: _Secrets(), prefs: SharedPreferences.getInstance),
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/charging'), (_) async => null);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') return {'text': clipboard};
    return null;
  });
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<EditorProvider>.value(value: editor),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<SyncProvider>.value(value: sync),
      ChangeNotifierProvider<HistoryProvider>.value(value: hist),
      ChangeNotifierProvider<NotesProvider>.value(value: notes),
      ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
      ChangeNotifierProvider<ShortcutsProvider>(create: (_) => ShortcutsProvider()),
      ChangeNotifierProvider<SprintController>(create: (_) => SprintController()),
    ],
    child: const MaterialApp(home: EditorScreen()),
  ));
  await tester.pump();
  _settings = settings;
  return editor;
}

/// What the engine does while Dart is busy: every key press sends the whole
/// field state (previous text plus the new character). Nothing is pumped
/// between them, as when a frame takes seconds.
void _typeRapidly(WidgetTester tester, String chars) {
  final st = tester.testTextInput.editingState!;
  var cur = st['text'] as String;
  var off = st['selectionBase'] as int;
  for (final ch in chars.split('')) {
    cur = cur.replaceRange(off, off, ch);
    off++;
    tester.testTextInput.updateEditingValue(TextEditingValue(text: cur, selection: TextSelection.collapsed(offset: off)));
  }
}

SettingsProvider? _settings;

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  _settings?.dispose();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('a large document pasted into a new project is in the windowed editor straight away', (tester) async {
    final text = _manuscript();
    expect(text.length, greaterThan(15000 * 6));
    final editor = await _mount(tester, '', text);
    expect(find.byType(WindowedEditor), findsNothing);
    tester.widget<EditableText>(find.byType(EditableText).first).focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(editor.content.length, text.length);
    expect(find.byType(WindowedEditor), findsOneWidget);
    await _done(tester);
  });

  for (final opened in [true, false]) {
    testWidgets('no keystroke is lost when characters arrive faster than frames (${opened ? 'opened' : 'pasted'} document)',
        (tester) async {
      final text = _manuscript();
      final editor = await _mount(tester, opened ? text : '', text);
      tester.widget<EditableText>(find.byType(EditableText).first).focusNode.requestFocus();
      await tester.pump();
      if (!opened) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(find.byType(WindowedEditor), findsOneWidget);
      final w = tester.state<WindowedEditorState>(find.byType(WindowedEditor));
      ActiveEditor.controller!.selection = TextSelection.collapsed(offset: text.length);
      await tester.pump();
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      const typed = 'the quick brown fox jumps over the lazy dog';
      _typeRapidly(tester, typed);
      await tester.pump();
      expect(editor.content.endsWith(typed), isTrue, reason: 'all ${typed.length} characters, in order');
      expect(editor.content.length, text.length + typed.length);
      await _done(tester);
    });
  }
}
