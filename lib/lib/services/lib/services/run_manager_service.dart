import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/run_session.dart';
import 'voice_assistant_service.dart';

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
