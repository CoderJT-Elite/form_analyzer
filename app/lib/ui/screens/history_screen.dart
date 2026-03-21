import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final StorageService _storage = StorageService();
  List<WorkoutSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final sessions = await _storage.loadSessions();
    setState(() {
      _sessions = sessions.reversed.toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAST WORKOUTS',
                      style: GoogleFonts.outfit(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'HISTORY',
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
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accentCyan),
              ),
            )
          else if (_sessions.isEmpty)
            SliverFillRemaining(child: _buildEmpty())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _SessionCard(session: _sessions[i]),
                  childCount: _sessions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.accentMagenta.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentMagenta.withValues(alpha: 0.1),
              ),
            ),
            child: Icon(
              Icons.history_rounded,
              color: AppColors.accentMagenta,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'NO HISTORY YET',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete a workout to see it here.',
            style: GoogleFonts.inter(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final WorkoutSession session;
  const _SessionCard({required this.session});

  Color _ratingColor(double r) {
    if (r >= 4.5) return AppColors.goodGreen;
    if (r >= 3.0) return AppColors.warnOrange;
    return AppColors.badRed;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy • HH:mm').format(session.date);
    final rating = session.overallRating;
    final rColor = rating != null ? _ratingColor(rating) : AppColors.textTertiary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentCyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          session.exerciseType.name.toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: AppColors.accentCyan,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dateStr,
                        style: GoogleFonts.inter(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Stats
                Row(
                  children: [
                    if (rating != null)
                      DataBadge(
                        label: 'FORM',
                        value: rating.toStringAsFixed(1),
                        color: rColor,
                      ),
                    const SizedBox(width: 8),
                    DataBadge(
                      label: 'REPS',
                      value: '${session.totalReps}',
                    ),
                  ],
                ),
              ],
            ),

            // Issues
            if (session.overallFeedback.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: session.overallFeedback.map((issue) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.badRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.badRed.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      issue.toUpperCase(),
                      style: GoogleFonts.outfit(
                        color: AppColors.badRed,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Sets
            if (session.sets.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              Text(
                'SETS',
                style: GoogleFonts.outfit(
                  color: AppColors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: session.sets.asMap().entries.map((entry) {
                  final i = entry.key + 1;
                  final set = entry.value;
                  final setColor =
                      set.isPR ? AppColors.accentGold : AppColors.textTertiary;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: set.isPR
                          ? AppColors.accentGold.withValues(alpha: 0.08)
                          : AppColors.glass,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: set.isPR
                            ? AppColors.accentGold.withValues(alpha: 0.2)
                            : AppColors.glassBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (set.isPR)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.stars_rounded,
                              color: AppColors.accentGold,
                              size: 11,
                            ),
                          ),
                        Text(
                          'S$i: ${set.reps} reps',
                          style: GoogleFonts.inter(
                            color: set.isPR
                                ? AppColors.accentGold
                                : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ' · ${set.rating.toStringAsFixed(1)}',
                          style: GoogleFonts.inter(
                            color: setColor.withValues(alpha: 0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
