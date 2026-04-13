import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/recipe_step.dart';
import '../services/app_exception.dart';
import '../services/cache_service.dart';
import '../services/supabase_service.dart';
import '../widgets/animated_entry.dart';
import '../widgets/app_button.dart';

class RecipeScreen extends StatefulWidget {
  final String recipeId;

  const RecipeScreen({super.key, required this.recipeId});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  Recipe? _recipe;
  bool _isInProgress = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecipe();
  }

  Future<void> _loadRecipe() async {
    // Serve cache instantly, then refresh from network in background.
    try {
      final cached =
          await CacheService.instance.getCachedRecipe(widget.recipeId);
      if (cached != null) {
        if (mounted) {
          setState(() {
            _recipe = cached;
            _loading = false;
          });
        }
        _fetchFromNetwork();
        return;
      }
    } catch (_) {
      // Cache unavailable — fall through to network.
    }
    await _fetchFromNetwork();
  }

  Future<void> _fetchFromNetwork() async {
    try {
      final results = await Future.wait<Object?>([
        SupabaseService.instance.getRecipeById(widget.recipeId),
        SupabaseService.instance.getRecipeStatus(widget.recipeId),
      ]);

      final recipe = results[0] as Recipe?;
      final status = results[1] as String?;

      if (recipe != null) {
        await CacheService.instance.cacheRecipe(recipe);
      }

      if (mounted) {
        setState(() {
          _recipe = recipe;
          _isInProgress = status == 'in_progress';
          _loading = false;
          _error = recipe == null ? 'Recipe not found.' : null;
        });
      }
    } on AppException catch (e) {
      if (mounted && _recipe == null) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && _recipe == null) {
        setState(() {
          _error = 'Something went wrong. Try again.';
          _loading = false;
        });
      }
    }
  }

  void _launchVideo(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open YouTube')),
        );
      }
    }
  }

  void _showIngredientsSheet(Recipe recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IngredientsSheet(ingredients: recipe.ingredients),
    );
  }

  void _showPreparationSheet(Recipe recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreparationSheet(preparations: recipe.preparations),
    );
  }

  void _startCooking(Recipe recipe) {
    context.push('/recipe/${recipe.id}/cook');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _recipe == null) return _buildSkeleton();
    if (_error != null && _recipe == null) return _buildError();
    return _buildContent(_recipe!);
  }

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmer,
      highlightColor: AppColors.surface,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header image
            Container(height: 220, color: AppColors.shimmer),
            const SizedBox(height: AppSpacing.lg),
            // Chip row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: EdgeInsets.only(right: i < 3 ? AppSpacing.sm : 0),
                    child: Container(
                      height: 32,
                      width: 80,
                      decoration: BoxDecoration(
                        color: AppColors.shimmer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.shimmer,
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.shimmer,
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.shimmer,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Steps label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Container(
                height: 18,
                width: 60,
                decoration: BoxDecoration(
                  color: AppColors.shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Step card placeholders
            ...List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.shimmer,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _error!,
              style: AppTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppButton.primary('Try Again', onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _loadRecipe();
            }),
            const SizedBox(height: AppSpacing.md),
            AppButton.text('Go Back', onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Recipe recipe) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
        // ── Parallax header ──────────────────────────────────
        SliverAppBar(
          expandedHeight: 220,
          toolbarHeight: 0,
          pinned: false,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: _RecipeHeaderBackground(
              recipe: recipe,
              onBack: () => context.canPop() ? context.pop() : context.go('/home'),
              onYouTube: (recipe.videoUrl != null && recipe.videoUrl!.isNotEmpty)
                  ? () => _launchVideo(recipe.videoUrl!)
                  : null,
            ),
          ),
        ),

        // ── Info chips (stagger index 0) ─────────────────────
        SliverToBoxAdapter(
          child: AnimatedEntry(
            index: 0,
            child: _InfoChipsRow(recipe: recipe),
          ),
        ),

        // ── Action buttons (stagger index 1) ─────────────────
        SliverToBoxAdapter(
          child: AnimatedEntry(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      'Ingredients (${recipe.ingredients.length})',
                      onPressed: () => _showIngredientsSheet(recipe),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton.secondary(
                      'Preparation',
                      onPressed: () => _showPreparationSheet(recipe),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Steps label (stagger index 2) ────────────────────
        SliverToBoxAdapter(
          child: AnimatedEntry(
            index: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text('Steps', style: AppTextStyles.titleLarge),
            ),
          ),
        ),

        // ── Step cards ───────────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _StepCard(step: recipe.steps[index]),
            ),
            childCount: recipe.steps.length,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),

        // Bottom-fixed Start Cooking button
        AnimatedEntry(
          index: 1,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: AppColors.background,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: AppButton.primary(
              _isInProgress ? 'Continue Cooking' : 'Start Cooking',
              onPressed: () => _startCooking(recipe),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────

/// Used as [FlexibleSpaceBar.background] — fills whatever height the
/// [SliverAppBar] gives it, so no outer [SizedBox] needed.
class _RecipeHeaderBackground extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onBack;
  final VoidCallback? onYouTube;

  const _RecipeHeaderBackground({
    required this.recipe,
    required this.onBack,
    this.onYouTube,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          recipe.thumbnailUrl != null && recipe.thumbnailUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: recipe.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      Container(color: AppColors.surfaceVariant),
                  errorWidget: (_, _, _) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.image_not_supported_rounded,
                      color: AppColors.textTertiary,
                      size: 48,
                    ),
                  ),
                )
              : Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: AppColors.textTertiary,
                    size: 48,
                  ),
                ),

          // Gradient overlay
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1.0],
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),

          // Recipe title + creator (bottom-left)
          Positioned(
            bottom: 20,
            left: 20,
            right: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  recipe.title,
                  style: AppTextStyles.displayMedium
                      .copyWith(color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'by ${recipe.creatorName}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),

          // Back button (top-left)
          Positioned(
            top: topPad + 12,
            left: 16,
            child: _CircleIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: onBack,
            ),
          ),

          // YouTube icon button (top-right) — only shown for recipes with a video
          if (onYouTube != null)
            Positioned(
              top: topPad + 12,
              right: 16,
              child: _CircleIconButton(
                icon: Icons.play_circle_outline_rounded,
                onTap: onYouTube!,
              ),
            ),
        ],
      );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.9),
          boxShadow: AppShadows.card,
        ),
        child: Icon(icon, color: AppColors.text, size: 20),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Info chips
// ─────────────────────────────────────────────────────────────

class _InfoChipsRow extends StatelessWidget {
  final Recipe recipe;

  const _InfoChipsRow({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final chips = [
      '\u23f1 ${recipe.cookingTimeMinutes} min',
      '\ud83c\udf7d Serves ${recipe.portionSize}',
      '\ud83d\udcdd ${recipe.steps.length} steps',
      '${recipe.ingredients.length} ingredients',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            _InfoChip(label: chips[i]),
            if (i < chips.length - 1) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: AppTextStyles.bodySmall),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Step card (expandable)
// ─────────────────────────────────────────────────────────────

class _StepCard extends StatefulWidget {
  final RecipeStep step;

  const _StepCard({required this.step});

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool _expanded = false;

  String _formatTimer(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '$m min' : '$m min $s sec';
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Color _flameLevelColor(FlameLevel level) {
    switch (level) {
      case FlameLevel.low:
        return const Color(0xFF1976D2);
      case FlameLevel.medium:
        return const Color(0xFFE65100);
      case FlameLevel.high:
        return const Color(0xFFD32F2F);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Always-visible header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  // Step number circle
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: step.isPrep
                          ? AppColors.surfaceVariant
                          : AppColors.primary.withValues(alpha: 0.12),
                    ),
                    child: Center(
                      child: Text(
                        '${step.stepNumber}',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: step.isPrep
                              ? AppColors.textSecondary
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title + optional "Prep" subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.title, style: AppTextStyles.titleMedium),
                        if (step.isPrep) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Prep step',
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Expand/collapse chevron
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Animated expanded content
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1, thickness: 0.5),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Description
                              Text(
                                step.description,
                                style: AppTextStyles.bodyMedium,
                              ),

                              // Timer + flame badges
                              if (step.timerSeconds != null ||
                                  step.flameLevel != null) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  children: [
                                    if (step.timerSeconds != null)
                                      _DetailBadge(
                                        icon: Icons.timer_outlined,
                                        label: _formatTimer(step.timerSeconds!),
                                        color: AppColors.primary,
                                      ),
                                    if (step.flameLevel != null)
                                      _DetailBadge(
                                        icon: Icons.local_fire_department_rounded,
                                        label:
                                            '${_capitalise(step.flameLevel!.name)} flame',
                                        color: _flameLevelColor(step.flameLevel!),
                                      ),
                                  ],
                                ),
                              ],

                              // Per-step ingredients
                              if (step.ingredients.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'Ingredients',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...step.ingredients.map(
                                  (ing) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 7),
                                          child: Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            [
                                              ing.name,
                                              ing.quantity,
                                              if (ing.prepMethod != null)
                                                ing.prepMethod!,
                                            ].join(' · '),
                                            style: AppTextStyles.bodyMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DetailBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom sheet wrapper
// ─────────────────────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _BottomSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.bottomSheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(title, style: AppTextStyles.displayMedium),
          ),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPad + 24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Ingredients bottom sheet
// ─────────────────────────────────────────────────────────────

class _IngredientsSheet extends StatelessWidget {
  final List<Ingredient> ingredients;

  const _IngredientsSheet({required this.ingredients});

  @override
  Widget build(BuildContext context) {
    return _BottomSheet(
      title: 'Ingredients',
      child: ingredients.isEmpty
          ? Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Text(
                'No ingredients listed.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ingredients.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                thickness: 0.5,
                indent: 20,
                endIndent: 20,
              ),
              itemBuilder: (_, i) =>
                  _IngredientRow(ingredient: ingredients[i]),
            ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final Ingredient ingredient;

  const _IngredientRow({required this.ingredient});

  @override
  Widget build(BuildContext context) {
    final detail = [
      ingredient.quantity,
      if (ingredient.prepMethod != null) ingredient.prepMethod!,
    ].join(' · ');

    final aliasText = ingredient.aliases.isNotEmpty
        ? ingredient.aliases.join(' · ')
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bullet
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ingredient.name, style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (aliasText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    aliasText,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Preparation bottom sheet
// ─────────────────────────────────────────────────────────────

class _PreparationSheet extends StatelessWidget {
  final List<String> preparations;

  const _PreparationSheet({required this.preparations});

  @override
  Widget build(BuildContext context) {
    return _BottomSheet(
      title: 'Before You Start',
      child: preparations.isEmpty
          ? Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No advance preparation needed. Jump straight to cooking!',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: preparations.length,
              itemBuilder: (_, i) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Numbered circle
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.1),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        preparations[i],
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
