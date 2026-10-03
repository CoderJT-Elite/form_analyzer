import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';
import '../widgets/profile_avatar_button.dart';

class StatsScreen extends StatefulWidget {
  final VoidCallback? onProfileTap;

  const StatsScreen({super.key, this.onProfileTap});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  final StorageService _storage = StorageService();
  List<WorkoutSession> _sessions = [];
  bool _isLoading = true;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final sessions = await _storage.loadSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
      _animController.forward();
    }
  }

  int get _totalReps => _sessions.fold(0, (s, e) => s + e.repsForTotals);

  double get _avgRating {
    final ratings = _sessions
        .where((s) => s.overallRating != null)
        .map((s) => s.overallRating!)
        .toList();
    if (ratings.isEmpty) return 0;
    return ratings.reduce((a, b) => a + b) / ratings.length;
  }

  Map<ExerciseType, int> get _distribution {
    final map = <ExerciseType, int>{};
    for (final s in _sessions) {
      map[s.exerciseType] = (map[s.exerciseType] ?? 0) + 1;
    }
    return map;
  }

  List<WorkoutSession> get _recentRatedSessions {
    final rated = _sessions.where((s) => s.overallRating != null).toList();
    rated.sort((a, b) => a.date.compareTo(b.date));
    if (rated.length <= 7) return rated;
    return rated.sublist(rated.length - 7);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accentCyan)),
      );
    }

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
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR METRICS',
                            style: GoogleFonts.outfit(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'STATS',
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
                    ProfileAvatarButton(onTap: widget.onProfileTap),
                  ],
                ),
              ),
            ),
          ),
          if (_sessions.isEmpty)
            SliverFillRemaining(child: _buildEmpty())
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.paddingOf(context).bottom + 100,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildOverviewCards(),
                  const SizedBox(height: 32),
                  const SectionLabel(text: 'EXERCISE BREAKDOWN'),
                  const SizedBox(height: 16),
                  ..._buildDistributionList(),
                  const SizedBox(height: 32),
                  _buildTrendCard(),
                  const SizedBox(height: 24),
                  _buildFormRatingCard(),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewCards() {
    return Column(
      children: [
        const SectionLabel(text: 'OVERVIEW'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: CyanGlowCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.accentCyan,
                      size: 20,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _totalReps.toString(),
                      style: GoogleFonts.outfit(
                        color: AppColors.accentCyan,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'TOTAL REPS',
                      style: GoogleFonts.outfit(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassContainer(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: AppColors.accentMagenta,
                      size: 20,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _sessions.length.toString(),
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SESSIONS',
                      style: GoogleFonts.outfit(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildDistributionList() {
    final dist = _distribution;
    if (dist.isEmpty) return [];
    final total = _sessions.length;
    return dist.entries.map((e) {
      final frac = e.value / total;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    e.key.displayName.toUpperCase(),
                    style: GoogleFonts.outfit(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${e.value} sessions',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(frac * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.outfit(
                          color: AppColors.accentCyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...?_exerciseNote(e.key),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) => LinearProgressIndicator(
                    value: frac * _animController.value,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accentCyan,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  /// How form is going on one exercise: the latest rating, the change from the
  /// session before it (only between sessions scored the same way), and the
  /// fault that comes up most. The old trend line mixed every exercise together,
  /// so a good squat day made push-ups look better.
  List<Widget>? _exerciseNote(ExerciseType type) {
    final rated = _sessions
        .where((s) => s.exerciseType == type && s.overallRating != null)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (rated.isEmpty) return null;
    final latest = rated.last;
    final previous = rated.length > 1 ? rated[rated.length - 2] : null;
    final comparable = previous != null && previous.scoringVersion == latest.scoringVersion;

    final issueCounts = <String, int>{};
    for (final s in rated.skip(rated.length > 5 ? rated.length - 5 : 0)) {
      for (final issue in s.overallFeedback) {
        issueCounts[issue] = (issueCounts[issue] ?? 0) + 1;
      }
    }
    final topIssue = issueCounts.isEmpty
        ? null
        : (issueCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

    final parts = <String>['Form ${latest.overallRating!.toStringAsFixed(1)}'];
    if (comparable) {
      final delta = latest.overallRating! - previous.overallRating!;
      if (delta.abs() >= 0.05) {
        parts.add('${delta > 0 ? '▲' : '▼'}${delta.abs().toStringAsFixed(1)} vs last time');
      } else {
        parts.add('same as last time');
      }
    }
    if (topIssue != null) parts.add('most common fault: ${topIssue.toLowerCase()}');
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          parts.join(' · '),
          key: Key('exercise-note-${type.name}'),
          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      const SizedBox(height: 10),
    ];
  }

  Widget _buildFormRatingCard() {
    final rating = _avgRating;
    final color = rating <= 0
        ? AppColors.textTertiary
        : rating >= 4
            ? AppColors.goodGreen
            : rating >= 3
                ? AppColors.warnOrange
                : AppColors.badRed;

    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AVG FORM RATING',
                  style: GoogleFonts.outfit(
                    color: AppColors.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  rating > 0
                      ? '${rating.toStringAsFixed(1)} / 5.0'
                      : 'N/A',
                  style: GoogleFonts.outfit(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                if (rating > 0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rating / 5,
                      minHeight: 4,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Icon(
            Icons.star_rounded,
            color: color,
            size: 40,
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard() {
    final points = _recentRatedSessions;
    final hasEnoughPoints = points.length >= 2;
    final improvement = hasEnoughPoints
        ? (points.last.overallRating! - points.first.overallRating!)
        : 0.0;

    final IconData trendIcon;
    final Color trendColor;
    final String trendLabel;

    if (!hasEnoughPoints) {
      trendIcon = Icons.horizontal_rule_rounded;
      trendColor = AppColors.textSecondary;
      trendLabel = 'Need more sessions';
    } else if (improvement > 0) {
      trendIcon = Icons.trending_up_rounded;
      trendColor = AppColors.goodGreen;
      trendLabel = 'Trending up';
    } else if (improvement < 0) {
      trendIcon = Icons.trending_down_rounded;
      trendColor = AppColors.badRed;
      trendLabel = 'Trending down';
    } else {
      trendIcon = Icons.trending_flat_rounded;
      trendColor = AppColors.accentCyan;
      trendLabel = 'Maintaining form';
    }

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECENT FORM TREND',
            style: GoogleFonts.outfit(
              color: AppColors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                trendIcon,
                color: trendColor,
              ),
              const SizedBox(width: 8),
              Text(
                trendLabel,
                style: GoogleFonts.outfit(
                  color: trendColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                points.isEmpty ? 'N/A' : '${points.last.overallRating!.toStringAsFixed(1)} / 5.0',
                style: GoogleFonts.outfit(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
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
              color: AppColors.accentCyan.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentCyan.withValues(alpha: 0.1),
              ),
            ),
            child: Image.asset(
              'assets/icons/empty_stats.png',
              width: 36,
              height: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'NO DATA YET',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete a workout to see your stats.',
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
