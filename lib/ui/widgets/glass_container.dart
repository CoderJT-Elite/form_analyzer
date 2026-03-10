import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.blur = 15,
    this.opacity = 0.15,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha((opacity * 255).toInt()),
            borderRadius: borderRadius ?? BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withAlpha(51),
              width: 1.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
