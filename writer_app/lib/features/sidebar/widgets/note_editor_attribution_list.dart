import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/note_card.dart';
import '../../editor/providers/theme_provider.dart';
import 'note_editor_attribution_list_item.dart';

class LinkHighlightingTextEditingController extends TextEditingController {
  WriterTheme theme;

  LinkHighlightingTextEditingController({
    super.text,
    required this.theme,
  });

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> children = [];
    final textVal = text;

    // Matches http://, https://, or www.
    final regex = RegExp(r'(https?://[^\s]+|www\.[^\s]+)');
    int start = 0;

    for (final match in regex.allMatches(textVal)) {
      if (match.start > start) {
        children.add(TextSpan(
          text: textVal.substring(start, match.start),
          style: style,
        ));
      }

      final linkText = match.group(0)!;
      final isDark = theme.backgroundColor.computeLuminance() < 0.5;
      final linkColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);

      children.add(TextSpan(
        text: linkText,
        style: (style ?? const TextStyle()).copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
      ));
      start = match.end;
    }

    if (start < textVal.length) {
      children.add(TextSpan(
        text: textVal.substring(start),
        style: style,
      ));
    }

    return TextSpan(
      style: style,
      children: children.isEmpty ? null : children,
      text: children.isEmpty ? textVal : null,
    );
  }
}

class NoteEditorAttributionList extends StatefulWidget {
  final TextEditingController titleController;
  final List<AttributionItem> items;
  final String attributionType;
  final List<NoteCard> availableNotes;
  final WriterTheme theme;
  final ValueChanged<String> onTypeChanged;
  final Function(int index, String text) onItemTextChanged;
  final Function(int index, String text) onItemAdded;
  final ValueChanged<int> onItemDeleted;
  final Function(int index, String targetNoteId) onLinkNote;
  final Function(int index, String targetNoteId) onUnlinkNote;
  final ValueChanged<String> onNavigateToNote;

  const NoteEditorAttributionList({
    super.key,
    required this.titleController,
    required this.items,
    required this.attributionType,
    required this.availableNotes,
    required this.theme,
    required this.onTypeChanged,
    required this.onItemTextChanged,
    required this.onItemAdded,
    required this.onItemDeleted,
    required this.onLinkNote,
    required this.onUnlinkNote,
    required this.onNavigateToNote,
  });

  @override
  State<NoteEditorAttributionList> createState() => _NoteEditorAttributionListState();
}

class _NoteEditorAttributionListState extends State<NoteEditorAttributionList> {
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  int? _indexToFocus;
  int? _selectionOffset;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(NoteEditorAttributionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
    _handleFocusShift();
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    while (_controllers.length < widget.items.length) {
      final index = _controllers.length;
      final controller = LinkHighlightingTextEditingController(
        text: widget.items[index].text,
        theme: widget.theme,
      );
      _controllers.add(controller);

      final focusNode = FocusNode();
      _focusNodes.add(focusNode);
    }
    while (_controllers.length > widget.items.length) {
      _controllers.removeLast().dispose();
      _focusNodes.removeLast().dispose();
    }

    // Bind key events dynamically to capture correct indices
    for (int i = 0; i < _focusNodes.length; i++) {
      final index = i;
      _focusNodes[index].onKeyEvent = (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (HardwareKeyboard.instance.isShiftPressed) {
              return KeyEventResult.ignored; // Bubble to insert standard newline
            } else {
              final controller = _controllers[index];
              final text = controller.text;
              final selection = controller.selection;
              final cursorPosition = selection.baseOffset;
              String currentText = text;
              String nextText = '';

              if (cursorPosition >= 0 && cursorPosition <= text.length) {
                currentText = text.substring(0, cursorPosition);
                nextText = text.substring(cursorPosition);
              }

              controller.text = currentText;
              widget.onItemTextChanged(index, currentText);

              _indexToFocus = index + 1;
              _selectionOffset = 0;
              widget.onItemAdded(index, nextText);

              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
            final controller = _controllers[index];
            if (controller.text.isEmpty) {
              if (index > 0) {
                _indexToFocus = index - 1;
                _selectionOffset = _controllers[index - 1].text.length;
              } else if (widget.items.length > 1) {
                _indexToFocus = 0;
                _selectionOffset = 0;
              }
              widget.onItemDeleted(index);
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      };
    }

    for (int i = 0; i < widget.items.length; i++) {
      if (_controllers[i] is LinkHighlightingTextEditingController) {
        (_controllers[i] as LinkHighlightingTextEditingController).theme = widget.theme;
      }
      if (_controllers[i].text != widget.items[i].text) {
        _controllers[i].text = widget.items[i].text;
      }
    }
  }

  void _handleFocusShift() {
    if (_indexToFocus != null) {
      final index = _indexToFocus!;
      final offset = _selectionOffset ?? 0;
      _indexToFocus = null;
      _selectionOffset = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (index >= 0 && index < _controllers.length) {
          final controller = _controllers[index];
          controller.selection = TextSelection.collapsed(offset: offset);
          _focusNodes[index].requestFocus();
        }
      });
    }
  }

  Widget _buildStyleButton(String type, IconData icon, String label) {
    final isActive = widget.attributionType == type;
    return OutlinedButton.icon(
      icon: Icon(icon, size: 14, color: isActive ? widget.theme.foregroundColor : widget.theme.foregroundColor.withValues(alpha: 0.4)),
      label: Text(label, style: TextStyle(fontSize: 11, color: isActive ? widget.theme.foregroundColor : widget.theme.foregroundColor.withValues(alpha: 0.4))),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: isActive ? widget.theme.foregroundColor : widget.theme.foregroundColor.withValues(alpha: 0.1),
        ),
        backgroundColor: isActive ? widget.theme.foregroundColor.withValues(alpha: 0.05) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: () => widget.onTypeChanged(type),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title Field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.titleController,
                  style: TextStyle(
                    color: widget.theme.foregroundColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Attributions Note',
                    hintStyle: TextStyle(color: widget.theme.foregroundColor.withValues(alpha: 0.2)),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Style Selector
          Row(
            children: [
              Text(
                'LIST STYLE:',
                style: TextStyle(
                  color: widget.theme.foregroundColor.withValues(alpha: 0.4),
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 12),
              _buildStyleButton('bullet', Icons.format_list_bulleted, 'Bulleted'),
              const SizedBox(width: 8),
              _buildStyleButton('number', Icons.format_list_numbered, 'Numbered'),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: widget.theme.foregroundColor.withValues(alpha: 0.1)),
          const SizedBox(height: 16),

          // List Items Editor
          Expanded(
            child: widget.items.isEmpty
                ? GestureDetector(
                    onTap: () {
                      _indexToFocus = 0;
                      _selectionOffset = 0;
                      widget.onItemAdded(-1, '');
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Text(
                        'No attribution items yet. Click here to add the first item.',
                        style: TextStyle(
                          color: widget.theme.foregroundColor.withValues(alpha: 0.4),
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final prefix = widget.attributionType == 'number' ? '${index + 1}.' : '•';

                      return NoteEditorAttributionListItem(
                        item: item,
                        index: index,
                        prefix: prefix,
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        availableNotes: widget.availableNotes,
                        theme: widget.theme,
                        onItemTextChanged: widget.onItemTextChanged,
                        onItemDeleted: widget.onItemDeleted,
                        onLinkNote: widget.onLinkNote,
                        onUnlinkNote: widget.onUnlinkNote,
                        onNavigateToNote: widget.onNavigateToNote,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
