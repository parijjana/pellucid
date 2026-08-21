// Description: The library's Drive -> local half, at the UI level. The point
// of these is that discovery and pull are DELIBERATE: nothing calls Drive
// until the user asks, and nothing lands on disk until they ask again.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/widgets/drive_projects_section.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';
import 'package:pellucid/features/sync/services/project_pull.dart';

class MockSyncProvider extends Mock implements SyncProvider {}

class MockSettingsProvider extends Mock implements SettingsProvider {}

class MockStorageService extends Mock implements StorageService {}

class _FakeStorageService extends Fake implements StorageService {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeStorageService());
  });

  late MockSyncProvider sync;
  late MockSettingsProvider settings;
  late MockStorageService storage;

  setUp(() {
    sync = MockSyncProvider();
    settings = MockSettingsProvider();
    storage = MockStorageService();

    when(() => sync.isLoggedIn).thenReturn(true);
    when(() => settings.masterDirectoryPath).thenReturn('/master');
    when(() => settings.refreshProjects()).thenAnswer((_) async {});
    when(() => settings.markProjectMirrored(any())).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriveProjectsSection(
                theme: WriterTheme.presets.first,
                storageService: storage,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('says nothing useful and calls nothing when signed out',
      (tester) async {
    when(() => sync.isLoggedIn).thenReturn(false);

    await pump(tester);

    expect(find.textContaining('Sign in to Google Drive'), findsOneWidget);
    verifyNever(() => sync.listRemoteProjects(
          masterPath: any(named: 'masterPath'),
          storageService: any(named: 'storageService'),
        ));
  });

  testWidgets('does not touch Drive until asked', (tester) async {
    await pump(tester);

    verifyNever(() => sync.listRemoteProjects(
          masterPath: any(named: 'masterPath'),
          storageService: any(named: 'storageService'),
        ));
    expect(find.text('Check Drive'), findsOneWidget);
  });

  testWidgets('lists the vault, offering only what is not on this device',
      (tester) async {
    when(() => sync.listRemoteProjects(
          masterPath: any(named: 'masterPath'),
          storageService: any(named: 'storageService'),
        )).thenAnswer((_) async => const [
          RemoteProject(name: 'Novel', existsLocally: true),
          RemoteProject(name: 'Sketches', existsLocally: false),
        ]);

    await pump(tester);
    await tester.tap(find.text('Check Drive'));
    await tester.pumpAndSettle();

    expect(find.text('Novel'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('Sketches'), findsOneWidget);
    expect(find.text('Copy here'), findsOneWidget);
    expect(find.textContaining('1 of 2 not on this device'), findsOneWidget);
  });

  testWidgets('a pull refreshes the local library and reports the outcome',
      (tester) async {
    when(() => sync.listRemoteProjects(
          masterPath: any(named: 'masterPath'),
          storageService: any(named: 'storageService'),
        )).thenAnswer((_) async =>
        const [RemoteProject(name: 'Sketches', existsLocally: false)]);
    when(() => sync.pullProject(
          projectName: any(named: 'projectName'),
          masterPath: any(named: 'masterPath'),
          storageService: any(named: 'storageService'),
        )).thenAnswer((_) async => const PullResult(
          projectName: 'Sketches',
          outcome: PullOutcome.pulled,
        ));

    await pump(tester);
    await tester.tap(find.text('Check Drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy here'));
    await tester.pumpAndSettle();

    verify(() => sync.pullProject(
          projectName: 'Sketches',
          masterPath: '/master',
          storageService: storage,
        )).called(1);
    // The grid above this section renders from the local library, which just
    // changed underneath it.
    verify(() => settings.refreshProjects()).called(1);
    expect(find.textContaining('Copied "Sketches"'), findsOneWidget);
  });

  testWidgets('a refused pull says the local copy was untouched',
      (tester) async {
    when(() => sync.listRemoteProjects(
          masterPath: any(named: 'masterPath'),
          storageService: any(named: 'storageService'),
        )).thenAnswer((_) async =>
        const [RemoteProject(name: 'Novel', existsLocally: false)]);
    when(() => sync.pullProject(
          projectName: any(named: 'projectName'),
          masterPath: any(named: 'masterPath'),
          storageService: any(named: 'storageService'),
        )).thenAnswer((_) async => const PullResult(
          projectName: 'Novel',
          outcome: PullOutcome.alreadyExistsLocally,
        ));

    await pump(tester);
    await tester.tap(find.text('Check Drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy here'));
    await tester.pumpAndSettle();

    expect(find.textContaining('was not touched'), findsOneWidget);
  });
}
