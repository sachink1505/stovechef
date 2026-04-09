import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../models/user_profile.dart';
import '../app.dart';
import '../services/app_exception.dart';
import '../services/supabase_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';

class PersonalDetailsScreen extends StatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  State<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends State<PersonalDetailsScreen> {
  final _nameController = TextEditingController();
  String? _nameError;
  FoodPreference? _foodPreference;
  bool _loading = false;

  bool get _canSubmit =>
      _nameController.text.trim().length >= 2 && _foodPreference != null;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _nameError = 'Please enter at least 2 characters.');
      return;
    }
    if (_foodPreference == null) return;

    setState(() {
      _nameError = null;
      _loading = true;
    });

    try {
      await SupabaseService.instance.updateProfile(
        name: name,
        foodPreference: _foodPreference,
      );
      resetProfileCompleteCache();
      if (mounted) context.go('/home');
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text),
            ),
            backgroundColor: AppColors.surfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              80,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // No AppBar — user must complete this screen.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xxxl),
              Text("Almost there!", style: AppTextStyles.displayLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Tell us a bit about yourself",
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Name field
              AppTextField(
                label: 'Name',
                hint: 'Your name',
                controller: _nameController,
                errorText: _nameError,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
                prefixIcon: const Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Food preference
              Text("What do you eat?", style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _PreferenceChip(
                    label: '🥬  Vegetarian',
                    value: FoodPreference.vegetarian,
                    selected: _foodPreference == FoodPreference.vegetarian,
                    onTap: () => setState(
                        () => _foodPreference = FoodPreference.vegetarian),
                  ),
                  _PreferenceChip(
                    label: '🍗  Non-Veg',
                    value: FoodPreference.nonVegetarian,
                    selected: _foodPreference == FoodPreference.nonVegetarian,
                    onTap: () => setState(
                        () => _foodPreference = FoodPreference.nonVegetarian),
                  ),
                  _PreferenceChip(
                    label: '🍽️  Everything',
                    value: FoodPreference.everything,
                    selected: _foodPreference == FoodPreference.everything,
                    onTap: () => setState(
                        () => _foodPreference = FoodPreference.everything),
                  ),
                ],
              ),

              const Spacer(),

              // Submit button
              Opacity(
                opacity: _canSubmit ? 1.0 : 0.4,
                child: AppButton.primary(
                  "Let's Cook!",
                  onPressed: _canSubmit ? _onSubmit : null,
                  isLoading: _loading,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Preference chip with scale animation
// ─────────────────────────────────────────────────────────────

class _PreferenceChip extends StatefulWidget {
  final String label;
  final FoodPreference value;
  final bool selected;
  final VoidCallback onTap;

  const _PreferenceChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PreferenceChip> createState() => _PreferenceChipState();
}

class _PreferenceChipState extends State<_PreferenceChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(_PreferenceChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _scaleController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.primary : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: widget.selected ? AppColors.surface : AppColors.textSecondary,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
