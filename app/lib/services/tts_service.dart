import 'package:flutter_tts/flutter_tts.dart';

/// How badly a phrase needs to be heard right now.
enum SpeechPriority {
  /// The rep count: said only into silence, and cut off by any coaching.
  low,

  /// Coaching that can wait: dropped if something is already being said.
  normal,

  /// Safety warnings and the countdown: may interrupt lower-priority speech, but
  /// never another urgent phrase (that just chops both to pieces).
  urgent,
}

/// Speaks coaching cues aloud.
///
/// Deciding *what is worth saying* is a coaching concern and lives in
/// `CueEngine`. This class decides only what can physically be said *now*.
///
/// Every `speak()` used to flush whatever was playing, so a safety cue that
/// repeats every two seconds -- but takes about four to say at this speech
/// rate -- was cut off by its own next repeat and the athlete only ever heard
/// "Stop and reset, your back is..." for half a minute (live test 2026-09-20).
class TTSService {
  TTSService({FlutterTts? engine}) : _flutterTts = engine ?? FlutterTts();

  final FlutterTts _flutterTts;
  bool isEnabled = true;

  bool _speaking = false;
  SpeechPriority _current = SpeechPriority.normal;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Guard against a completion callback that never arrives (some engines drop
  /// it on interruption), which would otherwise silence the coach for good.
  static const Duration _stuckAfter = Duration(seconds: 8);

  bool get isSpeaking => _speaking;

  Future<void> init() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setStartHandler(() => _speaking = true);
    _flutterTts.setCompletionHandler(_finished);
    _flutterTts.setCancelHandler(_finished);
    _flutterTts.setErrorHandler((_) => _finished());
  }

  void _finished() => _speaking = false;

  /// Whether [priority] speech would be accepted right now.
  bool canSpeak(SpeechPriority priority, {DateTime? now}) {
    if (!isEnabled) return false;
    if (!_speaking) return true;
    final t = now ?? DateTime.now();
    if (t.difference(_startedAt) > _stuckAfter) return true;
    return priority.index > _current.index;
  }

  /// Returns true if the phrase was handed to the engine.
  Future<bool> speak(
    String message, {
    SpeechPriority priority = SpeechPriority.normal,
  }) async {
    if (message.isEmpty || !canSpeak(priority)) return false;

    final interrupting = _speaking;
    _speaking = true;
    _current = priority;
    _startedAt = DateTime.now();
    if (interrupting) await _flutterTts.stop();
    await _flutterTts.speak(message);
    return true;
  }

  Future<void> stop() async {
    _speaking = false;
    await _flutterTts.stop();
  }

  void toggle() {
    isEnabled = !isEnabled;
  }

  void setEnabled(bool value) {
    isEnabled = value;
  }
}
