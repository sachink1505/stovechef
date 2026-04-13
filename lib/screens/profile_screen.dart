import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../config/theme.dart';
import '../models/recipe.dart';
import '../models/user_profile.dart';
import '../services/cache_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  List<Recipe> _recipes = [];
  int _totalRecipes = 0;
  bool _loading = true;
  bool _loadingMore = false;

  static const _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.getProfile(),
        SupabaseService.instance.getUserRecipes(limit: _pageSize),
        SupabaseService.instance.getUserRecipeCount(),
      ]);

      if (!mounted) return;
      setState(() {
        _profile = results[0] as UserProfile;
        _recipes = results[1] as List<Recipe>;
        _totalRecipes = results[2] as int;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _recipes.length >= _totalRecipes) return;
    setState(() => _loadingMore = true);
    try {
      final more = await SupabaseService.instance.getUserRecipes(
        limit: _pageSize,
        offset: _recipes.length,
      );
      if (!mounted) return;
      setState(() {
        _recipes.addAll(more);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _onLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => ctx.pop(true),
            child: Text(
              'Log out',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await SupabaseService.instance.signOut();
      await CacheService.instance.clearAll();
      if (mounted) context.go('/welcome');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not log out. Please try again.')),
        );
      }
    }
  }

  void _showAddPhoneSheet() {
    final controller = TextEditingController(text: _profile?.phone ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _profile?.phone != null ? 'Edit Phone Number' : 'Add Phone Number',
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter your phone number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              'Save',
              onPressed: () async {
                final phone = controller.text.trim();
                if (phone.isEmpty) return;
                try {
                  await SupabaseService.instance.updateProfile(phone: phone);
                  if (mounted) {
                    setState(() {
                      _profile = _profile?.copyWith(phone: phone);
                    });
                  }
                  if (ctx.mounted) ctx.pop();
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Could not save phone number.'),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App bar row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                            child: const Icon(
                              Icons.arrow_back_ios,
                              size: 20,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text('Profile', style: AppTextStyles.displayMedium),
                        ],
                      ),
                    ),

                    // Avatar & info
                    _AvatarSection(
                      profile: _profile,
                      onEditAvatar: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coming soon!')),
                        );
                      },
                    ),

                    // Phone section
                    _PhoneSection(
                      phone: _profile?.phone,
                      onTap: _showAddPhoneSheet,
                    ),

                    // My Creations
                    _MyCreationsSection(
                      recipes: _recipes,
                      totalCount: _totalRecipes,
                      loadingMore: _loadingMore,
                      onLoadMore: _loadMore,
                      onRecipeTap: (r) => context.push('/recipe/${r.id}'),
                    ),

                    // Bottom section
                    _BottomSection(onLogout: _onLogout),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Avatar & Info
// ─────────────────────────────────────────────────────────────

class _AvatarSection extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onEditAvatar;

  const _AvatarSection({required this.profile, required this.onEditAvatar});

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Column(
          children: [
            // Avatar with edit icon
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                children: [
                  // Avatar circle
                  if (profile?.avatarUrl != null)
                    ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: profile!.avatarUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 80,
                          height: 80,
                          color: AppColors.surfaceVariant,
                        ),
                        errorWidget: (_, _, _) => _InitialAvatar(initial: initial),
                      ),
                    )
                  else
                    _InitialAvatar(initial: initial),

                  // Edit icon
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: onEditAvatar,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 14,
                          color: AppColors.surface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              name,
              style: AppTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              profile?.email ?? '',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String initial;

  const _InitialAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.displayMedium.copyWith(
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Phone Section
// ─────────────────────────────────────────────────────────────

class _PhoneSection extends StatelessWidget {
  final String? phone;
  final VoidCallback onTap;

  const _PhoneSection({required this.phone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Icon(
                Icons.phone_outlined,
                size: 20,
                color: phone != null ? AppColors.text : AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  phone ?? 'Add phone number',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: phone != null ? AppColors.text : AppColors.primary,
                  ),
                ),
              ),
              Icon(
                phone != null ? Icons.edit : Icons.add,
                size: 20,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// My Creations
// ─────────────────────────────────────────────────────────────

class _MyCreationsSection extends StatelessWidget {
  final List<Recipe> recipes;
  final int totalCount;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final ValueChanged<Recipe> onRecipeTap;

  const _MyCreationsSection({
    required this.recipes,
    required this.totalCount,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onRecipeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('My Creations', style: AppTextStyles.titleLarge),
              const Spacer(),
              Text(
                '$totalCount recipe${totalCount == 1 ? '' : 's'}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Recipe list
          if (recipes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(
                child: Text(
                  'No recipes yet',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < recipes.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  _RecipeCard(
                    recipe: recipes[i],
                    onTap: () => onRecipeTap(recipes[i]),
                  ),
                ],
                // Load more button
                if (recipes.length < totalCount) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: loadingMore
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : AppButton.text(
                            'Load more',
                            onPressed: onLoadMore,
                          ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

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
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: recipe.thumbnailUrl != null && recipe.thumbnailUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: recipe.thumbnailUrl!,
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
                    )
                  : Container(
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
            const SizedBox(width: 12),
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
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
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
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
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
// Bottom Section
// ─────────────────────────────────────────────────────────────

class _BottomSection extends StatelessWidget {
  final VoidCallback onLogout;

  const _BottomSection({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        children: [
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          // Log out
          GestureDetector(
            onTap: onLogout,
            child: Row(
              children: [
                const Icon(Icons.logout, size: 20, color: AppColors.error),
                const SizedBox(width: AppSpacing.md),
                Text(
                  'Log out',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // App version
          Center(
            child: Text(
              'StoveChef v1.0.0',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
