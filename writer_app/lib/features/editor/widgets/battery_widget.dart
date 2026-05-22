import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';

class BatteryWidget extends StatefulWidget {
  final WriterTheme theme;
  const BatteryWidget({super.key, required this.theme});

  @override
  State<BatteryWidget> createState() => _BatteryWidgetState();
}

class _BatteryWidgetState extends State<BatteryWidget> {
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  StreamSubscription<BatteryState>? _stateSubscription;
  Timer? _timer;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _getBatteryStatus();
    _stateSubscription = _battery.onBatteryStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _batteryState = state;
        });
        _getBatteryLevel();
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _getBatteryStatus());
  }

  Future<void> _getBatteryStatus() async {
    await _getBatteryLevel();
    await _getBatteryState();
  }

  Future<void> _getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
        });
      }
    } catch (_) {}
  }

  Future<void> _getBatteryState() async {
    try {
      final state = await _battery.batteryState;
      if (mounted) {
        setState(() {
          _batteryState = state;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isCharging = _batteryState == BatteryState.charging;
    final isBelowThreshold = _batteryLevel <= settings.batteryAlertThreshold;
    final isRedAlert = isBelowThreshold && !isCharging && settings.batteryGuardEnabled;

    final double opacity = _isHovered || isRedAlert ? 1.0 : 0.2;
    final Color color = isRedAlert ? Colors.red : widget.theme.foregroundColor;
    final Color bg = widget.theme.backgroundColor;

    final bool showPercentage = settings.showBatteryPercentage;
    final double batteryWidth = showPercentage ? 34.0 : 22.0;
    final double batteryHeight = 12.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 200),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isCharging && showPercentage) ...[
              Icon(Icons.bolt, size: 12, color: color),
              const SizedBox(width: 2),
            ],
            Stack(
              alignment: Alignment.centerLeft,
              children: [
                CustomPaint(
                  size: Size(batteryWidth, batteryHeight),
                  painter: HorizontalBatteryPainter(
                    level: _batteryLevel,
                    isCharging: isCharging,
                    color: color,
                    showPercentage: showPercentage,
                    backgroundColor: bg,
                  ),
                ),
                if (showPercentage)
                  Positioned(
                    left: 0,
                    top: 0,
                    width: batteryWidth - 2.0, // exclude the cap
                    height: batteryHeight,
                    child: BatteryText(
                      level: _batteryLevel,
                      width: batteryWidth - 2.0,
                      height: batteryHeight,
                      foregroundColor: color,
                      backgroundColor: bg,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HorizontalBatteryPainter extends CustomPainter {
  final int level;
  final bool isCharging;
  final Color color;
  final bool showPercentage;
  final Color backgroundColor;

  HorizontalBatteryPainter({
    required this.level,
    required this.isCharging,
    required this.color,
    required this.showPercentage,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double capWidth = 2.0;
    final double bodyWidth = size.width - capWidth;
    final double bodyHeight = size.height;

    // 1. Draw battery body outline
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color;

    final RRect bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, bodyWidth, bodyHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(bodyRRect, borderPaint);

    // 2. Draw terminal cap
    final Paint capPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final RRect capRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bodyWidth,
        bodyHeight * 0.25,
        capWidth,
        bodyHeight * 0.5,
      ),
      const Radius.circular(1),
    );
    canvas.drawRRect(capRRect, capPaint);

    // 3. Draw battery level fill inside
    final double padding = 1.5;
    final double maxFillWidth = bodyWidth - (padding * 2);
    final double fillWidth = maxFillWidth * (level / 100.0);
    final double fillHeight = bodyHeight - (padding * 2);

    if (level > 0) {
      final Paint fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;

      final RRect fillRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          padding,
          padding,
          fillWidth,
          fillHeight,
        ),
        const Radius.circular(0.5),
      );
      canvas.drawRRect(fillRRect, fillPaint);
    }

    // 4. Draw charging bolt inside ONLY if percentage is hidden
    if (isCharging && !showPercentage) {
      final Paint boltPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = level >= 50 ? backgroundColor : color;

      final Paint boltOutline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = level >= 50 ? color : backgroundColor;

      final double cx = bodyWidth / 2;
      final double cy = bodyHeight / 2;
      final double w = bodyWidth * 0.25;
      final double h = bodyHeight * 0.7;

      final Path boltPath = Path()
        ..moveTo(cx + w * 0.2, cy - h * 0.5)
        ..lineTo(cx - w * 0.4, cy + h * 0.05)
        ..lineTo(cx - w * 0.05, cy + h * 0.05)
        ..lineTo(cx - w * 0.2, cy + h * 0.5)
        ..lineTo(cx + w * 0.4, cy - h * 0.05)
        ..lineTo(cx + w * 0.05, cy - h * 0.05)
        ..close();

      canvas.drawPath(boltPath, boltOutline);
      canvas.drawPath(boltPath, boltPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HorizontalBatteryPainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.isCharging != isCharging ||
        oldDelegate.color != color ||
        oldDelegate.showPercentage != showPercentage ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class BatteryText extends StatelessWidget {
  final int level;
  final double width;
  final double height;
  final Color foregroundColor;
  final Color backgroundColor;

  const BatteryText({
    super.key,
    required this.level,
    required this.width,
    required this.height,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final text = '$level';
    const textStyle = TextStyle(
      fontSize: 8.0,
      fontWeight: FontWeight.bold,
      height: 1.0,
    );

    final double padding = 1.5;
    final double maxFillWidth = width - (padding * 2);
    final double fillWidth = maxFillWidth * (level / 100.0);
    final double fillRightEdge = padding + fillWidth;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Base: Unfilled text color
          SizedBox(
            width: width,
            height: height,
            child: Center(
              child: Text(
                text,
                style: textStyle.copyWith(color: foregroundColor),
              ),
            ),
          ),
          // Clipped overlay: Filled text color
          ClipRect(
            clipper: _BatteryFillClipper(left: padding, right: fillRightEdge),
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                child: Text(
                  text,
                  style: textStyle.copyWith(color: backgroundColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryFillClipper extends CustomClipper<Rect> {
  final double left;
  final double right;

  _BatteryFillClipper({required this.left, required this.right});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(left, 0, right, size.height);
  }

  @override
  bool shouldReclip(_BatteryFillClipper oldClipper) {
    return oldClipper.left != left || oldClipper.right != right;
  }
}
