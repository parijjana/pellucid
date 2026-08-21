// Description: Shared responsive/input-context helpers.
//
// This is the single place that answers "what kind of device/input am I
// running on" for the rest of the app. It exists to de-duplicate a
// responsive check that used to be copy-pasted verbatim across five files
// (main.dart, editor_screen.dart, integrated_header.dart,
// editor_status_bar.dart, settings_screen.dart).
//
// IMPORTANT: [isPhoneLayout] is a pure refactor of that pre-existing logic.
// It must keep evaluating to exactly the same value as the old inline
// expression in every case, including the `kScreenshotCaptureMode` override
// used by the store-screenshot capture harness (see screenshot_mode.dart).
//
// [LayoutWidth]/[layoutWidthOf] and [PointerTypeNotifier] are new signals
// added ahead of later work (iPad Split View / Stage Manager support, which
// `shortestSide` cannot express, and mouse/trackpad detection). Nothing in
// the app consumes them yet — wiring them up is a separate task.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/editor/screenshot_mode.dart';

/// True on touch-first platforms (iOS/Android) and false everywhere else
/// (web, macOS, Windows, Linux). No [BuildContext] needed — this is a device
/// property, not a layout one.
bool get isTouchPlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// True on platforms whose native keyboard-shortcut convention uses Command
/// as the primary modifier: macOS and iOS/iPadOS. Everywhere else (Windows,
/// Linux, Android, web) the convention is Ctrl.
///
/// This exists so that iPad users with an attached hardware keyboard (Magic
/// Keyboard etc.) get Cmd-based shortcuts, matching iPadOS convention,
/// instead of falling through to the Ctrl/Alt combos that used to apply to
/// every non-macOS platform. Use this for `SingleActivator(meta: ..., control:
/// !...)`-style modifier selection instead of a raw `Platform.isMacOS` check.
///
/// NOT a substitute for `Platform.isMacOS` in non-keyboard contexts (window
/// chrome/traffic lights, the native macOS menu bar, the macOS spell-check
/// service, etc.) or for genuinely macOS-*specific* shortcut conventions
/// (e.g. the Ctrl+Cmd+F fullscreen convention in main.dart, which has no iOS
/// equivalent and must stay gated on `Platform.isMacOS` directly) — those
/// still need the raw macOS check.
bool get usesCommandModifier =>
    !kIsWeb && (Platform.isMacOS || Platform.isIOS);

/// Whether the current build should use the single-column "mobile phone"
/// layout.
///
/// This is EXACTLY the semantics of the `isMobilePhone` expression that used
/// to be duplicated inline at each call site:
///   - When the store-screenshot capture harness is active
///     ([kScreenshotCaptureMode]), the forced [kScreenshotLayout] wins
///     regardless of the real host platform/size, so the harness can render
///     the mobile layout on a desktop machine.
///   - Otherwise it's a real touch device ([isTouchPlatform]) whose shortest
///     side is under 600 logical pixels.
///
/// Note this is device-`shortestSide`-based, not width-based, so it cannot
/// distinguish an iPad Split View / Stage Manager pane from a full-width
/// iPad. That's a known limitation carried over unchanged from the old code;
/// see [LayoutWidth] for the width-based signal intended to replace it.
bool isPhoneLayout(BuildContext context) {
  if (kScreenshotCaptureMode) {
    return kScreenshotLayout == ScreenshotLayout.mobilePhone;
  }
  return isTouchPlatform && MediaQuery.of(context).size.shortestSide < 600;
}

/// A width-based layout class, derived from the current [BuildContext]'s
/// `MediaQuery` width (NOT `shortestSide`). Unlike [isPhoneLayout], this can
/// correctly narrow for an iPad Split View / Stage Manager pane, since it
/// tracks the actual available width rather than a fixed device property.
///
/// Breakpoints: `compact` < 600, `medium` 600–899, `expanded` >= 900.
///
/// Not wired into any consumer yet; added for later responsive work.
enum LayoutWidth { compact, medium, expanded }

/// Derives the current [LayoutWidth] from `MediaQuery.of(context).size.width`.
LayoutWidth layoutWidthOf(BuildContext context) {
  final double width = MediaQuery.of(context).size.width;
  if (width < 600) return LayoutWidth.compact;
  if (width < 900) return LayoutWidth.medium;
  return LayoutWidth.expanded;
}

/// Latches on the first sign of a mouse/trackpad, and never unlatches.
///
/// `hasPointer` starts `false` and flips permanently to `true` the first
/// time [onPointerHover] observes a hover event. Touch input never generates
/// hover events, so this is a reliable (one-way) signal that a pointer
/// device is in use. Not wired into any consumer yet; added for later
/// responsive/input work.
class PointerTypeNotifier extends ChangeNotifier {
  bool _hasPointer = false;

  /// True once a [PointerHoverEvent] has ever been observed. Sticky: never
  /// reverts to false, since a device that has a mouse/trackpad keeps it.
  bool get hasPointer => _hasPointer;

  /// Call this from a `Listener.onPointerHover` (or similar) high in the
  /// widget tree. No-ops after the first call.
  void onPointerHover(PointerHoverEvent event) {
    if (_hasPointer) return;
    _hasPointer = true;
    notifyListeners();
  }
}

/// Reads [PointerTypeNotifier.hasPointer] from the widget tree, subscribing
/// to rebuilds (`context.watch`) so callers repaint the instant a hover is
/// first observed.
///
/// Defaults to `true` (i.e. "assume a pointer device, same as before this
/// signal existed") when no [PointerTypeNotifier] is registered above
/// [context] — this is deliberately the pre-existing/legacy behavior of the
/// Ghost UI's dim-until-hover widgets, so any widget tree built without the
/// app's real provider set (most of the existing widget tests, which predate
/// this signal) keeps behaving exactly as it did before this signal was
/// wired up, instead of throwing a [ProviderNotFoundException].
bool hasPointerOrDefault(BuildContext context) {
  try {
    return context.watch<PointerTypeNotifier>().hasPointer;
  } on ProviderNotFoundException {
    return true;
  }
}

/// True only for a touch device that has never shown a sign of a real
/// pointer (mouse/trackpad) — i.e. exactly the case the Ghost UI's
/// dim-until-hover widgets cannot serve, because hover never fires there.
///
/// Deliberately short-circuits on [isTouchPlatform] rather than checking
/// [hasPointerOrDefault] alone: [PointerTypeNotifier] is registered
/// app-wide (not just on touch builds), and on a fresh desktop launch
/// `hasPointer` briefly reads `false` until the very first mouse-hover
/// event arrives. Without this platform short-circuit, that instant would
/// use the touch-resting treatment on macOS/Windows/Linux too — a real,
/// if tiny, desktop behavior change. Desktop must be unaffected, so the
/// touch-specific styling only ever applies when [isTouchPlatform] is true.
bool isTouchWithoutPointer(BuildContext context) {
  return isTouchPlatform && !hasPointerOrDefault(context);
}
