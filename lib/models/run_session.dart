import 'package:latlong2/latlong.dart';

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
