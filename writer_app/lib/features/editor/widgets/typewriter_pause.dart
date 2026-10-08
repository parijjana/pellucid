// Description: Backlog item 18. Typewriter scroll re-centres the caret line on
// every caret move, which makes the page jump under the pointer while the
// writer selects with the mouse. A pointer press in the editor suspends
// re-centring; the next text-changing or caret-moving key resumes it.
// Shift+arrow selection is keyboard input, so it resumes too (typewriter
// stays on for it). Scroll-wheel / trackpad scrolling never touches this.

import 'package:flutter/services.dart';

class TypewriterPause {
  /// True from a pointer press until the next resuming key.
  bool suspended = false;

  void pointerDown() => suspended = true;

  /// Whether [event] ends a pause: a key press that edits text or moves the
  /// caret. Bare modifiers, Escape, Cmd/Ctrl+C and Alt shortcuts do not.
  static bool resumes(
    KeyEvent event, {
    required bool ctrlOrMeta,
    required bool alt,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final k = event.logicalKey;
    if (_ignored.contains(k)) return false;
    if (_caretKeys.contains(k)) return true;
    if (alt) return false;
    if (ctrlOrMeta) return _editingChords.contains(k);
    return true;
  }

  static final Set<LogicalKeyboardKey> _caretKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
  };

  static final Set<LogicalKeyboardKey> _editingChords = {
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyZ,
    LogicalKeyboardKey.keyY,
  };

  static final Set<LogicalKeyboardKey> _ignored = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.escape,
  };
}
