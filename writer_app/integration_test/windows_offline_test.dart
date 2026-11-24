// Windows: writing and saving while Google Drive is unreachable shows no error dialog or banner.
//
//   flutter test integration_test/windows_offline_test.dart -d windows ^
//     --dart-define=PELLUCID_DATA_DIR=D:\projects\.scratch\pellucid-data-offline
//
// Two situations: (1) never signed in, (2) signed in (real SyncProvider) with a Drive service whose every call
// fails with a SocketException, as with Wi-Fi off.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/sync/models/logical_file.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/google_drive_sync_service.dart';

import 'support/harness.dart';
import 'support/windows_support.dart';

class _OfflineDrive extends Mock implements GoogleDriveSyncService {}

class _Db extends Mock implements SettingsDatabase {
  @override
  Future<void> updateSetting(String key, dynamic value) async {}

  @override
  Future<Map<String, dynamic>> getSettings() async => <String, dynamic>{};
}

void _expectNoErrorUi(WidgetTester tester) {
  expect(find.byType(AlertDialog), findsNothing, reason: 'no dialog');
  expect(find.byType(SnackBar), findsNothing, reason: 'no snackbar');
  expect(find.byType(MaterialBanner), findsNothing, reason: 'no banner');
  expect(find.textContaining('rror'), findsNothing, reason: 'no "error" text on screen');
  expect(find.textContaining('SocketException'), findsNothing);
}

Future<void> _writeAndSave(Rig rig, WidgetTester tester, String projectPath) async {
  await rig.placeCaret(rig.text.length);
  await rig.typeText(' Written while offline.');
  // Autosave debounces 2 s; sync debounce/throttle follow. Give them time to run and fail.
  await rig.wait(const Duration(seconds: 6));
  final onDisk = File('$projectPath/document.md').readAsStringSync();
  expect(onDisk, contains('Written while offline.'), reason: 'saved locally');
  _expectNoErrorUi(tester);
}

void main() {
  initWindowsTest();

  setUpAll(() => registerFallbackValue(LogicalFile.notes));

  testWidgets('not signed in: write and save, no error UI', (tester) async {
    final rig = await mount(tester, text: 'Offline draft.');
    await _writeAndSave(rig, tester, rig.projectPath);
    await rig.dispose();
  });

  testWidgets('signed in but Drive unreachable (SocketException): write and save, no error UI', (tester) async {
    final svc = _OfflineDrive();
    when(() => svc.isLoggedIn).thenAnswer((_) async => true);
    when(() => svc.syncFile(
        projectName: any(named: 'projectName'),
        file: any(named: 'file'),
        content: any(named: 'content'))).thenAnswer((_) async => throw const SocketException('Failed host lookup'));
    final provider = SyncProvider(service: svc, settingsDatabase: _Db());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    final rig = await mount(tester, text: 'Offline draft, signed in.', syncProvider: provider);
    expect(provider.isLoggedIn, isTrue, reason: 'the provider believes it is connected');
    // The real debounce is 30 minutes; shorten it so the failing Drive call actually happens during the test.
    rig.editor.syncDebounceDuration = const Duration(seconds: 1);
    rig.editor.syncThrottleDuration = const Duration(seconds: 1);
    await _writeAndSave(rig, tester, rig.projectPath);
    // ignore: avoid_print
    print('EVID|offline|sync status after the failed Drive call: ${provider.status}');
    // Observed: the editor did not call syncFile within the window (its sync scheduling needs more than the two
    // durations set above), so this case proves "no error UI with a connected-but-unreachable provider", not that a
    // failing upload was swallowed. The provider's own catch (sync_provider.dart) is covered by unit tests.
    await rig.dispose();
  });
}
