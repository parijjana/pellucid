// @trace FEAT-20260516-120000-0001
// Description: Local storage service for the editor (Multi-Project & Immediate Save).
// TestID: TEST-20260516-120000-0001

import 'dart:convert';
import 'package:file/file.dart';
import 'package:file/local.dart';
import '../../sidebar/providers/note_card.dart';
import '../../settings/providers/project_stats.dart';
import 'local_snapshot_store.dart';
import 'user_manual_seed.dart' as manual_seed;

class StorageService {
  final FileSystem _fileSystem;
  final LocalSnapshotStore _snapshotStore;
  static const String _docName = 'document.md';
  static const String _notesName = 'notes.json';
  static const String _statsName = 'stats.json';

  static const String userManualContent = manual_seed.userManualContent;

  StorageService({FileSystem? fileSystem, LocalSnapshotStore? snapshotStore})
      : _fileSystem = fileSystem ?? const LocalFileSystem(),
        _snapshotStore = snapshotStore ?? LocalSnapshotStore(fileSystem ?? const LocalFileSystem());

  Future<List<String>> listProjects(String masterPath) async {
    final dir = _fileSystem.directory(masterPath);
    if (!await dir.exists()) return [];
    
    final List<String> projects = [];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        projects.add(_fileSystem.path.basename(entity.path));
      }
    }
    return projects;
  }

  Future<void> initProject(String masterPath, String projectName, {String initialContent = ''}) async {
    final projectDir = _fileSystem.directory('$masterPath/$projectName');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
      await _fileSystem.file('${projectDir.path}/$_docName').writeAsString(initialContent);
      
      final notesJson = projectName == 'User Manual' ? manual_seed.userManualNotesJson() : '[]';
      await _fileSystem.file('${projectDir.path}/$_notesName').writeAsString(notesJson);
      await _fileSystem.file('${projectDir.path}/$_statsName').writeAsString(jsonEncode(ProjectStats().toJson()));
    }
  }

  Future<String> readDocument(String projectPath) async {
    try {
      final file = _fileSystem.file('$projectPath/$_docName');
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (e) {
      return '';
    }
  }

  Future<void> saveDocument(String projectPath, String content) async {
    final file = _fileSystem.file('$projectPath/$_docName');
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true); // Immediate flush to OS
  }

  Future<List<NoteCard>> readNotes(String projectPath) async {
    try {
      final file = _fileSystem.file('$projectPath/$_notesName');
      if (!await file.exists()) return [];
      final String content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((j) => NoteCard.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveNotes(String projectPath, List<NoteCard> cards) async {
    final file = _fileSystem.file('$projectPath/$_notesName');
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final String jsonString = jsonEncode(cards.map((c) => c.toJson()).toList());
    await file.writeAsString(jsonString, flush: true); // Immediate flush
  }

  // Project Stats I/O
  Future<ProjectStats> readProjectStats(String projectPath) async {
    try {
      final file = _fileSystem.file('$projectPath/$_statsName');
      ProjectStats stats;
      if (!await file.exists()) {
        stats = ProjectStats();
      } else {
        final String content = await file.readAsString();
        stats = ProjectStats.fromJson(jsonDecode(content));
      }

      if (stats.totalWordCount == 0) {
        final docFile = _fileSystem.file('$projectPath/document.md');
        if (await docFile.exists()) {
          final content = await docFile.readAsString();
          final trimmed = content.trim();
          if (trimmed.isNotEmpty) {
            final words = trimmed.split(RegExp(r'\s+')).length;
            stats = stats.copyWith(totalWordCount: words);
            await saveProjectStats(projectPath, stats);
          }
        }
      }
      return stats;
    } catch (e) {
      return ProjectStats();
    }
  }

  Future<void> saveProjectStats(String projectPath, ProjectStats stats) async {
    final file = _fileSystem.file('$projectPath/$_statsName');
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(stats.toJson()), flush: true);
  }

  // Categories I/O
  static const String _categoriesName = 'categories.json';

  Future<List<String>> readCategories(String projectPath) async {
    try {
      final file = _fileSystem.file('$projectPath/$_categoriesName');
      if (!await file.exists()) {
        return ['general', 'people', 'places', 'events'];
      }
      final String content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return List<String>.from(jsonList);
    } catch (e) {
      return ['general', 'people', 'places', 'events'];
    }
  }

  Future<void> saveCategories(String projectPath, List<String> categories) async {
    final file = _fileSystem.file('$projectPath/$_categoriesName');
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(categories), flush: true);
  }

  // Local Snapshot Safety Net (rolling `.history/` snapshots independent of cloud sync)
  Future<void> saveLocalSnapshot(String projectPath, String content) =>
      _snapshotStore.saveSnapshot(projectPath, content);

  Future<List<LocalSnapshotRecord>> listLocalSnapshots(String projectPath) =>
      _snapshotStore.listSnapshots(projectPath);

  Future<String> readLocalSnapshot(String filePath) => _snapshotStore.readSnapshot(filePath);

  Future<bool> renameProject(String masterPath, String oldName, String newName) async {
    final oldDir = _fileSystem.directory('$masterPath/$oldName');
    final newDir = _fileSystem.directory('$masterPath/$newName');
    if (await newDir.exists()) {
      return false;
    }
    if (await oldDir.exists()) {
      await oldDir.rename(newDir.path);
      return true;
    }
    return false;
  }
}
