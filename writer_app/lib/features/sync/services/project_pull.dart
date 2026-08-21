// Description: Pure decision logic for pulling a project OUT of the Drive
// vault and onto this device — the first Drive -> local path in the app
// (docs/release-plan.md, "Remaining for iOS 1.0"). Until now sync was
// upload-only: nothing enumerated the vault, so a fresh iPad opened to an
// empty library while the manuscript sat in Drive.
//
// As with manuscript_migration.dart, no I/O lives here. The decisions below
// govern whether a device is about to write over a user's prose, so they are
// tested offline with no Drive account or network involved. The I/O lives in
// SyncProvider.

import '../models/logical_file.dart';
import 'manuscript_migration.dart';

/// Which Drive file a project's manuscript should be read from.
///
/// Both filenames can exist at once — the `manuscript.md.md` bug produced
/// pairs, and the migration deliberately never deletes the legacy copy. A
/// device pulling from the vault therefore cannot assume the canonical name
/// is the current one: on a vault the migration has not yet swept, the legacy
/// file is the live one. Reading both and taking the newer is what makes an
/// iOS release independent of the Mac release train.
enum ManuscriptSource {
  /// Read `manuscript.md`.
  canonical,

  /// Read `manuscript.md.md` — it is the only copy, or the newer one.
  legacy,

  /// The project has no manuscript in Drive at all.
  none,

  /// Both exist but a `modifiedTime` is missing for one of them, so "newer"
  /// cannot be established. Refuse rather than guess: picking wrong here
  /// silently seeds the device with a stale draft, and every later edit
  /// compounds it.
  ambiguous,
}

/// Chooses which Drive file holds the live manuscript for a project.
///
/// Ties go to [ManuscriptSource.canonical]: equal timestamps mean the
/// migration has copied legacy forward, so the two agree and the canonical
/// name is the one going forward.
ManuscriptSource chooseManuscriptSource({
  required bool canonicalExists,
  required bool legacyExists,
  required DateTime? canonicalModifiedTime,
  required DateTime? legacyModifiedTime,
}) {
  if (!canonicalExists && !legacyExists) return ManuscriptSource.none;
  if (canonicalExists && !legacyExists) return ManuscriptSource.canonical;
  if (!canonicalExists && legacyExists) return ManuscriptSource.legacy;

  if (canonicalModifiedTime == null || legacyModifiedTime == null) {
    return ManuscriptSource.ambiguous;
  }

  return legacyModifiedTime.toUtc().isAfter(canonicalModifiedTime.toUtc())
      ? ManuscriptSource.legacy
      : ManuscriptSource.canonical;
}

/// The exact Drive filename a [ManuscriptSource] refers to.
String? driveFileNameFor(ManuscriptSource source) {
  switch (source) {
    case ManuscriptSource.canonical:
      return canonicalManuscriptDriveFileName;
    case ManuscriptSource.legacy:
      return legacyManuscriptDriveFileName;
    case ManuscriptSource.none:
    case ManuscriptSource.ambiguous:
      return null;
  }
}

/// How a single project pull ended.
enum PullOutcome {
  /// The project was written to the local master directory.
  pulled,

  /// A directory of that name already exists locally. Refused — a pull is a
  /// Drive -> local WRITE, and overwriting local prose with a remote copy is
  /// the exact data loss the whole sync design is built to avoid. Resolving a
  /// name that exists on both sides is two-way sync's job (1.2), not this
  /// path's.
  alreadyExistsLocally,

  /// Not signed in to Drive.
  notLoggedIn,

  /// The project folder exists in the vault but holds no manuscript, or the
  /// manuscript could not be downloaded.
  noManuscript,

  /// Both manuscript filenames exist and could not be ordered — see
  /// [ManuscriptSource.ambiguous].
  ambiguousManuscript,

  /// The pull threw.
  failed,
}

/// The result of pulling one project, including which of the optional files
/// came across. A pull that lands the manuscript but not the notes is a
/// success worth reporting honestly rather than a failure.
class PullResult {
  final String projectName;
  final PullOutcome outcome;

  /// Optional files that were present in Drive and written locally.
  final Set<LogicalFile> filesPulled;

  /// Files that were present in Drive but could not be parsed, and so were
  /// skipped rather than written as garbage. Never includes the manuscript,
  /// which is plain text and cannot fail to parse.
  final Set<LogicalFile> filesSkipped;

  final Object? error;

  const PullResult({
    required this.projectName,
    required this.outcome,
    this.filesPulled = const {},
    this.filesSkipped = const {},
    this.error,
  });

  bool get succeeded => outcome == PullOutcome.pulled;
}

/// A project in the Drive vault, paired with whether this device already has
/// it. The library UI needs both halves to say anything useful: a name that
/// exists on both sides is not offerable as a pull.
class RemoteProject {
  final String name;
  final bool existsLocally;

  const RemoteProject({required this.name, required this.existsLocally});

  bool get isPullable => !existsLocally;
}

/// Pairs the vault's project names with the local library.
///
/// Case-insensitive on purpose: Drive folder names are case-sensitive but
/// macOS and iOS filesystems are not, so "Novel" and "novel" would collide on
/// disk. Treating them as the same name means the collision is reported as
/// [PullOutcome.alreadyExistsLocally] instead of silently writing into the
/// existing project's directory.
List<RemoteProject> pairWithLocalProjects({
  required List<String> remoteNames,
  required List<String> localNames,
}) {
  final localLower = localNames.map((n) => n.toLowerCase()).toSet();
  final paired = remoteNames
      .map((name) => RemoteProject(
            name: name,
            existsLocally: localLower.contains(name.toLowerCase()),
          ))
      .toList();
  paired.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return paired;
}
