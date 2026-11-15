import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';

/// Local guest profiles only. No login, cloud account, or remote sync.
class ProfileRepository {
  ProfileRepository(this.db);

  final AppDatabase db;
  final Uuid _uuid = Uuid();

  Future<List<Profile>> profiles() =>
      (db.select(db.profiles)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<Profile?> activeProfile() async {
    final setting = await (db.select(db.appSettings)
          ..where((t) => t.key.equals('active_profile')))
        .getSingleOrNull();
    if (setting == null) return null;

    return (db.select(db.profiles)
          ..where((t) => t.id.equals(setting.value)))
        .getSingleOrNull();
  }

  Future<Profile> createGuestProfile({
    required bool forSelf,
    String? displayName,
  }) async {
    final cleaned = (displayName ?? '').trim();
    final name = cleaned.isEmpty ? (forSelf ? 'من' : 'عزیز من') : cleaned;
    if (name.length > 80) {
      throw ArgumentError('نام پروفایل باید حداکثر ۸۰ نویسه باشد.');
    }

    final id = _uuid.v4();
    final created = DateTime.now().toUtc();
    await db.transaction(() async {
      await db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: id,
            displayName: name,
            kind: forSelf ? 'self' : 'managed',
            createdAt: created,
          ));
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: 'active_profile', value: id),
          );
    });

    return (db.select(db.profiles)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> selectActiveProfile(String id) async {
    final found = await (db.select(db.profiles)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (found == null) throw StateError('پروفایل پیدا نشد.');

    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: 'active_profile', value: id),
        );
  }
}
