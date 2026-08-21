// Description: Fork naming. The suffix is what keeps a device's forks
// distinct and stable across sessions, so getting it wrong either collides
// two devices' work or grows a new project every time the app is opened.

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/sync/services/project_fork.dart';

void main() {
  group('forkSuffixFor', () {
    test('every suffix survives the project-name validator', () {
      // A suffix using a character outside the allowlist would produce a fork
      // name that initProject silently refuses, losing the edit entirely.
      for (final device in ForkDevice.values) {
        final name = 'Novel${forkSuffixFor(device)}';
        expect(StorageService.isValidProjectName(name), isTrue,
            reason: 'invalid fork name for $device: $name');
      }
    });

    test('device classes are distinct, so two devices never share a fork', () {
      final suffixes = ForkDevice.values.map(forkSuffixFor).toSet();
      expect(suffixes.length, ForkDevice.values.length);
    });

    test('iPad and iPhone get the names the plan specifies', () {
      expect(forkSuffixFor(ForkDevice.iPad), '_iPad');
      expect(forkSuffixFor(ForkDevice.iPhone), '_iPhone');
    });
  });

  group('forkNameFor', () {
    test('appends the suffix', () {
      expect(forkNameFor('Novel', '_iPad'), 'Novel_iPad');
    });

    test('is stable — a second session reuses the same name', () {
      expect(forkNameFor('Novel', '_iPad'), forkNameFor('Novel', '_iPad'));
    });

    test('trims the source name so the result is a valid project name', () {
      final long = 'A' * StorageService.maxProjectNameLength;

      final forked = forkNameFor(long, '_iPad');

      expect(forked.length, lessThanOrEqualTo(StorageService.maxProjectNameLength));
      expect(StorageService.isValidProjectName(forked), isTrue);
    });

    test('truncation never eats the suffix — that would collide with the mirror',
        () {
      final long = 'A' * 200;

      final forked = forkNameFor(long, '_iPad');

      expect(forked.endsWith('_iPad'), isTrue);
      expect(forked, isNot(long));
    });

    test('a trailing space before the suffix is trimmed away', () {
      // 'Name ' + '_iPad' would be a name the validator accepts but that reads
      // as a typo in the library.
      final long = '${'A' * 94} B';
      final forked = forkNameFor(long, '_iPad');
      expect(forked.contains(' _iPad'), isFalse);
      expect(StorageService.isValidProjectName(forked), isTrue);
    });
  });
}
