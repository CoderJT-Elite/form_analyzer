import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../logic/exercise_analyzer.dart';
import '../../models/exercise_model.dart';
import 'glass_container.dart';
import 'set_report.dart';

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
    final insights =
        reps.isEmpty ? null : SetInsights.from(session.exerciseType, reps);

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
              session.exerciseType.displayName.toUpperCase(),
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
            if (timed) ...[
              _buildStatRow('TIME HELD', formatHold(session.heldSeconds)),
              if (insights != null && insights.rejected.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'of ${formatHold(session.heldSeconds + insights.rejected.length)} in position',
                    key: const Key('in-position'),
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                  ),
                ),
            ] else
              _buildRepStepper(),
            if (insights != null && !insights.isEmpty) ...[
              const Divider(color: Colors.white12, height: 32),
              _sectionLabel(timed ? 'FORM SECOND BY SECOND' : 'REP QUALITY'),
              const SizedBox(height: 12),
              RepQualityStrip(type: session.exerciseType, attempts: reps),
              const SizedBox(height: 6),
              Text(
                'Tap a bar to see that ${timed ? 'second' : 'rep'}.',
                style: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
              ),
              const SizedBox(height: 16),
              SetReportText(insights: insights),
            ],
            const SizedBox(height: 16),
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
