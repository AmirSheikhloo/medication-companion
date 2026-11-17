import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_plan.dart';

abstract class ReminderNotificationPort {
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<bool> hasPermissions();
  Future<void> replaceManaged(List<ReminderJob> jobs);
  Future<void> scheduleDemo();
}

/// Android plugin adapter. No widgets, SQL, or medical rules live here.
class AndroidReminderPort implements ReminderNotificationPort {
  AndroidReminderPort({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static NotificationDetails _details(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'm2_medication_reminder_v1',
      'یادآور دارو',
      channelDescription: 'اعلان نوبت دارو طبق زمان ثبت‌شده توسط کاربر',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      styleInformation: BigTextStyleInformation(body),
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
    ),
  );

  @override
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> hasPermissions() async {
    final android = _android;
    if (android == null) return false;
    final canPost = await android.areNotificationsEnabled();
    final canExact = await android.canScheduleExactNotifications();
    return canPost == true && canExact == true;
  }

  @override
  Future<bool> requestPermissions() async {
    final android = _android;
    if (android == null) return false;
    if (await android.requestNotificationsPermission() != true) return false;
    if (await android.requestExactAlarmsPermission() != true) return false;
    return hasPermissions();
  }

  @override
  Future<void> replaceManaged(List<ReminderJob> jobs) async {
    // Never cancel M0 test alarms (IDs 101/202) or other app channels.
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.id >= ReminderPlanner.firstManagedId &&
          notification.id <= ReminderPlanner.lastManagedId) {
        await _plugin.cancel(id: notification.id);
      }
    }
    for (final job in jobs) {
      final local = tz.TZDateTime.from(job.localAt, tz.local);
      await _plugin.zonedSchedule(
        id: job.id,
        title: job.title,
        body: job.body,
        scheduledDate: local,
        notificationDetails: _details(job.body),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents:
            job.daily ? DateTimeComponents.time : null,
      );
    }
  }

  @override
  Future<void> scheduleDemo() async {
    // This is not a medication dose, and the demo ID is outside the managed
    // schedule range. Real dose times are never shortened to five seconds.
    await _plugin.zonedSchedule(
      id: ReminderPlanner.demoNotificationId,
      title: 'تست یادآور دارو',
      body: 'اعلان آزمایشی ۵ ثانیه‌ای؛ دارویی مصرف نکنید.',
      scheduledDate:
          tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5)),
      notificationDetails: _details('اعلان آزمایشی ۵ ثانیه‌ای؛ دارویی مصرف نکنید.'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
