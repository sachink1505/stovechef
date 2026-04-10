import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../services/connectivity_service.dart';
import '../services/recipe_creation_service.dart';
import '../services/recipe_generator_service.dart';
import '../services/supabase_service.dart';
import '../services/transcript_service.dart';
import '../widgets/app_button.dart';
import '../widgets/no_internet_screen.dart';

class CreateRecipeScreen extends StatefulWidget {
  /// Pre-filled YouTube URL passed from home screen.
  final String? youtubeUrl;

  const CreateRecipeScreen({super.key, this.youtubeUrl});

  @override
  State<CreateRecipeScreen> createState() => _CreateRecipeScreenState();
}

class _CreateRecipeScreenState extends State<CreateRecipeScreen>
    with SingleTickerProviderStateMixin {
  late final RecipeCreationService _service;
  StreamSubscription<RecipeCreationProgress>? _subscription;

  RecipeCreationProgress? _progress;
  double _displayProgress = 0;
  bool _isOffline = false;

  // Pulse animation for the stage icon
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _service = RecipeCreationService(
      transcriptService: TranscriptService.instance,
      generatorService: RecipeGeneratorService.instance,
      supabaseService: SupabaseService.instance,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-start if a URL was passed
    if (widget.youtubeUrl != null && widget.youtubeUrl!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCreation());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startCreation() async {
    setState(() {
      _isOffline = false;
      _progress = null;
      _displayProgress = 0;
    });

    final isOnline = await ConnectivityService.instance.checkConnectivity();
    if (!mounted) return;
    if (!isOnline) {
      setState(() => _isOffline = true);
      return;
    }

    final url = widget.youtubeUrl ?? '';
    final userId = SupabaseService.instance.getCurrentUser()?.id ?? '';

    _subscription = _service
        .createRecipe(url, userId)
        .listen(_onProgress, onError: (_) {
      _onProgress(RecipeCreationProgress(
        stage: RecipeCreationStage.failed,
        progress: 0,
        message: 'Something went wrong. Try again.',
        error: 'Something went wrong. Try again.',
      ));
    });
  }

  void _onProgress(RecipeCreationProgress progress) {
    if (!mounted) return;
    if (progress.progress > _displayProgress) {
      _displayProgress = progress.progress;
    }
    setState(() => _progress = progress);

    if (progress.stage == RecipeCreationStage.completed &&
        progress.recipe != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) context.go('/recipe/${progress.recipe!.id}');
      });
    }
  }

  void _onCancel() {
    _service.cancel();
    _subscription?.cancel();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: PopScope(
        canPop: progress == null || progress.isTerminal,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: _buildBody(progress),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(RecipeCreationProgress? progress) {
    if (_isOffline) {
      return NoInternetScreen(onRetry: () => _startCreation());
    }

    if (progress == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (progress.stage == RecipeCreationStage.failed) {
      return _FailedView(
        error: progress.error ?? progress.message,
        onTryAgain: () => context.go('/home'),
        onGoBack: () => context.go('/home'),
      );
    }

    return _CreatingView(
      progress: progress,
      displayProgress: _displayProgress,
      pulseAnim: _pulseAnim,
      onCancel: _onCancel,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Creating view
// ─────────────────────────────────────────────────────────────

class _CreatingView extends StatelessWidget {
  final RecipeCreationProgress progress;
  final double displayProgress;
  final Animation<double> pulseAnim;
  final VoidCallback onCancel;

  const _CreatingView({
    required this.progress,
    required this.displayProgress,
    required this.pulseAnim,
    required this.onCancel,
  });

  IconData _iconForStage(RecipeCreationStage stage) {
    switch (stage) {
      case RecipeCreationStage.validating:
      case RecipeCreationStage.checkingExisting:
        return Icons.link_rounded;
      case RecipeCreationStage.extractingTranscript:
        return Icons.play_circle_outline_rounded;
      case RecipeCreationStage.generatingRecipe:
        return Icons.auto_awesome_rounded;
      case RecipeCreationStage.saving:
      case RecipeCreationStage.completed:
        return Icons.save_outlined;
      case RecipeCreationStage.failed:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (displayProgress * 100).round();
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pulsing stage icon
          ScaleTransition(
            scale: pulseAnim,
            child: SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  // Inner ring
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  // Icon
                  Icon(
                    _iconForStage(progress.stage),
                    color: AppColors.primary,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Stage message
          Text(
            progress.message,
            style: AppTextStyles.titleLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.xl),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              width: screenWidth - 80,
              height: 6,
              child: Stack(
                children: [
                  // Background
                  Container(color: AppColors.surfaceVariant),
                  // Fill
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    width: (screenWidth - 80) * displayProgress,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          Text(
            '$percent%',
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),

          const SizedBox(height: AppSpacing.xxl),

          AppButton.text(
            'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Failed view
// ─────────────────────────────────────────────────────────────

class _FailedView extends StatefulWidget {
  final String error;
  final VoidCallback onTryAgain;
  final VoidCallback onGoBack;

  const _FailedView({
    required this.error,
    required this.onTryAgain,
    required this.onGoBack,
  });

  @override
  State<_FailedView> createState() => _FailedViewState();
}

class _FailedViewState extends State<_FailedView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.error.withValues(alpha: 0.1),
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.error.withValues(alpha: 0.2),
                    ),
                  ),
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          Text(
            widget.error,
            style: AppTextStyles.titleLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.xl),

          AppButton.primary('Try Again', onPressed: widget.onTryAgain),

          const SizedBox(height: AppSpacing.md),

          AppButton.text('Go Back', onPressed: widget.onGoBack),
        ],
      ),
    );
  }
}
