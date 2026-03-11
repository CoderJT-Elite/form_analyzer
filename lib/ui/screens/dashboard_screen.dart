import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../logic/exercise_analyzer.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';
import 'exercise_screen.dart';
<<<<<<< Updated upstream
<<<<<<< Updated upstream
import 'profile_screen.dart';
=======
import 'history_screen.dart';
import 'routine_execution_screen.dart';
>>>>>>> Stashed changes
=======
import 'history_screen.dart';
import 'routine_execution_screen.dart';
>>>>>>> Stashed changes

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final StorageService _storage = StorageService();
  List<WorkoutSession> _sessions = [];
  List<WorkoutRoutine> _routines = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final sessions = await _storage.loadSessions();
    final routines = await _storage.loadRoutines();
    setState(() {
      _sessions = sessions;
      _routines = routines;
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercises = [
      Exercise(
        name: 'SQUATS',
        description: 'Perfect your depth and torso angle',
        instructions:
            'Stand with feet shoulder-width apart. Lower your hips until thighs are parallel to the floor.',
        muscleGroup: 'Quadriceps, Glutes',
        difficulty: 'Intermediate',
        icon: Icons.fitness_center_rounded,
        type: ExerciseType.squat,
        analyzer: SquatAnalyzer(),
      ),
      Exercise(
        name: 'PUSH-UPS',
        description: 'Build upper body and core strength',
        instructions:
            'Keep your body in a straight line. Lower your chest until it nearly touches the floor.',
        muscleGroup: 'Chest, Triceps, Shoulders',
        difficulty: 'Beginner',
        icon: Icons.horizontal_rule_rounded,
        type: ExerciseType.pushup,
        analyzer: PushupAnalyzer(),
      ),
      Exercise(
        name: 'LUNGES',
        description: 'Improves balance and leg strength',
        instructions:
            'Step forward and lower your back knee until it nearly touches the ground.',
        muscleGroup: 'Hamstrings, Glutes',
        difficulty: 'Beginner',
        icon: Icons.directions_walk_rounded,
        type: ExerciseType.lunge,
        analyzer: LungeAnalyzer(),
      ),
      Exercise(
        name: 'OVERHEAD PRESS',
        description: 'Build powerful shoulders',
        instructions:
            'Press the weights directly overhead while keeping your core tight.',
        muscleGroup: 'Shoulders, Triceps',
        difficulty: 'Intermediate',
        icon: Icons.upload_rounded,
        type: ExerciseType.overheadPress,
        analyzer: OverheadPressAnalyzer(),
      ),
      Exercise(
        name: 'PLANK',
        description: 'The ultimate core endurance test',
        instructions:
            'Hold a straight body position resting on your forearms and toes.',
        muscleGroup: 'Core, Abs',
        difficulty: 'Advanced',
        icon: Icons.view_headline_rounded,
        type: ExerciseType.plank,
        analyzer: PlankAnalyzer(),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
<<<<<<< Updated upstream
<<<<<<< Updated upstream
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.history_rounded, color: Colors.white),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_rounded, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsetsDirectional.only(
                start: 72,
                end: 72,
                bottom: 16,
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.self_improvement_rounded,
                      color: AppColors.accentCyan, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'FORM ANALYZER',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accentCyan.withAlpha(51),
                      Colors.transparent,
                    ],
                  ),
=======
=======
>>>>>>> Stashed changes
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'YOUR DAILY GOALS',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
<<<<<<< Updated upstream
>>>>>>> Stashed changes
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.accentCyan.withAlpha(30),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.accentCyan.withAlpha(80),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.self_improvement_rounded,
                            color: AppColors.accentCyan,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'FORM ANALYZER PRO',
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),
=======
>>>>>>> Stashed changes
                ),
              ),
            ),
          ),
          _buildQuickStats(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ROUTINES',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  GestureDetector(
                    onTap: _showCreateRoutineDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentCyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accentCyan.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.add,
                            color: AppColors.accentCyan,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'CREATE',
                            style: GoogleFonts.inter(
                              color: AppColors.accentCyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: _routines.isEmpty
                  ? Center(
                      child: Text(
                        'No routines yet. Create one to get started!',
                        style: GoogleFonts.inter(
                          color: Colors.white24,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _routines.length,
                      itemBuilder: (context, index) {
                        final routine = _routines[index];
                        return _RoutineCard(
                          routine: routine,
                          onTap: () => _startRoutine(routine),
                        );
                      },
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'EXERCISES',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HistoryScreen(),
                      ),
                    ),
                    child: Text(
                      'VIEW HISTORY',
                      style: GoogleFonts.inter(
                        color: AppColors.accentCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final ex = exercises[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ExerciseCard(exercise: ex),
                );
              }, childCount: exercises.length),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      elevation: 0,
      backgroundColor: AppColors.background,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.accentCyan.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Image.asset(
                'assets/logo.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'FORM ANALYZER',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
        background: Stack(
          children: [
            Positioned(
              right: -30,
              top: -20,
              child: CircleAvatar(
                radius: 80,
                backgroundColor: AppColors.accentCyan.withAlpha(20),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.accentCyan.withAlpha(30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    final totalReps = _sessions.fold(0, (sum, s) => sum + s.totalReps);
    final sessionsToday = _sessions
        .where(
          (s) =>
              s.date.day == DateTime.now().day &&
              s.date.month == DateTime.now().month &&
              s.date.year == DateTime.now().year,
        )
        .length;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: GlassContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'TOTAL REPS',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalReps.toString(),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'SESSIONS TODAY',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sessionsToday.toString(),
                        style: GoogleFonts.outfit(
                          color: AppColors.accentCyan,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateRoutineDialog() {
    String name = "";
    List<ExerciseType> selectedExercises = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Color(0xFF151515),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NEW ROUTINE',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                onChanged: (v) => name = v,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Routine Name (e.g. Leg Day)',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SELECT EXERCISES',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: ExerciseType.values.map((type) {
                    final isSelected = selectedExercises.contains(type);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              selectedExercises.remove(type);
                            } else {
                              selectedExercises.add(type);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accentCyan.withOpacity(0.1)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.accentCyan
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                type.name.toUpperCase(),
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.accentCyan
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.accentCyan,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (name.isNotEmpty && selectedExercises.isNotEmpty) {
                      final routine = WorkoutRoutine(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: name,
                        exercises: selectedExercises,
                      );
                      await _storage.saveRoutine(routine);
                      if (mounted) {
                        _loadHistory();
                        Navigator.pop(context);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'SAVE ROUTINE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startRoutine(WorkoutRoutine routine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoutineExecutionScreen(routine: routine),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final Exercise exercise;

  const _ExerciseCard({required this.exercise});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ExerciseScreen(exercise: exercise),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Hero(
                tag: 'exercise_${exercise.type.name}',
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withAlpha(20),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    exercise.icon,
                    color: AppColors.accentCyan,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          exercise.name,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _DifficultyTag(difficulty: exercise.difficulty),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exercise.muscleGroup,
                      style: GoogleFonts.inter(
                        color: AppColors.accentCyan.withAlpha(180),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exercise.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultyTag extends StatelessWidget {
  final String difficulty;
  const _DifficultyTag({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        color = Colors.greenAccent;
        break;
      case 'intermediate':
        color = Colors.orangeAccent;
        break;
      case 'advanced':
        color = Colors.redAccent;
        break;
      default:
        color = Colors.white24;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        difficulty.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  final WorkoutRoutine routine;
  final VoidCallback onTap;

  const _RoutineCard({required this.routine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onTap: onTap,
        child: GlassContainer(
          width: 140,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.accentCyan,
                  size: 20,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                routine.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${routine.exercises.length} Exercises',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
