import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../config/theme.dart';

/// Shimmer placeholder that matches the recipe card layout exactly.
/// Use while recipes are loading.
class RecipeCardShimmer extends StatelessWidget {
  const RecipeCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmer,
      highlightColor: AppColors.surface,
      child: Container(
        height: 88,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            // Thumbnail placeholder
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.shimmer,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
            ),
            const SizedBox(width: 12),
            // Text lines
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title line (full width)
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.shimmer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Creator line (medium width)
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: AppColors.shimmer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Timer line (short width)
                  Container(
                    height: 10,
                    width: 72,
                    decoration: BoxDecoration(
                      color: AppColors.shimmer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
