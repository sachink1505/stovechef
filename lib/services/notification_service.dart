import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _channelId = 'stovechef_timers';
  static const _channelName = 'StoveChef Timers';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 100;

  // ──────────────────────────────────────────────────────────
  // Init
  // ──────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    _initialized = true;
  }

  // ──────────────────────────────────────────────────────────
  // Permission
  // ──────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    await init();

    // iOS
    final iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    // Android 13+ (API 33) runtime permission
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    return true;
  }

  // ──────────────────────────────────────────────────────────
  // Show immediate notification
  // ──────────────────────────────────────────────────────────

  Future<void> showTimerCompleteNotification(String stepTitle) async {
    await init();
    await _plugin.show(
      _nextId++,
      'Timer Done! \u23f0',
      stepTitle,
      _details(),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Schedule notification
  // ──────────────────────────────────────────────────────────

  Future<int> scheduleTimerNotification(
    String stepTitle,
    Duration delay,
  ) async {
    await init();
    final id = _nextId++;
    final scheduledTime =
        tz.TZDateTime.now(tz.local).add(delay);

    await _plugin.zonedSchedule(
      id,
      'Timer Done! \u23f0',
      stepTitle,
      scheduledTime,
      _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    return id;
  }

  // ──────────────────────────────────────────────────────────
  // Cancel
  // ──────────────────────────────────────────────────────────

  Future<void> cancelNotification(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Cooking step timer alerts',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );
  }
}
