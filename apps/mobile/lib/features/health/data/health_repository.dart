import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../domain/health_metric.dart';

/// All reads and writes are restricted to the explicitly selected profile.
/// Edits append immutable snapshots before returning success to the UI.
class HealthRepository {
  HealthRepository(this.db);

  final AppDatabase db;
  final Uuid _uuid = const Uuid();

  Future<void> _requireProfile(String profileId) async {
    final profile = await (db.select(db.profiles)
          ..where((t) => t.id.equals(profileId)))
        .getSingleOrNull();
    if (profile == null) throw StateError('پروفایل پیدا نشد.');
  }

  Future<HealthMeasurement> _owned(String profileId, String id) async {
    final record = await (db.select(db.healthMeasurements)
          ..where((t) => t.id.equals(id) & t.profileId.equals(profileId)))
        .getSingleOrNull();
    if (record == null) {
      throw StateError('اندازه‌گیری متعلق به این پروفایل نیست.');
    }
    return record;
  }

  void _validate(HealthMeasurementDraft draft) {
    bool isValidValue(int? value) =>
        value != null && value > 0 && value <= 1000000000;
    if (!isValidValue(draft.primaryMilliunits)) {
      throw ArgumentError('مقدار اول باید مثبت و قابل ذخیره باشد.');
    }
    if (draft.metric.hasSecondValue != (draft.secondaryMilliunits != null) ||
        (draft.secondaryMilliunits != null &&
            !isValidValue(draft.secondaryMilliunits))) {
      throw ArgumentError('برای فشار خون هر دو مقدار الزامی‌اند.');
    }
    if (draft.observedAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      throw ArgumentError('زمان اندازه‌گیری نباید در آینده باشد.');
    }
    if (draft.metric == HealthMetric.glucose) {
      const values = {'fasting', 'before_meal', 'after_meal', 'other'};
      if (!values.contains(draft.context)) {
        throw ArgumentError('شرایط اندازه‌گیری قند را مشخص کنید.');
      }
    } else if (draft.context != null) {
      throw ArgumentError('شرایط ثبت با شاخص انتخاب‌شده سازگار نیست.');
    }
    if ((draft.note ?? '').trim().length > 500) {
      throw ArgumentError('یادداشت نمی‌تواند بیشتر از ۵۰۰ نویسه باشد.');
    }
  }

  Future<List<HealthMeasurement>> measurementsFor({
    required String profileId,
    HealthMetric? metric,
    int? days,
    DateTime? now,
  }) async {
    await _requireProfile(profileId);
    if (days != null && days <= 0) throw ArgumentError('بازه نامعتبر است.');
    final since = days == null
        ? null
        : (now ?? DateTime.now()).subtract(Duration(days: days));
    final query = db.select(db.healthMeasurements)
      ..where((t) {
        var condition = t.profileId.equals(profileId) &
            t.archived.equals(false);
        if (metric != null) condition = condition & t.metric.equals(metric.name);
        if (since != null) {
          condition = condition & t.observedAt.isBiggerOrEqualValue(since.toUtc());
        }
        return condition;
      })
      ..orderBy([
        (t) => OrderingTerm.desc(t.observedAt),
        (t) => OrderingTerm.desc(t.recordedAt),
      ]);
    return query.get();
  }

  Future<String> addMeasurement({
    required String profileId,
    required HealthMeasurementDraft draft,
  }) async {
    _validate(draft);
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await db.transaction(() async {
      await _requireProfile(profileId);
      await db.into(db.healthMeasurements).insert(
            HealthMeasurementsCompanion.insert(
              id: id,
              profileId: profileId,
              metric: draft.metric.name,
              primaryMilliunits: draft.primaryMilliunits,
              secondaryMilliunits: Value(draft.secondaryMilliunits),
              unit: draft.metric.unit,
              context: Value(draft.context),
              note: Value(draft.note?.trim()),
              observedAt: draft.observedAt.toUtc(),
              recordedAt: now,
              updatedAt: now,
              version: 1,
            ),
          );
      await _appendVersion(
        id: id,
        profileId: profileId,
        version: 1,
        action: 'created',
        draft: draft,
        changedAt: now,
      );
    });
    return id;
  }

  Future<void> correctMeasurement({
    required String profileId,
    required String measurementId,
    required HealthMeasurementDraft draft,
  }) async {
    _validate(draft);
    await db.transaction(() async {
      final current = await _owned(profileId, measurementId);
      if (current.archived) {
        throw StateError('اندازه‌گیری بایگانی‌شده قابل اصلاح نیست.');
      }
      if (current.metric != draft.metric.name) {
        throw ArgumentError('نوع شاخص را نمی‌توان هنگام اصلاح تغییر داد.');
      }
      final now = DateTime.now().toUtc();
      final version = current.version + 1;
      await (db.update(db.healthMeasurements)
            ..where((t) => t.id.equals(measurementId) &
                t.profileId.equals(profileId)))
          .write(HealthMeasurementsCompanion(
            primaryMilliunits: Value(draft.primaryMilliunits),
            secondaryMilliunits: Value(draft.secondaryMilliunits),
            context: Value(draft.context),
            note: Value(draft.note?.trim()),
            observedAt: Value(draft.observedAt.toUtc()),
            updatedAt: Value(now),
            version: Value(version),
          ));
      await _appendVersion(
        id: measurementId,
        profileId: profileId,
        version: version,
        action: 'corrected',
        draft: draft,
        changedAt: now,
      );
    });
  }

  Future<void> archiveMeasurement({
    required String profileId,
    required String measurementId,
  }) async {
    await db.transaction(() async {
      final current = await _owned(profileId, measurementId);
      if (current.archived) {
        throw StateError('این اندازه‌گیری قبلاً بایگانی شده است.');
      }
      final now = DateTime.now().toUtc();
      final version = current.version + 1;
      await (db.update(db.healthMeasurements)
            ..where((t) => t.id.equals(measurementId) &
                t.profileId.equals(profileId)))
          .write(HealthMeasurementsCompanion(
            archived: const Value(true),
            version: Value(version),
            updatedAt: Value(now),
          ));
      await _appendVersion(
        id: current.id,
        profileId: profileId,
        version: version,
        action: 'archived',
        draft: HealthMeasurementDraft(
          metric: HealthMetric.fromCode(current.metric),
          primaryMilliunits: current.primaryMilliunits,
          secondaryMilliunits: current.secondaryMilliunits,
          observedAt: current.observedAt,
          context: current.context,
          note: current.note,
        ),
        changedAt: now,
      );
    });
  }

  Future<List<HealthMeasurementVersion>> versionsFor({
    required String profileId,
    required String measurementId,
  }) async {
    await _owned(profileId, measurementId);
    return (db.select(db.healthMeasurementVersions)
          ..where((t) => t.profileId.equals(profileId) &
              t.measurementId.equals(measurementId))
          ..orderBy([(t) => OrderingTerm.asc(t.version)]))
        .get();
  }

  Future<void> _appendVersion({
    required String id,
    required String profileId,
    required int version,
    required String action,
    required HealthMeasurementDraft draft,
    required DateTime changedAt,
  }) async {
    await db.into(db.healthMeasurementVersions).insert(
          HealthMeasurementVersionsCompanion.insert(
            id: _uuid.v4(),
            measurementId: id,
            profileId: profileId,
            version: version,
            action: action,
            metric: draft.metric.name,
            primaryMilliunits: draft.primaryMilliunits,
            secondaryMilliunits: Value(draft.secondaryMilliunits),
            unit: draft.metric.unit,
            context: Value(draft.context),
            note: Value(draft.note?.trim()),
            observedAt: draft.observedAt.toUtc(),
            changedAt: changedAt,
          ),
        );
  }
}
