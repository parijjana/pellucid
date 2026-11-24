// Shared bits for the Windows-only integration tests (real native channels, real window).
//
// Every run must be started with --dart-define=PELLUCID_DATA_DIR=D:\projects\.scratch\pellucid-data-<purpose>
// so settings, shared_preferences and temp files stay on D:. [initWindowsTest] refuses to run otherwise.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pellucid/core/data_dir_override.dart';

IntegrationTestWidgetsFlutterBinding initWindowsTest() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    throw StateError('These tests are Windows-only.');
  }
  applyDataDirOverride(); // the tests do not go through lib/main.dart
  final root = dataDirOverride;
  if (root == null || !root.toUpperCase().startsWith('D:\\')) {
    throw StateError('Run with --dart-define=PELLUCID_DATA_DIR=D:\\projects\\.scratch\\pellucid-data-<purpose> '
        '(got "$root").');
  }
  return binding;
}

/// Fails if app-owned folders are not under the D: override.
Future<void> expectDataOnD() async {
  final root = dataDirOverride!;
  for (final p in [
    (await getApplicationSupportDirectory()).path,
    (await getTemporaryDirectory()).path,
  ]) {
    expect(p.toLowerCase().startsWith(root.toLowerCase()), isTrue, reason: '$p is under $root');
  }
}

/// Opt-in flag for tests that touch state outside D: (the Windows user spelling dictionary).
const bool kAllowLearn = bool.fromEnvironment('PELLUCID_TEST_ALLOW_LEARN');
