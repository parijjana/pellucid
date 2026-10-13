// Long-document (windowed editor) end-to-end suite. See tool/e2e/run_long_doc.sh,
// which builds this under an isolated bundle id and guards the owner's data.
// Check numbers follow the owner's manual list ("step 6: big manuscript").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pellucid/features/editor/long_document/windowed_editor.dart';

import 'support/harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  check('Check 0: setup - 127k-word manuscript opens in the windowed editor', (tester) async {
    final rig = await mount(tester);
    rig.expectWindowed();
    expect(rig.fx.words, greaterThan(125000));
    expect(rig.text, rig.fx.text);
    final w = rig.win;
    // ignore: avoid_print
    print('EVID|setup|words=${rig.fx.words} chars=${rig.text.length} lines=${w.buffer.lineCount} '
        'windowChars=${w.window.text.length} threshold=$kWindowedEditorMinWords words');
    expect(w.window.text.length, lessThan(rig.text.length ~/ 20), reason: 'only a window is live');
    await rig.dispose();
  });
}
