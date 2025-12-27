import 'package:flutter/material.dart';

import '../app_theme.dart';

class DecorativeBackground extends StatelessWidget {
  const DecorativeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF6F1E7),
                Color(0xFFF0E7D7),
                Color(0xFFF8F3EA),
              ],
            ),
          ),
        ),
        Positioned(
          left: -120,
          top: -140,
          child: _GlowOrb(
            diameter: 320,
            colors: [
              AppColors.accentSoft.withOpacity(0.5),
              AppColors.accentSoft.withOpacity(0.05),
            ],
          ),
        ),
        Positioned(
          right: -140,
          top: 120,
          child: _GlowOrb(
            diameter: 360,
            colors: [
              AppColors.accentCool.withOpacity(0.35),
              AppColors.accentCool.withOpacity(0.05),
            ],
          ),
        ),
        Positioned(
          right: -120,
          bottom: -140,
          child: _GlowOrb(
            diameter: 340,
            colors: [
              AppColors.accent.withOpacity(0.35),
              AppColors.accent.withOpacity(0.05),
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DotGridPainter(),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.diameter, required this.colors});

  final double diameter;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.outline.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    const spacing = 26.0;
    const radius = 1.4;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x + (y % (spacing * 2)), y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
