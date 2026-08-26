import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/run_session.dart';

class TempleRunTrackWidget extends StatefulWidget {
  final double currentSpeedKmh;
  final TrackTheme theme;

  const TempleRunTrackWidget({
    super.key,
    required this.currentSpeedKmh,
    this.theme = TrackTheme.grass,
  });

  @override
  State<TempleRunTrackWidget> createState() => _TempleRunTrackWidgetState();
}

class _TempleRunTrackWidgetState extends State<TempleRunTrackWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  double _trackOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateAnimation);
    _animController.repeat();
  }

  void _updateAnimation() {
    final speedMultiplier = (widget.currentSpeedKmh / 10.0).clamp(0.0, 3.0);
    setState(() {
      _trackOffset = (_trackOffset + (0.04 * speedMultiplier)) % 1.0;
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CustomPaint(
          painter: _TrackPainter(
            offset: _trackOffset,
            theme: widget.theme,
            isMoving: widget.currentSpeedKmh > 1.0,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  transform: Matrix4.translationValues(
                    0,
                    widget.currentSpeedKmh > 1.0
                        ? math.sin(_trackOffset * math.pi * 8) * 4
                        : 0,
                    0,
                  ),
                  child: const Icon(
                    Icons.directions_run_rounded,
                    size: 58,
                    color: Color(0xFF00F5D4),
                    shadows: [
                      Shadow(color: Color(0xFF00F5D4), blurRadius: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final double offset;
  final TrackTheme theme;
  final bool isMoving;

  _TrackPainter({
    required this.offset,
    required this.theme,
    required this.isMoving,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final groundPaint = Paint()..color = const Color(0xFF1B4332);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), groundPaint);

    final path = Path()
      ..moveTo(w * 0.38, 0)
      ..lineTo(w * 0.62, 0)
      ..lineTo(w * 0.85, h)
      ..lineTo(w * 0.15, h)
      ..close();

    final trackPaint = Paint()..color = const Color(0xFF523A28);
    canvas.drawPath(path, trackPaint);

    final stripePaint = Paint()
      ..color = const Color(0xFF8B5A2B)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 5; i++) {
      double yNorm = ((i / 5.0) + offset) % 1.0;
      double currentY = yNorm * h;
      double stripeWidth = (w * 0.1) + (yNorm * (w * 0.4));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(w / 2, currentY),
          width: stripeWidth,
          height: 6 + (yNorm * 8),
        ),
        stripePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) => true;
}
