import 'package:flutter_tts/flutter_tts.dart';

class VoiceAssistantService {
  final FlutterTts _tts = FlutterTts();
  DateTime? _lastEncouragementTime;
  int _lastAnnouncedKm = 0;

  VoiceAssistantService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("hi-IN");
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
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
