import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'app_button.dart';

class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionText;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Illustration(),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              style: AppTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                subtitle,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            if (actionText != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton.secondary(
                actionText!,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Illustration
// ─────────────────────────────────────────────────────────────

class _Illustration extends StatelessWidget {
  const _Illustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
          ),

          // Tilted recipe card (back — slightly offset)
          Positioned(
            top: 22,
            left: 22,
            child: Transform.rotate(
              angle: -8 * math.pi / 180,
              child: Container(
                width: 54,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // Main recipe card (front)
          Transform.rotate(
            angle: -5 * math.pi / 180,
            child: Container(
              width: 60,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    offset: Offset(0, 3),
                    blurRadius: 8,
                    color: Color(0x14000000),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Simulated text lines
                  _TextLine(width: double.infinity, opacity: 0.5),
                  const SizedBox(height: 5),
                  _TextLine(width: 32, opacity: 0.35),
                  const SizedBox(height: 10),
                  _TextLine(width: double.infinity, opacity: 0.25),
                  const SizedBox(height: 4),
                  _TextLine(width: double.infinity, opacity: 0.25),
                  const SizedBox(height: 4),
                  _TextLine(width: 24, opacity: 0.25),
                ],
              ),
            ),
          ),

          // YouTube-style badge at top-right
          Positioned(
            top: 18,
            right: 18,
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    offset: Offset(0, 2),
                    blurRadius: 4,
                    color: Color(0x33E85D2A),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.surface,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextLine extends StatelessWidget {
  final double width;
  final double opacity;

  const _TextLine({required this.width, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: opacity * 4),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
