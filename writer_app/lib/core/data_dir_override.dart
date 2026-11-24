// Test-only redirect of Pellucid's on-disk app data on Windows.
//
// Debug and profile builds made with
//   --dart-define=PELLUCID_DATA_DIR=D:\some\folder
// keep the settings database, shared_preferences.json, cache and temp files under that
// folder instead of %APPDATA% / %TEMP% on C:. Used for local and integration-test runs
// on the Windows PC, where all work stays on D:.
//
// Release builds ignore it (the Store package never reads the define), and so does every
// non-Windows platform. Secrets still go to Windows Credential Manager, and words added with
// Learn spelling go to the OS dictionary; neither is a Pellucid folder.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

const String _dataDirDefine = String.fromEnvironment('PELLUCID_DATA_DIR');

/// The redirected root, or null when the override is off.
String? get dataDirOverride {
  if (kIsWeb || kReleaseMode || !Platform.isWindows) return null;
  if (_dataDirDefine.trim().isEmpty) return null;
  return _dataDirDefine.trim();
}

/// Call once, right after `WidgetsFlutterBinding.ensureInitialized()` and before anything
/// reads settings or preferences. Does nothing unless [dataDirOverride] is set.
void applyDataDirOverride() {
  final root = dataDirOverride;
  if (root == null) return;
  final provider = RedirectedPathProviderWindows(root);
  PathProviderPlatform.instance = provider;
  final prefs = SharedPreferencesStorePlatform.instance;
  if (prefs is SharedPreferencesWindows) {
    // ignore: invalid_use_of_visible_for_testing_member
    prefs.pathProvider = provider;
  }
  debugPrint('Pellucid: app data redirected to $root');
}

/// [PathProviderWindows] with every app-owned folder moved under [root].
@visibleForTesting
class RedirectedPathProviderWindows extends PathProviderWindows {
  RedirectedPathProviderWindows(this.root);

  final String root;

  Future<String> _dir(String name) async {
    final dir = Directory(p.join(root, name));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _dir('support');

  @override
  Future<String?> getApplicationDocumentsPath() => _dir('documents');

  @override
  Future<String?> getApplicationCachePath() => _dir('cache');

  @override
  Future<String?> getTemporaryPath() => _dir('temp');

  @override
  Future<String?> getDownloadsPath() => _dir('downloads');
}
