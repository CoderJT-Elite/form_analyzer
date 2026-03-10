import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _historyKey = 'workout_history';

  Future<List<String>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? [];
  }

  Future<void> saveWorkout(int repCount, String exerciseName) async {
    if (repCount == 0) return;
    
    final now = DateTime.now();
    final entry = "${_formatDate(now)}: $repCount $exerciseName reps";

    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_historyKey) ?? [];
    history.insert(0, entry);
    await prefs.setStringList(_historyKey, history);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  String _formatDate(DateTime date) {
    // Simple format helper to avoid full intl dependency in storage service if possible
    // but we have intl, so let's use it for consistency.
    return "${_monthName(date.month)} ${date.day}, ${date.hour > 12 ? date.hour - 12 : date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}";
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
