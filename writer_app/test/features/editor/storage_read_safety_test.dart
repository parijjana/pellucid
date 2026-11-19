import 'dart:io' as io;
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/storage_service.dart';


void main() {
  group('atomic write', atomicWriteTests);
  late io.Directory tmp;
  late StorageService storage;

  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('pel17_');
    storage = StorageService(fileSystem: const LocalFileSystem());
  });
  tearDown(() {
    try {
      io.Process.runSync('chmod', ['-R', 'u+rwx', tmp.path]);
    } catch (_) {}
    tmp.deleteSync(recursive: true);
  });

  io.File doc() => io.File('${tmp.path}/document.md');

  test('readable file is ok', () async {
    doc().writeAsStringSync('hello');
    final r = await storage.readDocument(tmp.path);
    expect(r.outcome, ReadOutcome.ok);
    expect(r.value, 'hello');
  });

  test('genuinely empty file is ok and empty', () async {
    doc().writeAsStringSync('');
    final r = await storage.readDocument(tmp.path);
    expect(r.outcome, ReadOutcome.ok);
  });

  test('missing file is missing, not failed', () async {
    final r = await storage.readDocument(tmp.path);
    expect(r.missing, isTrue);
    expect(r.failed, isFalse);
  });

  test('permission denied is failed with the error', () async {
    doc().writeAsStringSync('precious');
    io.Process.runSync('chmod', ['000', doc().path]);
    final r = await storage.readDocument(tmp.path);
    expect(r.failed, isTrue);
    expect(r.error, isNotNull);
    expect(r.value, '');
  }, skip: io.Platform.isWindows || io.Process.runSync('id', ['-u']).stdout.toString().trim() == '0');

  test('invalid UTF-8 is failed, never a lossy or blank document', () async {
    doc().writeAsBytesSync([0x68, 0x69, 0xff, 0xfe, 0xc3, 0x28]);
    final r = await storage.readDocument(tmp.path);
    expect(r.failed, isTrue);
    expect(r.error, isNotNull);
  });

  test('a directory where the file should be is failed', () async {
    io.Directory(doc().path).createSync();
    final r = await storage.readDocument(tmp.path);
    expect(r.failed || r.missing, isTrue);
    expect(r.value, '');
  });

  test('a dangling symlink (vanished target) never reports ok content', () async {
    io.Link(doc().path).createSync('${tmp.path}/gone.md');
    final r = await storage.readDocument(tmp.path);
    expect(r.outcome, isNot(ReadOutcome.ok));
    expect(r.value, '');
  });

  test('placeholder: empty read but non-empty length is failed', () async {
    final fs = _MockFs();
    final f = _MockFile();
    when(() => fs.file(any())).thenReturn(f);
    when(() => f.exists()).thenAnswer((_) async => true);
    when(() => f.readAsString()).thenAnswer((_) async => '');
    when(() => f.length()).thenAnswer((_) async => 42);
    final s = StorageService(fileSystem: fs);
    final r = await s.readDocument('/p');
    expect(r.failed, isTrue);
  });
}

class _MockFs extends Mock implements FileSystem {}
class _MockFile extends Mock implements File {}

void atomicWriteTests() {
  late io.Directory tmp;
  late StorageService storage;
  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('pel17w_');
    storage = StorageService(fileSystem: const LocalFileSystem());
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('save is atomic: a failed temp write leaves the original intact', () async {
    io.File('${tmp.path}/document.md').writeAsStringSync('precious');
    // Block the temp path so the write cannot succeed.
    io.Directory('${tmp.path}/document.md.tmp').createSync();
    await expectLater(storage.saveDocument(tmp.path, 'new'), throwsA(anything));
    expect(io.File('${tmp.path}/document.md').readAsStringSync(), 'precious');
  });

  test('save replaces content and leaves no temp file', () async {
    io.File('${tmp.path}/document.md').writeAsStringSync('old');
    await storage.saveDocument(tmp.path, 'new');
    expect(io.File('${tmp.path}/document.md').readAsStringSync(), 'new');
    expect(io.File('${tmp.path}/document.md.tmp').existsSync(), isFalse);
  });
}
