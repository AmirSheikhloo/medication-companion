import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';

/// Local-only care planning. Every read and mutation is scoped to one profile.
/// Tasks describe user intentions, never clinical instructions.
class CareRepository {
  CareRepository(this.db);

  final AppDatabase db;
  final Uuid _uuid = const Uuid();

  Future<void> _requireProfile(String profileId) async {
    final profile = await (db.select(db.profiles)
          ..where((t) => t.id.equals(profileId)))
        .getSingleOrNull();
    if (profile == null) throw StateError('پروفایل پیدا نشد.');
  }

  Future<CareVisit> _visit(String profileId, String visitId) async {
    final visit = await (db.select(db.careVisits)
          ..where((t) => t.id.equals(visitId) & t.profileId.equals(profileId)))
        .getSingleOrNull();
    if (visit == null || visit.archived) {
      throw StateError('ویزیت متعلق به این پروفایل نیست.');
    }
    return visit;
  }

  Future<CareTask> _task(String profileId, String taskId) async {
    final task = await (db.select(db.careTasks)
          ..where((t) => t.id.equals(taskId) & t.profileId.equals(profileId)))
        .getSingleOrNull();
    if (task == null || task.archived) {
      throw StateError('کار متعلق به این پروفایل نیست.');
    }
    return task;
  }

  String _title(String text, {int max = 160}) {
    final result = text.trim();
    if (result.isEmpty || result.length > max) {
      throw ArgumentError('عنوان باید بین ۱ تا $max نویسه باشد.');
    }
    return result;
  }

  String? _optional(String? value, {int max = 400}) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.length > max) throw ArgumentError('متن بیش از حد طولانی است.');
    return text;
  }

  Future<List<CareVisit>> visitsFor(String profileId) async {
    await _requireProfile(profileId);
    return (db.select(db.careVisits)
          ..where((t) => t.profileId.equals(profileId) & t.archived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.scheduledAt)]))
        .get();
  }

  Future<String> addVisit({
    required String profileId,
    required String title,
    required DateTime scheduledAt,
    String? doctor,
    String? location,
    String? purpose,
  }) async {
    final safeTitle = _title(title);
    final safeDoctor = _optional(doctor, max: 120);
    final safeLocation = _optional(location, max: 160);
    final safePurpose = _optional(purpose, max: 500);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      await _requireProfile(profileId);
      await db.into(db.careVisits).insert(CareVisitsCompanion.insert(
        id: id,
        profileId: profileId,
        title: safeTitle,
        scheduledAt: scheduledAt.toUtc(),
        doctor: Value(safeDoctor),
        location: Value(safeLocation),
        purpose: Value(safePurpose),
        createdAt: now,
        updatedAt: now,
      ));
      for (final phase in ['before', 'after']) {
        final labels = phase == 'before'
            ? [
                'مدارک و نسخه‌های قبلی',
                'فهرست داروهای فعلی',
                'جواب آزمایش‌ها',
                'گزارش‌های سلامت',
                'سؤال‌هایی که می‌خواهم بپرسم',
              ]
            : [
                'ثبت تغییرات دارو طبق نسخه',
                'ثبت قرار بعدی در صورت نیاز',
                'ثبت آزمایش‌ها و پیگیری‌های تجویزشده',
              ];
        for (var i = 0; i < labels.length; i++) {
          await db.into(db.visitChecklistItems).insert(
            VisitChecklistItemsCompanion.insert(
              id: _uuid.v4(),
              profileId: profileId,
              visitId: id,
              phase: phase,
              title: labels[i],
              position: i,
            ),
          );
        }
      }
    });
    return id;
  }

  Future<void> updateVisit({
    required String profileId,
    required String visitId,
    required String title,
    required DateTime scheduledAt,
    String? doctor,
    String? location,
    String? purpose,
  }) async {
    final safeTitle = _title(title);
    final safeDoctor = _optional(doctor, max: 120);
    final safeLocation = _optional(location, max: 160);
    final safePurpose = _optional(purpose, max: 500);
    await db.transaction(() async {
      await _visit(profileId, visitId);
      await (db.update(db.careVisits)
            ..where((t) => t.id.equals(visitId) & t.profileId.equals(profileId)))
          .write(CareVisitsCompanion(
        title: Value(safeTitle),
        scheduledAt: Value(scheduledAt.toUtc()),
        doctor: Value(safeDoctor),
        location: Value(safeLocation),
        purpose: Value(safePurpose),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    });
  }

  Future<void> setVisitStatus({
    required String profileId,
    required String visitId,
    required String status,
  }) async {
    if (!{'scheduled', 'completed', 'cancelled'}.contains(status)) {
      throw ArgumentError('وضعیت ویزیت نامعتبر است.');
    }
    await db.transaction(() async {
      await _visit(profileId, visitId);
      await (db.update(db.careVisits)
            ..where((t) => t.id.equals(visitId) & t.profileId.equals(profileId)))
          .write(CareVisitsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    });
  }

  Future<List<CareTask>> tasksFor(String profileId) async {
    await _requireProfile(profileId);
    return (db.select(db.careTasks)
          ..where((t) => t.profileId.equals(profileId) & t.archived.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<String> addTask({
    required String profileId,
    required String title,
    DateTime? dueAt,
    String? visitId,
  }) async {
    final safeTitle = _title(title);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      await _requireProfile(profileId);
      if (visitId != null) await _visit(profileId, visitId);
      await db.into(db.careTasks).insert(CareTasksCompanion.insert(
        id: id,
        profileId: profileId,
        title: safeTitle,
        dueAt: Value(dueAt?.toUtc()),
        visitId: Value(visitId),
        createdAt: now,
        updatedAt: now,
      ));
      await _taskEvent(profileId, id, 'created', now);
    });
    return id;
  }

  Future<void> updateTask({
    required String profileId,
    required String taskId,
    required String title,
    DateTime? dueAt,
    String? visitId,
  }) async {
    final safeTitle = _title(title);
    await db.transaction(() async {
      await _task(profileId, taskId);
      if (visitId != null) await _visit(profileId, visitId);
      final now = DateTime.now().toUtc();
      await (db.update(db.careTasks)
            ..where((t) => t.id.equals(taskId) & t.profileId.equals(profileId)))
          .write(CareTasksCompanion(
        title: Value(safeTitle),
        dueAt: Value(dueAt?.toUtc()),
        visitId: Value(visitId),
        updatedAt: Value(now),
      ));
      await _taskEvent(profileId, taskId, 'edited', now);
    });
  }

  Future<void> setTaskStatus({
    required String profileId,
    required String taskId,
    required String status,
  }) async {
    if (!{'open', 'done', 'deferred'}.contains(status)) {
      throw ArgumentError('وضعیت کار نامعتبر است.');
    }
    await db.transaction(() async {
      final task = await _task(profileId, taskId);
      if (task.status == status) return;
      final now = DateTime.now().toUtc();
      await (db.update(db.careTasks)
            ..where((t) => t.id.equals(taskId) & t.profileId.equals(profileId)))
          .write(CareTasksCompanion(
        status: Value(status),
        updatedAt: Value(now),
      ));
      await _taskEvent(profileId, taskId, status, now);
    });
  }

  Future<void> archiveTask(String profileId, String taskId) async {
    await db.transaction(() async {
      await _task(profileId, taskId);
      final now = DateTime.now().toUtc();
      await (db.update(db.careTasks)
            ..where((t) => t.id.equals(taskId) & t.profileId.equals(profileId)))
          .write(CareTasksCompanion(
        archived: const Value(true),
        updatedAt: Value(now),
      ));
      await _taskEvent(profileId, taskId, 'archived', now);
    });
  }

  Future<void> _taskEvent(String profileId, String taskId, String action,
      DateTime when) async {
    await db.into(db.careTaskEvents).insert(CareTaskEventsCompanion.insert(
      id: _uuid.v4(),
      profileId: profileId,
      taskId: taskId,
      action: action,
      recordedAt: when,
    ));
  }

  Future<List<CareTaskEvent>> eventsFor(String profileId, String taskId) async {
    await _requireProfile(profileId);
    final exists = await (db.select(db.careTasks)
          ..where((t) => t.id.equals(taskId) & t.profileId.equals(profileId)))
        .getSingleOrNull();
    if (exists == null) throw StateError('کار متعلق به این پروفایل نیست.');
    return (db.select(db.careTaskEvents)
          ..where((t) => t.profileId.equals(profileId) & t.taskId.equals(taskId))
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
        .get();
  }

  Future<List<VisitChecklistItem>> checklistFor({
    required String profileId,
    required String visitId,
    required String phase,
  }) async {
    if (phase != 'before' && phase != 'after') {
      throw ArgumentError('مرحلهٔ چک‌لیست نامعتبر است.');
    }
    await _visit(profileId, visitId);
    return (db.select(db.visitChecklistItems)
          ..where((t) => t.profileId.equals(profileId) &
              t.visitId.equals(visitId) & t.phase.equals(phase))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Future<VisitChecklistItem> _checkItem(String profileId, String itemId) async {
    final item = await (db.select(db.visitChecklistItems)
          ..where((t) => t.id.equals(itemId) & t.profileId.equals(profileId)))
        .getSingleOrNull();
    if (item == null) throw StateError('مورد چک‌لیست متعلق به این پروفایل نیست.');
    await _visit(profileId, item.visitId);
    return item;
  }

  Future<void> addChecklistItem({
    required String profileId,
    required String visitId,
    required String phase,
    required String title,
  }) async {
    final safeTitle = _title(title);
    if (phase != 'before' && phase != 'after') {
      throw ArgumentError('مرحلهٔ چک‌لیست نامعتبر است.');
    }
    await db.transaction(() async {
      final existing = await checklistFor(
          profileId: profileId, visitId: visitId, phase: phase);
      final next = existing.isEmpty
          ? 0
          : existing.map((item) => item.position).reduce((a, b) => a > b ? a : b) + 1;
      await db.into(db.visitChecklistItems).insert(
        VisitChecklistItemsCompanion.insert(
          id: _uuid.v4(),
          profileId: profileId,
          visitId: visitId,
          phase: phase,
          title: safeTitle,
          position: next,
        ),
      );
    });
  }

  Future<void> toggleChecklistItem({
    required String profileId,
    required String itemId,
    bool? checked,
    bool? enabled,
  }) async {
    if (checked == null && enabled == null) return;
    await db.transaction(() async {
      final item = await _checkItem(profileId, itemId);
      if (checked != null && !item.enabled && checked) {
        throw StateError('ابتدا این مورد را فعال کنید.');
      }
      await (db.update(db.visitChecklistItems)
            ..where((t) => t.id.equals(itemId) & t.profileId.equals(profileId)))
          .write(VisitChecklistItemsCompanion(
        checked: Value(checked ?? (enabled == false ? false : item.checked)),
        enabled: Value(enabled ?? item.enabled),
      ));
    });
  }

  Future<void> moveChecklistItem({
    required String profileId,
    required String itemId,
    required int direction,
  }) async {
    if (direction != -1 && direction != 1) throw ArgumentError('جهت نامعتبر است.');
    await db.transaction(() async {
      final item = await _checkItem(profileId, itemId);
      final items = await checklistFor(
          profileId: profileId, visitId: item.visitId, phase: item.phase);
      final index = items.indexWhere((other) => other.id == itemId);
      final otherIndex = index + direction;
      if (index == -1 || otherIndex < 0 || otherIndex >= items.length) return;
      final other = items[otherIndex];
      await (db.update(db.visitChecklistItems)
            ..where((t) => t.id.equals(item.id) & t.profileId.equals(profileId)))
          .write(VisitChecklistItemsCompanion(position: Value(other.position)));
      await (db.update(db.visitChecklistItems)
            ..where((t) => t.id.equals(other.id) & t.profileId.equals(profileId)))
          .write(VisitChecklistItemsCompanion(position: Value(item.position)));
    });
  }

  Future<void> removeChecklistItem(String profileId, String itemId) async {
    await db.transaction(() async {
      await _checkItem(profileId, itemId);
      await (db.delete(db.visitChecklistItems)
            ..where((t) => t.id.equals(itemId) & t.profileId.equals(profileId)))
          .go();
    });
  }

  Future<List<VisitQuestion>> questionsFor(String profileId,
      {String? visitId}) async {
    await _requireProfile(profileId);
    if (visitId != null) await _visit(profileId, visitId);
    return (db.select(db.visitQuestions)
          ..where((t) {
            var condition = t.profileId.equals(profileId) & t.archived.equals(false);
            if (visitId != null) condition = condition & t.visitId.equals(visitId);
            return condition;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<String> addQuestion({
    required String profileId,
    required String question,
    String? visitId,
  }) async {
    final text = _title(question, max: 500);
    final id = _uuid.v4();
    await db.transaction(() async {
      await _requireProfile(profileId);
      if (visitId != null) await _visit(profileId, visitId);
      await db.into(db.visitQuestions).insert(VisitQuestionsCompanion.insert(
        id: id,
        profileId: profileId,
        visitId: Value(visitId),
        question: text,
        createdAt: DateTime.now().toUtc(),
      ));
    });
    return id;
  }

  Future<void> setQuestionAnswered({
    required String profileId,
    required String questionId,
    required bool answered,
  }) async {
    await db.transaction(() async {
      final question = await (db.select(db.visitQuestions)
            ..where((t) => t.id.equals(questionId) & t.profileId.equals(profileId)))
          .getSingleOrNull();
      if (question == null || question.archived) {
        throw StateError('سؤال متعلق به این پروفایل نیست.');
      }
      await (db.update(db.visitQuestions)
            ..where((t) => t.id.equals(questionId) & t.profileId.equals(profileId)))
          .write(VisitQuestionsCompanion(
        answered: Value(answered),
        answeredAt: Value(answered ? DateTime.now().toUtc() : null),
      ));
    });
  }

  Future<void> archiveQuestion(String profileId, String questionId) async {
    await db.transaction(() async {
      final question = await (db.select(db.visitQuestions)
            ..where((t) => t.id.equals(questionId) & t.profileId.equals(profileId)))
          .getSingleOrNull();
      if (question == null || question.archived) {
        throw StateError('سؤال متعلق به این پروفایل نیست.');
      }
      await (db.update(db.visitQuestions)
            ..where((t) => t.id.equals(questionId) & t.profileId.equals(profileId)))
          .write(const VisitQuestionsCompanion(archived: Value(true)));
    });
  }
}
