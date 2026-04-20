import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  // Tuned for typical rep cadence: fast corrective hints, slightly slower safety repeats.
  static const int _correctionThrottleMilliseconds = 900;
  static const int _safetyThrottleMilliseconds = 1200;

  final FlutterTts _flutterTts = FlutterTts();
  bool isEnabled = true;
  String _lastSpokenMessage = '';
  DateTime _lastCorrectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSafetyAt = DateTime.fromMillisecondsSinceEpoch(0);

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

  Future<void> speakSuccess(String message) async {
    if (!isEnabled) return;
    _lastSpokenMessage = '';
    await _flutterTts.speak(message);
  }

  Future<void> speakCorrection(String message) async {
    if (!isEnabled) return;
    final now = DateTime.now();
    if (now.difference(_lastCorrectionAt).inMilliseconds < _correctionThrottleMilliseconds) return;
    _lastCorrectionAt = now;
    _lastSpokenMessage = '';
    await _flutterTts.speak(message);
  }

  Future<void> speakSafety(String message) async {
    if (!isEnabled) return;
    final now = DateTime.now();
    if (now.difference(_lastSafetyAt).inMilliseconds < _safetyThrottleMilliseconds) return;
    _lastSafetyAt = now;
    _lastSpokenMessage = '';
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
