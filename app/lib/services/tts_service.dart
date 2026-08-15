import 'package:flutter_tts/flutter_tts.dart';

/// Speaks coaching cues aloud.
///
/// This used to own the rate limiting — a 900ms correction throttle, a 1200ms
/// safety throttle, and a dedupe guard that compared against the last message
/// with no expiry (so a cue said once could stay silent indefinitely). Deciding
/// *what is worth saying* is a coaching concern, not a speech-synthesis one, so
/// it now lives in `CueEngine`. This class just speaks what it is handed.
class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool isEnabled = true;

  Future<void> init() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> speak(String message) async {
    if (!isEnabled) return;
    if (message.isEmpty) return;
    await _flutterTts.speak(message);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  void toggle() {
    isEnabled = !isEnabled;
  }

  void setEnabled(bool value) {
    isEnabled = value;
  }
}
