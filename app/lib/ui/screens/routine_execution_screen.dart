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
    if (_currentIndex >= widget.routine.exercises.length) {
      Navigator.pop(context);
      return;
    }

    final type = widget.routine.exercises[_currentIndex];
    final exercise = ExerciseCatalog.exerciseForType(type);

    final result = await Navigator.push<WorkoutSession>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ExerciseScreen(exercise: exercise, isRoutineMode: true),
      ),
    );

    if (!mounted) return;

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
    final hasExercises = widget.routine.exercises.isNotEmpty;
    final progress = hasExercises
        ? (_currentIndex / widget.routine.exercises.length).clamp(0.0, 1.0)
        : 0.0;
    final isFinished = _currentIndex >= widget.routine.exercises.length;

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
                  Expanded(
                    child: Text(
                      widget.routine.name.toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                      overflow: TextOverflow.ellipsis,
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
                    hasExercises
                        ? 'Exercise ${_currentIndex < widget.routine.exercises.length ? _currentIndex + 1 : widget.routine.exercises.length} of ${widget.routine.exercises.length}'
                        : '0 of 0 exercises',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: hasExercises && !isFinished
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
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
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: 180,
                              height: 180,
                              child: GlassContainer(
                                padding: const EdgeInsets.all(32),
                                child: Image.asset(
                                  ExerciseCatalog.definitionForType(
                                    widget.routine.exercises[_currentIndex],
                                  ).iconAsset,
                                  width: 80,
                                  height: 80,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasExercises
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.info_outline_rounded,
                              color: AppColors.accentCyan,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              hasExercises
                                  ? 'ALL EXERCISES COMPLETE'
                                  : 'NO EXERCISES IN ROUTINE',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
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
                    !hasExercises
                        ? 'CLOSE'
                        : isFinished
                            ? 'FINISH ROUTINE'
                            : (_currentIndex == 0
                                ? 'START WORKOUT'
                                : 'START NEXT EXERCISE'),
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
