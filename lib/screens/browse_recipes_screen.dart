import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../data/categories.dart';
import '../models/recipe.dart';
import '../services/supabase_service.dart';
import '../widgets/animated_entry.dart';
import '../widgets/category_chip.dart';
import '../widgets/recipe_card.dart';
import '../widgets/recipe_card_shimmer.dart';

class BrowseRecipesScreen extends StatefulWidget {
  const BrowseRecipesScreen({super.key});

  @override
  State<BrowseRecipesScreen> createState() => _BrowseRecipesScreenState();
}

class _BrowseRecipesScreenState extends State<BrowseRecipesScreen> {
  List<Recipe> _recipes = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _selectedCategory;
  int _offset = 0;
  bool _hasMore = true;
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  List<Recipe>? _searchResults;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadRecipes(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecipes({bool reset = false}) async {
    if (reset) {
      setState(() {
        _offset = 0;
        _hasMore = true;
        _recipes = [];
        _loading = true;
        _loadingMore = false;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final results = await SupabaseService.instance.getPlatformRecipes(
        limit: _pageSize,
        offset: _offset,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _recipes = reset ? results : [..._recipes, ...results];
        _offset += results.length;
        _hasMore = results.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onCategorySelected(String? category) {
    if (_selectedCategory == category) return;
    _searchController.clear();
    _searchResults = null;
    setState(() => _selectedCategory = category);
    _loadRecipes(reset: true);
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    await _loadRecipes();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results =
            await SupabaseService.instance.searchPlatformRecipes(query);
        if (mounted) {
          setState(() => _searchResults = results);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayRecipes = _searchResults ?? _recipes;
    final isSearching = _searchController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, 0),
              child: Text('Browse Recipes', style: AppTextStyles.titleLarge),
            ),
            const SizedBox(height: AppSpacing.md),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'Search recipes...',
                    hintStyle: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textTertiary),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Category chips (hidden during search)
            if (!isSearching)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    CategoryChip(
                      label: 'All',
                      selected: _selectedCategory == null,
                      onTap: () => _onCategorySelected(null),
                    ),
                    for (final cat in kRecipeCategories) ...[
                      const SizedBox(width: 8),
                      CategoryChip(
                        label: cat,
                        selected: _selectedCategory == cat,
                        onTap: () => _onCategorySelected(cat),
                      ),
                    ],
                  ],
                ),
              ),
            if (!isSearching) const SizedBox(height: AppSpacing.md),

            // Recipe list
            Expanded(
              child: _loading
                  ? _buildShimmer()
                  : displayRecipes.isEmpty
                      ? _buildEmpty(isSearching)
                      : _buildList(displayRecipes, isSearching),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AnimatedEntry(index: i, child: const RecipeCardShimmer()),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isSearching) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          isSearching
              ? 'No recipes found in catalog'
              : 'No recipes available yet',
          style:
              AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildList(List<Recipe> recipes, bool isSearching) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: recipes.length + (_hasMore && !isSearching ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == recipes.length) {
          // Load more button
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: GestureDetector(
                onTap: _loadingMore ? null : _loadMore,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: _loadingMore
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Load more',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.primary),
                        ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            top: index == 0 ? 0 : AppSpacing.md,
          ),
          child: RecipeCard(
            recipe: recipes[index],
            onTap: () => context.go('/recipe/${recipes[index].id}'),
          ),
        );
      },
    );
  }
}
