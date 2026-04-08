import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../services/app_exception.dart';
import '../services/supabase_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';

enum _AuthState { emailEntry, otpEntry }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthState _authState = _AuthState.emailEntry;
  String _email = '';

  void _onOtpSent(String email) {
    setState(() {
      _email = email;
      _authState = _AuthState.otpEntry;
    });
  }

  void _onBackToEmail() {
    setState(() => _authState = _AuthState.emailEntry);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_authState) {
      _AuthState.emailEntry => _EmailEntryView(onOtpSent: _onOtpSent),
      _AuthState.otpEntry => _OtpEntryView(
          email: _email,
          onBack: _onBackToEmail,
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────
// STATE 1 — Email Entry
// ─────────────────────────────────────────────────────────────

class _EmailEntryView extends StatefulWidget {
  final void Function(String email) onOtpSent;

  const _EmailEntryView({required this.onOtpSent});

  @override
  State<_EmailEntryView> createState() => _EmailEntryViewState();
}

class _EmailEntryViewState extends State<_EmailEntryView> {
  final _controller = TextEditingController();
  String? _emailError;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$').hasMatch(email.trim());
  }

  Future<void> _onContinue() async {
    final email = _controller.text.trim();

    if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _emailError = null;
      _loading = true;
    });

    try {
      await SupabaseService.instance.signInWithOtp(email);
      widget.onOtpSent(email);
    } on AppException catch (e) {
      if (mounted) _showErrorSnackBar(e.message);
    } catch (_) {
      if (mounted) {
        _showErrorSnackBar('Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
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
        elevation: 4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go('/welcome'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text("What's your email?", style: AppTextStyles.displayMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "We'll send you a 4-digit code to verify",
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                label: 'Email',
                hint: 'your@email.com',
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_emailError != null) {
                    setState(() => _emailError = null);
                  }
                },
                prefixIcon: const Icon(
                  Icons.mail_outline_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton.primary(
                'Continue',
                onPressed: _onContinue,
                isLoading: _loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STATE 2 — OTP Entry
// ─────────────────────────────────────────────────────────────

class _OtpEntryView extends StatefulWidget {
  final String email;
  final VoidCallback onBack;

  const _OtpEntryView({required this.email, required this.onBack});

  @override
  State<_OtpEntryView> createState() => _OtpEntryViewState();
}

class _OtpEntryViewState extends State<_OtpEntryView>
    with SingleTickerProviderStateMixin {
  static const _otpLength = 6;

  final _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final _focusNodes = List.generate(_otpLength, (_) => FocusNode());

  String? _otpError;
  bool _loading = false;

  // Resend cooldown
  int _resendCooldown = 0;
  Timer? _resendTimer;

  // Shake animation
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 0), weight: 1),
    ]).animate(_shakeController);

    _startResendCooldown();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() => _resendCooldown = 30);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  String get _currentOtp =>
      _controllers.map((c) => c.text).join();

  void _onDigitEntered(int index, String value) {
    // Handle paste of full OTP
    if (value.length == _otpLength) {
      _distributePaste(value);
      return;
    }

    if (value.length > 1) {
      // More than one char typed — keep only last digit
      _controllers[index].text = value[value.length - 1];
      _controllers[index].selection = const TextSelection.collapsed(offset: 1);
    }

    if (_controllers[index].text.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    if (_currentOtp.length == _otpLength) {
      _submitOtp();
    }

    setState(() => _otpError = null);
  }

  void _distributePaste(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < _otpLength) return;

    for (int i = 0; i < _otpLength; i++) {
      _controllers[i].text = digits[i];
    }
    _focusNodes[_otpLength - 1].requestFocus();
    _submitOtp();
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  Future<void> _submitOtp() async {
    final otp = _currentOtp;
    if (otp.length < _otpLength) return;

    setState(() {
      _loading = true;
      _otpError = null;
    });

    try {
      await SupabaseService.instance.verifyOtp(widget.email, otp);
      if (!mounted) return;

      final complete = await SupabaseService.instance.isProfileComplete();
      if (!mounted) return;

      context.go(complete ? '/home' : '/personal-details');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _otpError = e.message);
      _shakeController.forward(from: 0);
      _clearOtp();
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _otpError = 'Wrong OTP entered. Please check the OTP again.');
      _shakeController.forward(from: 0);
      _clearOtp();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearOtp() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;
    try {
      await SupabaseService.instance.signInWithOtp(widget.email);
      _startResendCooldown();
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _otpError = e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: widget.onBack,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text('Enter the code', style: AppTextStyles.displayMedium),
              const SizedBox(height: AppSpacing.sm),
              Text.rich(
                TextSpan(
                  text: 'We sent a 4-digit code to ',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                  children: [
                    TextSpan(
                      text: widget.email,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // OTP boxes
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_shakeAnim.value, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    _otpLength,
                    (i) => _OtpBox(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      hasError: _otpError != null,
                      onChanged: (v) => _onDigitEntered(i, v),
                      onKeyEvent: (e) => _onKeyEvent(i, e),
                    ),
                  ),
                ),
              ),

              // Error text
              if (_otpError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _otpError!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // Resend
              Center(
                child: _resendCooldown > 0
                    ? Text(
                        'Resend in ${_resendCooldown}s',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textTertiary),
                      )
                    : TextButton(
                        onPressed: _loading ? null : _resendOtp,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text.rich(
                          TextSpan(
                            text: "Didn't receive it? ",
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            children: [
                              TextSpan(
                                text: 'Resend',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              // Loading indicator (full OTP submitted, awaiting verify)
              if (_loading) ...[
                const SizedBox(height: AppSpacing.xl),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Individual OTP box
// ─────────────────────────────────────────────────────────────

class _OtpBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKeyEvent;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onKeyEvent,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.hasError
        ? AppColors.error
        : _isFocused
            ? AppColors.primary
            : Colors.transparent;

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: widget.onKeyEvent,
      child: SizedBox(
        width: 64,
        height: 64,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 4, // allow 4 for paste detection
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: widget.onChanged,
          style: AppTextStyles.bodyLarge.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: widget.hasError
                  ? const BorderSide(color: AppColors.error, width: 1.5)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
