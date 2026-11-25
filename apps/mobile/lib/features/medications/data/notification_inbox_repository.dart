import 'dart:convert';
import '../../../core/storage/app_database.dart';

class InboxNotice {
  const InboxNotice({required this.condition, required this.medicationId,
    required this.title, required this.message, required this.urgent,
    this.id = '', this.read = false, this.active = true});
  final String condition, medicationId, title, message, id;
  final bool urgent, read, active;
  InboxNotice copy({String? id, bool? read, bool? active}) => InboxNotice(
    condition: condition, medicationId: medicationId, title: title,
    message: message, urgent: urgent, id: id ?? this.id,
    read: read ?? this.read, active: active ?? this.active);
  Map<String, Object> toJson() => {
    'condition': condition, 'medicationId': medicationId, 'title': title,
    'message': message, 'urgent': urgent, 'id': id, 'read': read,
    'active': active,
  };
  factory InboxNotice.fromJson(Map<String, dynamic> value) => InboxNotice(
    condition: value['condition'] as String,
    medicationId: value['medicationId'] as String,
    title: value['title'] as String, message: value['message'] as String,
    urgent: value['urgent'] as bool, id: value['id'] as String,
    read: value['read'] as bool, active: value['active'] as bool);
}

/// Read status and condition resolution are independent, profile scoped.
/// Each observed recurrence starts a new unread episode; resolved records
/// remain reviewable without a navigation action.
class NotificationInboxRepository {
  const NotificationInboxRepository(this.db);
  final AppDatabase db;
  String _key(String profile) => 'medication-inbox:v1:$profile';
  Future<List<InboxNotice>> load(String profile) async {
    final row = await (db.select(db.appSettings)
      ..where((t) => t.key.equals(_key(profile)))).getSingleOrNull();
    if (row == null) return [];
    return (jsonDecode(row.value) as List).map((v) =>
      InboxNotice.fromJson(Map<String, dynamic>.from(v as Map))).toList();
  }
  Future<void> _save(String profile, List<InboxNotice> rows) async {
    await db.into(db.appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: _key(profile),
        value: jsonEncode(rows.map((v) => v.toJson()).toList())));
  }
  Future<List<InboxNotice>> reconcile(String profile,
      List<InboxNotice> current) => db.transaction(() async {
    final stored = await load(profile);
    final old = stored.where((row) => !row.condition.startsWith('dose:')).toList();
    final byCondition = {for (final row in current) row.condition: row};
    final result = <InboxNotice>[];
    for (final row in old) {
      final live = row.active ? byCondition.remove(row.condition) : null;
      result.add(live == null ? row.copy(active: false)
        : live.copy(id: row.id, read: row.read));
    }
    var sequence = stored.fold<int>(0, (max, row) {
      final id = int.tryParse(row.id) ?? 0;
      return id > max ? id : max;
    });
    for (final row in byCondition.values) {
      result.add(row.copy(id: '${++sequence}'));
    }
    if (jsonEncode(stored.map((v) => v.toJson()).toList()) !=
        jsonEncode(result.map((v) => v.toJson()).toList())) {
      await _save(profile, result);
    }
    return result;
  });
  Future<List<InboxNotice>> markRead(String profile, String id) =>
    db.transaction(() async {
      final rows = (await load(profile)).map((row) =>
        row.id == id ? row.copy(read: true) : row).toList();
      await _save(profile, rows);
      return rows;
    });
}
