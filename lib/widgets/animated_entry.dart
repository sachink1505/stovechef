import 'package:flutter/material.dart';

/// Wraps [child] in a combined slide-from-bottom + fade-in entrance animation.
///
/// The animation starts automatically on first build. Use [index] to stagger
/// multiple items — each index adds [80ms] to the base [delay].
///
/// ```dart
/// for (int i = 0; i < items.length; i++)
///   AnimatedEntry(index: i, child: ItemWidget(items[i])),
/// ```
class AnimatedEntry extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;

  const AnimatedEntry({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
  });

  @override
  State<AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    // 20px upward entry (Offset.dy is in fractional units of the child size,
    // but we clamp to a fixed pixel amount using a FractionalTranslation-like
    // approach via SlideTransition with a small offset fraction).
    // 0.06 ≈ ~20px for a typical 300+px card; for smaller widgets we use
    // a fixed pixel offset via Transform.translate in the builder instead.
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08), // ~20px downward start
      end: Offset.zero,
    ).animate(curved);

    _fade = Tween<double>(begin: 0, end: 1).animate(curved);

    // Total delay = base delay + stagger per index.
    final totalDelay = widget.delay + Duration(milliseconds: widget.index * 80);

    if (totalDelay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(totalDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
