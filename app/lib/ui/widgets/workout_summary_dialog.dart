import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../logic/exercise_analyzer.dart';
import '../../models/exercise_model.dart';
import 'glass_container.dart';

class WorkoutSummaryDialog extends StatelessWidget {
  final WorkoutSession session;
  final VoidCallback onConfirm;

  /// Average form score (0-5) from the last session of the same exercise, so
  /// the athlete can see whether they are improving. Null when this is their
  /// first time doing it.
  final double? previousRating;

  const WorkoutSummaryDialog({
    super.key,
    required this.session,
    required this.onConfirm,
    this.previousRating,
  });

  /// Every rep across every set, in order.
  List<RepRecord> get _allReps =>
      session.sets.expand((set) => set.repRecords).toList();

  @override
  Widget build(BuildContext context) {
    final rating = session.overallRating ?? 0.0;
    final int stars = rating.round().clamp(0, 5);
    final reps = _allReps;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GlassContainer(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WORKOUT COMPLETE',
              style: GoogleFonts.outfit(
                color: AppColors.accentCyan,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              session.exerciseType.name.toUpperCase(),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return Icon(
                  index < stars
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: index < stars ? Colors.amber : Colors.white10,
                  size: 40,
                );
              }),
            ),
            if (previousRating != null) ...[
              const SizedBox(height: 8),
              _TrendLabel(current: rating, previous: previousRating!),
            ],
            const SizedBox(height: 32),
            _buildStatRow('TOTAL REPS', '${session.totalReps}'),
            if (reps.isNotEmpty) ...[
              const Divider(color: Colors.white12, height: 32),
              _sectionLabel('REP QUALITY'),
              const SizedBox(height: 12),
              _RepQualityStrip(reps: reps),
              const SizedBox(height: 12),
              _buildRepDetail(reps),
            ],
            const SizedBox(height: 16),
            if (session.overallFeedback.isNotEmpty) ...[
              const Divider(color: Colors.white12, height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'COACH\'S FEEDBACK',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: session.overallFeedback
                    .map((f) => _FeedbackChip(label: f))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _focusHint(session.overallFeedback.first),
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentCyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'DONE',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  static Widget _sectionLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }

  /// Best and worst rep, plus average tempo when it was measured.
  Widget _buildRepDetail(List<RepRecord> reps) {
    final best = reps.reduce((a, b) => b.score > a.score ? b : a);
    final worst = reps.reduce((a, b) => b.score < a.score ? b : a);

    final timed = reps.where((record) => record.eccentricMs > 0).toList();
    final averageEccentric = timed.isEmpty
        ? null
        : timed.fold<int>(0, (sum, r) => sum + r.eccentricMs) ~/ timed.length;

    final lines = <String>[
      if (best.score != worst.score)
        'Best rep #${best.index}, weakest rep #${worst.index}.'
      else
        'Every rep scored the same.',
      if (averageEccentric != null)
        'Average lowering time ${(averageEccentric / 1000).toStringAsFixed(1)}s.',
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        lines.join(' '),
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }

  /// Turn the most frequent issue into one actionable thing to work on.
  static String _focusHint(String topIssue) {
    switch (topIssue) {
      case 'Rounded Back':
      case 'Critical Back Rounding':
        return 'Focus next time: brace your core and keep your chest up '
            'through the whole rep.';
      case 'Insufficient Depth':
        return 'Focus next time: slow down and go a little lower before '
            'driving back up.';
      case 'Insufficient Range':
        return 'Focus next time: bring the weight all the way down before '
            'pressing.';
      case 'Incomplete Lockout':
      case 'No Full Lockout':
        return 'Focus next time: finish each rep fully extended before '
            'starting the next.';
      case 'Hips Sagging':
        return 'Focus next time: squeeze your glutes to keep your hips in '
            'line with your shoulders.';
      case 'Hips Piked':
        return 'Focus next time: lower your hips so your body makes one '
            'straight line.';
      default:
        return 'Focus next time: $topIssue.';
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

/// One bar per rep, coloured by how clean it was. Shows at a glance whether
/// form held up or fell apart as the set went on.
class _RepQualityStrip extends StatelessWidget {
  final List<RepRecord> reps;

  const _RepQualityStrip({required this.reps});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final record in reps)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  height: 8 + (48 * record.score.clamp(0.0, 1.0)),
                  decoration: BoxDecoration(
                    color: _colorFor(record.score),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Color _colorFor(double score) {
    if (score >= 0.9) return AppColors.goodGreen;
    if (score >= 0.7) return AppColors.accentCyan;
    if (score >= 0.5) return AppColors.warnOrange;
    return AppColors.badRed;
  }
}

/// "Up 0.4 stars from last time" — the reason to come back tomorrow.
class _TrendLabel extends StatelessWidget {
  final double current;
  final double previous;

  const _TrendLabel({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final delta = current - previous;
    final improved = delta > 0.05;
    final declined = delta < -0.05;

    final Color color = improved
        ? AppColors.goodGreen
        : declined
            ? AppColors.warnOrange
            : Colors.white38;

    final String text;
    if (improved) {
      text = '▲ ${delta.abs().toStringAsFixed(1)} vs last session';
    } else if (declined) {
      text = '▼ ${delta.abs().toStringAsFixed(1)} vs last session';
    } else {
      text = 'Same as last session';
    }

    return Text(
      text,
      style: GoogleFonts.inter(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FeedbackChip extends StatelessWidget {
  final String label;

  const _FeedbackChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
