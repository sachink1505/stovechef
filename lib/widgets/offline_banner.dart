import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../services/connectivity_service.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  // Assume online initially; the stream will correct this on first event.
  bool _isOnline = true;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return StreamBuilder<bool>(
      stream: ConnectivityService.instance.isOnline,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? _isOnline;
        if (snapshot.hasData) _isOnline = isOnline;

        return AnimatedSlide(
          offset: isOnline ? const Offset(0, -1) : Offset.zero,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Container(
            width: double.infinity,
            height: 40 + topPadding,
            padding: EdgeInsets.only(
              top: topPadding,
              left: AppSpacing.lg,
              right: AppSpacing.lg,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              border: Border(
                left: BorderSide(
                  color: Color(0xFFF59E0B), // amber-500
                  width: 4,
                ),
              ),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              "You're offline. Some features may be unavailable.",
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.text,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}
