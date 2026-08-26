import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/run_manager_service.dart';
import '../widgets/temple_run_track.dart';

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
    final distanceKm = ((session?.totalDistanceMeters ?? 0) / 1000).toStringAsFixed(2);

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
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text("${((session?.progressFraction ?? 0) * 100).toInt()}% COMPLETED",
                        style: const TextStyle(color: Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: session?.progressFraction ?? 0.0,
                  backgroundColor: const Color(0xFF1E2532),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00F5D4)),
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
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
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
                            width: 28,
                            height: 28,
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF0055),
                                boxShadow: [
                                  BoxShadow(color: Color(0xFFFF0055), blurRadius: 12),
                                ],
                              ),
                              child: const Icon(Icons.navigation, size: 16, color: Colors.white),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          onPressed: () => _manager.startRun(targetDistanceKm: 5.0),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F5D4),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("START 5KM RUN", style: TextStyle(fontWeight: FontWeight.bold)),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
