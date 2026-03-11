import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final StorageService _storage = StorageService();
  List<WorkoutSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sessions = await _storage.loadSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentCyan),
        ),
      );
    }

    final totalReps = _sessions.fold(0, (sum, s) => sum + s.totalReps);
    final totalSessions = _sessions.length;

    // Group by exercise type
    Map<ExerciseType, int> exerciseDistribution = {};
    for (var session in _sessions) {
      exerciseDistribution[session.exerciseType] =
          (exerciseDistribution[session.exerciseType] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'STATISTICS',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontSize: 20,
                ),
              ),
              centerTitle: false,
              titlePadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatHeader('OVERVIEW'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Total Reps',
                          totalReps.toString(),
                          Icons.bolt_rounded,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          'Sessions',
                          totalSessions.toString(),
                          Icons.history_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildStatHeader('EXERCISE DISTRIBUTION'),
                  const SizedBox(height: 16),
                  ...exerciseDistribution.entries.map((e) {
                    final percentage = (e.value / totalSessions * 100)
                        .toStringAsFixed(0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildProgressRow(
                        e.key.name.toUpperCase(),
                        e.value / totalSessions,
                        "$percentage%",
                      ),
                    );
                  }),
                  if (exerciseDistribution.isEmpty)
                    const Center(
                      child: Text(
                        'No data yet. Start training!',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        color: Colors.white70,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accentCyan, size: 24),
          const SizedBox(height: 16),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, double value, String trailing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              trailing,
              style: GoogleFonts.inter(
                color: AppColors.accentCyan,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.white.withOpacity(0.05),
            color: AppColors.accentCyan,
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
