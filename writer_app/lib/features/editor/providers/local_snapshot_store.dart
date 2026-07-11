// Description: Rolling on-device manuscript snapshot storage (Local Snapshot Safety Net).

import 'package:file/file.dart';

class LocalSnapshotRecord {
  final DateTime timestamp;
  final String filePath;

  const LocalSnapshotRecord({required this.timestamp, required this.filePath});
}

/// Persists rolling `.history/<timestamp>.md` snapshots inside a project folder,
/// independent of cloud sync. Composed into [StorageService] rather than mixed in,
/// keeping snapshot logic testable and storage_service.dart within the line budget.
class LocalSnapshotStore {
  static const int maxSnapshots = 50;
  static const String _historyDirName = '.history';

  final FileSystem _fileSystem;
  final DateTime Function() _clock;

  LocalSnapshotStore(this._fileSystem, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  Directory _historyDir(String projectPath) => _fileSystem.directory('$projectPath/$_historyDirName');

  String _formatTimestamp(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)}T${pad(dt.hour)}-${pad(dt.minute)}-${pad(dt.second)}';
  }

  DateTime? _parseTimestamp(String fileName) {
    final base = fileName.endsWith('.md') ? fileName.substring(0, fileName.length - 3) : fileName;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})$').firstMatch(base);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  Future<List<File>> _filesNewestFirst(Directory dir) async {
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> saveSnapshot(String projectPath, String content) async {
    if (content.isEmpty) return;

    final dir = _historyDir(projectPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final existing = await _filesNewestFirst(dir);
    if (existing.isNotEmpty && await existing.first.readAsString() == content) return;

    DateTime candidate = _clock();
    late File target;
    while (true) {
      target = _fileSystem.file('${dir.path}/${_formatTimestamp(candidate)}.md');
      if (!await target.exists()) break;
      candidate = candidate.add(const Duration(seconds: 1));
    }
    await target.writeAsString(content, flush: true);

    final updated = await _filesNewestFirst(dir);
    if (updated.length > maxSnapshots) {
      for (final file in updated.sublist(maxSnapshots)) {
        await file.delete();
      }
    }
  }

  Future<List<LocalSnapshotRecord>> listSnapshots(String projectPath) async {
    final dir = _historyDir(projectPath);
    if (!await dir.exists()) return [];

    final records = <LocalSnapshotRecord>[];
    for (final file in await _filesNewestFirst(dir)) {
      final timestamp = _parseTimestamp(_fileSystem.path.basename(file.path));
      if (timestamp != null) {
        records.add(LocalSnapshotRecord(timestamp: timestamp, filePath: file.path));
      }
    }
    return records;
  }

  Future<String> readSnapshot(String filePath) async {
    final file = _fileSystem.file(filePath);
    if (!await file.exists()) return '';
    return file.readAsString();
  }
}
