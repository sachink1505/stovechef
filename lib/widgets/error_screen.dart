import 'dart:math';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'app_button.dart';

class ErrorScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;
  final VoidCallback? onGoBack;

  const ErrorScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.onRetry,
    this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _WarningTriangle(),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  title,
                  style: AppTextStyles.displayMedium,
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  AppButton.primary('Try Again', onPressed: onRetry),
                ],
                if (onGoBack != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton.text('Go Back', onPressed: onGoBack),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Rounded warning triangle illustration
// ─────────────────────────────────────────────────────────────

class _WarningTriangle extends StatelessWidget {
  const _WarningTriangle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: CustomPaint(
        painter: _RoundedTrianglePainter(
          color: AppColors.error.withValues(alpha: 0.1),
        ),
        child: const Center(
          child: Padding(
            // Shift icon slightly down to optically center inside triangle
            padding: EdgeInsets.only(top: 10),
            child: Icon(
              Icons.priority_high_rounded,
              color: AppColors.error,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundedTrianglePainter extends CustomPainter {
  final Color color;
  const _RoundedTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(_buildPath(size), paint);
  }

  Path _buildPath(Size size) {
    final w = size.width;
    final h = size.height;
    const r = 10.0; // corner radius

    // Vertices (inset slightly so corners don't clip)
    final top = Offset(w / 2, 2.0);
    final bottomRight = Offset(w - 2.0, h - 2.0);
    final bottomLeft = Offset(2.0, h - 2.0);

    // Helper: normalized direction from a → b
    Offset dir(Offset a, Offset b) {
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = sqrt(dx * dx + dy * dy);
      return Offset(dx / len, dy / len);
    }

    final dTopRight = dir(top, bottomRight);
    final dRightTop = dir(bottomRight, top);
    final dRightLeft = dir(bottomRight, bottomLeft);
    final dLeftRight = dir(bottomLeft, bottomRight);
    final dLeftTop = dir(bottomLeft, top);
    final dTopLeft = dir(top, bottomLeft);

    final path = Path()
      // Start: tangent point approaching top vertex from left side
      ..moveTo(top.dx + dTopLeft.dx * r, top.dy + dTopLeft.dy * r)
      // Arc at top vertex
      ..arcToPoint(
        Offset(top.dx + dTopRight.dx * r, top.dy + dTopRight.dy * r),
        radius: const Radius.circular(r),
        clockwise: false,
      )
      // Line to tangent point approaching bottom-right from above
      ..lineTo(
        bottomRight.dx + dRightTop.dx * r,
        bottomRight.dy + dRightTop.dy * r,
      )
      // Arc at bottom-right vertex
      ..arcToPoint(
        Offset(
          bottomRight.dx + dRightLeft.dx * r,
          bottomRight.dy + dRightLeft.dy * r,
        ),
        radius: const Radius.circular(r),
        clockwise: false,
      )
      // Line to tangent point approaching bottom-left from right
      ..lineTo(
        bottomLeft.dx + dLeftRight.dx * r,
        bottomLeft.dy + dLeftRight.dy * r,
      )
      // Arc at bottom-left vertex
      ..arcToPoint(
        Offset(
          bottomLeft.dx + dLeftTop.dx * r,
          bottomLeft.dy + dLeftTop.dy * r,
        ),
        radius: const Radius.circular(r),
        clockwise: false,
      )
      ..close();

    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
