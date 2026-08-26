import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TempleRunnerApp());
}

class TempleRunnerApp extends StatelessWidget {
  const TempleRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Temple Run GPS Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D111A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFFFF0055),
          surface: Color(0xFF141923),
        ),
      ),
      home: const MainTrackerScreen(),
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

enum TrackTheme { grass, neonCity, desert, lava }

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
  TrackTheme activeTheme;

  RunSession({
    required this.id,
    required this.startTime,
    this.targetDistanceKm = 5.0,
    this.totalDistanceMeters = 0.0,
    this.durationSeconds = 0,
    this.currentSpeedKmh = 0.0,
    this.targetPaceKmh = 8.0,
    this.activeTheme = TrackTheme.grass,
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
      speak("शाबाश! आपने $currentKm किलोमीटर पूरा कर लिया है।");
      return;
    }

    if (_lastEncouragementTime == null ||
        now.difference(_lastEncouragementTime!).inSeconds > 45) {
      if (currentSpeedKmh > 1.5 && currentSpeedKmh < (targetSpeedKmh * 0.75)) {
        _lastEncouragementTime = now;
        speak("कम ऑन! स्पीड धीमी हो रही है, थोड़ा और जोर लगाओ, लक्ष्य करीब है!");
      }
    }
  }
}

// ---------------- RUN MANAGER ----------------
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

    voiceCoach.speak("रनिंग शुरू! आपका लक्ष्य है $targetDistanceKm किलोमीटर।");

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (session != null) {
        session!.durationSeconds++;
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
      "चक्कर नंबर ${newLap.lapNumber} पूरा हुआ, समय लगा ${newLap.formattedTime}",
    );
    notifyListeners();
  }

  void stopRun() {
    isRunning = false;
    _timer?.cancel();
    _positionSub?.cancel();
    voiceCoach.speak("शानदार रन! आपने वर्कआउट पूरा कर लिया है।");
    notifyListeners();
  }
}

// ---------------- TEMPLE RUN TRACK WIDGET ----------------
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
      height: 180,
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
                    size: 56,
                    color: Color(0xFF00F5D4),
                    shadows: [
                      Shadow(color: Color(0xFF00F5D4), blurRadius: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
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

// ---------------- MAIN TRACKER SCREEN ----------------
class MainTrackerScreen extends StatefulWidget {
  const MainTrackerScreen({super.key});

  @override
  State<MainTrackerScreen> createState() => _MainTrackerScreenState();
}

class _MainTrackerScreenState extends State<MainTrackerScreen> {
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
      backgroundColor: const Color(0xFF0D111A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "TEMPLE RUNNER HUD",
          style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TempleRunTrackWidget(currentSpeedKmh: speed),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("TARGET: ${session?.targetDistanceKm ?? 5.0} KM",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    Text(
                        "${((session?.progressFraction ?? 0) * 100).toInt()}% COMPLETED",
                        style: const TextStyle(
                            color: Color(0xFF00F5D4),
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: session?.progressFraction ?? 0.0,
                  backgroundColor: const Color(0xFF1E2532),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF00F5D4)),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    if (session != null &&
                        session.routeCoordinates.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: session.routeCoordinates.last,
                            width: 28,
                            height: 28,
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF0055),
                                boxShadow: [
                                  BoxShadow(
                                      color: Color(0xFFFF0055),
                                      blurRadius: 12),
                                ],
                              ),
                              child: const Icon(Icons.navigation,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF141923),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statItem("DIST", "$distanceKm km"),
                    _statItem("SPEED", "${speed.toStringAsFixed(1)} km/h"),
                    _statItem("ENERGY", "${session?.caloriesBurned ?? 0} kcal"),
                    _statItem("LAPS", "${session?.laps.length ?? 0}"),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!_manager.isRunning)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              _manager.startRun(targetDistanceKm: 5.0),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F5D4),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("START 5KM RUN",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _manager.recordLap,
                          icon: const Icon(Icons.flag),
                          label: const Text("NEW LAP (चक्कर)"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7B2CBF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
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

  Widget _statItem(String label, String val) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: Colors.white54,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val,
            style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w900)),
      ],
    );
  }
}
