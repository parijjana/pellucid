// Description: Offline tests for the pure pull decisions. These govern
// whether a device seeds itself from a stale draft, so they are exercised
// with no Drive account and no network — same discipline as
// manuscript_migration_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/sync/services/manuscript_migration.dart';
import 'package:pellucid/features/sync/services/project_pull.dart';

void main() {
  group('chooseManuscriptSource', () {
    ManuscriptSource choose({
      bool canonical = false,
      bool legacy = false,
      DateTime? canonicalAt,
      DateTime? legacyAt,
    }) =>
        chooseManuscriptSource(
          canonicalExists: canonical,
          legacyExists: legacy,
          canonicalModifiedTime: canonicalAt,
          legacyModifiedTime: legacyAt,
        );

    test('no manuscript in Drive at all', () {
      expect(choose(), ManuscriptSource.none);
    });

    test('only the canonical name', () {
      expect(choose(canonical: true), ManuscriptSource.canonical);
    });

    test('only the legacy name — an unmigrated vault', () {
      // The case that makes iOS independent of the Mac release train: the
      // desktop fix has not shipped, so `manuscript.md.md` is the live file.
      expect(choose(legacy: true), ManuscriptSource.legacy);
    });

    test('both exist, legacy is newer', () {
      expect(
        choose(
          canonical: true,
          legacy: true,
          canonicalAt: DateTime.utc(2026, 8, 1),
          legacyAt: DateTime.utc(2026, 8, 2),
        ),
        ManuscriptSource.legacy,
      );
    });

    test('both exist, canonical is newer', () {
      expect(
        choose(
          canonical: true,
          legacy: true,
          canonicalAt: DateTime.utc(2026, 8, 2),
          legacyAt: DateTime.utc(2026, 8, 1),
        ),
        ManuscriptSource.canonical,
      );
    });

    test('a tie goes to canonical — the migration copied legacy forward', () {
      final t = DateTime.utc(2026, 8, 2);
      expect(
        choose(canonical: true, legacy: true, canonicalAt: t, legacyAt: t),
        ManuscriptSource.canonical,
      );
    });

    test('compares across time zones in UTC', () {
      // Same instant, different zones: must not read as "newer".
      final utc = DateTime.utc(2026, 8, 2, 12);
      expect(
        choose(
          canonical: true,
          legacy: true,
          canonicalAt: utc,
          legacyAt: utc.add(const Duration(seconds: 1)).toLocal(),
        ),
        ManuscriptSource.legacy,
      );
    });

    test('a missing timestamp on either side is ambiguous, never a guess', () {
      expect(
        choose(canonical: true, legacy: true, canonicalAt: DateTime.utc(2026)),
        ManuscriptSource.ambiguous,
      );
      expect(
        choose(canonical: true, legacy: true, legacyAt: DateTime.utc(2026)),
        ManuscriptSource.ambiguous,
      );
    });
  });

  group('driveFileNameFor', () {
    test('maps to the exact Drive filenames, never built by hand', () {
      expect(driveFileNameFor(ManuscriptSource.canonical),
          canonicalManuscriptDriveFileName);
      expect(driveFileNameFor(ManuscriptSource.legacy),
          legacyManuscriptDriveFileName);
      expect(driveFileNameFor(ManuscriptSource.none), isNull);
      expect(driveFileNameFor(ManuscriptSource.ambiguous), isNull);
    });
  });

  group('pairWithLocalProjects', () {
    test('marks projects this device already has as not pullable', () {
      final paired = pairWithLocalProjects(
        remoteNames: ['Novel', 'Sketches'],
        localNames: ['Novel'],
      );

      expect(paired.map((p) => p.name), ['Novel', 'Sketches']);
      expect(paired.first.isPullable, isFalse);
      expect(paired.last.isPullable, isTrue);
    });

    test('matches case-insensitively — the filesystem does', () {
      // Drive folder names are case-sensitive; macOS and iOS paths are not.
      // "novel" must not be offered as a pull beside an existing "Novel".
      final paired = pairWithLocalProjects(
        remoteNames: ['novel'],
        localNames: ['Novel'],
      );

      expect(paired.single.isPullable, isFalse);
    });

    test('sorts case-insensitively so the list reads alphabetically', () {
      final paired = pairWithLocalProjects(
        remoteNames: ['zebra', 'Apple', 'banana'],
        localNames: const [],
      );

      expect(paired.map((p) => p.name), ['Apple', 'banana', 'zebra']);
    });

    test('an empty vault yields nothing', () {
      expect(
        pairWithLocalProjects(remoteNames: const [], localNames: ['Novel']),
        isEmpty,
      );
    });
  });
}
