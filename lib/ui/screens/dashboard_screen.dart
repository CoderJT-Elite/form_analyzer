import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../logic/exercise_analyzer.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';
import 'exercise_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final StorageService _storage = StorageService();
  List<String> _history = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await _storage.loadHistory();
    setState(() => _history = history);
  }

  @override
  Widget build(BuildContext context) {
    final exercises = [
      Exercise(
        name: 'SQUATS',
        description: 'Track depth and torso angle',
        icon: Icons.fitness_center_rounded,
        type: ExerciseType.squat,
        analyzer: SquatAnalyzer(),
      ),
      Exercise(
        name: 'PUSH-UPS',
        description: 'Monitor spine and elbow alignment',
        icon: Icons.horizontal_rule_rounded,
        type: ExerciseType.pushup,
        analyzer: PushupAnalyzer(),
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _buildHistoryDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.history_rounded, color: Colors.white),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              title: Text(
                'WORKOUT',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
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
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final ex = exercises[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _ExerciseCard(exercise: ex),
                  );
                },
                childCount: exercises.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: AppColors.accentCyan.withAlpha(25),
              border: Border(bottom: BorderSide(color: AppColors.accentCyan.withAlpha(10))),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, color: AppColors.accentCyan, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'WORKOUT HISTORY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _history.isEmpty
                ? const Center(
                    child: Text('No sessions yet', style: TextStyle(color: Colors.white24)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      return GlassContainer(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          item,
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                        ),
                      );
                    },
                  ),
          ),
          if (_history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: TextButton.icon(
                onPressed: () async {
                  await _storage.clearHistory();
                  _loadHistory();
                },
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.badRed),
                label: const Text('Clear History', style: TextStyle(color: AppColors.badRed)),
              ),
            ),
        ],
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
      padding: const EdgeInsets.all(20),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ExerciseScreen(exercise: exercise),
          ),
        ),
        child: Row(
          children: [
            Hero(
              tag: 'exercise_${exercise.type.name}',
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withAlpha(25),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(exercise.icon, color: AppColors.accentCyan, size: 32),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exercise.description,
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}
