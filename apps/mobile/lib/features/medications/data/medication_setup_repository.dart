import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';

/// A structured, versioned extension of the existing v5 database.
///
/// The beta backup format pins the exact v5 SQL schema. Keeping this data in
/// the existing AppSettings table preserves backup/restore compatibility while
/// allowing typed dosage amounts to be associated with immutable plan IDs.
/// No stock movement is inferred from legacy free-text descriptions.
class ScheduledQuantity {
  const ScheduledQuantity({required this.milliunits, required this.unit});

  final int milliunits;
  final String unit;

  Map<String, Object> toJson() => {'amount': milliunits, 'unit': unit};

  static ScheduledQuantity? fromJson(Object? source) {
    if (source is! Map) return null;
    final quantity = source['amount'];
    final unit = source['unit'];
    if (quantity is! int || quantity <= 0 || quantity > 999999999 ||
        unit is! String || !MedicationUnits.supported.contains(unit)) {
      return null;
    }
    return ScheduledQuantity(milliunits: quantity, unit: unit);
  }
}

abstract final class MedicationUnits {
  static const count = ['عدد', 'ورق', 'بسته'];
  static const liquid = ['میلی‌لیتر', 'سی‌سی', 'لیتر'];
  static const supported = [...count, ...liquid];

  static bool isLiquid(String unit) => liquid.contains(unit);

  /// Convert only exact, dimensionally meaningful amounts. A strip is not a
  /// tablet: never guess how many tablets a user's strip contains.
  static int? toPackageMilliunits(ScheduledQuantity dose, String packageUnit) {
    if (dose.unit == packageUnit) return dose.milliunits;
    if (!isLiquid(dose.unit) || !isLiquid(packageUnit)) return null;
    final doseMillilitres = dose.unit == 'لیتر'
        ? dose.milliunits * 1000
        : dose.milliunits;
    if (packageUnit == 'لیتر') {
      if (doseMillilitres % 1000 != 0) return null;
      return doseMillilitres ~/ 1000;
    }
    return doseMillilitres;
  }
}

class MedicationSetup {
  const MedicationSetup({
    this.reminderNote = '',
    this.artwork = 'capsule',
    this.localImagePath,
    this.doses = const {},
  });

  final String reminderNote;
  final String artwork;
  final String? localImagePath;
  final Map<String, ScheduledQuantity> doses;

  MedicationSetup copyWith({
    String? reminderNote,
    String? artwork,
    String? localImagePath,
    Map<String, ScheduledQuantity>? doses,
  }) => MedicationSetup(
    reminderNote: reminderNote ?? this.reminderNote,
    artwork: artwork ?? this.artwork,
    localImagePath: localImagePath ?? this.localImagePath,
    doses: doses ?? this.doses,
  );
}

class MedicationSetupRepository {
  const MedicationSetupRepository(this.db);

  final AppDatabase db;

  String _key(String profileId, String medicationId) =>
      'medication-setup:v1:$profileId:$medicationId';

  Future<void> _assertOwned(String profileId, String medicationId) async {
    final owned = await (db.select(db.medications)
          ..where((m) => m.id.equals(medicationId) &
              m.profileId.equals(profileId)))
        .getSingleOrNull();
    if (owned == null) throw StateError('دارو متعلق به این پروفایل نیست.');
  }

  Future<MedicationSetup> read(String profileId, String medicationId) async {
    await _assertOwned(profileId, medicationId);
    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(_key(profileId, medicationId))))
        .getSingleOrNull();
    if (row == null) return const MedicationSetup();
    try {
      final data = jsonDecode(row.value);
      if (data is! Map<String, dynamic> || data['version'] != 1) {
        return const MedicationSetup();
      }
      final rawDoses = data['doses'];
      final doses = <String, ScheduledQuantity>{};
      if (rawDoses is Map<String, dynamic>) {
        for (final entry in rawDoses.entries) {
          final dose = ScheduledQuantity.fromJson(entry.value);
          if (dose != null) doses[entry.key] = dose;
        }
      }
      return MedicationSetup(
        reminderNote: data['note'] is String ? data['note'] as String : '',
        artwork: data['artwork'] is String
            ? data['artwork'] as String : 'capsule',
        localImagePath: data['imagePath'] is String
            ? data['imagePath'] as String : null,
        doses: doses,
      );
    } on FormatException {
      return const MedicationSetup();
    }
  }

  Future<void> save({
    required String profileId,
    required String medicationId,
    required MedicationSetup setup,
  }) async {
    await _assertOwned(profileId, medicationId);
    if (setup.reminderNote.length > 500) {
      throw ArgumentError('متن یادآور بیش از 500 نویسه است.');
    }
    await db.into(db.appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: _key(profileId, medicationId),
        value: jsonEncode({
          'version': 1,
          'note': setup.reminderNote,
          'artwork': setup.artwork,
          'imagePath': setup.localImagePath,
          'doses': {for (final e in setup.doses.entries) e.key: e.value.toJson()},
        }),
      ),
    );
  }
}
