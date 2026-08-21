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

/// Why a read of a project file produced the value it did.
///
/// The distinction that matters is [failed] versus everything else: a value
/// that came back because the read *threw* tells us nothing about what is on
/// disk, so it must never be written back over the original.
enum ReadOutcome {
  /// The file was read and parsed. The value is what is on disk.
  ok,

  /// The file is not there. A new project, or one not yet pulled from Drive.
  /// The fallback value is a legitimate starting point.
  missing,

  /// The read threw — permission denied, an undownloaded iCloud/Drive
  /// placeholder, a corrupt or half-written file. The real content is
  /// UNKNOWN and the fallback value is a guess.
  failed,
}

/// The outcome of a read, alongside the value the caller should display.
///
/// Callers may render [value] in every case, but must consult [failed] before
/// persisting anything derived from it. Writing a fallback back to disk is how
/// a transient read error turns into permanent data loss.
class ReadResult<T> {
  final T value;
  final ReadOutcome outcome;

  /// The exception that caused [ReadOutcome.failed]; null otherwise.
  final Object? error;

  const ReadResult.ok(this.value)
      : outcome = ReadOutcome.ok,
        error = null;

  const ReadResult.missing(this.value)
      : outcome = ReadOutcome.missing,
        error = null;

  const ReadResult.failed(this.value, this.error) : outcome = ReadOutcome.failed;

  /// True when the content on disk is unknown. Do not overwrite it.
  bool get failed => outcome == ReadOutcome.failed;

  bool get missing => outcome == ReadOutcome.missing;
}

class StorageService {
  final FileSystem _fileSystem;
  final LocalSnapshotStore _snapshotStore;
  static const String _docName = 'document.md';
  static const String _notesName = 'notes.json';
  static const String _statsName = 'stats.json';

  static const String userManualContent = manual_seed.userManualContent;

  static const int maxProjectNameLength = 100;

  // Allowlist: letters, digits, spaces, underscore, hyphen, and dot. This
  // implicitly excludes path separators ('/', '\'), NUL and other control
  // characters, and any other characters that could be abused when the name
  // is interpolated directly into a filesystem path or Drive folder name.
  static final RegExp _validProjectNamePattern = RegExp(r'^[A-Za-z0-9 _.-]+$');

  /// Returns true iff [name] is safe to use as a project (directory) name.
  ///
  /// A name is invalid if, after trimming, it is empty; equals `.` or `..`;
  /// starts with `.`; contains a path separator, control character, or NUL;
  /// contains any character outside the allowlist; or exceeds
  /// [maxProjectNameLength] characters. Pure and side-effect free.
  static bool isValidProjectName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length > maxProjectNameLength) return false;
    if (trimmed == '.' || trimmed == '..') return false;
    if (trimmed.startsWith('.')) return false;
    if (!_validProjectNamePattern.hasMatch(trimmed)) return false;
    return true;
  }

  StorageService({FileSystem? fileSystem, LocalSnapshotStore? snapshotStore})
      : _fileSystem = fileSystem ?? const LocalFileSystem(),
        _snapshotStore = snapshotStore ?? LocalSnapshotStore(fileSystem ?? const LocalFileSystem());

  Future<List<String>> listProjects(String masterPath) async {
    try {
      final dir = _fileSystem.directory(masterPath);
      if (!await dir.exists()) return [];
      
      final List<String> projects = [];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          projects.add(_fileSystem.path.basename(entity.path));
        }
      }
      return projects;
    } catch (e) {
      return [];
    }
  }

  Future<void> initProject(String masterPath, String projectName, {String initialContent = ''}) async {
    if (!isValidProjectName(projectName)) return;
    final projectDir = _fileSystem.directory('$masterPath/$projectName');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
      await _fileSystem.file('${projectDir.path}/$_docName').writeAsString(initialContent);
      
      final notesJson = projectName == 'User Manual' ? manual_seed.userManualNotesJson() : '[]';
      await _fileSystem.file('${projectDir.path}/$_notesName').writeAsString(notesJson);
      await _fileSystem.file('${projectDir.path}/$_statsName').writeAsString(jsonEncode(ProjectStats().toJson()));
    }
  }

  /// Reads `document.md`, reporting *why* the result is what it is.
  ///
  /// A missing file and a failed read both yield an empty string, but only the
  /// former means the document is genuinely empty. Callers must not autosave
  /// over a [ReadOutcome.failed] result — that is how a transient read error
  /// becomes a destroyed manuscript.
  Future<ReadResult<String>> readDocument(String projectPath) async {
    try {
      final file = _fileSystem.file('$projectPath/$_docName');
      if (!await file.exists()) return const ReadResult.missing('');
      return ReadResult.ok(await file.readAsString());
    } catch (e) {
      return ReadResult.failed('', e);
    }
  }

  Future<void> saveDocument(String projectPath, String content) async {
    final file = _fileSystem.file('$projectPath/$_docName');
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true); // Immediate flush to OS
  }

  /// Reads `notes.json`. Same contract as [readDocument]: an empty list from a
  /// [ReadOutcome.failed] read is a guess, and saving it back deletes every
  /// note in the project.
  Future<ReadResult<List<NoteCard>>> readNotes(String projectPath) async {
    try {
      final file = _fileSystem.file('$projectPath/$_notesName');
      if (!await file.exists()) return const ReadResult.missing(<NoteCard>[]);
      final String content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return ReadResult.ok(jsonList.map((j) => NoteCard.fromJson(j)).toList());
    } catch (e) {
      return ReadResult.failed(const <NoteCard>[], e);
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
    if (!isValidProjectName(newName)) return false;
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
