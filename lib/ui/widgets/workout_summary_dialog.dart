import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import 'glass_container.dart';

class WorkoutSummaryDialog extends StatelessWidget {
  final WorkoutSession session;
  final VoidCallback onConfirm;

  const WorkoutSummaryDialog({
    super.key,
    required this.session,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final rating = session.overallRating ?? 0.0;
    final int stars = (rating * 5).round().clamp(1, 5);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GlassContainer(
        padding: const EdgeInsets.all(32),
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
            const SizedBox(height: 32),
            _buildStatRow('TOTAL REPS', '${session.totalReps}'),
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
