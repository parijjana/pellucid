import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/core/data_dir_override.dart';

void main() {
  test('override is off without the PELLUCID_DATA_DIR define', () {
    expect(dataDirOverride, isNull);
    applyDataDirOverride(); // must be a no-op
  });

  test('redirected provider keeps every app folder under the root', () async {
    final root = await Directory.systemTemp.createTemp('pellucid_data_dir_test');
    addTearDown(() => root.delete(recursive: true));
    final provider = RedirectedPathProviderWindows(root.path);
    final paths = [
      await provider.getApplicationSupportPath(),
      await provider.getApplicationDocumentsPath(),
      await provider.getApplicationCachePath(),
      await provider.getTemporaryPath(),
      await provider.getDownloadsPath(),
    ];
    for (final path in paths) {
      expect(path, startsWith(root.path));
      expect(Directory(path!).existsSync(), isTrue);
    }
    expect(paths.toSet(), hasLength(paths.length));
  });
}
