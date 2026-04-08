import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/recipe_state.dart';
import '../models/recipe_step.dart';

class StepCard extends StatelessWidget {
  final RecipeStep step;
  final StepStatus status;
  final bool isExpanded;
  final VoidCallback onTap;
  final bool isCookingMode;

  const StepCard({
    super.key,
    required this.step,
    required this.status,
    required this.isExpanded,
    required this.onTap,
    this.isCookingMode = false,
  });

  bool get _isDimmed =>
      status == StepStatus.completed || status == StepStatus.skipped;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: _isDimmed
              ? AppColors.surfaceVariant.withValues(alpha: 0.5)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: _isDimmed ? null : AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: _CollapsedRow(
                    step: step,
                    status: status,
                    isExpanded: isExpanded,
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: isExpanded ? _ExpandedContent(step: step) : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Collapsed row
// ─────────────────────────────────────────────────────────────

class _CollapsedRow extends StatelessWidget {
  final RecipeStep step;
  final StepStatus status;
  final bool isExpanded;

  const _CollapsedRow({
    required this.step,
    required this.status,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepNumberCircle(stepNumber: step.stepNumber, status: status),
        const SizedBox(width: 12),
        Expanded(child: _StepTitle(title: step.title, status: status)),
        const SizedBox(width: 8),
        _StepMeta(step: step),
        const SizedBox(width: 4),
        AnimatedRotation(
          turns: isExpanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textTertiary,
            size: 20,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Step number circle
// ─────────────────────────────────────────────────────────────

class _StepNumberCircle extends StatelessWidget {
  final int stepNumber;
  final StepStatus status;

  const _StepNumberCircle({
    required this.stepNumber,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    Widget child;

    switch (status) {
      case StepStatus.active:
        bg = AppColors.primary;
        child = Text(
          '$stepNumber',
          style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
        );
        break;
      case StepStatus.completed:
        bg = AppColors.secondary;
        child = const Icon(
          Icons.check_rounded,
          color: Colors.white,
          size: 16,
        );
        break;
      case StepStatus.skipped:
        bg = AppColors.surfaceVariant;
        child = Text(
          '$stepNumber',
          style: AppTextStyles.labelLarge.copyWith(
            color: AppColors.textTertiary,
            decoration: TextDecoration.lineThrough,
          ),
        );
        break;
      case StepStatus.notStarted:
        bg = AppColors.surfaceVariant;
        child = Text(
          '$stepNumber',
          style: AppTextStyles.labelLarge.copyWith(
            color: AppColors.textSecondary,
          ),
        );
        break;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Center(child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Step title
// ─────────────────────────────────────────────────────────────

class _StepTitle extends StatelessWidget {
  final String title;
  final StepStatus status;

  const _StepTitle({required this.title, required this.status});

  @override
  Widget build(BuildContext context) {
    final TextStyle base = AppTextStyles.titleMedium;

    final TextStyle style;
    switch (status) {
      case StepStatus.completed:
        style = base.copyWith(color: AppColors.textSecondary);
        break;
      case StepStatus.skipped:
        style = base.copyWith(
          color: AppColors.textTertiary,
          decoration: TextDecoration.lineThrough,
        );
        break;
      default:
        style = base;
    }

    return Text(title, style: style);
  }
}

// ─────────────────────────────────────────────────────────────
// Right-side meta (timer, flame)
// ─────────────────────────────────────────────────────────────

class _StepMeta extends StatelessWidget {
  final RecipeStep step;

  const _StepMeta({required this.step});

  String _formatTimer(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m${s}s';
  }

  String _flameLevelLabel(FlameLevel level) {
    switch (level) {
      case FlameLevel.low:
        return 'Low';
      case FlameLevel.medium:
        return 'Med';
      case FlameLevel.high:
        return 'High';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (step.timerSeconds != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.timer_outlined,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 2),
              Text(
                _formatTimer(step.timerSeconds!),
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        if (step.timerSeconds != null && step.flameLevel != null)
          const SizedBox(height: 2),
        if (step.flameLevel != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔥', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 2),
              Text(
                _flameLevelLabel(step.flameLevel!),
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Expanded content
// ─────────────────────────────────────────────────────────────

class _ExpandedContent extends StatelessWidget {
  final RecipeStep step;

  const _ExpandedContent({required this.step});

  Color _flameLevelColor(FlameLevel level) {
    switch (level) {
      case FlameLevel.low:
        return const Color(0xFF1565C0); // blue
      case FlameLevel.medium:
        return const Color(0xFFE65100); // amber-orange
      case FlameLevel.high:
        return const Color(0xFFB71C1C); // deep red
    }
  }

  String _flameLevelLabel(FlameLevel level) {
    switch (level) {
      case FlameLevel.low:
        return 'Low';
      case FlameLevel.medium:
        return 'Medium';
      case FlameLevel.high:
        return 'High';
    }
  }

  String _timerDisplay(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Divider
        Container(height: 1, color: AppColors.border),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Description
              Text(
                step.description,
                style: AppTextStyles.bodyLarge.copyWith(height: 1.5),
              ),

              // Per-step ingredients
              if (step.ingredients.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Ingredients for this step',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: step.ingredients.map((ing) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${ing.quantity} ${ing.name}',
                        style: AppTextStyles.bodySmall,
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Cooking step: flame row + timer
              if (!step.isPrep && step.timerSeconds != null) ...[
                const SizedBox(height: 12),
                if (step.flameLevel != null)
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 18,
                        color: _flameLevelColor(step.flameLevel!),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_flameLevelLabel(step.flameLevel!)} flame',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _flameLevelColor(step.flameLevel!),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _timerDisplay(step.timerSeconds!),
                    style: AppTextStyles.displayLarge,
                  ),
                ),
              ],

              // Flame with no timer
              if (!step.isPrep &&
                  step.timerSeconds == null &&
                  step.flameLevel != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 18,
                      color: _flameLevelColor(step.flameLevel!),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_flameLevelLabel(step.flameLevel!)} flame',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _flameLevelColor(step.flameLevel!),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],

              // Prep step label
              if (step.isPrep) ...[
                const SizedBox(height: 12),
                Text(
                  '✋ Prep step — no heat needed',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
