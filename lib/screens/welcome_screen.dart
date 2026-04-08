import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../services/supabase_service.dart';
import '../widgets/app_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _checkAuthAndAnimate();
  }

  Future<void> _checkAuthAndAnimate() async {
    final user = SupabaseService.instance.getCurrentUser();

    if (!mounted) return;

    if (user != null) {
      final complete = await SupabaseService.instance.isProfileComplete();
      if (!mounted) return;
      context.go(complete ? '/home' : '/personal-details');
      return;
    }

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Stack(
            children: [
              // ── Scrollable content ──────────────────────────────
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xxxl,
                  AppSpacing.xl,
                  120, // leaves room for fixed button
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const _HeroIllustration(),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'StoveChef',
                      style: AppTextStyles.displayLarge.copyWith(fontSize: 32),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Turn any YouTube recipe into\nstep-by-step cooking guidance',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const _FeatureBullets(),
                  ],
                ),
              ),

              // ── Bottom-fixed CTA ────────────────────────────────
              Positioned(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom: AppSpacing.xxl,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: AppButton.primary(
                      'Get Started',
                      onPressed: () => context.go('/auth'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Hero illustration
// ──────────────────────────────────────────────────────────────

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Pot card
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.card + 8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Steam lines above the icon
              Positioned(
                top: 28,
                child: CustomPaint(
                  size: const Size(80, 28),
                  painter: _SteamPainter(),
                ),
              ),
              // Pot icon
              Positioned(
                bottom: 32,
                child: Icon(
                  Icons.soup_kitchen_rounded,
                  size: 72,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // YouTube → Recipe flow strip
        const _FlowStrip(),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Steam painter
// ──────────────────────────────────────────────────────────────

class _SteamPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withAlpha(80)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Three wavy steam lines
    const xOffsets = [16.0, 40.0, 64.0];
    for (final x in xOffsets) {
      final path = Path();
      path.moveTo(x, size.height);
      path.cubicTo(x - 6, size.height * 0.66, x + 6, size.height * 0.33, x, 0);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SteamPainter oldDelegate) => false;
}

// ──────────────────────────────────────────────────────────────
// YouTube → Recipe flow strip
// ──────────────────────────────────────────────────────────────

class _FlowStrip extends StatelessWidget {
  const _FlowStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FlowPill(
          icon: Icons.play_circle_fill_rounded,
          label: 'YouTube',
          iconColor: const Color(0xFFFF0000),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ),
        _FlowPill(
          icon: Icons.menu_book_rounded,
          label: 'Recipe',
          iconColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _FlowPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _FlowPill({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Feature bullets
// ──────────────────────────────────────────────────────────────

class _FeatureBullets extends StatelessWidget {
  const _FeatureBullets();

  static const _bullets = [
    (emoji: '🎬', text: 'Paste a YouTube link'),
    (emoji: '🍳', text: 'Get a guided recipe'),
    (emoji: '⏱️', text: 'Cook with timers & steps'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _bullets.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _BulletRow(emoji: _bullets[i].emoji, text: _bullets[i].text),
        ],
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  final String emoji;
  final String text;

  const _BulletRow({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text),
        ),
      ],
    );
  }
}
