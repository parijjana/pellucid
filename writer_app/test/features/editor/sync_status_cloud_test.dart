import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/widgets/sync_status_cloud.dart';
import 'package:pellucid/features/sync/providers/sync_provider.dart';

/// Counts the primitives the painter emits, so these tests can assert what was
/// drawn without golden files to maintain. The version stack is two `drawLine`
/// calls, so every assertion below is a line-count delta against the same glyph
/// painted without the affordance — which keeps the tests honest even though
/// several sync states draw lines of their own.
class _RecordingCanvas implements Canvas {
  int lines = 0;
  int paths = 0;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines++;
  }

  @override
  void drawPath(Path path, Paint paint) {
    paths++;
  }

  @override
  noSuchMethod(Invocation invocation) {}
}

_RecordingCanvas _paint({
  required bool isLoggedIn,
  required SyncStatus status,
  required bool showHistoryAffordance,
}) {
  final canvas = _RecordingCanvas();
  CloudStatusPainter(
    isLoggedIn: isLoggedIn,
    status: status,
    strokeColor: const Color(0xFF000000),
    fillColor: const Color(0x14000000),
    animValue: 0.0,
    showHistoryAffordance: showHistoryAffordance,
  ).paint(canvas, const Size(24, 25));
  return canvas;
}

/// The two rules the version stack contributes.
const int kStackLines = 2;

void main() {
  group('CloudStatusPainter version stack', () {
    test('is absent unless asked for, so other placements stay pure status',
        () {
      final off = _paint(
        isLoggedIn: true,
        status: SyncStatus.idle,
        showHistoryAffordance: false,
      );
      expect(off.lines, 0);
    });

    test('is drawn when idle', () {
      final on = _paint(
        isLoggedIn: true,
        status: SyncStatus.idle,
        showHistoryAffordance: true,
      );
      expect(on.lines, kStackLines);
    });

    test('never coexists with the syncing transfer arrows', () {
      // Both draw into the same strip below the cloud. If this ever fires, the
      // two are overlapping into an unreadable smudge.
      final off = _paint(
        isLoggedIn: true,
        status: SyncStatus.syncing,
        showHistoryAffordance: false,
      );
      final on = _paint(
        isLoggedIn: true,
        status: SyncStatus.syncing,
        showHistoryAffordance: true,
      );
      expect(on.lines, off.lines);
    });

    test('survives every non-syncing status, including signed out and error',
        () {
      // The control must never look dead: local snapshots exist with no Drive
      // connection at all, and a sync error is exactly when a writer wants to
      // reach for an earlier version.
      for (final probe in <({bool loggedIn, SyncStatus status})>[
        (loggedIn: false, status: SyncStatus.idle),
        (loggedIn: true, status: SyncStatus.error),
        (loggedIn: true, status: SyncStatus.success),
      ]) {
        final off = _paint(
          isLoggedIn: probe.loggedIn,
          status: probe.status,
          showHistoryAffordance: false,
        );
        final on = _paint(
          isLoggedIn: probe.loggedIn,
          status: probe.status,
          showHistoryAffordance: true,
        );
        expect(on.lines, off.lines + kStackLines,
            reason: 'loggedIn=${probe.loggedIn} status=${probe.status}');
        // The cloud body and its fill are untouched by the affordance.
        expect(on.paths, off.paths,
            reason: 'loggedIn=${probe.loggedIn} status=${probe.status}');
      }
    });

    test('repaints when the affordance flag changes', () {
      CloudStatusPainter build(bool show) => CloudStatusPainter(
            isLoggedIn: true,
            status: SyncStatus.idle,
            strokeColor: const Color(0xFF000000),
            fillColor: const Color(0x14000000),
            animValue: 0.0,
            showHistoryAffordance: show,
          );
      expect(build(true).shouldRepaint(build(false)), isTrue);
      expect(build(true).shouldRepaint(build(true)), isFalse);
    });
  });
}
