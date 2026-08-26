import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UltraTempleRunnerApp());
}

class UltraTempleRunnerApp extends StatelessWidget {
  const UltraTempleRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultra Temple Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07090E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFFFF0055),
          surface: Color(0xFF10141E),
        ),
      ),
      home: const UltraTrackerDashboard(),
    );
  }
}

// ---------------- DATA MODELS ----------------
class LapInfo {
  final int lapNumber;
  final int durationSeconds;
  final double distanceMeters;

  LapInfo({
    required this.lapNumber,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  String get formattedTime {
    final m = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }
}

class RunSession {
  final String id;
  final DateTime startTime;
  final double targetDistanceKm;
  double totalDistanceMeters;
  int durationSeconds;
  List<LatLng> routeCoordinates;
  List<LapInfo> laps;
  double currentSpeedKmh;
  double targetPaceKmh;
  int coinsCollected;

  RunSession({
    required this.id,
    required this.startTime,
    this.targetDistanceKm = 5.0,
    this.totalDistanceMeters = 0.0,
    this.durationSeconds = 0,
    this.currentSpeedKmh = 0.0,
    this.targetPaceKmh = 8.0,
    this.coinsCollected = 0,
    List<LatLng>? routeCoordinates,
    List<LapInfo>? laps,
  })  : routeCoordinates = routeCoordinates ?? [],
        laps = laps ?? [];

  int get caloriesBurned => (totalDistanceMeters / 1000 * 65).toInt();

  double get progressFraction =>
      (totalDistanceMeters / (targetDistanceKm * 1000)).clamp(0.0, 1.0);
}

// ---------------- VOICE ASSISTANT ----------------
class VoiceAssistantService {
  final FlutterTts _tts = FlutterTts();
  DateTime? _lastEncouragementTime;
  int _lastAnnouncedKm = 0;

  VoiceAssistantService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage("hi-IN");
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  void evaluateSpeed({
    required double currentSpeedKmh,
    required double targetSpeedKmh,
    required double distanceMeters,
    required double targetKm,
  }) {
    final now = DateTime.now();

    int currentKm = (distanceMeters / 1000).floor();
    if (currentKm > _lastAnnouncedKm && currentKm <= targetKm && currentKm > 0) {
      _lastAnnouncedKm = currentKm;
      speak("शानदार! आपने $currentKm किलोमीटर पूरा कर लिया है!");
      return;
    }

    if (_lastEncouragementTime == null ||
        now.difference(_lastEncouragementTime!).inSeconds > 40) {
      if (currentSpeedKmh > 1.5 && currentSpeedKmh < (targetSpeedKmh * 0.75)) {
        _lastEncouragementTime = now;
        speak("स्पीड धीमी हो रही है! थोड़ा और जोर लगाओ, टारगेट करीब है!");
      }
    }
  }
}

// ---------------- GPS RUN MANAGER ----------------
class RunManagerService extends ChangeNotifier {
  RunSession? session;
  final VoiceAssistantService voiceCoach = VoiceAssistantService();
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  bool isRunning = false;
  int _lastLapSeconds = 0;
  double _lastLapDistanceMeters = 0.0;

  void startRun({required double targetDistanceKm}) {
    session = RunSession(
      id: DateTime.now().toIso8601String(),
      startTime: DateTime.now(),
      targetDistanceKm: targetDistanceKm,
    );
    isRunning = true;
    _lastLapSeconds = 0;
    _lastLapDistanceMeters = 0.0;

    voiceCoach.speak("रनिंग शुरू! लक्ष्य है $targetDistanceKm किलोमीटर। ऑल द बेस्ट!");

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (session != null) {
        session!.durationSeconds++;
        // हर 20 मीटर पर एक सिक्का कलेक्ट होता है
        session!.coinsCollected = (session!.totalDistanceMeters / 20).floor();
        notifyListeners();
      }
    });

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Position pos) {
      if (session == null) return;

      final newCoord = LatLng(pos.latitude, pos.longitude);
      session!.currentSpeedKmh = (pos.speed * 3.6).clamp(0.0, 45.0);

      if (session!.routeCoordinates.isNotEmpty) {
        final last = session!.routeCoordinates.last;
        final d = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          newCoord.latitude,
          newCoord.longitude,
        );
        session!.totalDistanceMeters += d;
      }
      session!.routeCoordinates.add(newCoord);

      voiceCoach.evaluateSpeed(
        currentSpeedKmh: session!.currentSpeedKmh,
        targetSpeedKmh: session!.targetPaceKmh,
        distanceMeters: session!.totalDistanceMeters,
        targetKm: session!.targetDistanceKm,
      );

      notifyListeners();
    });

    notifyListeners();
  }

  void recordLap() {
    if (session == null) return;
    final lapDuration = session!.durationSeconds - _lastLapSeconds;
    final lapDistance = session!.totalDistanceMeters - _lastLapDistanceMeters;

    final newLap = LapInfo(
      lapNumber: session!.laps.length + 1,
      durationSeconds: lapDuration,
      distanceMeters: lapDistance,
    );

    session!.laps.insert(0, newLap);
    _lastLapSeconds = session!.durationSeconds;
    _lastLapDistanceMeters = session!.totalDistanceMeters;

    voiceCoach.speak(
      "चक्कर नंबर ${newLap.lapNumber} पूरा हुआ! समय: ${newLap.formattedTime}",
    );
    notifyListeners();
  }

  void stopRun() {
    isRunning = false;
    _timer?.cancel();
    _positionSub?.cancel();
    voiceCoach.speak("शानदार वर्कआउट पूरा हुआ! आपने बहुत अच्छा दौड़ा।");
    notifyListeners();
  }
}

// ---------------- 3D TEMPLE RUN GRAPHICS ENGINE ----------------
class UltraTempleCanvasWidget extends StatefulWidget {
  final double currentSpeedKmh;
  final int coins;

  const UltraTempleCanvasWidget({
    super.key,
    required this.currentSpeedKmh,
    required this.coins,
  });

  @override
  State<UltraTempleCanvasWidget> createState() => _UltraTempleCanvasWidgetState();
}

class _UltraTempleCanvasWidgetState extends State<UltraTempleCanvasWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  double _trackOffset = 0.0;
  double _runnerLimbPhase = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateScene);
    _animController.repeat();
  }

  void _updateScene() {
    final speedFactor = (widget.currentSpeedKmh / 8.0).clamp(0.1, 3.5);
    setState(() {
      _trackOffset = (_trackOffset + (0.025 * speedFactor)) % 1.0;
      _runnerLimbPhase = (_runnerLimbPhase + (0.15 * speedFactor)) % (2 * math.pi);
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
      height: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F5D4).withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _Ultra3DWorldPainter(
                offset: _trackOffset,
                limbPhase: _runnerLimbPhase,
                speedKmh: widget.currentSpeedKmh,
              ),
            ),
            // Coin Counter HUD
            Positioned(
              top: 12,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amberAccent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      "${widget.coins}",
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ultra3DWorldPainter extends CustomPainter {
  final double offset;
  final double limbPhase;
  final double speedKmh;

  _Ultra3DWorldPainter({
    required this.offset,
    required this.limbPhase,
    required this.speedKmh,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizonY = h * 0.28;

    // 1. DYNAMIC SKY & SUN
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF0A1128),
        const Color(0xFF1C3144),
        const Color(0xFFD00000).withOpacity(0.7),
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, horizonY),
      Paint()..shader = skyGradient.createShader(Rect.fromLTWH(0, 0, w, horizonY)),
    );

    // Glowing Sun
    canvas.drawCircle(
      Offset(w * 0.5, horizonY * 0.65),
      22,
      Paint()
        ..color = const Color(0xFFFFBA08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 14),
    );

    // 2. 3D TERRAIN & GRASS
    final grassPaint = Paint()..color = const Color(0xFF0F3820);
    canvas.drawRect(Rect.fromLTWH(0, horizonY, w, h - horizonY), grassPaint);

    // 3. 3D STONE TEMPLE PATH (Ancient Flagstones)
    final path3D = Path()
      ..moveTo(w * 0.42, horizonY)
      ..lineTo(w * 0.58, horizonY)
      ..lineTo(w * 0.88, h)
      ..lineTo(w * 0.12, h)
      ..close();

    final pathShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF2B2118),
        const Color(0xFF533E2D),
        const Color(0xFF382A1E),
      ],
    ).createShader(Rect.fromLTWH(0, horizonY, w, h));

    canvas.drawPath(path3D, Paint()..shader = pathShader);

    // Moving 3D Flagstone Slabs & Side Pillars
    for (int i = 0; i < 7; i++) {
      double t = ((i / 7.0) + offset) % 1.0;
      double y = horizonY + (math.pow(t, 2.2) * (h - horizonY));
      double roadWidth = (w * 0.16) + (t * (w * 0.76));

      // Slab separator
      canvas.drawLine(
        Offset((w / 2) - (roadWidth / 2), y),
        Offset((w / 2) + (roadWidth / 2), y),
        Paint()
          ..color = const Color(0xFF140F0A)
          ..strokeWidth = 2.0 + (t * 3.5),
      );

      // Ancient Pillars on Road Sides
      if (i % 2 == 0) {
        double pXLeft = (w / 2) - (roadWidth / 2) - (t * 18);
        double pXRight = (w / 2) + (roadWidth / 2) + (t * 18);
        double pillarH = 10 + (t * 38);
        double pillarW = 4 + (t * 12);

        final pillarPaint = Paint()..color = const Color(0xFF7A6855);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(pXLeft - pillarW, y - pillarH, pillarW, pillarH),
            const Radius.circular(2),
          ),
          pillarPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(pXRight, y - pillarH, pillarW, pillarH),
            const Radius.circular(2),
          ),
          pillarPaint,
        );
      }

      // Rotating 3D Gold Coins floating along the path
      if (i % 2 == 1) {
        double coinY = y - (12 + (t * 22));
        double coinRadius = 3 + (t * 8);
        double spinScale = math.cos((offset * math.pi * 6) + i).abs();

        final coinPaint = Paint()
          ..color = const Color(0xFFFFD166)
          ..style = PaintingStyle.fill;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w * 0.5, coinY),
            width: coinRadius * 2 * spinScale,
            height: coinRadius * 2,
          ),
          coinPaint,
        );
      }
    }

    // 4. ANIMATED 3D ATHLETIC RUNNER CHARACTER
    _draw3DAnimatedRunner(canvas, w * 0.5, h * 0.78);
  }

  void _draw3DAnimatedRunner(Canvas canvas, double rx, double ry) {
    final isRunningFast = speedKmh > 1.0;
    final legSwing = isRunningFast ? math.sin(limbPhase) * 22 : 0.0;
    final armSwing = isRunningFast ? math.cos(limbPhase) * 20 : 0.0;
    final bounce = isRunningFast ? (math.sin(limbPhase * 2).abs() * 6) : 0.0;

    final actualY = ry - bounce;

    // Ground Shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rx, ry + 20),
        width: 36 + (bounce * 1.5),
        height: 10,
      ),
      Paint()..color = Colors.black.withOpacity(0.55),
    );

    // Dust particles under feet
    if (isRunningFast) {
      canvas.drawCircle(
        Offset(rx - 12 + math.Random().nextDouble() * 24, ry + 18),
        3,
        Paint()..color = const Color(0xFFC49A6C).withOpacity(0.6),
      );
    }

    final neonBodyPaint = Paint()
      ..color = const Color(0xFF00F5D4)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final darkLimbPaint = Paint()
      ..color = const Color(0xFF00B4D8)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    // Legs (Left & Right with realistic knee bend)
    canvas.drawLine(
      Offset(rx - 4, actualY + 4),
      Offset(rx - 8 - (legSwing * 0.5), actualY + 12),
      darkLimbPaint,
    );
    canvas.drawLine(
      Offset(rx - 8 - (legSwing * 0.5), actualY + 12),
      Offset(rx - 10 - legSwing, actualY + 22),
      darkLimbPaint,
    );

    canvas.drawLine(
      Offset(rx + 4, actualY + 4),
      Offset(rx + 8 + (legSwing * 0.5), actualY + 12),
      neonBodyPaint,
    );
    canvas.drawLine(
      Offset(rx + 8 + (legSwing * 0.5), actualY + 12),
      Offset(rx + 10 + legSwing, actualY + 22),
      neonBodyPaint,
    );

    // Torso (Athletic body)
    canvas.drawLine(
      Offset(rx, actualY - 14),
      Offset(rx, actualY + 4),
      Paint()
        ..color = const Color(0xFFFF0055)
        ..strokeWidth = 7.0
        ..strokeCap = StrokeCap.round,
    );

    // Arms
    canvas.drawLine(
      Offset(rx - 4, actualY - 10),
      Offset(rx - 10 - armSwing, actualY),
      darkLimbPaint,
    );
    canvas.drawLine(
      Offset(rx + 4, actualY - 10),
      Offset(rx + 10 + armSwing, actualY),
      neonBodyPaint,
    );

    // Head with Neon Visor
    canvas.drawCircle(
      Offset(rx, actualY - 20),
      7.5,
      Paint()..color = const Color(0xFF00F5D4),
    );
  }

  @override
  bool shouldRepaint(covariant _Ultra3DWorldPainter oldDelegate) => true;
}

// ---------------- DASHBOARD UI ----------------
class UltraTrackerDashboard extends StatefulWidget {
  const UltraTrackerDashboard({super.key});

  @override
  State<UltraTrackerDashboard> createState() => _UltraTrackerDashboardState();
}

class _UltraTrackerDashboardState extends State<UltraTrackerDashboard> {
  final RunManagerService _manager = RunManagerService();
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (_manager.session != null &&
        _manager.session!.routeCoordinates.isNotEmpty) {
      _mapController.move(_manager.session!.routeCoordinates.last, 16.5);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = _manager.session;
    final speed = session?.currentSpeedKmh ?? 0.0;
    final distanceKm =
        ((session?.totalDistanceMeters ?? 0) / 1000).toStringAsFixed(2);

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "TEMPLE RUN 3D GPS",
          style: TextStyle(
            letterSpacing: 3,
            fontWeight: FontWeight.w900,
            color: Color(0xFF00F5D4),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 1. 3D TEMPLE RUN GRAPHICS SCREEN
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0),
            child: UltraTempleCanvasWidget(
              currentSpeedKmh: speed,
              coins: session?.coinsCollected ?? 0,
            ),
          ),
          const SizedBox(height: 10),

          // 2. TARGET PROGRESS BAR
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "GOAL: ${session?.targetDistanceKm ?? 5.0} KM",
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "${((session?.progressFraction ?? 0) * 100).toInt()}% COMPLETED",
                      style: const TextStyle(
                        color: Color(0xFF00F5D4),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: session?.progressFraction ?? 0.0,
                    backgroundColor: const Color(0xFF141923),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF00F5D4)),
                    minHeight: 7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. LIVE MAP WITH RUNNER PIN
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(26.8467, 80.9462),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    if (session != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: session.routeCoordinates,
                            strokeWidth: 5.0,
                            color: const Color(0xFF00F5D4),
                          ),
                        ],
                      ),
                    if (session != null && session.routeCoordinates.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: session.routeCoordinates.last,
                            width: 26,
                            height: 26,
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF0055),
                                boxShadow: [
                                  BoxShadow(color: Color(0xFFFF0055), blurRadius: 10),
                                ],
                              ),
                              child: const Icon(Icons.navigation, size: 15, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 4. CONTROL DECK & METRICS
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFF10141E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _hudCard("DISTANCE", "$distanceKm km"),
                    _hudCard("SPEED", "${speed.toStringAsFixed(1)} km/h"),
                    _hudCard("ENERGY", "${session?.caloriesBurned ?? 0} kcal"),
                    _hudCard("LAPS", "${session?.laps.length ?? 0}"),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (!_manager.isRunning)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _manager.startRun(targetDistanceKm: 5.0),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F5D4),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text(
                            "START 5KM RUN 🏃",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _manager.recordLap,
                          icon: const Icon(Icons.flag, size: 20),
                          label: const Text("LAP (चक्कर)"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7B2CBF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        onPressed: _manager.stopRun,
                        icon: const Icon(Icons.stop),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFF0055),
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudCard(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
