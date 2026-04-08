import 'package:flutter/material.dart';
import '../config/theme.dart';

enum _ButtonVariant { primary, secondary, text }

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final _ButtonVariant _variant;

  const AppButton.primary(
    this.text, {
    super.key,
    required this.onPressed,
    this.isLoading = false,
  }) : _variant = _ButtonVariant.primary;

  const AppButton.secondary(
    this.text, {
    super.key,
    required this.onPressed,
    this.isLoading = false,
  }) : _variant = _ButtonVariant.secondary;

  const AppButton.text(
    this.text, {
    super.key,
    required this.onPressed,
    this.isLoading = false,
  }) : _variant = _ButtonVariant.text;

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case _ButtonVariant.primary:
        return _PrimaryButton(
          text: text,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
        );
      case _ButtonVariant.secondary:
        return _SecondaryButton(
          text: text,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
        );
      case _ButtonVariant.text:
        return _TextButton(
          text: text,
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
        );
    }
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _PrimaryButton({
    required this.text,
    required this.onPressed,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppColors.surface,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.surface,
                ),
              ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _SecondaryButton({
    required this.text,
    required this.onPressed,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _TextButton({
    required this.text,
    required this.onPressed,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )
          : Text(
              text,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.primary,
              ),
            ),
    );
  }
}
