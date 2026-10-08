// Description: Click a checklist box to tick it (backlog item 17).
//
// The box is part of the text, so a click on it is an ordinary tap in the
// editor. This listener watches raw pointer events (it takes no part in the
// gesture arena, so selection and focus work as ever), hit-tests the tap with
// the editor's own render object and, when it lands on a checklist box,
// flips `[ ]` / `[x]` in the text.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../list_editing.dart';

class ChecklistTapListener extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Same callback the TextField gets, so the change is autosaved.
  final ValueChanged<String> onChanged;
  final Widget child;

  const ChecklistTapListener({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.child,
  });

  @override
  State<ChecklistTapListener> createState() => _ChecklistTapListenerState();
}

class _ChecklistTapListenerState extends State<ChecklistTapListener> {
  Offset? _down;
  Duration? _downAt;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        _down = e.position;
        _downAt = e.timeStamp;
      },
      onPointerUp: _up,
      onPointerCancel: (_) => _down = null,
      child: widget.child,
    );
  }

  void _up(PointerUpEvent e) {
    final down = _down;
    final downAt = _downAt;
    _down = null;
    if (down == null || downAt == null) return;
    // A tap, not a drag or a long press.
    if ((e.position - down).distance > 8 || e.timeStamp - downAt > const Duration(milliseconds: 500)) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != 0) return;
    final state = widget.focusNode.context?.findAncestorStateOfType<EditableTextState>();
    if (state == null || state.widget.readOnly) return;
    final int offset = state.renderEditable.getPositionForPoint(e.position).offset;
    final String text = widget.controller.text;
    final int? lineStart = checkboxLineAt(text, offset);
    if (lineStart == null) return;
    final next = toggleCheckbox(widget.controller.value, lineStart);
    if (next == null) return;
    // After the field has handled the same tap (selection, focus).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = widget.controller.value;
      final again = toggleCheckbox(current, lineStart);
      if (again == null) return;
      widget.controller.value = again;
      widget.onChanged(again.text);
    });
  }
}
