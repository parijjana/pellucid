import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../sync/providers/sync_provider.dart';
import '../providers/theme_provider.dart';

class SyncStatusCloud extends StatefulWidget {
  final bool isLoggedIn;
  final SyncStatus status;
  final WriterTheme theme;

  const SyncStatusCloud({
    super.key,
    required this.isLoggedIn,
    required this.status,
    required this.theme,
  });

  @override
  State<SyncStatusCloud> createState() => _SyncStatusCloudState();
}

class _SyncStatusCloudState extends State<SyncStatusCloud> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isLoggedIn && widget.status == SyncStatus.syncing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(SyncStatusCloud oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool isCurrentlySyncing = widget.isLoggedIn && widget.status == SyncStatus.syncing;
    if (isCurrentlySyncing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!isCurrentlySyncing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color strokeColor = widget.theme.foregroundColor.withValues(alpha: 0.4);
    final Color fillColor = widget.theme.foregroundColor.withValues(alpha: 0.08);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(24, 24),
          painter: CloudStatusPainter(
            isLoggedIn: widget.isLoggedIn,
            status: widget.status,
            strokeColor: strokeColor,
            fillColor: fillColor,
            animValue: _controller.value,
          ),
        );
      },
    );
  }
}

class CloudStatusPainter extends CustomPainter {
  final bool isLoggedIn;
  final SyncStatus status;
  final Color strokeColor;
  final Color fillColor;
  final double animValue;

  CloudStatusPainter({
    required this.isLoggedIn,
    required this.status,
    required this.strokeColor,
    required this.fillColor,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    // Draw Cloud Outline Path
    final cloudPath = Path()
      ..moveTo(6.0, 15.0)
      ..lineTo(18.0, 15.0)
      ..quadraticBezierTo(22.0, 15.0, 21.0, 11.0)
      ..quadraticBezierTo(21.5, 7.5, 17.5, 8.0)
      ..quadraticBezierTo(13.0, 4.0, 9.5, 7.5)
      ..quadraticBezierTo(5.0, 7.0, 6.0, 11.0)
      ..quadraticBezierTo(2.0, 15.0, 6.0, 15.0)
      ..close();

    // 1. Logged In & Synced (Idle or Success) -> Faint Filled Cloud
    final bool isSynced = isLoggedIn && (status == SyncStatus.success || status == SyncStatus.idle);
    if (isSynced) {
      canvas.drawPath(cloudPath, fillPaint);
    }

    // Always draw cloud outline
    canvas.drawPath(cloudPath, strokePaint);

    if (!isLoggedIn) {
      // 2. Not Logged In -> Cloud with diagonal line
      canvas.drawLine(
        const Offset(4.0, 4.0),
        const Offset(20.0, 16.0),
        strokePaint..strokeWidth = 1.5,
      );
    } else if (status == SyncStatus.error) {
      // 3. Sync Failure -> Cloud with cross overlay in the center
      canvas.drawLine(
        const Offset(9.5, 7.5),
        const Offset(14.5, 12.5),
        strokePaint..strokeWidth = 1.5,
      );
      canvas.drawLine(
        const Offset(14.5, 7.5),
        const Offset(9.5, 12.5),
        strokePaint..strokeWidth = 1.5,
      );
    } else if (status == SyncStatus.syncing) {
      // 4. Syncing (Activity) -> Tiny up/down arrows below cloud
      final double dy = math.sin(animValue * 2 * math.pi) * 1.5;

      // Left arrow pointing up
      canvas.drawLine(
        Offset(9.0, 22.5 + dy),
        Offset(9.0, 17.5 + dy),
        strokePaint..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(9.0, 17.5 + dy),
        Offset(7.0, 19.5 + dy),
        strokePaint..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(9.0, 17.5 + dy),
        Offset(11.0, 19.5 + dy),
        strokePaint..strokeWidth = 1.0,
      );

      // Right arrow pointing down
      canvas.drawLine(
        Offset(15.0, 17.5 - dy),
        Offset(15.0, 22.5 - dy),
        strokePaint..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(15.0, 22.5 - dy),
        Offset(13.0, 20.5 - dy),
        strokePaint..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(15.0, 22.5 - dy),
        Offset(17.0, 20.5 - dy),
        strokePaint..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CloudStatusPainter oldDelegate) {
    return oldDelegate.isLoggedIn != isLoggedIn ||
        oldDelegate.status != status ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.animValue != animValue;
  }
}
