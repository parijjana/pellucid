// Description: Exhaustive offline unit tests for decideManuscriptMigration,
// the pure decision function behind the one-time Drive-side manuscript
// filename migration (docs/two-way-sync-design.md §1). No Drive account, no
// network — this logic touches irreplaceable user data and must be provably
// correct without ever touching the real service.

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sync/services/manuscript_migration.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
  final earlier = t0.subtract(const Duration(minutes: 5));
  final later = t0.add(const Duration(minutes: 5));

  group('decideManuscriptMigration', () {
    test('neither file exists -> noneExist, terminal no-op, no copy', () {
      final decision = decideManuscriptMigration(
        canonicalExists: false,
        legacyExists: false,
      );

      expect(decision.action, ManuscriptMigrationAction.noneExist);
      expect(decision.isTerminalNoOp, isTrue);
      expect(decision.shouldCopyLegacyToCanonical, isFalse);
      expect(decision.isAbort, isFalse);
    });

    test('only canonical (manuscript.md) exists -> onlyCanonicalExists, terminal no-op, no copy', () {
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: false,
        canonicalModifiedTime: t0,
      );

      expect(decision.action, ManuscriptMigrationAction.onlyCanonicalExists);
      expect(decision.isTerminalNoOp, isTrue);
      expect(decision.shouldCopyLegacyToCanonical, isFalse);
      expect(decision.isAbort, isFalse);
    });

    test('only legacy (manuscript.md.md) exists -> onlyLegacyExists, must copy', () {
      final decision = decideManuscriptMigration(
        canonicalExists: false,
        legacyExists: true,
        legacyModifiedTime: t0,
      );

      expect(decision.action, ManuscriptMigrationAction.onlyLegacyExists);
      expect(decision.isTerminalNoOp, isFalse);
      expect(decision.shouldCopyLegacyToCanonical, isTrue);
      expect(decision.isAbort, isFalse);
    });

    test('both exist, legacy strictly newer -> legacyIsNewer, must copy', () {
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: true,
        canonicalModifiedTime: earlier,
        legacyModifiedTime: later,
      );

      expect(decision.action, ManuscriptMigrationAction.legacyIsNewer);
      expect(decision.isTerminalNoOp, isFalse);
      expect(decision.shouldCopyLegacyToCanonical, isTrue);
      expect(decision.isAbort, isFalse);
    });

    test('both exist, canonical strictly newer -> canonicalIsNewerOrEqual, no copy', () {
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: true,
        canonicalModifiedTime: later,
        legacyModifiedTime: earlier,
      );

      expect(decision.action, ManuscriptMigrationAction.canonicalIsNewerOrEqual);
      expect(decision.isTerminalNoOp, isTrue);
      expect(decision.shouldCopyLegacyToCanonical, isFalse);
      expect(decision.isAbort, isFalse);
    });

    test('both exist, timestamps exactly equal -> canonicalIsNewerOrEqual (biased against unnecessary copy), no copy', () {
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: true,
        canonicalModifiedTime: t0,
        legacyModifiedTime: t0,
      );

      expect(decision.action, ManuscriptMigrationAction.canonicalIsNewerOrEqual);
      expect(decision.shouldCopyLegacyToCanonical, isFalse);
    });

    test('both exist, canonical modifiedTime missing -> ambiguousAbort, never guess', () {
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: true,
        canonicalModifiedTime: null,
        legacyModifiedTime: t0,
      );

      expect(decision.action, ManuscriptMigrationAction.ambiguousAbort);
      expect(decision.isAbort, isTrue);
      expect(decision.isTerminalNoOp, isFalse);
      expect(decision.shouldCopyLegacyToCanonical, isFalse);
    });

    test('both exist, legacy modifiedTime missing -> ambiguousAbort, never guess', () {
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: true,
        canonicalModifiedTime: t0,
        legacyModifiedTime: null,
      );

      expect(decision.action, ManuscriptMigrationAction.ambiguousAbort);
      expect(decision.isAbort, isTrue);
    });

    test('both exist, both modifiedTimes missing -> ambiguousAbort, never guess', () {
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: true,
      );

      expect(decision.action, ManuscriptMigrationAction.ambiguousAbort);
      expect(decision.isAbort, isTrue);
    });

    test('timezone-normalized comparison: local-zone legacy time equal in absolute terms to UTC canonical is not treated as newer', () {
      final canonicalUtc = t0;
      final legacyLocalZoned = t0.toLocal(); // same instant, different representation
      final decision = decideManuscriptMigration(
        canonicalExists: true,
        legacyExists: true,
        canonicalModifiedTime: canonicalUtc,
        legacyModifiedTime: legacyLocalZoned,
      );

      expect(decision.action, ManuscriptMigrationAction.canonicalIsNewerOrEqual);
      expect(decision.shouldCopyLegacyToCanonical, isFalse);
    });

    group('idempotency: running the decision twice in a row changes nothing the second time', () {
      test('after copying legacy -> canonical (onlyLegacyExists case), re-running with post-migration state is a no-op', () {
        // First run: only legacy exists.
        final first = decideManuscriptMigration(
          canonicalExists: false,
          legacyExists: true,
          legacyModifiedTime: t0,
        );
        expect(first.shouldCopyLegacyToCanonical, isTrue);

        // Runner acts: creates canonical with legacy's content. Its
        // modifiedTime becomes "now", which is at/after legacy's (unchanged)
        // modifiedTime. Legacy is never touched, so its modifiedTime is
        // unchanged. Simulate the resulting state:
        final canonicalModifiedTimeAfterMigration = t0.add(const Duration(seconds: 1));

        final second = decideManuscriptMigration(
          canonicalExists: true,
          legacyExists: true, // legacy is NEVER deleted
          canonicalModifiedTime: canonicalModifiedTimeAfterMigration,
          legacyModifiedTime: t0, // unchanged
        );

        expect(second.action, ManuscriptMigrationAction.canonicalIsNewerOrEqual);
        expect(second.shouldCopyLegacyToCanonical, isFalse,
            reason: 'second run must not re-copy — that would be a wasted '
                'Drive write at best and a data race at worst');
      });

      test('after copying legacy -> canonical (legacyIsNewer case), re-running with post-migration state is a no-op', () {
        final first = decideManuscriptMigration(
          canonicalExists: true,
          legacyExists: true,
          canonicalModifiedTime: earlier,
          legacyModifiedTime: later,
        );
        expect(first.shouldCopyLegacyToCanonical, isTrue);

        final canonicalModifiedTimeAfterMigration = later.add(const Duration(seconds: 1));

        final second = decideManuscriptMigration(
          canonicalExists: true,
          legacyExists: true,
          canonicalModifiedTime: canonicalModifiedTimeAfterMigration,
          legacyModifiedTime: later, // legacy untouched
        );

        expect(second.action, ManuscriptMigrationAction.canonicalIsNewerOrEqual);
        expect(second.shouldCopyLegacyToCanonical, isFalse);
      });

      test('re-running a no-op case (onlyCanonicalExists) again is still a no-op', () {
        final decision = decideManuscriptMigration(
          canonicalExists: true,
          legacyExists: false,
          canonicalModifiedTime: t0,
        );
        final again = decideManuscriptMigration(
          canonicalExists: true,
          legacyExists: false,
          canonicalModifiedTime: t0,
        );

        expect(decision, again);
        expect(again.shouldCopyLegacyToCanonical, isFalse);
      });

      test('re-running the noneExist case again is still a no-op', () {
        final decision = decideManuscriptMigration(canonicalExists: false, legacyExists: false);
        final again = decideManuscriptMigration(canonicalExists: false, legacyExists: false);

        expect(decision, again);
        expect(again.isTerminalNoOp, isTrue);
      });
    });

    test('legacy file name constant is the exact historical bug artifact', () {
      expect(legacyManuscriptDriveFileName, 'manuscript.md.md');
    });

    test('canonical file name constant matches LogicalFile.manuscript mapping', () {
      expect(canonicalManuscriptDriveFileName, 'manuscript.md');
    });
  });
}
