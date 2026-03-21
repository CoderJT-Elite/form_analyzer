import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';
import 'routine_execution_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  List<WorkoutRoutine> _routines = [];
  List<WorkoutSession> _sessions = [];
  bool _isLoading = true;
  late AnimationController _headerAnimController;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFade = CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOut,
    );
    _loadData();
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final routines = await _storageService.loadRoutines();
      final sessions = await _storageService.loadSessions();
      setState(() {
        _routines = routines;
        _sessions = sessions;
        _isLoading = false;
      });
      _headerAnimController.forward();
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRoutine(String id) async {
    try {
      await _storageService.deleteRoutine(id);
      _loadData();
    } catch (e) {
      debugPrint('Error deleting routine: $e');
    }
  }

  int get _totalReps => _sessions.fold(0, (s, e) => s + e.totalReps);
  int get _totalSessions => _sessions.length;
  double get _avgForm {
    final ratings = _sessions
        .where((s) => s.overallRating != null)
        .map((s) => s.overallRating!)
        .toList();
    if (ratings.isEmpty) return 0.0;
    return ratings.reduce((a, b) => a + b) / ratings.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accentCyan),
            )
          : CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsRow(),
                        const SizedBox(height: 36),
                        _buildRoutinesSection(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSliverAppBar() {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';

    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
          child: FadeTransition(
            opacity: _headerFade,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'TRAIN',
                  style: GoogleFonts.outfit(
                    color: AppColors.textPrimary,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMiniStat(
            label: 'SESSIONS',
            value: _totalSessions.toString(),
            icon: Icons.bolt_rounded,
            color: AppColors.accentCyan,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMiniStat(
            label: 'TOTAL REPS',
            value: _totalReps.toString(),
            icon: Icons.bar_chart_rounded,
            color: AppColors.accentMagenta,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMiniStat(
            label: 'AVG FORM',
            value: _avgForm > 0 ? _avgForm.toStringAsFixed(1) : '--',
            icon: Icons.star_rounded,
            color: AppColors.accentGold,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: AppColors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutinesSection() {
    return Column(
      children: [
        SectionLabel(
          text: 'MY ROUTINES',
          trailing: GestureDetector(
            onTap: _showCreateRoutineDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accentCyan.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add,
                    color: AppColors.accentCyan,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'NEW',
                    style: GoogleFonts.outfit(
                      color: AppColors.accentCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _routines.isEmpty
            ? _buildEmptyState()
            : Column(
                children:
                    _routines.map((r) => _buildRoutineCard(r)).toList(),
              ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accentCyan.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.1)),
            ),
            child: const Icon(
              Icons.fitness_center_rounded,
              color: AppColors.accentCyan,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'NO ROUTINES YET',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first routine to start training.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showCreateRoutineDialog,
              child: const Text('CREATE ROUTINE'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineCard(WorkoutRoutine routine) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(routine.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: AppColors.badRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.badRed.withValues(alpha: 0.15)),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: AppColors.badRed,
            size: 22,
          ),
        ),
        onDismissed: (_) => _deleteRoutine(routine.id),
        child: GlassContainer(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    RoutineExecutionScreen(routine: routine),
              ),
            );
            _loadData();
          },
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accentCyan.withValues(alpha: 0.15),
                  ),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.accentCyan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.name,
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${routine.exercises.length} exercise${routine.exercises.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateRoutineDialog() async {
    final nameController = TextEditingController();
    final List<ExerciseType> selectedExercises = [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 32,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppColors.border),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderBright,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'NEW ROUTINE',
                  style: GoogleFonts.outfit(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  style: GoogleFonts.outfit(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Routine Name',
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'SELECT EXERCISES',
                  style: GoogleFonts.outfit(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExerciseType.values.map((type) {
                    final isSelected = selectedExercises.contains(type);
                    return FilterChip(
                      selected: isSelected,
                      label: Text(
                        type.name.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: isSelected
                              ? Colors.black
                              : AppColors.textSecondary,
                        ),
                      ),
                      selectedColor: AppColors.accentCyan,
                      onSelected: (val) {
                        setModalState(() {
                          val
                              ? selectedExercises.add(type)
                              : selectedExercises.remove(type);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isNotEmpty &&
                          selectedExercises.isNotEmpty) {
                        final routine = WorkoutRoutine(
                          id: DateTime.now()
                              .millisecondsSinceEpoch
                              .toString(),
                          name: nameController.text,
                          exercises: selectedExercises,
                        );
                        await _storageService.saveRoutine(routine);
                        _loadData();
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    child: const Text('CREATE ROUTINE'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
