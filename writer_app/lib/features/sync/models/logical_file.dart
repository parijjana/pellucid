// Description: The closed set of files Pellucid syncs into each project's
// folder in the user's Google Drive vault.
//
// This enum exists to make a historical, now-fixed production bug
// structurally impossible to reintroduce: `GoogleDriveSyncService.syncFile`
// used to take a bare `String` filename and unconditionally append `.md` to
// it. Callers disagreed about whether to include the extension themselves,
// so the manuscript ended up written to two different Drive files —
// `manuscript.md` (from callers that passed the bare name) and
// `manuscript.md.md` (from callers that already included `.md`). See
// docs/two-way-sync-design.md §1 for the full incident writeup and
// lib/features/sync/services/manuscript_migration.dart for the one-time
// Drive-side repair.
//
// With this enum, a bare string can never again reach the sync layer: every
// sync API takes a [LogicalFile], and exactly one place — [LogicalFileDriveName]
// below — knows how a logical file maps to a concrete Drive filename.
enum LogicalFile {
  manuscript,
  notes,
  stats,
}

/// The ONE place in the codebase that maps a [LogicalFile] to the exact
/// filename it is stored as in Drive. Nothing else should ever construct one
/// of these names by hand or by string concatenation.
extension LogicalFileDriveName on LogicalFile {
  String get driveFileName {
    switch (this) {
      case LogicalFile.manuscript:
        return 'manuscript.md';
      case LogicalFile.notes:
        return 'notes.md';
      case LogicalFile.stats:
        return 'stats.md';
    }
  }
}
