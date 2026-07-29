// Standalone multi-store screenshot-capture entry point for Pellucid.
//
// Renders the editor and its panels off-screen (inside the running Flutter
// engine, never on the real screen) and rasterizes each scene via
// RenderRepaintBoundary.toImage at a per-target logical size + pixelRatio, then
// writes store-spec PNGs. Because it captures the widget tree's own layer it
// needs no Screen Recording permission and never shows the native window chrome.
//
// Run:  flutter run -d macos -t lib/screenshot_main.dart
//
// It opens a window, silently renders every (target x scene), writes the PNGs
// under store_screenshots/<store>/, prints SCREENSHOTS_WRITTEN_TO: + paths, exits.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'features/editor/screens/editor_screen.dart';
import 'features/editor/screenshot_mode.dart';
import 'features/editor/providers/theme_provider.dart';
import 'features/editor/providers/editor_provider.dart';
import 'features/editor/providers/sprint_controller.dart';
import 'features/editor/providers/shortcuts_provider.dart';
import 'features/settings/providers/history_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/sync/providers/sync_provider.dart';
import 'features/sidebar/providers/notes_provider.dart';
import 'features/search/providers/search_provider.dart';
import 'features/sidebar/widgets/snapshot_management_dialog.dart';
import 'screenshot_seed.dart';

const String _outRoot = '/Users/animeshsarkar/code/projects/pellucid/writer_app/store_screenshots';

// ---------------------------------------------------------------------------
// OVERFLOW ATTRIBUTION (harness-side, framework ground truth). A single
// FlutterError.onError hook (installed in main()) records any RenderFlex
// "overflowed" layout error against the shot being rendered RIGHT NOW
// (_currentShotId), which is set BEFORE setState for each shot so errors thrown
// during the build / _settle() layout pass attribute to the correct shot. Each
// shot's list is folded into its capture_manifest.json entry.
// DEBUG-ONLY: Flutter only routes overflow errors here when assertions are on —
// never capture with --release/--profile or overflows go silently undetected.
// ---------------------------------------------------------------------------
final Map<String, List<String>> _overflowByShot = <String, List<String>>{};
String _currentShotId = '';

/// One store/device output target.
///
/// SOURCE OF TRUTH: rows below mirror `screenshot_targets` in
/// store-launch-kit/references/store-fields.json (store, device, dir, prefix,
/// logical w/h, ratio, layout, controls). px = w*ratio by h*ratio.
class _Target {
  final String store; // store id, matches store-fields.json (e.g. 'ios-app-store')
  final String device; // device id, matches store-fields.json (e.g. 'ipad-13-landscape')
  final String dir; // output subfolder under _outRoot; may be nested, e.g. 'ios/ipad13'
  final String prefix; // filename prefix to disambiguate orientations sharing a dir
  final double w, h, ratio; // logical size + pixelRatio (px = w*ratio by h*ratio)
  final ScreenshotLayout layout;
  final ScreenshotWindowControls controls;
  final List<int> scenes; // scene numbers to render (1..5)
  const _Target(this.store, this.device, this.dir, this.prefix, this.w, this.h,
      this.ratio, this.layout, this.controls, this.scenes);
}

// One row per screenshot_targets entry in store-fields.json. Multi-device stores
// use device subfolders (ios/iphone69, ios/ipad13, play/phone, play/tablet); those
// dirs hold no cross-device collision so filenames drop the device prefix — EXCEPT
// the landscape iPad, which shares ios/ipad13/ with portrait and is disambiguated
// by the 'land-' prefix. Single-device stores (mac, microsoft) stay flat, no prefix.
// Landscape is expressed purely by w>h (+ the forced MediaQuery size); the
// ScreenshotLayout enum is deliberately NOT expanded — landscape reuses .tablet.
const List<_Target> _targets = [
  // store             device               dir             prefix   w     h     ratio  layout                        controls                        scenes
  _Target('mac-app-store',   'mac',               'mac',          '',      1440, 900,  2.0, ScreenshotLayout.desktop,     ScreenshotWindowControls.macOS, [1, 2, 3, 4, 5]),
  _Target('microsoft-store', 'desktop',           'microsoft',    '',      1280, 720,  2.0, ScreenshotLayout.desktop,     ScreenshotWindowControls.none,  [1, 2, 3, 4, 5]),
  _Target('ios-app-store',   'iphone-6.9',        'ios/iphone69', '',      430,  932,  3.0, ScreenshotLayout.mobilePhone, ScreenshotWindowControls.none,  [1, 2, 3]),
  _Target('ios-app-store',   'ipad-13',           'ios/ipad13',   '',      1024, 1366, 2.0, ScreenshotLayout.tablet,      ScreenshotWindowControls.none,  [1, 2, 3, 4, 5]),
  // Landscape iPad 13" — shares the ios/ipad13 section (App Store Connect accepts
  // both orientations there). Defaults to the SAME scenes as portrait iPad; this
  // is a reviewer-tunable choice — a landscape composition may want a different subset.
  _Target('ios-app-store',   'ipad-13-landscape', 'ios/ipad13',   'land-', 1366, 1024, 2.0, ScreenshotLayout.tablet,      ScreenshotWindowControls.none,  [1, 2, 3, 4, 5]),
  _Target('google-play',     'phone',             'play/phone',   '',      360,  800,  3.0, ScreenshotLayout.mobilePhone, ScreenshotWindowControls.none,  [1, 2, 3]),
  _Target('google-play',     'tablet',            'play/tablet',  '',      800,  1280, 2.0, ScreenshotLayout.tablet,      ScreenshotWindowControls.none,  [1, 2, 3, 4, 5]),
];

const Map<int, String> _sceneNames = {
  1: '01-hero-editor',
  2: '02-navigation',
  3: '03-notes-codex',
  4: '04-writing-sprint',
  5: '05-version-history',
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Overflow hook (DEBUG-ONLY): attribute any RenderFlex "overflowed" error to the
  // shot rendering now (_currentShotId), then still present it normally. Flutter
  // only routes overflow errors here when assertions are on — never --release/--profile.
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains('overflowed')) {
      (_overflowByShot[_currentShotId] ??= <String>[]).add(msg.split('\n').first.trim());
    }
    FlutterError.presentError(details);
  };
  if (!kIsWeb && Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1480, 1000),
      center: true,
      title: 'Pellucid — Screenshot Capture',
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
    });
  }
  runApp(const _CaptureApp());
}

class _CaptureApp extends StatefulWidget {
  const _CaptureApp();
  @override
  State<_CaptureApp> createState() => _CaptureAppState();
}

class _CaptureAppState extends State<_CaptureApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<String> _written = [];
  final List<String> _skipped = [];
  final List<Map<String, dynamic>> _manifestShots = []; // one entry per written PNG
  bool _started = false;
  Widget? _shot;
  String _shotId = '';
  _Target _target = _targets.first;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  double _pageWidthFor(_Target t) =>
      t.layout == ScreenshotLayout.mobilePhone ? t.w - 24 : (t.w < 900 ? t.w - 120 : 820).toDouble();

  Widget _buildScene(int scene, _Target t) {
    final shortcuts = ShortcutsProvider();
    if (scene == 2) shortcuts.toggleLeftSidebar();
    if (scene == 3) shortcuts.toggleRightSidebar();

    final editor = ScreenshotEditorProvider(content: kManuscript, pageWidth: _pageWidthFor(t));
    final SprintController sprint = scene == 4 ? ScreenshotSprintController() : SprintController();

    Widget child = const EditorScreen();
    if (scene == 5) {
      child = Stack(
        children: [
          const Positioned.fill(child: EditorScreen()),
          const Positioned.fill(child: ColoredBox(color: Color(0x73000000))),
          const Center(child: SnapshotManagementDialog(projectName: kProjectTitle)),
        ],
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ShortcutsProvider>.value(value: shortcuts),
        ChangeNotifierProvider<EditorProvider>.value(value: editor),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<SettingsProvider>.value(value: ScreenshotSettingsProvider()),
        ChangeNotifierProvider<HistoryProvider>.value(value: ScreenshotHistoryProvider()),
        ChangeNotifierProvider<SyncProvider>.value(value: ScreenshotSyncProvider(seedRevisions())),
        ChangeNotifierProvider<NotesProvider>.value(value: ScreenshotNotesProvider(seedNotes())),
        ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
        ChangeNotifierProvider<SprintController>.value(value: sprint),
      ],
      child: child,
    );
  }

  Future<void> _run() async {
    for (final t in _targets) {
      Directory('$_outRoot/${t.dir}').createSync(recursive: true);
      for (final scene in t.scenes) {
        kScreenshotCaptureMode = true;
        kScreenshotLayout = t.layout;
        kScreenshotWindowControls = t.controls;
        final shotId = '${t.dir}/${t.prefix}${_sceneNames[scene]}';
        // Set the CURRENT shot id BEFORE setState so any overflow error thrown
        // during the build / _settle() layout pass attributes to this shot.
        _currentShotId = shotId;
        final sceneWidget = _buildScene(scene, t);
        setState(() {
          _target = t;
          _shotId = shotId;
          _shot = sceneWidget;
        });
        await _settle();
        await _capture(t, scene);
      }
    }
    _writeManifest();
    // ignore: avoid_print
    print('SCREENSHOTS_WRITTEN_TO: $_outRoot');
    for (final p in _written) {
      // ignore: avoid_print
      print(p);
    }
    if (_skipped.isNotEmpty) {
      // ignore: avoid_print
      print('SKIPPED: ${_skipped.join(' | ')}');
    }
    exit(0);
  }

  Future<void> _capture(_Target t, int scene) async {
    final rel = '${t.dir}/${t.prefix}${_sceneNames[scene]}.png';
    try {
      final ro = _boundaryKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        _skipped.add('$_shotId: no boundary');
        return;
      }
      final image = await ro.toImage(pixelRatio: t.ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        _skipped.add('$_shotId: encode failed');
        return;
      }
      final path = '$_outRoot/$rel';
      await File(path).writeAsBytes(data.buffer.asUint8List());
      _written.add(path);
      // Record the authoritative manifest entry. `overflow` reflects whatever the
      // FlutterError hook attributed to _shotId during this shot's layout/paint.
      final overflow = _overflowByShot[_shotId] ?? const <String>[];
      _manifestShots.add(<String, dynamic>{
        'file': rel,
        'store': t.store,
        'device': t.device,
        'dir': t.dir,
        'scene': scene,
        'expected_w': (t.w * t.ratio).round(),
        'expected_h': (t.h * t.ratio).round(),
        'overflow': overflow.isNotEmpty,
        'overflow_details': List<String>.from(overflow),
      });
      // ignore: avoid_print
      print('CAPTURED $path');
    } catch (e, st) {
      _skipped.add('$_shotId: $e');
      stderr.writeln('SHOT_ERROR $_shotId: $e\n$st');
    }
  }

  /// Writes the AUTHORITATIVE capture manifest that validate_screenshots.py reads.
  /// `file` paths are relative to _outRoot; expected_w/h are the exact store pixel
  /// sizes (logical x ratio); skipped[] lists shots that never produced a PNG.
  void _writeManifest() {
    final manifest = <String, dynamic>{
      'generated': DateTime.now().toUtc().toIso8601String(),
      'out_root': _outRoot,
      'shots': _manifestShots,
      'skipped': _skipped,
    };
    final path = '$_outRoot/capture_manifest.json';
    File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
    // ignore: avoid_print
    print('MANIFEST_WRITTEN: $path');
  }

  Future<void> _settle() async {
    for (var i = 0; i < 6; i++) {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Widget build(BuildContext context) {
    final shot = _shot;
    return MaterialApp(
      key: ValueKey(_shotId),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: shot == null
          ? const Scaffold(body: SizedBox.shrink())
          : Scaffold(
              body: Center(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: _target.w,
                  maxWidth: _target.w,
                  minHeight: _target.h,
                  maxHeight: _target.h,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: Size(_target.w, _target.h),
                      devicePixelRatio: _target.ratio,
                    ),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: SizedBox(width: _target.w, height: _target.h, child: shot),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
