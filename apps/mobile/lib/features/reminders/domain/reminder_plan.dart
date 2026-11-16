/// Pure scheduling model. All times are local wall-clock values,
/// not elapsed durations or prescribed dose intervals.
class ReminderSlot {
  const ReminderSlot({
    required this.occurrenceKey,
    required this.planId,
    required this.profileName,
    required this.medicationName,
    required this.doseText,
    required this.scheduledAt,
    required this.status,
  });

  final String occurrenceKey;
  final String planId;
  final String profileName;
  final String medicationName;
  final String doseText;
  final DateTime scheduledAt;
  final String status;
}

class ReminderJob {
  const ReminderJob({
    required this.id,
    required this.localAt,
    required this.title,
    required this.body,
    required this.daily,
  });

  final int id;
  final DateTime localAt;
  final String title;
  final String body;
  final bool daily;
}

/// M0 uses IDs 101 and 202; M2 reserves an entirely different range.
class ReminderPlanner {
  const ReminderPlanner();

  static const int firstManagedId = 1000000;
  static const int lastManagedId = 1500999999;
  static const int demoNotificationId = 900001;
  static const int maxJobs = 120;

  /// FNV-1a over UTF-16 code units, made stable across app launches.
  static int stableId(String key) {
    var hash = 0x811c9dc5;
    for (final code in key.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0xffffffff;
    }
    return firstManagedId + (hash % 1500000000);
  }

  List<ReminderJob> plan({
    required DateTime now,
    required List<ReminderSlot> today,
    required List<ReminderSlot> tomorrow,
  }) {
    final jobs = <ReminderJob>[];
    final used = <int>{};

    void append(ReminderSlot slot, {required bool daily, DateTime? date}) {
      final id = stableId(daily
          ? 'daily:${slot.planId}'
          : 'once:${slot.occurrenceKey}');
      if (!used.add(id)) {
        throw StateError('شناسه دو یادآور با هم تداخل دارد؛ برنامه ثبت نشد.');
      }
      jobs.add(ReminderJob(
        id: id,
        localAt: date ?? slot.scheduledAt,
        title: 'یادآور دارو',
        body: 'برای ${slot.profileName}: ${slot.medicationName} — '
            '${slot.doseText}',
        daily: daily,
      ));
    }

    for (final slot in today) {
      if (slot.status != 'pending') continue;
      if (!slot.scheduledAt.isAfter(now)) continue;
      append(slot, daily: false);
    }

    // Repeat from tomorrow, so editing a schedule today cannot replace or
    // duplicate today's dose record. On next app visit reconciliation
    // suppresses already-marked today's occurrences again.
    for (final slot in tomorrow) {
      final date = slot.status == 'pending'
          ? slot.scheduledAt
          : DateTime(
              slot.scheduledAt.year,
              slot.scheduledAt.month,
              slot.scheduledAt.day + 1,
              slot.scheduledAt.hour,
              slot.scheduledAt.minute,
            );
      append(slot, daily: true, date: date);
    }

    if (jobs.length > maxJobs) {
      throw StateError('تعداد یادآورها از سقف نسخه آزمایشی بیشتر است.');
    }
    jobs.sort((a, b) => a.localAt.compareTo(b.localAt));
    return jobs;
  }
}
