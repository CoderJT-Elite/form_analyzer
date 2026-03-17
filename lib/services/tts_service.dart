import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool isEnabled = true;
  String _lastSpokenMessage = '';

  Future<void> init() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> speak(String message) async {
    if (!isEnabled) return;
    if (message == _lastSpokenMessage) return;
    // Don't speak initialization messages or very repetitive framing messages
    if (message.contains('Ready') || message.contains('Align')) return;
    
    _lastSpokenMessage = message;
    await _flutterTts.speak(message);
  }

  /// Speaks [message] immediately, bypassing the deduplication guard.
  /// Use for important one-off coaching cues (e.g. "Go deeper next time.").
  Future<void> speakFeedback(String message) async {
    if (!isEnabled) return;
    _lastSpokenMessage = '';
    await _flutterTts.speak(message);
  }

  void toggle() {
    isEnabled = !isEnabled;
  }
}
