// @trace BACKLOG-27
// Description: Owns the SmartPunctuationFormatter for the editor and makes one
// Cmd/Ctrl+Z straight after a conversion undo just that conversion; any other
// Undo falls through to the editor's normal undo history.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/platform_context.dart';
import '../utils/smart_punctuation.dart';

class _SmartUndoIntent extends Intent {
  const _SmartUndoIntent();
}

class SmartPunctuationScope extends StatefulWidget {
  final bool enabled;
  final TextEditingController controller;

  /// Same callback the TextField gets, so the reverted text is autosaved.
  final ValueChanged<String> onChanged;
  final Widget Function(BuildContext context, List<TextInputFormatter> formatters) builder;

  const SmartPunctuationScope({
    super.key,
    required this.enabled,
    required this.controller,
    required this.onChanged,
    required this.builder,
  });

  @override
  State<SmartPunctuationScope> createState() => _SmartPunctuationScopeState();
}

class _SmartPunctuationScopeState extends State<SmartPunctuationScope> {
  late final SmartPunctuationFormatter _formatter = SmartPunctuationFormatter(enabled: widget.enabled);
  late final List<TextInputFormatter> _formatters = [_formatter];

  @override
  void didUpdateWidget(SmartPunctuationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _formatter.enabled = widget.enabled;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.keyZ, meta: usesCommandModifier, control: !usesCommandModifier):
            const _SmartUndoIntent(),
      },
      child: Actions(
        actions: {
          _SmartUndoIntent: _SmartUndoAction(_formatter, widget.controller, (text) => widget.onChanged(text)),
        },
        child: widget.builder(context, _formatters),
      ),
    );
  }
}

class _SmartUndoAction extends Action<_SmartUndoIntent> {
  final SmartPunctuationFormatter formatter;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  _SmartUndoAction(this.formatter, this.controller, this.onChanged);

  /// Disabled unless a conversion is pending, so the key press carries on to
  /// the editor's own Undo.
  @override
  bool isEnabled(_SmartUndoIntent intent) => formatter.canUndo(controller.value);

  @override
  Object? invoke(_SmartUndoIntent intent) {
    final straight = formatter.undoLast(controller.value);
    if (straight != null) {
      controller.value = straight;
      onChanged(straight.text);
    }
    return null;
  }
}
