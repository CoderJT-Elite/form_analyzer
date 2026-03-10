import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

class ControlIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  const ControlIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            color: color ?? (active ? AppColors.accentCyan : Colors.white24),
            size: 24,
          ),
        ),
      ),
    );
  }
}
