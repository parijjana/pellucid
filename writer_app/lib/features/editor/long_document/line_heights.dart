// Description: Static-line heights for the windowed editor (slice 3c).
//
// A SliverList finds the child at a scroll offset by laying out every child
// between the last one it built and that offset, so a long scrollbar drag in a
// 100k-word document laid out hundreds of lines in one frame (28-64 ms). Here
// each line's height is known (measured just before it is laid out) or
// estimated from its length, and prefix sums turn "which line is at this
// offset" into a binary search: a jump lays out only the lines it shows.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Height of every document line as a static line on the page.
class LineHeights {
  LineHeights({required this.measure, required this.lengthOf, required this.rowHeight});

  /// Lays out line [line] at [width] exactly as its static line does.
  final double Function(int line, double width) measure;

  /// Character length of line [line] (for estimates).
  final int Function(int line) lengthOf;

  /// One row of text, the estimate's unit.
  double rowHeight;

  // > 0: measured. < 0: measured before a styling change, kept (negated) as
  // the estimate until measured again, so content does not jump. NaN: never
  // measured (estimated from the length).
  final List<double> _h = [];
  Float64List _prefix = Float64List(1); // _prefix[i]: lines [0, i)
  bool _dirty = true;
  double _width = 0;

  int get lineCount => _h.length;
  double get width => _width;

  /// Every line unknown (document load).
  void reset(int lineCount) {
    _h
      ..clear()
      ..addAll(List<double>.filled(lineCount, double.nan));
    _dirty = true;
  }

  /// Lines [first, first + removed) became [inserted] new, unmeasured lines.
  void replaceLines(int first, int removed, int inserted) {
    _h.replaceRange(first, min(first + removed, _h.length), List<double>.filled(inserted, double.nan));
    _dirty = true;
  }

  /// Every height is stale (page width, font, theme or bullet style changed).
  void invalidateAll() {
    for (int i = 0; i < _h.length; i++) {
      if (_h[i] > 0) _h[i] = -_h[i];
    }
    _dirty = true;
  }

  /// The layout width; a new width invalidates every height.
  set width(double w) {
    if ((w - _width).abs() < 0.01) return;
    _width = w;
    invalidateAll();
  }

  bool isKnown(int line) => _h[line] > 0;

  double heightOf(int line) {
    final double h = _h[line];
    return h.isNaN ? _estimate(line) : h.abs();
  }

  /// A fixed function of the line length: an estimate must not change until
  /// the line is measured, or unmeasured lines would move the page.
  double _estimate(int line) {
    final double perRow = max(20.0, _width / (rowHeight * 0.3));
    return rowHeight * max(1, (lengthOf(line) / perRow).ceil());
  }

  /// Measures the unknown lines in [from, to); true when any was measured.
  bool ensure(int from, int to) {
    if (_width <= 0) return false;
    bool any = false;
    for (int i = max(0, from); i < min(to, _h.length); i++) {
      if (_h[i] > 0) continue;
      _h[i] = max(0.01, measure(i, _width));
      any = true;
    }
    if (any) _dirty = true;
    return any;
  }

  void _rebuild() {
    if (!_dirty) return;
    if (_prefix.length != _h.length + 1) _prefix = Float64List(_h.length + 1);
    double acc = 0;
    for (int i = 0; i < _h.length; i++) {
      _prefix[i] = acc;
      acc += heightOf(i);
    }
    _prefix[_h.length] = acc;
    _dirty = false;
  }

  /// Total height of lines [from, to).
  double sum(int from, int to) {
    _rebuild();
    final int a = from.clamp(0, _h.length), b = to.clamp(0, _h.length);
    return b <= a ? 0 : _prefix[b] - _prefix[a];
  }

  /// Prefix sum at [line] (for searches).
  double _at(int line) {
    _rebuild();
    return _prefix[line];
  }

  /// Lines counted down from [base]: the index i (line base + i) whose extent
  /// holds [offset] measured from base's top. Clamped to the [count] lines.
  int indexBelow(int base, int count, double offset) {
    if (count <= 0 || offset <= 0) return 0;
    final double target = _at(base) + offset;
    // Smallest k in [base, base + count) with prefix[k + 1] >= target.
    int lo = base, hi = base + count - 1;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (_at(mid + 1) >= target) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo - base;
  }

  /// Lines counted up from [base] (line base - 1 - i): the index i whose
  /// extent holds [offset] measured upward from base's top.
  int indexAbove(int base, int count, double offset) {
    if (count <= 0 || offset <= 0) return 0;
    final double target = _at(base) - offset;
    // Largest line k in [base - count, base) with prefix[k] <= target.
    int lo = base - count, hi = base - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (_at(mid) <= target) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return base - 1 - lo;
  }
}

/// A run of static lines placed by [LineHeights]: lines base, base + 1, ...
/// ([upward] false) or base - 1, base - 2, ... ([upward] true, the list above
/// the window, which grows up from the center sliver).
class LineSliver extends SliverVariedExtentList {
  LineSliver({super.key, required super.delegate, required this.heights, required this.base, required this.upward})
    : super(itemExtentBuilder: (i, _) => heights.heightOf(upward ? base - 1 - i : base + i));

  final LineHeights heights;
  final int base;
  final bool upward;

  @override
  RenderSliverVariedExtentList createRenderObject(BuildContext context) => RenderLineSliver(
    childManager: context as SliverMultiBoxAdaptorElement,
    itemExtentBuilder: itemExtentBuilder,
    heights: heights,
    base: base,
    upward: upward,
  );

  @override
  void updateRenderObject(BuildContext context, RenderSliverVariedExtentList renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as RenderLineSliver)
      ..heights = heights
      ..base = base
      ..upward = upward
      ..markNeedsLayout();
  }
}

class RenderLineSliver extends RenderSliverVariedExtentList {
  RenderLineSliver({
    required super.childManager,
    required super.itemExtentBuilder,
    required this.heights,
    required this.base,
    required this.upward,
  });

  LineHeights heights;
  int base;
  bool upward;

  int get _count => upward ? base : max(0, heights.lineCount - base);

  double _offsetOf(int index) {
    final int i = index.clamp(0, _count);
    return upward ? heights.sum(base - i, base) : heights.sum(base, base + i);
  }

  int _indexAt(double scrollOffset) =>
      upward ? heights.indexAbove(base, _count, scrollOffset) : heights.indexBelow(base, _count, scrollOffset);

  @override
  // ignore: deprecated_member_use
  double indexToLayoutOffset(double itemExtent, int index) => _offsetOf(index);

  @override
  // ignore: deprecated_member_use
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) => _indexAt(scrollOffset);

  @override
  // ignore: deprecated_member_use
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) => _indexAt(scrollOffset);

  @override
  // ignore: deprecated_member_use
  double computeMaxScrollOffset(SliverConstraints constraints, double itemExtent) => _offsetOf(_count);

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) => _offsetOf(_count);

  @override
  void performLayout() {
    heights.width = constraints.crossAxisExtent;
    // The first built child is the anchor: measuring lines nearer the center
    // than it moves it, and the scroll offset follows so nothing on screen
    // jumps (what RenderSliverList does for children of unexpected size).
    final RenderBox? anchor = firstChild;
    final int anchorIndex = anchor == null ? -1 : indexOf(anchor);
    final double anchorBefore = anchorIndex < 0 ? 0 : _offsetOf(anchorIndex);
    int first = 0, last = -1;
    if (_count > 0 && constraints.remainingCacheExtent > 0) {
      // Measure the lines this layout will show before placing them, so each
      // child gets its true height. Measuring moves later lines, so repeat
      // until the range is stable.
      final double start = max(0.0, constraints.scrollOffset + constraints.cacheOrigin);
      final double end = constraints.scrollOffset + constraints.cacheOrigin + constraints.remainingCacheExtent;
      for (int pass = 0; pass < 4; pass++) {
        first = _indexAt(start);
        last = min(_count - 1, _indexAt(end) + 1);
        final bool measured = upward
            ? heights.ensure(base - 1 - last, base - first)
            : heights.ensure(base + first, base + last + 1);
        if (!measured) break;
      }
    }
    // Only an anchor that stays on screen is kept still; one about to be
    // dropped (a jump, a window move) needs no correction.
    if (anchorIndex >= first && anchorIndex <= last) {
      final double delta = _offsetOf(anchorIndex) - anchorBefore;
      if (delta.abs() > 0.5) {
        geometry = SliverGeometry(scrollOffsetCorrection: delta);
        return;
      }
    }
    super.performLayout();
  }
}
