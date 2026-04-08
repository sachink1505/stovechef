import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'app_button.dart';

class NoInternetScreen extends StatelessWidget {
  final VoidCallback? onRetry;

  const NoInternetScreen({super.key, this.onRetry});

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
                const _CloudOffIllustration(),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'No Connection',
                  style: AppTextStyles.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Check your internet and try again',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton.primary('Try Again', onPressed: onRetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Custom cloud-off illustration: cloud icon + diagonal slash
// ─────────────────────────────────────────────────────────────

class _CloudOffIllustration extends StatelessWidget {
  const _CloudOffIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Cloud icon
          Icon(
            Icons.cloud_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          // Diagonal slash
          Transform.rotate(
            angle: -0.7854, // -45°
            child: Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
