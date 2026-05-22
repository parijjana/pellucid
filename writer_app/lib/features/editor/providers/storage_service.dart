// @trace FEAT-20260516-120000-0001
// Description: Local storage service for the editor (Multi-Project & Immediate Save).
// TestID: TEST-20260516-120000-0001

import 'dart:convert';
import 'package:file/file.dart';
import 'package:file/local.dart';
import '../../sidebar/providers/note_card.dart';
import '../../settings/providers/project_stats.dart';

class StorageService {
  final FileSystem _fileSystem;
  static const String _docName = 'document.md';
  static const String _notesName = 'notes.json';
  static const String _statsName = 'stats.json';

  static const String userManualContent = '''
# Welcome to Pellucid

Pellucid is a distraction-free writing environment designed to let your words breathe. Every interface element is a "Ghost"—barely visible until you need it—ensuring your manuscript remains the center of your universe.

## Core Features

- **Pellucid Interaction:** UI elements (like the status bar and project name) default to 20% opacity. Hover over them with your mouse to bring them into full focus.
- **Dynamic Table of Contents:** Use # headers to automatically build a navigation map in the left sidebar (Alt + 1).
- **Research Notes:** Jot down thoughts, lore, or character details in the right sidebar (Alt + 2).
- **Physical Paper Controls:** Use the "Ghost Bar" at the bottom to physically move or resize your paper area.

## Cloud Synchronization: Pellucid Vault

Your work is automatically backed up to Google Drive. This isn't a "Black Box"—Pellucid creates a visible folder called **Pellucid Vault** in your Drive so you always own your data.

### How to Connect
1. Open **Settings** (Alt + 4).
2. Choose a **Master Storage Folder** on your computer.
3. Click **CONNECT** under Google Drive Backup.
4. Authorize in your browser, and your "Vault" will be created instantly.

## Keyboard Navigation (Mouse-Free)

Pellucid is designed to be operated entirely from the keyboard.

### UI Toggles (Alt / Cmd+Opt)
- **Alt + 1**: Toggle Table of Contents
- **Alt + 2**: Toggle Research Notes
- **Alt + 3**: Toggle Formatting Toolbar
- **Alt + 4**: Open Dashboard / Settings
- **Alt + Enter**: Toggle Fullscreen (F11 also works)

### Formatting (Alt / Cmd+Opt)
- **Alt + T**: Set line as Title
- **Alt + H**: Set line as Header
- **Alt + G**: Set line as Body text
- **Alt + L**: Set line as Bullet point
- **Ctrl + B / I**: Standard Bold and Italic

### Notes Workflow
- **Alt + N**: Add New Note
- **Alt + M**: Cycle Note Category
- **Alt + B**: Save and Close Note

## Physical Alignment
- **Alt + Left/Right**: Adjust Page Width
- **Alt + Shift + Left/Right**: Shift Paper Position

---
*Build Timestamp: 2026-05-21 17:55*
''';

  StorageService({FileSystem? fileSystem}) : _fileSystem = fileSystem ?? const LocalFileSystem();

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
      await _fileSystem.file('${projectDir.path}/$_notesName').writeAsString('[]');
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
      if (!await file.exists()) return ProjectStats();
      final String content = await file.readAsString();
      return ProjectStats.fromJson(jsonDecode(content));
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
}
