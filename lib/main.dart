import 'package:flutter/material.dart';
import 'screens/main_tracker_screen.dart';

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
