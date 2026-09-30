import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../logic/exercise_analyzer.dart';
import '../../models/exercise_model.dart';
import 'glass_container.dart';

class WorkoutSummaryDialog extends StatefulWidget {
  final WorkoutSession session;

  /// Called with the session as the athlete leaves the dialog, including any
  /// correction they made to the rep count.
  final ValueChanged<WorkoutSession> onConfirm;

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

  @override
  State<WorkoutSummaryDialog> createState() => _WorkoutSummaryDialogState();
}

class _WorkoutSummaryDialogState extends State<WorkoutSummaryDialog> {
  late int _reps = widget.session.totalReps;

  double? get previousRating => widget.previousRating;

  /// Reps in every set but the last: the correction lands on the final set, so
  /// the total cannot go below this.
  int get _minReps {
    final sets = widget.session.sets;
    if (sets.isEmpty) return 0;
    return widget.session.totalReps - sets.last.reps;
  }

  /// The session with the athlete's correction applied.
  WorkoutSession get session {
    final base = widget.session;
    final delta = _reps - base.totalReps;
    if (delta == 0 || base.sets.isEmpty) return base;
    final sets = List<ExerciseSet>.of(base.sets);
    final last = sets.removeLast();
    sets.add(last.withCorrectedReps(math.max(0, last.reps + delta)));
    return base.copyWith(sets: sets);
  }

  /// Every rep across every set, in order.
  List<RepRecord> get _allReps =>
      widget.session.sets.expand((set) => set.repRecords).toList();

  @override
  Widget build(BuildContext context) {
    final timed = session.exerciseType.isTimedHold;
    final rating = session.overallRating;
    // A star rating comes from the counted reps. When the athlete has changed
    // the count a lot, or never had a counted rep at all, it would describe a
    // set that did not happen (five stars for a jumping-jack set of which a
    // quarter was counted).
    final showStars =
        rating != null && session.ratingTrustworthy && session.countedTotal > 0;
    final int stars = (rating ?? 0).round().clamp(0, 5);
    final reps = session.ratingTrustworthy ? _allReps : <RepRecord>[];

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
            if (showStars) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return Icon(
                    index < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: index < stars ? Colors.amber : Colors.white10,
                    size: 40,
                  );
                }),
              ),
              if (previousRating != null) ...[
                const SizedBox(height: 8),
                _TrendLabel(current: rating, previous: previousRating!),
              ],
            ] else
              Text(
                session.wasCorrectedNotably
                    ? 'No form rating this time \u2014 you changed the rep count a '
                        'lot, so a score from the counted reps would not describe '
                        'this set.'
                    : 'No form rating for this set.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
              ),
            if (showStars && !timed && session.totalReps > 0 && session.totalReps < 3) ...[
              const SizedBox(height: 8),
              Text(
                'Rated on only ${session.totalReps} '
                '${session.totalReps == 1 ? 'rep' : 'reps'} \u2014 do a few more '
                'for a rating you can trust.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 32),
            if (timed)
              _buildStatRow('TIME HELD', formatHold(session.heldSeconds))
            else
              _buildRepStepper(),
            if (reps.isNotEmpty) ...[
              const Divider(color: Colors.white12, height: 32),
              _sectionLabel(timed ? 'FORM SECOND BY SECOND' : 'REP QUALITY'),
              const SizedBox(height: 12),
              _RepQualityStrip(reps: reps),
              const SizedBox(height: 12),
              timed
                  ? _buildHoldDetail(reps)
                  : _buildRepDetail(reps, thinSet: session.totalReps < 3),
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
                onPressed: () => widget.onConfirm(session),
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

  /// m:ss for a hold, e.g. 75 -> 1:15.
  static String formatHold(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  /// How much of a hold was spent with good form, in place of the per-rep
  /// "best rep / weakest rep" wording that makes no sense for seconds.
  Widget _buildHoldDetail(List<RepRecord> reps) {
    final good = reps.where((r) => r.score >= 0.9).length;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Good form for $good of ${reps.length} seconds.',
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }

  /// Best and worst rep, plus average tempo when it was measured. Comparing
  /// reps only means something with a few of them ("Every rep scored the same"
  /// for a single rep is not a finding).
  Widget _buildRepDetail(List<RepRecord> reps, {required bool thinSet}) {
    final best = reps.reduce((a, b) => b.score > a.score ? b : a);
    final worst = reps.reduce((a, b) => b.score < a.score ? b : a);

    final timed = reps.where((record) => record.eccentricMs > 0).toList();
    final averageEccentric = timed.isEmpty
        ? null
        : timed.fold<int>(0, (sum, r) => sum + r.eccentricMs) ~/ timed.length;

    final lines = <String>[
      if (!thinSet && best.score != worst.score)
        'Best rep #${best.index}, weakest rep #${worst.index}.'
      else if (!thinSet)
        'Every rep scored the same.',
      if (averageEccentric != null)
        'Average lowering time ${(averageEccentric / 1000).toStringAsFixed(1)}s.',
    ];

    if (lines.isEmpty) return const SizedBox.shrink();
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
      case 'Excessive Forward Lean':
        return 'Focus next time: keep your chest up so your torso stays '
            'roughly parallel to your shins.';
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
      case 'Body Not Straight':
        return 'Focus next time: keep your head, hips and heels in one straight '
            'line.';
      default:
        return 'Focus next time: $topIssue.';
    }
  }

  /// Total reps with plus/minus, so a miscount can be put right. The counter's
  /// own number is kept alongside so the gap can be measured.
  Widget _buildRepStepper() {
    final counted = widget.session.countedTotal;
    final corrected = _reps != widget.session.totalReps;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TOTAL REPS',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('reps-minus'),
                  tooltip: 'One fewer rep',
                  onPressed: _reps > _minReps
                      ? () => setState(() => _reps = math.max(_minReps, _reps - 1))
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: Colors.white70,
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '$_reps',
                    textAlign: TextAlign.center,
                    key: const Key('reps-value'),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('reps-plus'),
                  tooltip: 'One more rep',
                  onPressed: _reps < 999
                      ? () => setState(() => _reps = math.min(999, _reps + 1))
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: AppColors.accentCyan,
                ),
              ],
            ),
          ],
        ),
        if (corrected)
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Counted $counted \u2014 corrected to $_reps',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
            ),
          ),
      ],
    );
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
