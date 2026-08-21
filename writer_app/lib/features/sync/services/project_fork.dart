// Description: Pure naming logic for the iOS 1.0 fork-on-first-edit stopgap
// (docs/release-plan.md, "iOS 1.0 sync model").
//
// A project pulled out of the Drive vault is a MIRROR: another device owns
// it and keeps writing to it. Editing a mirror in place would put two
// writers on one file with no conflict handling, which is exactly what 1.2
// exists to solve. So the first edit forks the mirror into a normally owned
// project — `Novel` becomes `Novel_iPad` — and the mirror stays behind,
// read-only, still tracking Drive. Conflict-free by construction, and ugly
// on purpose: the alternative is silent divergence.
//
// The suffix is a DEVICE CLASS, not a device name. `UIDevice.current.name`
// and device_info_plus have both returned the generic model since iOS 16,
// so a real name is not available — which turns out better, because a stable
// suffix means a second session on the same iPad reuses the one fork instead
// of accumulating `Novel_iPad_2`.

import 'dart:io' show Platform;

import '../../editor/providers/storage_service.dart';

/// The class of device a fork was made on. Deliberately coarse.
enum ForkDevice { iPad, iPhone, mac, windows, linux, unknown }

/// The suffix appended to a mirrored project's name when it forks.
///
/// Only characters inside [StorageService.isValidProjectName]'s allowlist are
/// used, so a fork name can never be rejected by the name validator.
String forkSuffixFor(ForkDevice device) {
  switch (device) {
    case ForkDevice.iPad:
      return '_iPad';
    case ForkDevice.iPhone:
      return '_iPhone';
    case ForkDevice.mac:
      return '_Mac';
    case ForkDevice.windows:
      return '_PC';
    case ForkDevice.linux:
      return '_Linux';
    case ForkDevice.unknown:
      return '_Copy';
  }
}

/// This device's class. [isTablet] comes from the caller because deciding
/// iPad-vs-iPhone needs the layout's shortest side, which lives in the
/// widget tree, not in `Platform`.
ForkDevice currentForkDevice({required bool isTablet}) {
  if (Platform.isIOS) return isTablet ? ForkDevice.iPad : ForkDevice.iPhone;
  if (Platform.isMacOS) return ForkDevice.mac;
  if (Platform.isWindows) return ForkDevice.windows;
  if (Platform.isLinux) return ForkDevice.linux;
  return ForkDevice.unknown;
}

/// The name a mirror forks to, guaranteed to satisfy
/// [StorageService.isValidProjectName].
///
/// A long source name is truncated from the RIGHT of the base name so the
/// suffix always survives — a fork whose suffix was trimmed away would
/// collide with the mirror itself, and the two would then be indistinguishable
/// in the library.
String forkNameFor(String sourceName, String suffix) {
  final base = sourceName.trim();
  final maxBase = StorageService.maxProjectNameLength - suffix.length;
  final trimmedBase =
      base.length > maxBase ? base.substring(0, maxBase).trimRight() : base;
  return '$trimmedBase$suffix';
}

/// What happened when a mirror was forked.
enum ForkOutcome {
  /// A new project was created from the mirror's current content.
  created,

  /// A fork of this mirror already existed on this device, and was opened
  /// instead. Its content is NOT refreshed from the mirror — it holds edits
  /// from an earlier session, and overwriting them with the mirror's copy
  /// would destroy exactly the work this whole mechanism exists to protect.
  reused,

  /// The fork could not be made.
  failed,
}

class ForkResult {
  final String sourceName;
  final String forkName;
  final ForkOutcome outcome;
  final Object? error;

  const ForkResult({
    required this.sourceName,
    required this.forkName,
    required this.outcome,
    this.error,
  });

  bool get succeeded => outcome != ForkOutcome.failed;
}
