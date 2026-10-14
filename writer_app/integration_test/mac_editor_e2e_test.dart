// Mac editor end-to-end suite: the open Mac items of the owner's 1.1.0 checklist, against the real
// EditorScreen on a SHORT document (normal single editor, not the windowed one). Same isolation and
// guard as the long-document suite; run with tool/e2e/run_mac_editor.sh.
//
// Check names are "Check L<n>: ..." where <n> is the line in the owner's checklist.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

import 'checks/checks_find_settings.dart';
import 'checks/checks_markers.dart';
import 'checks/checks_misc.dart';
import 'checks/checks_paste.dart';
import 'checks/checks_punct.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  timeDilation = 1.0;

  registerFindSettingsChecks();
  registerMarkerChecks();
  registerPunctChecks();
  registerPasteChecks();
  registerMiscChecks();
}
