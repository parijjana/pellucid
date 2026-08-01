// @trace FEAT-20260705-CODEX-0003
// Description: Overlays hover-peek + Alt/Cmd-Opt-click interaction onto the
// manuscript TextField for Codex mentions. Pointer positions are resolved to
// text offsets through the field's own RenderEditable (genuine in-text
// hit-testing), because TextSpan.recognizer/onEnter are not dispatched inside
// an editable field.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../providers/codex_index.dart';
import '../providers/theme_provider.dart';
import '../../sidebar/providers/note_card.dart';
import 'codex_mention_peek.dart';
import '../../../core/platform_context.dart';

class CodexMentionDetector extends StatefulWidget {
  final bool enabled;
  final WriterTheme theme;
  final CodexIndex index;
  final List<NoteCard> notes;
  final void Function(String noteId) onActivate;
  final Widget child;

  const CodexMentionDetector({
    super.key,
    required this.enabled,
    required this.theme,
    required this.index,
    required this.notes,
    required this.onActivate,
    required this.child,
  });

  @override
  State<CodexMentionDetector> createState() => _CodexMentionDetectorState();
}

class _CodexMentionDetectorState extends State<CodexMentionDetector> {
  final GlobalKey _childKey = GlobalKey();
  OverlayEntry? _peekEntry;
  String? _hoveredNoteId;
  Offset _lastGlobal = Offset.zero;

  @override
  void didUpdateWidget(CodexMentionDetector old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _hoveredNoteId != null) {
      _clearHover();
    }
  }

  @override
  void dispose() {
    _removePeek();
    super.dispose();
  }

  RenderEditable? _renderEditable() {
    final ro = _childKey.currentContext?.findRenderObject();
    return ro == null ? null : _findEditable(ro);
  }

  RenderEditable? _findEditable(RenderObject node) {
    if (node is RenderEditable) return node;
    RenderEditable? found;
    node.visitChildren((child) => found ??= _findEditable(child));
    return found;
  }

  /// Resolves [global] to a mention note id via the field's own layout, or null.
  String? _noteIdAt(Offset global) {
    final re = _renderEditable();
    if (re == null) return null;
    final TextPosition pos = re.getPositionForPoint(global);
    // Reject points below/above the actual glyph line (blank space in the field)
    // — the field is not internally scrolled (maxLines: null), so local space
    // and caret rects share one coordinate system.
    final Rect caret = re.getLocalRectForCaret(pos);
    final Offset local = re.globalToLocal(global);
    if (local.dy < caret.top - 2 || local.dy > caret.bottom + 2) return null;
    return widget.index.noteIdAt(pos.offset);
  }

  NoteCard? _noteById(String id) {
    for (final n in widget.notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _handleHover(PointerHoverEvent event) {
    if (!widget.enabled) return;
    final id = _noteIdAt(event.position);
    _lastGlobal = event.position;
    if (id == _hoveredNoteId) return; // only react when the target changes
    setState(() => _hoveredNoteId = id); // refresh the cursor
    _updatePeek();
  }

  void _clearHover() {
    if (_hoveredNoteId == null && _peekEntry == null) return;
    setState(() => _hoveredNoteId = null);
    _removePeek();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    final hw = HardwareKeyboard.instance;
    final bool combo = usesCommandModifier
        ? (hw.isAltPressed && hw.isMetaPressed) // Cmd + Opt on macOS/iOS
        : hw.isAltPressed;
    if (!combo) return;
    final id = _noteIdAt(event.position);
    if (id == null) return;
    _clearHover();
    widget.onActivate(id);
  }

  void _removePeek() {
    _peekEntry?.remove();
    _peekEntry = null;
  }

  void _updatePeek() {
    _removePeek();
    final id = _hoveredNoteId;
    if (id == null) return;
    final note = _noteById(id);
    if (note == null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _peekEntry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        double left = (_lastGlobal.dx + 12).clamp(8.0, size.width - 292.0);
        double top = _lastGlobal.dy + 20;
        if (top > size.height - 120) top = _lastGlobal.dy - 120;
        return Positioned(
          left: left,
          top: top.clamp(8.0, size.height - 8.0),
          child: CodexMentionPeek(
            theme: widget.theme,
            title: note.title,
            content: note.content,
          ),
        );
      },
    );
    overlay.insert(_peekEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final Widget keyed = KeyedSubtree(key: _childKey, child: widget.child);
    if (!widget.enabled) return keyed;
    return MouseRegion(
      opaque: false,
      cursor: _hoveredNoteId != null ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: _handleHover,
      onExit: (_) => _clearHover(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        child: keyed,
      ),
    );
  }
}
