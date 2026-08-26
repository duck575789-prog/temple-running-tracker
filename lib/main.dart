import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Force Portrait Mode Only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const UltraTempleRunnerApp());
}

class UltraTempleRunnerApp extends StatelessWidget {
  const UltraTempleRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Temple Runner Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07090E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFFFFB703),
          surface: Color(0xFF10141E),
        ),
      ),
      home: const UltraGameTrackerScreen(),
    );
  }
}

// ---------------- MODELS ----------------
class LapInfo {
  final int lapNumber;
  final int durationSeconds;
  final double distanceMeters;
  final double avgSpeed;

  LapInfo({
    required this.lapNumber,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.avgSpeed,
  });

  String get formattedTime {
    final m = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }
}

class GameParticle {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;

  GameParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
  });
}

// ---------------- 3D GAME TRACK ENGINE ----------------
class HighEndTempleTrack extends StatefulWidget {
  final double currentSpeedKmh;
  final int coinsCollected;
  final bool isRunning;

  const HighEndTempleTrack({
    super.key,
    required this.currentSpeedKmh,
    required this.coinsCollected,
    required this.isRunning,
  });

  @override
  State<HighEndTempleTrack> createState() => _HighEndTempleTrackState();
}

class _HighEndTempleTrackState extends State<HighEndTempleTrack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _trackScroll = 0.0;
  double _runnerCycle = 0.0;
  final List<GameParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_tick);
    _controller.repeat();
  }

  void _tick() {
    final speedRatio = (widget.currentSpeedKmh / 12.0).clamp(0.0, 3.5);
    final activeSpeed = widget.isRunning ? math.max(0.8, speedRatio) : 0.0;

    setState(() {
      _trackScroll = (_trackScroll + 0.03 * activeSpeed) % 1.0;
      _runnerCycle += 0.25 * activeSpeed;

      if (widget.isRunning && _random.nextDouble() < 0.4) {
        _particles.add(GameParticle(
          x: 0.5 + (_random.nextDouble() * 0.1 - 0.05),
          y: 0.82,
          vx: (_random.nextDouble() - 0.5) * 0.008,
          vy: -(_random.nextDouble() * 0.005 + 0.002),
          life: 1.0,
          color: const Color(0xFFD4A373).withOpacity(0.7),
        ));
      }

      for (int i = _particles.length - 1; i >= 0; i--) {
        final p = _particles[i];
        p.x += p.vx;
        p.y += p.vy;
        p.life -= 0.04;
        if (p.life <= 0) {
          _particles.removeAt(i);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24
