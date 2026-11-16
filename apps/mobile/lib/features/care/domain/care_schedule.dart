/// Civil-time calendar arithmetic for user-entered follow-up dates.
/// DateTime is reconstructed in the device's local zone instead of adding
/// 24 hours to UTC (which could shift the displayed hour around DST changes).
class CareSchedule {
  const CareSchedule();

  static const repeatRules = {'none', 'daily', 'weekly', 'monthly'};

  static DateTime monthsAfter(DateTime reference, int months,
      {int? anchorDay}) {
    if (months < 0 || months > 1200) {
      throw ArgumentError('فاصله ماه نامعتبر است.');
    }
    final local = reference.toLocal();
    final first = DateTime(local.year, local.month + months, 1);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final day = anchorDay ?? local.day;
    if (day < 1 || day > 31) throw ArgumentError('روز مرجع نامعتبر است.');
    return DateTime(first.year, first.month,
        day > daysInMonth ? daysInMonth : day,
        local.hour, local.minute, local.second);
  }

  static DateTime advance(DateTime dueAt, String rule,
      {int? anchorDay}) {
    final local = dueAt.toLocal();
    return switch (rule) {
      'daily' => DateTime(local.year, local.month, local.day + 1,
          local.hour, local.minute, local.second),
      'weekly' => DateTime(local.year, local.month, local.day + 7,
          local.hour, local.minute, local.second),
      'monthly' => monthsAfter(local, 1, anchorDay: anchorDay),
      _ => throw ArgumentError('قاعده تکرار نامعتبر است.'),
    };
  }

  /// Finds the next civil-time occurrence strictly after [after]. It never
  /// changes any medication or task row by itself.
  static DateTime nextAfter(DateTime dueAt, String rule, DateTime after,
      {int? anchorDay}) {
    if (!repeatRules.contains(rule) || rule == 'none') {
      throw ArgumentError('این کار تکرارشونده نیست.');
    }
    var current = dueAt.toLocal();
    for (var attempts = 0; attempts < 1500; attempts++) {
      if (current.isAfter(after)) return current;
      current = advance(current, rule, anchorDay: anchorDay);
    }
    throw StateError('محاسبه تاریخ بعدی بیش از حد طول کشید.');
  }
}

class CareReminderJob {
  const CareReminderJob({
    required this.id,
    required this.localAt,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime localAt;
  final String title;
  final String body;
}

class CareReminderCandidate {
  const CareReminderCandidate({
    required this.key,
    required this.localAt,
    required this.title,
    required this.body,
  });

  final String key;
  final DateTime localAt;
  final String title;
  final String body;
}

/// Owns a disjoint Android notification-ID range from M0 and medication M2.
class CareReminderPlanner {
  const CareReminderPlanner();

  static const firstManagedId = 1510000000;
  static const lastManagedId = 2100000000;
  static const demoNotificationId = 900003;
  static const maxJobs = 200;

  static int stableId(String key) {
    var hash = 0x811c9dc5;
    for (final code in key.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0xffffffff;
    }
    return firstManagedId + (hash % (lastManagedId - firstManagedId + 1));
  }

  List<CareReminderJob> plan({
    required DateTime now,
    required Iterable<CareReminderCandidate> candidates,
  }) {
    final jobs = <CareReminderJob>[];
    final ids = <int>{};
    for (final candidate in candidates) {
      if (!candidate.localAt.isAfter(now)) continue;
      final id = stableId(candidate.key);
      if (!ids.add(id)) {
        throw StateError('تداخل شناسه اعلان؛ هیچ زمان‌بندی جدیدی ثبت نشد.');
      }
      jobs.add(CareReminderJob(
        id: id,
        localAt: candidate.localAt,
        title: candidate.title,
        body: candidate.body,
      ));
      if (jobs.length > maxJobs) {
        throw StateError('تعداد یادآورهای پیگیری بیش از سقف نسخه آزمایشی است.');
      }
    }
    jobs.sort((a, b) => a.localAt.compareTo(b.localAt));
    return jobs;
  }
}
