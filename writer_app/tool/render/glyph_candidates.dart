// Not a test — a render harness, kept outside test/ so `flutter test` does not
// run it and write files as a side effect. `flutter test` is simply the easiest
// way to get a real dart:ui Canvas and PNG encoder.
//
// Draws each candidate status-cloud affordance through the SAME cloud path the
// production painter uses, in all three sync states, at 1x (the truth) and 10x
// (for shape). Used to choose the shipped version-stack treatment; keep it for
// the next time this glyph is up for debate.
//
//   flutter test tool/render/glyph_candidates.dart
//   GLYPH_OUT=/some/dir flutter test tool/render/glyph_candidates.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final String kOutDir = Platform.environment['GLYPH_OUT'] ??
    '${Directory.systemTemp.path}/pellucid-glyph-candidates';

// Approximate the app's default light theme: warm paper, near-black ink drawn
// at the 0.4 alpha the status bar uses.
const Color kPaper = Color(0xFFF3EFE6);
const Color kInk = Color(0xFF23211E);

const double kW = 24.0;
const double kH = 25.0;

enum CloudState { idle, signedOut, error }

Path cloudPath() => Path()
  ..moveTo(6.0, 15.0)
  ..lineTo(18.0, 15.0)
  ..quadraticBezierTo(22.0, 15.0, 21.0, 11.0)
  ..quadraticBezierTo(21.5, 7.5, 17.5, 8.0)
  ..quadraticBezierTo(13.0, 4.0, 9.5, 7.5)
  ..quadraticBezierTo(5.0, 7.0, 6.0, 11.0)
  ..quadraticBezierTo(2.0, 15.0, 6.0, 15.0)
  ..close();

Paint stroke({double width = 1.2}) => Paint()
  ..color = kInk.withValues(alpha: 0.4)
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round;

Paint fill() => Paint()
  ..color = kInk.withValues(alpha: 0.08)
  ..style = PaintingStyle.fill;

/// Everything the production painter draws before the affordance.
void paintCloudBase(Canvas c, CloudState state, {bool drawCloud = true}) {
  final path = cloudPath();
  if (state == CloudState.idle) c.drawPath(path, fill());
  if (drawCloud) c.drawPath(path, stroke());

  if (state == CloudState.signedOut) {
    c.drawLine(const Offset(4, 4), const Offset(20, 16), stroke(width: 1.5));
  } else if (state == CloudState.error) {
    c.drawLine(const Offset(9.5, 7.5), const Offset(14.5, 12.5), stroke(width: 1.5));
    c.drawLine(const Offset(14.5, 7.5), const Offset(9.5, 12.5), stroke(width: 1.5));
  }
}

typedef GlyphPainter = void Function(Canvas c, CloudState state);

// ---------------------------------------------------------------------------
// Candidates
// ---------------------------------------------------------------------------

/// A — the first attempt: a detached arc in the strip below the cloud.
/// Rejected — two objects rather than one mark, so at 24px the eye has to bind
/// them together and the pair reads as a smudge.
void candidateA(Canvas c, CloudState state) {
  paintCloudBase(c, state);
  final p = stroke();
  c.drawArc(const Rect.fromLTWH(8, 16.5, 8, 8), -math.pi * 0.55, math.pi * 1.45, false, p);
  const tip = Offset(10.4, 17.4);
  c.drawLine(tip, const Offset(12.6, 17.0), p);
  c.drawLine(tip, const Offset(10.9, 19.4), p);
}

/// B — clock hands inside the cloud; the cloud body IS the face. One silhouette,
/// nothing added below the baseline.
void candidateB(Canvas c, CloudState state) {
  paintCloudBase(c, state);
  final p = stroke(width: 1.1);
  const center = Offset(12.6, 11.2);
  c.drawLine(center, const Offset(12.6, 8.6), p); // hour hand, up
  c.drawLine(center, const Offset(15.0, 12.0), p); // minute hand
  c.drawCircle(center, 0.6, Paint()..color = kInk.withValues(alpha: 0.4));
}

/// C — the cloud's flat base opens into the arrow arc: one continuous stroke,
/// no second object. Cloud outline is drawn without its bottom edge.
void candidateC(Canvas c, CloudState state) {
  // Cloud minus the flat bottom run.
  final open = Path()
    ..moveTo(6.0, 15.0)
    ..quadraticBezierTo(2.0, 15.0, 6.0, 11.0)
    ..quadraticBezierTo(5.0, 7.0, 9.5, 7.5)
    ..quadraticBezierTo(13.0, 4.0, 17.5, 8.0)
    ..quadraticBezierTo(21.5, 7.5, 21.0, 11.0)
    ..quadraticBezierTo(22.0, 15.0, 18.0, 15.0);
  if (state == CloudState.idle) c.drawPath(cloudPath(), fill());
  c.drawPath(open, stroke());
  paintCloudBase(c, state, drawCloud: false);

  // The base sweeps down and back as a rewind arc.
  final p = stroke();
  c.drawArc(const Rect.fromLTWH(6, 11.5, 12, 8), 0, math.pi * 0.92, false, p);
  const tip = Offset(6.4, 14.2);
  c.drawLine(tip, const Offset(8.6, 14.6), p);
  c.drawLine(tip, const Offset(6.2, 16.6), p);
}

/// D — badge idiom: cloud shifted up slightly, small clock token punched into
/// the lower-right on its own paper-coloured knockout so it stays legible.
void candidateD(Canvas c, CloudState state) {
  c.save();
  c.translate(-1.5, -1.0);
  paintCloudBase(c, state);
  c.restore();

  const badge = Offset(17.0, 17.0);
  c.drawCircle(badge, 6.0, Paint()..color = kPaper); // knockout
  c.drawCircle(badge, 5.0, stroke(width: 1.1));
  final p = stroke(width: 1.1);
  c.drawLine(badge, badge + const Offset(0, -2.8), p);
  c.drawLine(badge, badge + const Offset(2.4, 0.6), p);
}

/// E — SHIPPED. Snapshots as a stack: two short rules beneath the cloud,
/// narrowing with age. Says "list of versions" rather than "time", and is the
/// quietest of the six — see _paintVersionStack in sync_status_cloud.dart.
void candidateE(Canvas c, CloudState state) {
  paintCloudBase(c, state);
  final p = stroke(width: 1.1);
  c.drawLine(const Offset(7.5, 18.5), const Offset(16.5, 18.5), p);
  c.drawLine(const Offset(9.5, 21.5), const Offset(14.5, 21.5), p);
}

/// F — rewind chevrons inside the cloud. Reads instantly as "go back", and
/// stays entirely within the existing silhouette.
void candidateF(Canvas c, CloudState state) {
  paintCloudBase(c, state);
  final p = stroke(width: 1.1);
  for (final dx in <double>[0.0, 3.6]) {
    c.drawLine(Offset(13.2 + dx, 8.8), Offset(10.6 + dx, 11.3), p);
    c.drawLine(Offset(10.6 + dx, 11.3), Offset(13.2 + dx, 13.8), p);
  }
}

const Map<String, GlyphPainter> kCandidates = {
  'a-current-detached-arc': candidateA,
  'b-clock-hands-in-cloud': candidateB,
  'c-base-becomes-arc': candidateC,
  'd-clock-badge': candidateD,
  'e-version-stack': candidateE,
  'f-rewind-chevrons': candidateF,
};

/// Draws the three states side by side at [scale].
Future<ui.Image> renderSheet(GlyphPainter painter, double scale) async {
  const double gap = 8.0;
  final double sheetW = (kW * 3 + gap * 2) * scale;
  final double sheetH = kH * scale;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, sheetW, sheetH), Paint()..color = kPaper);
  canvas.scale(scale);

  int i = 0;
  for (final state in CloudState.values) {
    canvas.save();
    canvas.translate(i * (kW + gap), 0);
    painter(canvas, state);
    canvas.restore();
    i++;
  }

  return recorder.endRecording().toImage(sheetW.ceil(), sheetH.ceil());
}

void main() {
  test('render glyph candidates', () async {
    Directory(kOutDir).createSync(recursive: true);

    for (final entry in kCandidates.entries) {
      for (final scale in <double>[1, 10]) {
        final image = await renderSheet(entry.value, scale);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull, reason: 'PNG encode failed for ${entry.key}');
        final name = '${entry.key}@${scale.toInt()}x.png';
        File('$kOutDir/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    }

    final written = Directory(kOutDir).listSync().length;
    expect(written, kCandidates.length * 2);
    // ignore: avoid_print
    print('wrote $written files to $kOutDir');
  });
}
