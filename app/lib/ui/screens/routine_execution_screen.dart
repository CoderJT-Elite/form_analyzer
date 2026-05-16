import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_catalog.dart';
import '../../models/exercise_model.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';
import 'exercise_screen.dart';

class RoutineExecutionScreen extends StatefulWidget {
  final WorkoutRoutine routine;

  const RoutineExecutionScreen({super.key, required this.routine});

  @override
  State<RoutineExecutionScreen> createState() => _RoutineExecutionScreenState();
}

class _RoutineExecutionScreenState extends State<RoutineExecutionScreen> {
  int _currentIndex = 0;
  final List<WorkoutSession> _completedSessions = [];
  final StorageService _storage = StorageService();

  void _nextExercise() async {
    if (_currentIndex < widget.routine.exercises.length) {
      final type = widget.routine.exercises[_currentIndex];
      final exercise = ExerciseCatalog.exerciseForType(type);

      final result = await Navigator.push<WorkoutSession>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ExerciseScreen(exercise: exercise, isRoutineMode: true),
        ),
      );

      if (result != null) {
        _completedSessions.add(result);
      }

      setState(() {
        _currentIndex++;
      });

      if (_currentIndex >= widget.routine.exercises.length) {
        _finishRoutine();
      }
    }
  }

  void _finishRoutine() async {
    if (_completedSessions.isNotEmpty) {
      final session = RoutineSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        routineId: widget.routine.id,
        routineName: widget.routine.name,
        date: DateTime.now(),
        exerciseSessions: _completedSessions,
      );
      await _storage.saveRoutineSession(session);
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            'ROUTINE COMPLETE!',
            style: GoogleFonts.outfit(
              color: AppColors.accentCyan,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Great job completing ${widget.routine.name}!',
            style: GoogleFonts.inter(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text(
                'AWESOME',
                style: TextStyle(color: AppColors.accentCyan),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _currentIndex / widget.routine.exercises.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.routine.name.toUpperCase(),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.accentCyan,
                      ),
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Exercise ${_currentIndex + 1} of ${widget.routine.exercises.length}',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_currentIndex < widget.routine.exercises.length)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Text(
                      'NEXT UP',
                      style: GoogleFonts.inter(
                        color: AppColors.accentCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.routine.exercises[_currentIndex].name
                          .toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: GlassContainer(
                        padding: const EdgeInsets.all(40),
                        child: Icon(
                          ExerciseCatalog.templateForType(
                            widget.routine.exercises[_currentIndex],
                          ).icon,
                          color: AppColors.accentCyan,
                          size: 80,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextExercise,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 10,
                    shadowColor: AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                  child: Text(
                    _currentIndex == 0
                        ? 'START WORKOUT'
                        : 'START NEXT EXERCISE',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
