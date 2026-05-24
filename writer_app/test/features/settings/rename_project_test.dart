import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/settings/providers/settings_database.dart';
import 'package:pellucid/features/editor/widgets/integrated_header.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';

class MockSettingsDatabase extends Mock implements SettingsDatabase {}

void main() {
  late MemoryFileSystem fileSystem;
  late StorageService storageService;
  late MockSettingsDatabase mockSettingsDatabase;
  late SettingsProvider settingsProvider;

  setUp(() {
    fileSystem = MemoryFileSystem();
    storageService = StorageService(fileSystem: fileSystem);
    mockSettingsDatabase = MockSettingsDatabase();
    settingsProvider = SettingsProvider(
      settingsDatabase: mockSettingsDatabase,
      storageService: storageService,
    );

    when(() => mockSettingsDatabase.updateSetting(any(), any()))
        .thenAnswer((_) async {});
  });

  group('StorageService & SettingsProvider Project Renaming', () {
    test('StorageService.renameProject renames project folder on disk', () async {
      await storageService.initProject('/master', 'Project A', initialContent: 'Hello');
      
      final oldFile = fileSystem.file('/master/Project A/document.md');
      expect(await oldFile.exists(), true);

      final success = await storageService.renameProject('/master', 'Project A', 'Project B');
      expect(success, true);

      expect(await fileSystem.file('/master/Project A/document.md').exists(), false);
      expect(await fileSystem.file('/master/Project B/document.md').exists(), true);
    });

    test('StorageService.renameProject returns false if destination already exists', () async {
      await storageService.initProject('/master', 'Project A');
      await storageService.initProject('/master', 'Project B');

      final success = await storageService.renameProject('/master', 'Project A', 'Project B');
      expect(success, false);
    });

    test('SettingsProvider.renameProject protects User Manual from being renamed', () async {
      await settingsProvider.setMasterDirectory('/master');
      
      final success = await settingsProvider.renameProject('User Manual', 'New Manual');
      expect(success, false);
    });

    test('SettingsProvider.renameProject renames active project and updates DB', () async {
      await settingsProvider.setMasterDirectory('/master');
      await settingsProvider.createProject('My Project');

      when(() => mockSettingsDatabase.updateSetting('current_project_name', 'Renamed Project'))
          .thenAnswer((_) async {});

      final success = await settingsProvider.renameProject('My Project', 'Renamed Project');
      expect(success, true);
      expect(settingsProvider.currentProjectName, 'Renamed Project');
      
      verify(() => mockSettingsDatabase.updateSetting('current_project_name', 'Renamed Project')).called(1);
    });
  });

  group('IntegratedHeader Double-click Renaming Widget Tests', () {
    testWidgets('Double clicking triggers inline text editing, commits on Enter', (tester) async {
      String? renamedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntegratedHeader(
              theme: WriterTheme.presets.first,
              actionButton: const SizedBox.shrink(),
              projectName: 'Old Name',
              onRename: (val) {
                renamedValue = val;
              },
            ),
          ),
        ),
      );

      // Verify initial project name is displayed
      expect(find.text('OLD NAME'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Double-click the title text by sending two taps separated by a short delay
      await tester.tap(find.text('OLD NAME'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('OLD NAME'));
      await tester.pumpAndSettle();

      // Verify TextField is now displayed with initial text
      expect(find.byType(TextField), findsOneWidget);

      // Type new name and submit
      await tester.enterText(find.byType(TextField), 'New Cool Name');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Verify callback was triggered and TextField dismissed
      expect(renamedValue, 'New Cool Name');
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Double clicking is ignored for User Manual project', (tester) async {
      bool renameCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntegratedHeader(
              theme: WriterTheme.presets.first,
              actionButton: const SizedBox.shrink(),
              projectName: 'User Manual',
              onRename: (_) {
                renameCalled = true;
              },
            ),
          ),
        ),
      );

      // Double-click
      await tester.tap(find.text('USER MANUAL'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('USER MANUAL'));
      await tester.pumpAndSettle();

      // Verify no TextField is displayed (User Manual is protected)
      expect(find.byType(TextField), findsNothing);
      expect(renameCalled, false);
    });
  });
}
