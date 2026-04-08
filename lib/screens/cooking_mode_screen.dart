import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/theme.dart';
import '../models/recipe.dart';
import '../models/recipe_state.dart';
import '../models/recipe_step.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_button.dart';

// ─────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────

class CookingModeScreen extends StatefulWidget {
  final String recipeId;

  const CookingModeScreen({super.key, required this.recipeId});

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends State<CookingModeScreen>
    with WidgetsBindingObserver {
  // ── Data ──────────────────────────────────────────────────
  Recipe? _recipe;
  RecipeState _state = RecipeState(recipeId: '');
  bool _loading = true;

  // ── Timer ─────────────────────────────────────────────────
  Timer? _tickTimer;
  int _secondsRemaining = 0;
  bool _timerRunning = false;
  bool _timerDone = false;
  DateTime? _timerEndTime; // persisted for background resume

  // ── Audio ─────────────────────────────────────────────────
  final _audio = AudioPlayer();

  // ─────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _tickTimer?.cancel();
    _audio.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused) {
      _onBackground();
    } else if (lifecycle == AppLifecycleState.resumed) {
      _onForeground();
    }
  }

  void _onBackground() {
    if (!_timerRunning || _timerDone || _timerEndTime == null) return;
    // Schedule a local notification for when the timer ends.
    final step = _currentStep;
    if (step != null) {
      final delay = _timerEndTime!.difference(DateTime.now());
      if (delay > Duration.zero) {
        NotificationService.instance
            .scheduleTimerNotification(step.title, delay);
      }
    }
  }

  void _onForeground() async {
    await NotificationService.instance.cancelAll();
    if (!_timerRunning || _timerDone || _timerEndTime == null) return;

    final remaining = _timerEndTime!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _handleTimerDone();
    } else {
      setState(() => _secondsRemaining = remaining);
    }
  }

  // ─────────────────────────────────────────────────────────
  // Init
  // ─────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      // Load recipe from cache, fall back to Supabase.
      _recipe = await CacheService.instance.getCachedRecipe(widget.recipeId);
      if (_recipe == null) {
        final fetched =
            await SupabaseService.instance.getRecipeById(widget.recipeId);
        if (fetched != null) {
          await CacheService.instance.cacheRecipe(fetched);
          _recipe = fetched;
        }
      }

      // Load or create cooking state.
      var savedState =
          await CacheService.instance.getRecipeState(widget.recipeId);
      // Discard a stale completed state so a new session starts fresh.
      if (savedState?.overallStatus == CookingStatus.completed) {
        await CacheService.instance.clearRecipeState(widget.recipeId);
        savedState = null;
      }
      if (savedState != null) {
        _state = savedState;
      } else {
        // Fresh session — end any previous in-progress recipe first.
        await SupabaseService.instance.completeAllActiveRecipes();
        await SupabaseService.instance.updateRecipeState(
          widget.recipeId,
          status: 'in_progress',
          currentStepIndex: 0,
          startedAt: DateTime.now(),
        );
        _state = RecipeState(
          recipeId: widget.recipeId,
          overallStatus: CookingStatus.inProgress,
          currentStepIndex: 0,
          startedAt: DateTime.now(),
        );
        await _saveStateToDisk();
      }

      // Restore timer end time if persisted.
      final storedEnd = await CacheService.instance
          .getPreference('${widget.recipeId}_timer_end') as String?;
      if (storedEnd != null) {
        _timerEndTime = DateTime.tryParse(storedEnd);
      }

      if (mounted) {
        setState(() => _loading = false);
        _maybeStartTimerForCurrentStep();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveStateToDisk() async {
    await CacheService.instance.saveRecipeState(_state);
  }

  // ─────────────────────────────────────────────────────────
  // Step helpers
  // ─────────────────────────────────────────────────────────

  int get _currentIndex => _state.currentStepIndex;
  List<RecipeStep> get _steps => _recipe?.steps ?? [];
  RecipeStep? get _currentStep =>
      _steps.isNotEmpty && _currentIndex < _steps.length
          ? _steps[_currentIndex]
          : null;
  bool get _isLastStep => _currentIndex == _steps.length - 1;

  StepStatus _statusFor(int index) {
    return _state.stepStates[index] ?? StepStatus.notStarted;
  }

  // ─────────────────────────────────────────────────────────
  // Timer
  // ─────────────────────────────────────────────────────────

  void _maybeStartTimerForCurrentStep() {
    _tickTimer?.cancel();
    setState(() {
      _timerRunning = false;
      _timerDone = false;
      _secondsRemaining = 0;
      _timerEndTime = null;
    });

    final step = _currentStep;
    if (step == null || step.timerSeconds == null) return;

    final end = DateTime.now().add(Duration(seconds: step.timerSeconds!));
    _timerEndTime = end;
    _persistTimerEnd(end);

    setState(() {
      _secondsRemaining = step.timerSeconds!;
      _timerRunning = true;
    });

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _timerEndTime!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        _handleTimerDone();
      } else {
        setState(() => _secondsRemaining = remaining);
      }
    });
  }

  Future<void> _persistTimerEnd(DateTime end) async {
    await CacheService.instance.setPreference(
      '${widget.recipeId}_timer_end',
      end.toIso8601String(),
    );
  }

  Future<void> _clearPersistedTimer() async {
    await CacheService.instance
        .setPreference('${widget.recipeId}_timer_end', null);
    _timerEndTime = null;
  }

  void _handleTimerDone() {
    _tickTimer?.cancel();
    HapticFeedback.heavyImpact();
    _audio.play(AssetSource('audio/timer_complete.mp3'));
    NotificationService.instance.showTimerCompleteNotification(_currentStep?.title ?? '');
    _clearPersistedTimer();
    if (mounted) {
      setState(() {
        _timerRunning = false;
        _timerDone = true;
        _secondsRemaining = 0;
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────

  Future<void> _advanceToStep(int index, {StepStatus currentStatus = StepStatus.completed}) async {
    final updated = Map<int, StepStatus>.from(_state.stepStates)
      ..[_currentIndex] = currentStatus;

    _state = _state.copyWith(
      currentStepIndex: index,
      stepStates: updated,
    );
    await _saveStateToDisk();
    await SupabaseService.instance.updateRecipeState(
      widget.recipeId,
      currentStepIndex: index,
    );
    if (mounted) setState(() {});
    _maybeStartTimerForCurrentStep();
  }

  void _onNext() {
    if (_isLastStep) {
      _onFinish();
    } else {
      _advanceToStep(_currentIndex + 1);
    }
  }

  void _onSkip() {
    if (_isLastStep) {
      _onFinish();
    } else {
      _advanceToStep(_currentIndex + 1, currentStatus: StepStatus.skipped);
    }
  }

  void _onBack() {
    if (_currentIndex == 0) return;
    _tickTimer?.cancel();
    setState(() {
      _timerRunning = false;
      _timerDone = false;
    });
    _advanceToStep(_currentIndex - 1, currentStatus: _statusFor(_currentIndex));
  }

  Future<void> _onFinish() async {
    _tickTimer?.cancel();
    final now = DateTime.now();
    final updated = Map<int, StepStatus>.from(_state.stepStates)
      ..[_currentIndex] = StepStatus.completed;

    _state = _state.copyWith(
      overallStatus: CookingStatus.completed,
      stepStates: updated,
      completedAt: now,
    );
    await _saveStateToDisk();
    await SupabaseService.instance.updateRecipeState(
      widget.recipeId,
      status: 'completed',
      completedAt: now,
    );
    if (mounted) _showCompletionDialog();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CompletionDialog(
        recipeName: _recipe?.title ?? 'Recipe',
        onHome: () => context.go('/home'),
      ),
    );
  }

  Future<void> _onExitConfirmed() async {
    _tickTimer?.cancel();
    _state = _state.copyWith(overallStatus: CookingStatus.paused);
    await _saveStateToDisk();
    await SupabaseService.instance.updateRecipeState(
      widget.recipeId,
      status: 'in_progress', // keep as in_progress so it shows in active bar
    );
    if (mounted) context.go('/home');
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text('Exit Cooking?', style: AppTextStyles.titleLarge),
        content: Text(
          'Your progress is saved. You can continue later from where you left off.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Keep Cooking',
              style:
                  AppTextStyles.labelLarge.copyWith(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _onExitConfirmed();
            },
            child: Text(
              'Exit',
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _recipe == null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Could not load recipe.', style: AppTextStyles.titleLarge),
              const SizedBox(height: AppSpacing.xl),
              AppButton.primary('Go Back', onPressed: () => context.pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final step = _currentStep;
    if (step == null) return _buildError();

    return Column(
      children: [
        _TopBar(
          title: _recipe!.title,
          onExit: _confirmExit,
        ),
        _StepCounter(
          current: _currentIndex + 1,
          total: _steps.length,
        ),
        Expanded(
          child: _StepContent(
            step: step,
            secondsRemaining: _secondsRemaining,
            timerDone: _timerDone,
            timerRunning: _timerRunning,
          ),
        ),
        _BottomActions(
          step: step,
          isFirst: _currentIndex == 0,
          isLast: _isLastStep,
          timerDone: _timerDone,
          onNext: _onNext,
          onSkip: _onSkip,
          onBack: _onBack,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onExit;

  const _TopBar({required this.title, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: title,
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            GestureDetector(
              onTap: onExit,
              child: Text(
                '✕ Exit',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Step counter + progress bar
// ─────────────────────────────────────────────────────────────

class _StepCounter extends StatelessWidget {
  final int current;
  final int total;

  const _StepCounter({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : current / total;
    return Column(
      children: [
        Text(
          'Step $current of $total',
          style:
              AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.surfaceVariant,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Main step content
// ─────────────────────────────────────────────────────────────

class _StepContent extends StatelessWidget {
  final RecipeStep step;
  final int secondsRemaining;
  final bool timerDone;
  final bool timerRunning;

  const _StepContent({
    required this.step,
    required this.secondsRemaining,
    required this.timerDone,
    required this.timerRunning,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Step title
          Text(
            step.title,
            style: AppTextStyles.displayLarge,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Description
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                step.description,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Cooking step: flame badge + timer
          if (!step.isPrep && step.timerSeconds != null) ...[
            if (step.flameLevel != null)
              _FlameBadge(level: step.flameLevel!),
            const SizedBox(height: AppSpacing.lg),
            _CircularTimer(
              totalSeconds: step.timerSeconds!,
              remainingSeconds: secondsRemaining,
              isDone: timerDone,
            ),
          ],

          // Prep step indicator
          if (step.isPrep) _PrepIndicator(),

          // Ingredient pills
          if (step.ingredients.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: step.ingredients.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (_, i) {
                  final ing = step.ingredients[i];
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
                },
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Flame badge
// ─────────────────────────────────────────────────────────────

class _FlameBadge extends StatelessWidget {
  final FlameLevel level;

  const _FlameBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final String label;

    switch (level) {
      case FlameLevel.low:
        bg = const Color(0xFF1565C0);
        label = '🔥 Low flame';
        break;
      case FlameLevel.medium:
        bg = const Color(0xFFE65100);
        label = '🔥🔥 Medium flame';
        break;
      case FlameLevel.high:
        bg = const Color(0xFFB71C1C);
        label = '🔥🔥🔥 High flame';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            AppTextStyles.bodyMedium.copyWith(color: Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Circular timer
// ─────────────────────────────────────────────────────────────

class _CircularTimer extends StatelessWidget {
  final int totalSeconds;
  final int remainingSeconds;
  final bool isDone;

  const _CircularTimer({
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.isDone,
  });

  String _format(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds == 0
        ? 1.0
        : (totalSeconds - remainingSeconds) / totalSeconds;
    final trackColor = AppColors.surfaceVariant;
    final fillColor = isDone ? AppColors.secondary : AppColors.primary;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Track
          SizedBox(
            width: 160,
            height: 160,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 6,
              valueColor: AlwaysStoppedAnimation<Color>(trackColor),
            ),
          ),
          // Progress
          SizedBox(
            width: 160,
            height: 160,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 6,
              valueColor: AlwaysStoppedAnimation<Color>(fillColor),
            ),
          ),
          // Center text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isDone ? '00:00' : _format(remainingSeconds),
                style: AppTextStyles.displayLarge.copyWith(fontSize: 36),
              ),
              const SizedBox(height: 2),
              Text(
                isDone ? "Time's up!" : 'remaining',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Prep indicator
// ─────────────────────────────────────────────────────────────

class _PrepIndicator extends StatelessWidget {
  const _PrepIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.border,
          style: BorderStyle.solid,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        '✋ No heat needed for this step',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom actions
// ─────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final RecipeStep step;
  final bool isFirst;
  final bool isLast;
  final bool timerDone;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  const _BottomActions({
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.timerDone,
    required this.onNext,
    required this.onSkip,
    required this.onBack,
  });

  String get _centerLabel {
    if (isLast) return 'Finish Recipe 🎉';
    if (step.isPrep) return 'Done ✓';
    if (timerDone) return 'Next Step →';
    return 'Done Early';
  }

  bool get _centerIsPrimary => step.isPrep || timerDone || isLast;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Row(
          children: [
            // Skip
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: onSkip,
                child: Text(
                  'Skip',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Center button
            Expanded(
              child: SizedBox(
                height: 56,
                child: _centerIsPrimary
                    ? ElevatedButton(
                        onPressed: onNext,
                        child: Text(
                          _centerLabel,
                          style: AppTextStyles.labelLarge
                              .copyWith(color: Colors.white),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: onNext,
                        child: Text(
                          _centerLabel,
                          style: AppTextStyles.labelLarge
                              .copyWith(color: AppColors.primary),
                        ),
                      ),
              ),
            ),

            const SizedBox(width: AppSpacing.md),

            // Back
            SizedBox(
              height: 48,
              child: isFirst
                  ? const SizedBox(width: 64) // spacer
                  : TextButton(
                      onPressed: onBack,
                      child: Text(
                        '← Back',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Completion dialog
// ─────────────────────────────────────────────────────────────

class _CompletionDialog extends StatelessWidget {
  final String recipeName;
  final VoidCallback onHome;

  const _CompletionDialog({
    required this.recipeName,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 56)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Recipe Complete!',
              style: AppTextStyles.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "You've finished cooking $recipeName",
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppButton.primary('Back to Home', onPressed: onHome),
          ],
        ),
      ),
    );
  }
}
