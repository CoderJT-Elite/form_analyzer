import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../widgets/glass_container.dart';
import '../widgets/set_report.dart';

/// Everything recorded about a past workout, set by set: what counted, what did
/// not and why, the per-rep bars (tap one for that rep) and what to fix.
///
/// History cards used to be dead ends showing a rating and two numbers, though
/// the per-rep detail had been saved with every set since the first release.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.session});

  final WorkoutSession session;

  static Future<void> open(BuildContext context, WorkoutSession session) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = session.exerciseType;
    final rating = session.overallRating;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          type.displayName.toUpperCase(),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            DateFormat('EEEE, MMM d, yyyy • HH:mm').format(session.date),
            style: GoogleFonts.inter(color: AppColors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (rating != null) ...[
                const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                const SizedBox(width: 6),
                Text(
                  rating.toStringAsFixed(1),
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 16),
              ],
              Text(
                type.isTimedHold ? '${session.heldSeconds}s held' : '${session.totalReps} reps',
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (session.scoringVersion < WorkoutSession.currentScoringVersion) ...[
            const SizedBox(height: 8),
            Text(
              "Recorded before reps could be turned down for form, so this set was "
              "scored more leniently than today's sets.",
              key: const Key('legacy-note'),
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < session.sets.length; i++) ...[
            _SetCard(type: type, set: session.sets[i], number: i + 1),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _SetCard extends StatelessWidget {
  const _SetCard({required this.type, required this.set, required this.number});

  final ExerciseType type;
  final ExerciseSet set;
  final int number;

  @override
  Widget build(BuildContext context) {
    final insights = set.repRecords.isEmpty ? null : SetInsights.from(type, set.repRecords);
    final counted = type.isTimedHold ? '${set.reps}s held' : '${set.reps} reps';
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SET $number',
                style: GoogleFonts.outfit(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              Text(
                set.counted == 0 ? '$counted · not analysed' : '$counted · form ${set.rating.toStringAsFixed(1)}',
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (set.wasCorrected) ...[
            const SizedBox(height: 4),
            Text(
              'Counted ${set.counted} — corrected to ${set.reps}',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
            ),
          ],
          if (insights == null || insights.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              set.counted == 0
                  ? 'Saved by hand: nothing was counted, so there is no form detail.'
                  : 'No per-rep detail was recorded for this set.',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 14),
            RepQualityStrip(type: type, attempts: set.repRecords),
            const SizedBox(height: 6),
            Text(
              'Tap a bar to see that ${type.isTimedHold ? 'second' : 'rep'}.',
              style: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
            ),
            const SizedBox(height: 14),
            SetReportText(insights: insights),
          ],
        ],
      ),
    );
  }
}
