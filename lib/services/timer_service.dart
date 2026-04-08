import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'notification_service.dart';

class TimerService {
  final void Function(int remainingSeconds)? onTick;
  final VoidCallback? onComplete;

  int totalSeconds = 0;
  int remainingSeconds = 0;
  bool isRunning = false;
  bool isCompleted = false;

  Timer? _timer;
  DateTime? _endTime;
  int? _scheduledNotificationId;

  static const _hiveBox = 'cooking_state';
  static const _endTimeKey = 'timer_end_time';

  TimerService({this.onTick, this.onComplete});

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  void start(int durationSeconds) {
    _cancelTimer();
    totalSeconds = durationSeconds;
    remainingSeconds = durationSeconds;
    isCompleted = false;
    _endTime = DateTime.now().add(Duration(seconds: durationSeconds));
    _startTicking();
  }

  void pause() {
    _cancelTimer();
    isRunning = false;
  }

  void resume() {
    if (isCompleted || remainingSeconds <= 0) return;
    _endTime = DateTime.now().add(Duration(seconds: remainingSeconds));
    _startTicking();
  }

  void reset() {
    _cancelTimer();
    remainingSeconds = totalSeconds;
    isRunning = false;
    isCompleted = false;
    _endTime = null;
    _clearPersistedEndTime();
  }

  void dispose() {
    _cancelTimer();
    _cancelScheduledNotification();
    _clearPersistedEndTime();
  }

  // ──────────────────────────────────────────────────────────
  // Background / foreground handling
  // ──────────────────────────────────────────────────────────

  Future<void> onAppPaused(String stepTitle) async {
    if (!isRunning || isCompleted || _endTime == null) return;
    _cancelTimer();

    // Persist end time to Hive
    await _persistEndTime(_endTime!);

    // Schedule a notification for when the timer would complete
    final remaining = _endTime!.difference(DateTime.now());
    if (remaining.inSeconds > 0) {
      _scheduledNotificationId =
          await NotificationService.instance.scheduleTimerNotification(
        stepTitle,
        remaining,
      );
    }
  }

  Future<void> onAppResumed() async {
    // Cancel the scheduled notification (we'll handle completion in-app)
    await _cancelScheduledNotification();

    final storedEnd = await _loadPersistedEndTime();
    if (storedEnd == null) return;

    _endTime = storedEnd;
    final now = DateTime.now();
    final remaining = storedEnd.difference(now).inSeconds;

    if (remaining <= 0) {
      // Timer finished while in background
      remainingSeconds = 0;
      _handleComplete();
    } else {
      remainingSeconds = remaining;
      _startTicking();
    }

    await _clearPersistedEndTime();
  }

  // ──────────────────────────────────────────────────────────
  // Internal
  // ──────────────────────────────────────────────────────────

  void _startTicking() {
    isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final remaining = _endTime!.difference(now).inSeconds;

      if (remaining <= 0) {
        remainingSeconds = 0;
        _handleComplete();
      } else {
        remainingSeconds = remaining;
        onTick?.call(remainingSeconds);
      }
    });
  }

  void _handleComplete() {
    _cancelTimer();
    isRunning = false;
    isCompleted = true;
    remainingSeconds = 0;

    // Haptic feedback
    HapticFeedback.heavyImpact();

    // Sound via notification (simplest — no extra asset needed)
    NotificationService.instance.showTimerCompleteNotification(
      'Step timer is done!',
    );

    onComplete?.call();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    isRunning = false;
  }

  Future<void> _cancelScheduledNotification() async {
    if (_scheduledNotificationId != null) {
      await NotificationService.instance
          .cancelNotification(_scheduledNotificationId!);
      _scheduledNotificationId = null;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Hive persistence for background timer
  // ──────────────────────────────────────────────────────────

  Future<void> _persistEndTime(DateTime endTime) async {
    final box = await Hive.openBox<String>(_hiveBox);
    await box.put(_endTimeKey, endTime.toIso8601String());
  }

  Future<DateTime?> _loadPersistedEndTime() async {
    final box = await Hive.openBox<String>(_hiveBox);
    final raw = box.get(_endTimeKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _clearPersistedEndTime() async {
    try {
      final box = await Hive.openBox<String>(_hiveBox);
      await box.delete(_endTimeKey);
    } catch (_) {
      // Hive may not be available during dispose
    }
  }
}
