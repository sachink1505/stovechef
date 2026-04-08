import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shimmer/shimmer.dart';

import '../config/theme.dart';
import '../models/recipe.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../widgets/animated_entry.dart';
import '../widgets/empty_state.dart';
import '../widgets/recipe_card_shimmer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Data
  UserProfile? _profile;
  List<Recipe> _recipes = [];
  int _totalRecipes = 0;
  Recipe? _activeRecipe;
  bool _loading = true;

  // URL input
  final _urlController = TextEditingController();
  String? _urlError;

  // Search
  final _searchController = TextEditingController();
  List<Recipe>? _searchResults; // null = not in search mode
  Timer? _debounceTimer;

  // Active recipe bar slide-up
  late final AnimationController _barAnimController;
  late final Animation<Offset> _barSlideAnim;

  @override
  void initState() {
    super.initState();
    _barAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _barSlideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _barAnimController, curve: Curves.easeOut));

    _loadData();
    _requestNotificationPermissionIfNeeded();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    _barAnimController.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.getProfile(),
        SupabaseService.instance.getUserRecipes(limit: 5),
        SupabaseService.instance.getUserRecipeCount(),
        SupabaseService.instance.getActiveRecipe(),
      ]);

      if (!mounted) return;
      setState(() {
        _profile = results[0] as UserProfile;
        _recipes = results[1] as List<Recipe>;
        _totalRecipes = results[2] as int;
        _activeRecipe = results[3] as Recipe?;
        _loading = false;
      });

      if (_activeRecipe != null) _barAnimController.forward();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Notification permission ───────────────────────────────

  Future<void> _requestNotificationPermissionIfNeeded() async {
    const flagKey = 'notification_permission_requested';
    final box = await Hive.openBox<dynamic>('app_flags');
    if (box.get(flagKey) == true) return;
    await box.put(flagKey, true);

    // Delay so the screen renders first
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    try {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(initSettings);

      await plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Non-critical — fail silently
    }
  }

  // ── URL validation ────────────────────────────────────────

  bool _isValidYouTubeUrl(String url) {
    return RegExp(
      r'^(https?://)?(www\.)?(youtube\.com/watch\?.*v=[\w-]+|youtu\.be/[\w-]+|youtube\.com/shorts/[\w-]+)',
    ).hasMatch(url.trim());
  }

  void _onGenerateRecipe() {
    final url = _urlController.text.trim();
    if (!_isValidYouTubeUrl(url)) {
      setState(
          () => _urlError = 'Please paste a valid YouTube video link');
      return;
    }
    setState(() => _urlError = null);
    context.go('/create-recipe?url=${Uri.encodeQueryComponent(url)}');
  }

  // ── Search ────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results =
            await SupabaseService.instance.searchUserRecipes(query);
        if (mounted) setState(() => _searchResults = results);
      } catch (_) {}
    });
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final hasBar = _activeRecipe != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              hasBar ? 96 + bottomInset : AppSpacing.xl,
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  _TopSection(
                    profile: _profile,
                    onAvatarTap: () => context.go('/profile'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _CreateRecipeCard(
                    controller: _urlController,
                    urlError: _urlError,
                    onChanged: (_) {
                      if (_urlError != null) {
                        setState(() => _urlError = null);
                      }
                    },
                    onGenerate: _onGenerateRecipe,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _MyRecipesSection(
                    recipes: _loading
                        ? const []
                        : (_searchResults ?? _recipes),
                    totalCount: _totalRecipes,
                    isLoading: _loading,
                    isSearching: _searchController.text.isNotEmpty,
                    searchController: _searchController,
                    onSearchChanged: _onSearchChanged,
                    onViewAll: () => context.go('/profile'),
                    onRecipeTap: (r) => context.go('/recipe/${r.id}'),
                  ),
                ],
              ),
            ),
          ),

          // Active recipe bar
          if (hasBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: _barSlideAnim,
                child: _ActiveRecipeBar(
                  recipe: _activeRecipe!,
                  onTap: () => context.go('/recipe/${_activeRecipe!.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Top section: greeting + avatar
// ─────────────────────────────────────────────────────────────

class _TopSection extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onAvatarTap;

  const _TopSection({required this.profile, required this.onAvatarTap});

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Row(
      children: [
        Expanded(
          child: Text(
            'Hey $name 👋',
            style: AppTextStyles.displayMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        GestureDetector(
          onTap: onAvatarTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.primary,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Create recipe card
// ─────────────────────────────────────────────────────────────

class _CreateRecipeCard extends StatelessWidget {
  final TextEditingController controller;
  final String? urlError;
  final ValueChanged<String> onChanged;
  final VoidCallback onGenerate;

  const _CreateRecipeCard({
    required this.controller,
    required this.urlError,
    required this.onChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create a Recipe', style: AppTextStyles.titleLarge),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _UrlInputField(
                      controller: controller,
                      hasError: urlError != null,
                      onChanged: onChanged,
                    ),
                    if (urlError != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        urlError!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.error),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _GenerateButton(onTap: onGenerate),
            ],
          ),
        ],
      ),
    );
  }
}

class _UrlInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String> onChanged;

  const _UrlInputField({
    required this.controller,
    required this.hasError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text),
        decoration: InputDecoration(
          hintText: 'Paste YouTube video link',
          hintStyle:
              AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
          prefixIcon: const Icon(
            Icons.content_paste_rounded,
            color: AppColors.textTertiary,
            size: 18,
          ),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: hasError
                ? const BorderSide(color: AppColors.error, width: 1.5)
                : BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: BorderSide(
              color: hasError ? AppColors.error : AppColors.primary,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GenerateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: const Icon(
          Icons.arrow_forward_rounded,
          color: AppColors.surface,
          size: 22,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// My Recipes section
// ─────────────────────────────────────────────────────────────

class _MyRecipesSection extends StatelessWidget {
  final List<Recipe> recipes;
  final int totalCount;
  final bool isLoading;
  final bool isSearching;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onViewAll;
  final ValueChanged<Recipe> onRecipeTap;

  const _MyRecipesSection({
    required this.recipes,
    required this.totalCount,
    required this.isLoading,
    required this.isSearching,
    required this.searchController,
    required this.onSearchChanged,
    required this.onViewAll,
    required this.onRecipeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text('My Recipes', style: AppTextStyles.titleLarge),
            const Spacer(),
            if (totalCount > 5)
              GestureDetector(
                onTap: onViewAll,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    'View all',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Search bar
        _SearchBar(
          controller: searchController,
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: AppSpacing.md),

        // Content
        if (isLoading)
          _buildShimmer()
        else if (recipes.isEmpty && !isSearching)
          const EmptyState(
            title: 'No recipes yet',
            subtitle:
                'Paste a YouTube cooking video link above to create your first guided recipe',
          )
        else if (recipes.isEmpty)
          _buildNoResults()
        else
          _buildList(),
      ],
    );
  }

  Widget _buildShimmer() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AnimatedEntry(index: i, child: const RecipeCardShimmer()),
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded,
                size: 36, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No recipe found. Search on YouTube\nand paste a link to create one!',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return Column(
      children: [
        for (int i = 0; i < recipes.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          AnimatedEntry(
            index: i,
            child: _RecipeCard(
              recipe: recipes[i],
              onTap: () => onRecipeTap(recipes[i]),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Search bar
// ─────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text),
        decoration: InputDecoration(
          hintText: 'Search your recipes...',
          hintStyle:
              AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textTertiary,
            size: 20,
          ),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Recipe card
// ─────────────────────────────────────────────────────────────

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onTap;

  const _RecipeCard({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 88,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: CachedNetworkImage(
                imageUrl: recipe.thumbnailUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                placeholder: (_, _) => Shimmer.fromColors(
                  baseColor: AppColors.shimmer,
                  highlightColor: AppColors.surface,
                  child: Container(
                    width: 64,
                    height: 64,
                    color: AppColors.shimmer,
                  ),
                ),
                errorWidget: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: AppColors.textTertiary,
                    size: 28,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    recipe.title,
                    style: AppTextStyles.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'by ${recipe.creatorName}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${recipe.cookingTimeMinutes} min',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────
// Active recipe bottom bar
// ─────────────────────────────────────────────────────────────

class _ActiveRecipeBar extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onTap;

  const _ActiveRecipeBar({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + bottomInset,
        ),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: Row(
          children: [
            Text(
              '🍳 Currently cooking:',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.surface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                recipe.title,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.surface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Continue →',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.surface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
