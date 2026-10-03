import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_colors.dart';
import '../../core/app_constants.dart';
import '../../logic/exercise_analyzer.dart';
import '../../models/exercise_model.dart';
import '../../models/feedback_copy.dart';

/// What a set of reps adds up to, in sentences an athlete can act on.
///
/// Built from the per-rep records the analyzers keep. The post-set report used
/// to show one bar per rep and one line ("Best rep #1, weakest rep #11"); the
/// tempo, depth, issues and why-a-rep-did-not-count recorded for every rep were
/// never shown. This turns them into: what counted and what did not, whether
/// form held up, how fast the lowering was, and the two things to fix.
class SetInsights {
  SetInsights._({
    required this.type,
    required this.attempts,
    required this.counted,
    required this.rejected,
    required this.noReps,
    required this.fixes,
    required this.consistency,
    required this.tempo,
    required this.holdLine,
  });

  factory SetInsights.from(ExerciseType type, List<RepRecord> attempts) {
    final counted = attempts.where((r) => r.counted).toList();
    final rejected = attempts.where((r) => !r.counted).toList();

    final noReps = <String, int>{};
    for (final r in rejected) {
      final reason = r.noRepReason ?? 'Did not count';
      noReps[reason] = (noReps[reason] ?? 0) + 1;
    }

    // The two things to work on: whatever turned reps down most, then whatever
    // cost counted reps their score.
    final issueCounts = <String, int>{};
    for (final r in counted) {
      for (final issue in r.issues) {
        issueCounts[issue] = (issueCounts[issue] ?? 0) + 1;
      }
    }
    final ranked = <String>[
      ...(noReps.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key),
      ...(issueCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key),
    ];
    final fixes = <String>[];
    for (final label in ranked) {
      if (!fixes.contains(label)) fixes.add(label);
      if (fixes.length == 2) break;
    }

    return SetInsights._(
      type: type,
      attempts: attempts,
      counted: counted,
      rejected: rejected,
      noReps: noReps,
      fixes: fixes,
      consistency: type.isTimedHold ? null : _consistency(attempts),
      tempo: type.isTimedHold ? null : _tempo(counted),
      holdLine: type.isTimedHold ? _holdLine(counted, rejected) : null,
    );
  }

  final ExerciseType type;
  final List<RepRecord> attempts;
  final List<RepRecord> counted;
  final List<RepRecord> rejected;

  /// Reasons attempts were turned down, with how many times each.
  final Map<String, int> noReps;

  /// Up to two labels to work on, most important first.
  final List<String> fixes;

  /// A sentence on whether form held up across the set, or null for a set too
  /// short to say anything about.
  final String? consistency;

  /// A sentence on lowering speed, or null when it was not measured.
  final String? tempo;

  /// For holds: good-form time against time in position.
  final String? holdLine;

  bool get isEmpty => attempts.isEmpty;

  /// First half against second half. A set of fewer than six attempts is too
  /// short for the comparison to be anything but noise.
  static String? _consistency(List<RepRecord> attempts) {
    if (attempts.length < 6) return null;
    double score(RepRecord r) => r.counted ? r.score : 0;
    final mid = attempts.length ~/ 2;
    double avg(Iterable<RepRecord> rs) =>
        rs.isEmpty ? 0 : rs.fold<double>(0, (s, r) => s + score(r)) / rs.length;
    final first = avg(attempts.take(mid));
    final second = avg(attempts.skip(mid));
    final firstOut = attempts.indexWhere((r) => !r.counted);
    if (second < first - 0.15) {
      // Say where it went wrong when there is a clear first rep that did not
      // count after a good start.
      if (firstOut >= 3 && attempts.skip(firstOut).where((r) => !r.counted).length >= 2) {
        return 'Form broke down from rep ${firstOut + 1}: '
            '${(first * 100).round()}% early, ${(second * 100).round()}% late.';
      }
      return 'Form faded as the set went on: ${(first * 100).round()}% in the first '
          'half, ${(second * 100).round()}% in the second.';
    }
    if (second > first + 0.15) {
      return 'You warmed into it: ${(first * 100).round()}% early, '
          '${(second * 100).round()}% late.';
    }
    return 'Form held steady all set (about ${(((first + second) / 2) * 100).round()}%).';
  }

  static String? _tempo(List<RepRecord> counted) {
    final timed = counted.where((r) => r.eccentricMs > 0).toList();
    if (timed.length < 2) return null;
    final seconds =
        timed.fold<int>(0, (s, r) => s + r.eccentricMs) / timed.length / 1000;
    final fast = timed.where((r) => r.eccentricMs < AppConstants.minEccentricMillis).length;
    final label = seconds.toStringAsFixed(1);
    if (fast >= timed.length / 2) {
      return 'Lowering averaged ${label}s and $fast of ${timed.length} reps were dropped '
          'rather than controlled. Aim for about two seconds down.';
    }
    if (seconds >= 1.5) return 'Controlled lowering: about ${label}s a rep.';
    return 'Lowering averaged ${label}s.';
  }

  static String? _holdLine(List<RepRecord> good, List<RepRecord> paused) {
    final total = good.length + paused.length;
    if (total == 0) return null;
    if (paused.isEmpty) return 'Good form for all $total seconds.';
    return 'Good form for ${good.length} of $total seconds; the clock paused for '
        '${paused.length} while form was broken.';
  }

  /// "Best rep #3, weakest rep #7." (or null when the set is too thin to compare).
  String? get bestWorst {
    if (type.isTimedHold || counted.length < 3) return null;
    final best = counted.reduce((a, b) => b.score > a.score ? b : a);
    final worst = counted.reduce((a, b) => b.score < a.score ? b : a);
    if (best.score == worst.score) return 'Every counted rep scored the same.';
    return 'Best rep #${best.index + 1}, weakest rep #${worst.index + 1}.';
  }
}

/// One bar per attempt: height and colour by score, a grey cross for an attempt
/// that did not count. Tapping a bar opens that rep's detail.
class RepQualityStrip extends StatelessWidget {
  const RepQualityStrip({super.key, required this.type, required this.attempts});

  final ExerciseType type;
  final List<RepRecord> attempts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < attempts.length; i++)
            Expanded(
              child: GestureDetector(
                key: Key('rep-bar-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => RepDetailSheet.show(context, type: type, record: attempts[i], number: i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: attempts[i].counted
                        ? Container(
                            height: 8 + (48 * attempts[i].score.clamp(0.0, 1.0)),
                            decoration: BoxDecoration(
                              color: _colorFor(attempts[i].score),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )
                        : Container(
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: attempts.length <= 24
                                ? const Icon(Icons.close_rounded, size: 10, color: Colors.white54)
                                : null,
                          ),
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

/// A bottom sheet with everything recorded about one rep.
class RepDetailSheet extends StatelessWidget {
  const RepDetailSheet({super.key, required this.type, required this.record, required this.number});

  final ExerciseType type;
  final RepRecord record;
  final int number;

  static Future<void> show(
    BuildContext context, {
    required ExerciseType type,
    required RepRecord record,
    required int number,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => RepDetailSheet(type: type, record: record, number: number),
    );
  }

  /// The lines to show, as (label, value) pairs.
  List<(String, String)> get rows {
    final timed = type.isTimedHold;
    final unit = timed ? 'Second' : 'Rep';
    return [
      (unit, '#$number'),
      if (record.counted)
        ('Result', record.uncertain ? 'Counted (tracking was shaky)' : 'Counted')
      else
        ('Result', timed ? 'Paused: ${record.noRepReason ?? 'form broke'}' : 'Did not count: ${record.noRepReason ?? 'form'}'),
      if (record.counted) ('Form score', '${(record.score * 100).round()}%'),
      if (record.romDeficitDegrees >= 5)
        ('Range', 'about ${record.romDeficitDegrees.round()} degrees short of full'),
      if (record.counted && record.romDeficitDegrees < 5 && !timed) ('Range', 'full'),
      if (record.eccentricMs > 0) ('Lowering', '${(record.eccentricMs / 1000).toStringAsFixed(1)} s'),
      if (record.concentricMs > 0) ('Driving up', '${(record.concentricMs / 1000).toStringAsFixed(1)} s'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final issues = record.issues.where((i) => i.isNotEmpty).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.counted ? 'THIS ${type.isTimedHold ? 'SECOND' : 'REP'}' : 'DID NOT COUNT',
              style: GoogleFonts.outfit(
                color: record.counted ? Colors.white : AppColors.warnOrange,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final issue in issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TipBlock(type: type, label: issue),
                ),
            ] else if (record.counted) ...[
              const SizedBox(height: 12),
              Text('Nothing to fix on this one.',
                  style: GoogleFonts.inter(color: AppColors.goodGreen, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipBlock extends StatelessWidget {
  const _TipBlock({required this.type, required this.label});

  final ExerciseType type;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tip = FeedbackCopy.tip(type, label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(tip.why, style: GoogleFonts.inter(color: Colors.white60, fontSize: 12, height: 1.35)),
        Text('Fix: ${tip.fix}', style: GoogleFonts.inter(color: AppColors.accentCyan, fontSize: 12, height: 1.35)),
      ],
    );
  }
}

/// The written part of the report: what counted, what did not, the trend, the
/// tempo and the top fixes with their tips.
class SetReportText extends StatelessWidget {
  const SetReportText({super.key, required this.insights});

  final SetInsights insights;

  @override
  Widget build(BuildContext context) {
    final type = insights.type;
    final style = GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.5);
    final lines = <String>[
      if (insights.holdLine != null) insights.holdLine!,
      if (insights.bestWorst != null) insights.bestWorst!,
      if (insights.consistency != null) insights.consistency!,
      if (insights.tempo != null) insights.tempo!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.rejected.isNotEmpty && !type.isTimedHold) ...[
          Text(
            "DIDN'T COUNT: ${insights.rejected.length}",
            key: const Key('no-rep-heading'),
            style: GoogleFonts.inter(
              color: AppColors.warnOrange,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in insights.noReps.entries)
                _Chip(label: e.value > 1 ? '${e.key} ×${e.value}' : e.key, warn: true),
            ],
          ),
          const SizedBox(height: 12),
        ],
        for (final line in lines)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line, style: style)),
        if (insights.fixes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            "COACH'S FEEDBACK",
            key: const Key('coach-heading'),
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          for (final label in insights.fixes)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: _TipBlock(type: type, label: label)),
        ] else if (insights.counted.isNotEmpty && insights.rejected.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Clean set: nothing to fix.',
            key: const Key('clean-set'),
            style: GoogleFonts.inter(color: AppColors.goodGreen, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (warn ? AppColors.warnOrange : Colors.white).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warn ? AppColors.warnOrange.withValues(alpha: 0.5) : Colors.white12),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: warn ? AppColors.warnOrange : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
