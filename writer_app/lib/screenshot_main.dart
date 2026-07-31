// ============================================================================
// Standalone multi-store screenshot-capture entry point for Pellucid.
//
// Instantiated from
// ~/code/projects/store-launch-kit/templates/screenshot_main.dart.template
// (the hardened D1-D11 fix pass) over the unmodified Pellucid app — every
// {{TOKEN}} filled by pure text substitution, no template STRUCTURE
// hand-edited. This supersedes the earlier pre-hardening harness that used
// to live at lib/screenshot_main.dart; that version lacked the layout-error
// bucket, the animation-aware _settle() with per-frame anti-hang timeout,
// and the scene-mount guard below. See HARNESS_BACKLOG.md P1.
//
// Notably D5 (`Widget child = {{APP_ROOT_WIDGET}};` no longer `final`) was
// exercised by making the APP_ROOT_WIDGET substitution itself a ternary
// (`scene == 5 ? Stack(...) : const EditorScreen()`), which needed no new
// code slot — the single substitution site was expressive enough. D3/D4
// (five scaffolded scene slots, tokens out of `//` comments) meant the
// _sceneNames / _expectedWidget maps needed no `{{MORE_SCENES}}` /
// `{{MORE_SCENE_WIDGETS}}` lines at all for exactly 5 scenes (delete-only).
//
// This is a STANDALONE entry point. The shipped app never imports it, so it can
// freely flip the capture-mode flags and pull in the (also-standalone) seed file.
//
// The proven MECHANICS below are app-agnostic — keep them:
//   * a _Target struct + _targets list mirroring store-fields.json,
//   * off-screen OverflowBox + MediaQuery + RepaintBoundary at a fixed SizedBox,
//   * a fresh ValueKey per shot so each scene remounts cleanly,
//   * _settle() — pump until the tree stops ANIMATING (transientCallbackCount),
//     with a per-frame timeout so a stalled macOS window cannot hang the run,
//   * the scene-mount guard (_expectedWidget + _mountAndVerify): confirm the
//     right screen is actually mounted before rasterizing it,
//   * _capture() via RenderRepaintBoundary.toImage(pixelRatio:),
//   * the SCREENSHOTS_WRITTEN_TO: / CAPTURED / SKIPPED prints + exit(0),
//   * a FlutterError hook with TWO buckets (overflow + layout error) and an
//     authoritative capture_manifest.json.
//
// Run in DEBUG (assertions on — required for overflow/layout-error detection):
//   flutter run -d macos -t lib/screenshot_main.dart
//
// ---------------------------------------------------------------------------
// macOS APP SANDBOX — Pellucid's macos/Runner/DebugProfile.entitlements already
// sets com.apple.security.app-sandbox = <false/>, so the debug build writes to
// an absolute path with no entitlement change and no re-sign. Nothing to do.
// (For a sandboxed app, keep the sandbox ON and add a DEBUG-ONLY exception:
//   <key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
//   <array><string>{_outRoot}/</string></array>
//   <key>com.apple.security.network.server</key><true/>
// never in Release.entitlements. See
// ~/code/projects/lessons_learnt/flutter-macos-sandboxed-screenshot-capture.md)
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import 'package:provider/provider.dart';

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

// Absolute path to the output root — the repo's committed store_screenshots/
// directory. The harness creates <root>/<store>/ subfolders under it.
const String _outRoot =
    '/Users/animeshsarkar/code/projects/pellucid/writer_app/store_screenshots';

/// How long `_settle()` waits for a screen to stop animating before giving up
/// and rasterizing anyway (recording a settle timeout). Set this comfortably
/// above the app's LONGEST entrance animation, with room for slow frames.
const Duration _settleTimeout = Duration(seconds: 4);

/// Consecutive animation-free frames `_settle()` requires before it calls the
/// tree settled. >1 so a controller that chains into another is not mistaken
/// for a fully settled tree.
const int _quietFramesRequired = 3;

/// Longest a SINGLE `endOfFrame` await may block before `_settle()` gives up on
/// that frame. Not optional: macOS stops producing frames for an occluded window
/// or a sleeping display, and an un-timed-out `await endOfFrame` then hangs the
/// whole capture run forever (this cost one 37-minute dead run). [_settleTimeout]
/// cannot save it — a deadline checked BETWEEN awaits is never reached while one
/// await is blocked. Every `endOfFrame` here goes through `_awaitFrame()`.
const Duration _frameWaitTimeout = Duration(milliseconds: 500);

// ---------------------------------------------------------------------------
// LAYOUT-ERROR ATTRIBUTION (harness-side, framework ground truth).
//
// A single FlutterError.onError hook (installed in main()) records layout errors
// against the shot being rendered RIGHT NOW. `_currentShotId` is set BEFORE
// setState for each shot, so errors thrown during the build / _settle()
// layout+paint pass attribute to the correct shot. Each shot remounts a fresh
// MaterialApp (fresh render objects), so attribution is clean and the outer
// OverflowBox scaffold itself never throws. Each shot's lists are folded into its
// capture_manifest.json entry.
//
// TWO buckets, because they fail differently:
//   _overflowByShot     — 'overflowed': content too big for its box, but it
//                         still PAINTS. Visible as clipped/striped content.
//   _layoutErrorsByShot — layout ASSERTION failures ([_layoutErrorNeedles]):
//                         the subtree never gets a size, so it paints NOTHING.
//                         Strictly worse, and invisible to every other check —
//                         the PNG has perfect pixel dimensions and is BLANK. A
//                         hook watching only 'overflowed' shipped four blank
//                         gameplay shots in the reference app. See
//                         lessons_learnt/flutter-fittedbox-infinite-width-blank-subtree.md
//
// IMPORTANT: this ONLY works in DEBUG mode (assertions on). Flutter routes these
// through FlutterError.onError only when assertions run — NEVER capture with
// --release / --profile, or both classes go silently undetected.
// ---------------------------------------------------------------------------
final Map<String, List<String>> _overflowByShot = <String, List<String>>{};
final Map<String, List<String>> _layoutErrorsByShot = <String, List<String>>{};

/// Substrings identifying a layout failure that leaves a subtree UNPAINTED.
/// App-agnostic — these are rendering-library assertions, not app strings.
/// Each needle below was confirmed against the Flutter SDK's own
/// `rendering/box.dart` (`RenderBox.debugAssertDoesMeetConstraints`) — grep
/// that file if a future SDK changes the wording upstream.
const List<String> _layoutErrorNeedles = [
  'forces an infinite', // BoxConstraints forces an infinite width/height
  'given an infinite size', // "'$runtimeType' object was given an infinite size during layout." — the RESULT-side infinite-size failure. THIS is what actually fires for an infinite-width child (the constraints-side needle above does not catch it), and is exactly the blank-subtree-at-perfect-dimensions failure this bucket exists for.
  'did not set its size', // 'RenderBox did not set its size during layout.'
  'does not meet its constraints', // "'$runtimeType' does not meet its constraints."
  'was not laid out', // RenderBox was not laid out
  'hasSize', // 'child!.hasSize': is not true
  // Catch-all for anything else. NOTE: `details.exceptionAsString()` on a
  // FlutterError returns just the ErrorSummary text (i.e. the needles above),
  // NOT a "Failed assertion:" prefix — that prefix is Dart's own formatting of
  // a raw AssertionError.toString(), a DIFFERENT and less common path than the
  // `throwError(ErrorSummary(...))` / `FlutterError.fromParts(...)` path most
  // rendering-library failures take. This needle only catches the raw-assert case.
  'Failed assertion',
];

String _currentShotId = '';

/// One store/device output target.
///
/// SOURCE OF TRUTH: the rows below MUST mirror `screenshot_targets` in
/// ~/code/projects/store-launch-kit/references/store-fields.json
/// (store, device, dir, filename_prefix, logical_w/h, ratio, layout,
/// window_controls). store-fields.json also lists px_w/px_h = logical x ratio —
/// that is the exact pixel size each store expects; verify captured PNGs against
/// it (see the reference doc's verification checklist).
class _Target {
  final String
  store; // store id, e.g. 'ios-app-store' (matches store-fields.json)
  final String
  device; // device id, e.g. 'ipad-13-landscape' (matches store-fields.json)
  final String
  dir; // output subfolder under _outRoot; may be nested, e.g. 'ios/ipad13'
  final String
  prefix; // filename prefix to disambiguate orientations sharing a dir
  final double w,
      h,
      ratio; // logical size + pixelRatio  (px = w*ratio by h*ratio)
  final ScreenshotLayout layout;
  final ScreenshotWindowControls controls;
  final List<int> scenes; // scene numbers to render for this target
  const _Target(
    this.store,
    this.device,
    this.dir,
    this.prefix,
    this.w,
    this.h,
    this.ratio,
    this.layout,
    this.controls,
    this.scenes,
  );
}

// One row per screenshot_targets entry in store-fields.json.
// Phone portrait targets deliberately SKIP scenes 4 + 5 (writing sprint and
// version history are too cramped in a narrow portrait column).
const List<_Target> _targets = [
  // store             device               dir             prefix   w     h     ratio  layout                        controls                        scenes
  _Target(
    'mac-app-store',
    'mac',
    'mac',
    '',
    1440,
    900,
    2.0,
    ScreenshotLayout.desktop,
    ScreenshotWindowControls.macOS,
    [1, 2, 3, 4, 5],
  ),
  _Target(
    'microsoft-store',
    'desktop',
    'microsoft',
    '',
    1280,
    720,
    2.0,
    ScreenshotLayout.desktop,
    ScreenshotWindowControls.none,
    [1, 2, 3, 4, 5],
  ),
  _Target(
    'ios-app-store',
    'iphone-6.9',
    'ios/iphone69',
    '',
    430,
    932,
    3.0,
    ScreenshotLayout.mobilePhone,
    ScreenshotWindowControls.none,
    [1, 2, 3],
  ),
  _Target(
    'ios-app-store',
    'ipad-13',
    'ios/ipad13',
    '',
    1024,
    1366,
    2.0,
    ScreenshotLayout.tablet,
    ScreenshotWindowControls.none,
    [1, 2, 3, 4, 5],
  ),
  _Target(
    'ios-app-store',
    'ipad-13-landscape',
    'ios/ipad13',
    'land-',
    1366,
    1024,
    2.0,
    ScreenshotLayout.tablet,
    ScreenshotWindowControls.none,
    [1, 2, 3, 4, 5],
  ),
  _Target(
    'google-play',
    'phone',
    'play/phone',
    '',
    360,
    800,
    3.0,
    ScreenshotLayout.mobilePhone,
    ScreenshotWindowControls.none,
    [1, 2, 3],
  ),
  _Target(
    'google-play',
    'tablet',
    'play/tablet',
    '',
    800,
    1280,
    2.0,
    ScreenshotLayout.tablet,
    ScreenshotWindowControls.none,
    [1, 2, 3, 4, 5],
  ),
];

// Human-readable, zero-padded, ordered filenames per scene number. Exactly 5
// scenes filled — the template's {{MORE_SCENES}} line was deleted per its own
// FILL note for the 5-scene case (D3/D4 scaffolded 5 slots by default).
const Map<int, String> _sceneNames = {
  1: '01-hero-editor',
  2: '02-navigation',
  3: '03-notes-codex',
  4: '04-writing-sprint',
  5: '05-version-history',
};

// Scene number -> the NAME of the widget that must be MOUNTED inside the
// capture boundary for that scene. This is the scene-mount guard's oracle.
//
// Pellucid is a single-screen app: every scene renders EditorScreen and varies
// only by provider state, so the per-scene entries below name the widget that
// characterises each scene's composition:
//   1 hero          — the editor itself
//   2 navigation    — the Table-of-Contents / navigation sidebar
//   3 notes-codex   — the notes & research sidebar
//   4 writing-sprint— the sprint countdown widget in the status bar
//   5 version-history — the snapshot/version dialog stacked over the editor
//
// NOTE (see the template's TAUTOLOGY warning + HARNESS_BACKLOG.md P6): scenes
// 1-4 all keep EditorNavigationSidebar/NotesSidebar/SprintWidget permanently
// mounted (just translated off-screen), so these four entries do not actually
// discriminate a wrong-screen mistake between each other — only the scene-5
// dialog entry genuinely does, because SnapshotManagementDialog is absent in
// every other scene. Left at parity with the proven v1 run; not re-designed
// here (that is a separate, undecided feature per P6).
const Map<int, String> _expectedWidget = {
  1: 'EditorScreen',
  2: 'EditorNavigationSidebar',
  3: 'NotesSidebar',
  4: 'SprintWidget',
  5: 'SnapshotManagementDialog',
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Layout hook: attribute any layout error to the shot being rendered now
  // (_currentShotId), then still present it normally so it shows in the console.
  // DEBUG-ONLY — Flutter only routes these here when assertions are on. See the
  // note on _overflowByShot / _layoutErrorsByShot above; never run capture with
  // --release/--profile.
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    final first = msg.split('\n').first.trim();
    if (msg.contains('overflowed')) {
      (_overflowByShot[_currentShotId] ??= <String>[]).add(first);
    } else if (_layoutErrorNeedles.any(msg.contains)) {
      // Cap the list: one broken subtree can throw the same assertion on every
      // pumped frame, and an unbounded list would bloat the manifest.
      final bucket = _layoutErrorsByShot[_currentShotId] ??= <String>[];
      if (bucket.length < 10 && !bucket.contains(first)) bucket.add(first);
    }
    FlutterError.presentError(details);
  };
  // Capture always runs on macOS; a hidden title bar keeps host chrome out of
  // the window while the off-screen raster (which never includes it) is taken.
  if (!kIsWeb && Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1480, 1000), // just needs to be >= the largest logical target
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

  /// Shots whose tree never reached visual rest within [_settleTimeout] — each
  /// one may have been rasterized mid-animation, so it needs a human look.
  /// Surfaced by validate_screenshots.py check 8 [SETTLE].
  final List<String> _settleTimeouts = [];

  /// Shots that landed on the wrong screen and recovered on the retry.
  /// Informational: the written PNG is correct, but the flake is real.
  /// Surfaced by validate_screenshots.py as a non-fatal [scene-retry].
  final List<String> _sceneRetries = [];

  /// Shots still on the wrong screen AFTER the retry — the PNG shows a different
  /// screen than its filename claims. A validator failure (check 9 [SCENE]).
  final List<String> _sceneMismatches = [];

  /// Scenes whose [_expectedWidget] entry was never filled in, so the mount
  /// guard did not run for them. Reported, non-fatal.
  final Set<int> _guardUnset = <int>{};
  final List<Map<String, dynamic>> _manifestShots =
      []; // one entry per written PNG
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

  // Content width heuristic for Pellucid's centered reading column.
  double _pageWidthFor(_Target t) => t.layout == ScreenshotLayout.mobilePhone
      ? t.w - 24
      : (t.w < 900 ? t.w - 120 : 820).toDouble();

  /// Builds one fully-seeded scene, wired with whatever state the screen reads.
  Widget _buildScene(int scene, _Target t) {
    // Per-scene state: scene 2 opens the navigation sidebar, scene 3 opens the
    // notes/codex sidebar, scene 4 swaps in an active sprint controller, and
    // scene 5 stacks the version-history dialog over a scrimmed editor.
    final shortcuts = ShortcutsProvider();
    if (scene == 2) shortcuts.toggleLeftSidebar();
    if (scene == 3) shortcuts.toggleRightSidebar();

    final editor = ScreenshotEditorProvider(
      content: kManuscript,
      pageWidth: _pageWidthFor(t),
    );
    final SprintController sprint = scene == 4
        ? ScreenshotSprintController()
        : SprintController();

    // NOT `final` in the template (D5): a scene is allowed to swap the root
    // widget entirely. Exercised here via a ternary in the single
    // {{APP_ROOT_WIDGET}} substitution site — scene 5 wraps EditorScreen in a
    // Stack to overlay the version-history dialog, with no other code slot
    // needed.
    Widget child = scene == 5
        ? Stack(
            children: [
              const Positioned.fill(child: EditorScreen()),
              const Positioned.fill(
                child: ColoredBox(color: Color(0x73000000)),
              ),
              const Center(
                child: SnapshotManagementDialog(projectName: kProjectTitle),
              ),
            ],
          )
        : const EditorScreen();

    // Pellucid uses the `provider` package (MultiProvider + ChangeNotifier
    // seeds), confirmed from pubspec.yaml — not Riverpod. One provider line per
    // notifier EditorScreen's subtree reads, each backed by a thin
    // screenshot_seed.dart subclass/override.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ShortcutsProvider>.value(value: shortcuts),
        ChangeNotifierProvider<EditorProvider>.value(value: editor),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<SettingsProvider>.value(
          value: ScreenshotSettingsProvider(),
        ),
        ChangeNotifierProvider<HistoryProvider>.value(
          value: ScreenshotHistoryProvider(),
        ),
        ChangeNotifierProvider<SyncProvider>.value(
          value: ScreenshotSyncProvider(seedRevisions()),
        ),
        ChangeNotifierProvider<NotesProvider>.value(
          value: ScreenshotNotesProvider(seedNotes()),
        ),
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
        // Flip the gated flags for THIS shot before building the scene. Every
        // additive/gated edit in the app tree reads these synchronously.
        kScreenshotCaptureMode = true;
        kScreenshotLayout = t.layout;
        kScreenshotWindowControls = t.controls;
        final shotId = '${t.dir}/${t.prefix}${_sceneNames[scene]}';
        // Set the CURRENT shot id BEFORE setState so any overflow/layout error
        // thrown during the build / _settle() layout+paint pass attributes to
        // this shot. It stays at the BASE id across the retry below, so the
        // manifest entry still finds its errors.
        _currentShotId = shotId;
        // Build the scene ONCE. _buildScene() may MUTATE shared app state
        // (seeding a controller, starting a round, pushing a route), so the
        // retry below must remount THIS SAME widget rather than call the builder
        // again — see _mountAndVerify().
        final sceneWidget = _buildScene(scene, t);
        // Mount the scene and CHECK we actually landed on it. One retry with a
        // forced fresh mount clears the transient case; a second failure is
        // recorded and fails the validator rather than silently shipping a
        // screenshot of the wrong screen.
        var landed = await _mountAndVerify(sceneWidget, scene, t, shotId);
        if (!landed) {
          // Blank the tree first so the retry is a genuine remount and not a
          // no-op rebuild of an identical widget.
          setState(() {
            _shot = null;
            _shotId = '$shotId#blank';
          });
          await _awaitFrame();
          landed = await _mountAndVerify(
            sceneWidget,
            scene,
            t,
            '$shotId#retry',
          );
          // Land in EXACTLY ONE bucket (D2 fix): recorded only once we know
          // whether the retry recovered it or not. Recording into
          // _sceneRetries BEFORE attempting the retry (the pre-fix behavior)
          // meant a hard mismatch landed in BOTH buckets — contradictory
          // validator output claiming the shot both "recovered" and "shows
          // the WRONG screen". A recovered shot stays non-fatal; only a shot
          // still wrong after the retry fails the validator.
          if (landed) {
            _sceneRetries.add(
              '$shotId: ${_expectedWidget[scene]} not mounted '
              'on first try — recovered on retry',
            );
          } else {
            _sceneMismatches.add(
              '$shotId: ${_expectedWidget[scene]} still not '
              'mounted after retry',
            );
          }
        }
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
    if (_settleTimeouts.isNotEmpty) {
      // ignore: avoid_print
      print(
        'SETTLE_TIMEOUT (may be mid-animation, inspect these): '
        '${_settleTimeouts.join(' | ')}',
      );
    }
    if (_sceneRetries.isNotEmpty) {
      // ignore: avoid_print
      print(
        'SCENE_RETRY (landed on the wrong screen, recovered): '
        '${_sceneRetries.join(' | ')}',
      );
    }
    if (_sceneMismatches.isNotEmpty) {
      // ignore: avoid_print
      print(
        'SCENE_MISMATCH (PNG shows the WRONG screen): '
        '${_sceneMismatches.join(' | ')}',
      );
    }
    if (_layoutErrorsByShot.isNotEmpty) {
      // ignore: avoid_print
      print(
        'LAYOUT_ERRORS (subtree unpainted — these shots are BLANK): '
        '${_layoutErrorsByShot.keys.join(' | ')}',
      );
    }
    if (_guardUnset.isNotEmpty) {
      // ignore: avoid_print
      print(
        'SCENE_GUARD_UNSET (fill _expectedWidget for these scene numbers — '
        'the wrong-screen guard did NOT run): ${_guardUnset.join(', ')}',
      );
    }
    exit(0);
  }

  /// The widget name the scene-mount guard should look for, or null when the
  /// guard is not configured for [scene] — a missing entry, an empty string, or
  /// an unreplaced `{{TOKEN}}` left over from the scaffold. Unconfigured scenes
  /// are NOT failed; they are collected in [_guardUnset] and printed at the end
  /// so a half-filled [_expectedWidget] map is obvious rather than silent.
  String? _expectedWidgetFor(int scene) {
    final name = _expectedWidget[scene];
    if (name == null || name.isEmpty || name.contains('{{')) {
      _guardUnset.add(scene);
      return null;
    }
    return name;
  }

  /// Whether a widget whose runtimeType is named [typeName] is mounted anywhere
  /// under [ctx]. Debug-harness only — matching on a type NAME would break under
  /// release obfuscation, but this entry point never ships.
  bool _isMountedUnder(BuildContext ctx, String typeName) {
    var found = false;
    void walk(Element el) {
      if (found) return;
      if (el.widget.runtimeType.toString() == typeName) {
        found = true;
        return;
      }
      el.visitChildren(walk);
    }

    ctx.visitChildElements(walk);
    return found;
  }

  /// Mounts an ALREADY-BUILT [screen] for [t] under [shotId], settles, and
  /// returns whether the expected widget for [scene] is actually mounted inside
  /// the capture boundary (see [_expectedWidget]); true when no expectation is
  /// registered for the scene.
  ///
  /// Takes a PRE-BUILT widget rather than a scene number ON PURPOSE. Scene
  /// builders typically mutate shared app/provider state. An earlier version of
  /// this retry path re-invoked the builder, running those side effects a second
  /// time; that corrupted the seeded state and cascaded into the FOLLOWING
  /// target's shots. Build once per shot, mount as many times as needed.
  Future<bool> _mountAndVerify(
    Widget screen,
    int scene,
    _Target t,
    String shotId,
  ) async {
    setState(() {
      _target = t;
      _shotId = shotId;
      _shot = screen;
    });
    await _settle();
    final expected = _expectedWidgetFor(scene);
    if (expected == null) return true;
    final ctx = _boundaryKey.currentContext;
    // No live boundary context means there is nothing to photograph; let
    // _capture()'s existing 'no boundary' skip path report that rather than
    // double-failing here.
    if (ctx == null || !ctx.mounted) return true;
    return _isMountedUnder(ctx, expected);
  }

  Future<void> _capture(_Target t, int scene) async {
    final rel = '${t.dir}/${t.prefix}${_sceneNames[scene]}.png';
    // Report against _currentShotId, NOT _shotId: _shotId carries the
    // '#blank'/'#retry' suffixes from the scene-mount guard, while
    // _currentShotId stays at the base id the error hook attributed to.
    try {
      final ro = _boundaryKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        _skipped.add('$_currentShotId: no boundary');
        return;
      }
      // pixelRatio turns the logical (w x h) into the store's exact pixel size.
      final image = await ro.toImage(pixelRatio: t.ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        _skipped.add('$_currentShotId: encode failed');
        return;
      }
      final path = '$_outRoot/$rel';
      await File(path).writeAsBytes(data.buffer.asUint8List());
      _written.add(path);
      // Record the authoritative manifest entry for this written shot.
      final overflow = _overflowByShot[_currentShotId] ?? const <String>[];
      // `layout_errors` are assertion failures that leave a subtree UNPAINTED —
      // a shot can be pixel-perfect in size and still be blank.
      final layoutErrors =
          _layoutErrorsByShot[_currentShotId] ?? const <String>[];
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
        'layout_error': layoutErrors.isNotEmpty,
        'layout_error_details': List<String>.from(layoutErrors),
      });
      // ignore: avoid_print
      print('CAPTURED $path');
    } catch (e, st) {
      _skipped.add('$_currentShotId: $e');
      stderr.writeln('SHOT_ERROR $_currentShotId: $e\n$st');
    }
  }

  /// Writes the AUTHORITATIVE capture manifest that scripts/validate_screenshots.py
  /// reads. `file` paths are relative to _outRoot; expected_w/h are the exact store
  /// pixel sizes (logical x ratio). skipped[] lists shots that never produced a PNG
  /// (the validator treats each as a MISSING screenshot / failure).
  void _writeManifest() {
    final manifest = <String, dynamic>{
      'generated': DateTime.now().toUtc().toIso8601String(),
      'out_root': _outRoot,
      'shots': _manifestShots,
      'skipped': _skipped,
      'settle_timeouts': _settleTimeouts,
      'scene_retries': _sceneRetries,
      'scene_mismatches': _sceneMismatches,
    };
    final path = '$_outRoot/capture_manifest.json';
    File(
      path,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
    // ignore: avoid_print
    print('MANIFEST_WRITTEN: $path');
  }

  /// Awaits the next frame, but never blocks longer than [_frameWaitTimeout] —
  /// see that constant for why a bare `endOfFrame` can hang an entire run.
  /// EVERY `endOfFrame` in this file must go through here.
  Future<void> _awaitFrame() => WidgetsBinding.instance.endOfFrame.timeout(
    _frameWaitTimeout,
    onTimeout: () {},
  );

  /// Pumps frames until nothing is ANIMATING, so async-decoded content (SVGs,
  /// web/async fonts, images) and post-frame callbacks complete — and no shot is
  /// rasterized mid entrance-animation — before we rasterize.
  Future<void> _settle() async {
    // Minimum pump: lets first-frame post-frame callbacks register their
    // tickers, so we never sample the count before any animation has started.
    for (var i = 0; i < 6; i++) {
      await _awaitFrame();
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }

    final deadline = DateTime.now().add(_settleTimeout);
    var quietFrames = 0;
    while (quietFrames < _quietFramesRequired) {
      if (!DateTime.now().isBefore(deadline)) {
        _settleTimeouts.add(_currentShotId);
        break;
      }
      // An idle tree schedules no frames on its own, so ask for one; otherwise
      // `endOfFrame` would wait forever once everything has settled.
      WidgetsBinding.instance.scheduleFrame();
      await _awaitFrame();
      // Require CONSECUTIVE quiet frames so a controller that chains into
      // another is not mistaken for a fully settled tree.
      quietFrames = WidgetsBinding.instance.transientCallbackCount == 0
          ? quietFrames + 1
          : 0;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // Final breather for async decode work already scheduled above. Tune upward
    // if the app streams content in.
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Widget build(BuildContext context) {
    final shot = _shot;
    // Fresh ValueKey(_shotId) => MaterialApp remounts for every shot, so no
    // state bleeds between scenes. OverflowBox lets the child take the full
    // logical target size even though the host window may be smaller; the inner
    // MediaQuery makes the tree BELIEVE it is on a size==(w,h) device at the
    // target devicePixelRatio; the RepaintBoundary at a fixed SizedBox(w,h) is
    // exactly what _capture() rasterizes.
    return MaterialApp(
      key: ValueKey(_shotId),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
      ),
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
                      child: SizedBox(
                        width: _target.w,
                        height: _target.h,
                        child: shot,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
