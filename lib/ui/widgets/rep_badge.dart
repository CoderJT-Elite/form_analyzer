import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import 'glass_container.dart';

class RepBadge extends StatelessWidget {
  final int count;

  const RepBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      borderRadius: BorderRadius.circular(40),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            tween: Tween(begin: 1.0, end: 1.0), // Placeholder for animation
            builder: (context, scale, child) {
              return Text(
                count.toString(),
                style: GoogleFonts.outfit(
                  color: AppColors.accentCyan,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: AppColors.accentCyan.withAlpha(128),
                      blurRadius: 20,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Text(
            'REPS',
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
