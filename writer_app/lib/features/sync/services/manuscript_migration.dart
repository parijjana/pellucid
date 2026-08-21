// Description: Pure decision logic for the one-time, data-preserving Drive
// migration that repairs the `manuscript.md` / `manuscript.md.md` filename
// bug (docs/two-way-sync-design.md §1). No I/O lives in this file on purpose:
// this logic decides the fate of irreplaceable user prose, so it is
// exhaustively unit-tested offline in
// test/features/sync/manuscript_migration_test.dart, with no Drive account
// or network involved.
//
// The actual I/O (listing Drive files, downloading/uploading content,
// recording completion) lives in `ManuscriptMigrationRunner` in
// lib/features/sync/providers/sync_provider.dart, which calls
// [decideManuscriptMigration] and acts on the result.

import '../models/logical_file.dart';

/// The exact filename Drive held for the manuscript before this fix, produced
/// when a caller passed `'manuscript.md'` into the old `syncFile`, which then
/// appended `.md` itself. NEVER deleted by the migration — kept in Drive
/// forever as a safety copy, even after a successful migration. Disk in
/// Drive is cheap; a user's words are not.
const String legacyManuscriptDriveFileName = 'manuscript.md.md';

/// The canonical, going-forward Drive filename for the manuscript. Matches
/// [LogicalFile.manuscript]'s mapping exactly, and matches the name the 24h
/// sweep and sign-in sync already used before this fix.
final String canonicalManuscriptDriveFileName = LogicalFile.manuscript.driveFileName;

/// What the one-time migration should do for a single project, given what
/// currently exists in that project's Drive folder.
enum ManuscriptMigrationAction {
  /// Neither `manuscript.md` nor `manuscript.md.md` exists (project never
  /// synced a manuscript). Nothing to migrate.
  noneExist,

  /// Only the canonical `manuscript.md` exists. Already correct; nothing to do.
  onlyCanonicalExists,

  /// Only the legacy `manuscript.md.md` exists. Its content must be copied
  /// into a newly created `manuscript.md`.
  onlyLegacyExists,

  /// Both exist and the legacy copy is strictly newer — the canonical file's
  /// content is stale and must be overwritten with the legacy content.
  legacyIsNewer,

  /// Both exist and canonical is newer or exactly as new — canonical already
  /// holds the right (or at least not-older) content. Nothing to copy.
  canonicalIsNewerOrEqual,

  /// Both exist but there isn't enough information to compare them safely
  /// (a required `modifiedTime` is missing/unusable). Never guess: abort this
  /// project and log it rather than risk overwriting newer content with older.
  ambiguousAbort,
}

/// The result of [decideManuscriptMigration]: an action plus convenience
/// getters used by the I/O runner.
class ManuscriptMigrationDecision {
  final ManuscriptMigrationAction action;
  const ManuscriptMigrationDecision(this.action);

  /// True for any outcome that requires copying legacy's content into canonical.
  bool get shouldCopyLegacyToCanonical =>
      action == ManuscriptMigrationAction.onlyLegacyExists ||
      action == ManuscriptMigrationAction.legacyIsNewer;

  /// True when nothing needs to change and the project can be marked done
  /// as-is (including the "neither file exists yet" case).
  bool get isTerminalNoOp =>
      action == ManuscriptMigrationAction.noneExist ||
      action == ManuscriptMigrationAction.onlyCanonicalExists ||
      action == ManuscriptMigrationAction.canonicalIsNewerOrEqual;

  /// True when the project must be skipped and logged rather than acted on.
  bool get isAbort => action == ManuscriptMigrationAction.ambiguousAbort;

  @override
  String toString() => 'ManuscriptMigrationDecision($action)';

  @override
  bool operator ==(Object other) =>
      other is ManuscriptMigrationDecision && other.action == action;

  @override
  int get hashCode => action.hashCode;
}

/// Pure decision function for the manuscript filename migration. No I/O.
///
/// [canonicalExists] / [legacyExists] describe whether `manuscript.md` /
/// `manuscript.md.md` currently exist in the project's Drive folder.
/// [canonicalModifiedTime] / [legacyModifiedTime] are their Drive
/// `modifiedTime`s and are only meaningful when the corresponding `*Exists`
/// flag is true; pass null when the file doesn't exist or its modifiedTime
/// couldn't be read.
///
/// Idempotency argument: after a caller acts on [shouldCopyLegacyToCanonical]
/// by overwriting/creating canonical with legacy's content, canonical's
/// `modifiedTime` becomes "now", which is at or after legacy's unchanged
/// `modifiedTime`. Re-running this function with the post-migration state
/// therefore yields [ManuscriptMigrationAction.canonicalIsNewerOrEqual] (a
/// no-op) — so calling this repeatedly, or interrupting and resuming a sweep
/// partway through, is always safe without needing to trust a persisted flag
/// alone (the runner keeps one anyway, as a fast-path and a belt-and-braces
/// measure, but correctness does not depend on it).
ManuscriptMigrationDecision decideManuscriptMigration({
  required bool canonicalExists,
  required bool legacyExists,
  DateTime? canonicalModifiedTime,
  DateTime? legacyModifiedTime,
}) {
  if (!canonicalExists && !legacyExists) {
    return const ManuscriptMigrationDecision(ManuscriptMigrationAction.noneExist);
  }
  if (canonicalExists && !legacyExists) {
    return const ManuscriptMigrationDecision(ManuscriptMigrationAction.onlyCanonicalExists);
  }
  if (!canonicalExists && legacyExists) {
    return const ManuscriptMigrationDecision(ManuscriptMigrationAction.onlyLegacyExists);
  }

  // Both exist. Never guess a winner without both timestamps.
  if (canonicalModifiedTime == null || legacyModifiedTime == null) {
    return const ManuscriptMigrationDecision(ManuscriptMigrationAction.ambiguousAbort);
  }

  if (legacyModifiedTime.toUtc().isAfter(canonicalModifiedTime.toUtc())) {
    return const ManuscriptMigrationDecision(ManuscriptMigrationAction.legacyIsNewer);
  }
  return const ManuscriptMigrationDecision(ManuscriptMigrationAction.canonicalIsNewerOrEqual);
}
