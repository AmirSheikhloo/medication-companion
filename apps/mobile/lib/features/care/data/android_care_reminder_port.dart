import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/care_schedule.dart';

abstract class CareReminderNotificationPort {
  Future<void> initialize();
  Future<bool> hasPermissions();
  Future<bool> requestPermissions();
  Future<void> replaceManaged(List<CareReminderJob> jobs);
  Future<void> scheduleDemo();
}

/// Uses its own channel and ID range. Medication and M0 alarms are untouched.
class AndroidCareReminderPort implements CareReminderNotificationPort {
  AndroidCareReminderPort({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static NotificationDetails _details(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'm3_care_reminder_v1',
      'پیگیری و ویزیت',
      channelDescription: 'اعلان اختیاری کارها و ویزیت‌ها',
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
    await _plugin.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    _initialized = true;
  }

  @override
  Future<bool> hasPermissions() async {
    final android = _android;
    if (android == null) return false;
    return await android.areNotificationsEnabled() == true &&
        await android.canScheduleExactNotifications() == true;
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
  Future<void> replaceManaged(List<CareReminderJob> jobs) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final item in pending) {
      if (item.id >= CareReminderPlanner.firstManagedId &&
          item.id <= CareReminderPlanner.lastManagedId) {
        await _plugin.cancel(id: item.id);
      }
    }
    for (final job in jobs) {
      await _plugin.zonedSchedule(
        id: job.id,
        title: job.title,
        body: job.body,
        scheduledDate: tz.TZDateTime.from(job.localAt, tz.local),
        notificationDetails: _details(job.body),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> scheduleDemo() => _plugin.zonedSchedule(
        id: CareReminderPlanner.demoNotificationId,
        title: 'تست یادآور پیگیری',
        body: 'اعلان آزمایشی 5 ثانیه‌ای؛ نیاز به اقدام پزشکی نیست.',
        scheduledDate: tz.TZDateTime.now(tz.local)
            .add(const Duration(seconds: 5)),
        notificationDetails: _details('اعلان آزمایشی 5 ثانیه‌ای؛ نیاز به اقدام پزشکی نیست.'),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
}
