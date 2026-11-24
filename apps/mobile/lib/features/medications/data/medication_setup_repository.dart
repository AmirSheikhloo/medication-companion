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
  const ScheduledQuantity({required this.milliunits, required this.unit,
    this.calibratedMlMilliunits});

  final int milliunits;
  final String unit;
  final int? calibratedMlMilliunits;

  Map<String, Object> toJson() => {
    'amount': milliunits, 'unit': unit,
    if (calibratedMlMilliunits != null)
      'calibratedMlMilliunits': calibratedMlMilliunits!,
  };

  static ScheduledQuantity? fromJson(Object? source) {
    if (source is! Map) return null;
    final quantity = source['amount'];
    final unit = source['unit'];
    if (quantity is! int || quantity <= 0 || quantity > 999999999 ||
        unit is! String || !MedicationUnits.supported.contains(unit)) {
      return null;
    }
    final calibration = source['calibratedMlMilliunits'];
    if (unit == MedicationUnits.dessertSpoon &&
        (calibration is! int || calibration <= 0 || calibration > 30000)) {
      return null;
    }
    return ScheduledQuantity(milliunits: quantity, unit: unit,
      calibratedMlMilliunits: calibration is int ? calibration : null);
  }
}

abstract final class MedicationUnits {
  static const dessertSpoon = 'قاشق مرباخوری مدرج';
  static const teaSpoon = 'قاشق چای‌خوری مدرج';
  static const tableSpoon = 'قاشق غذاخوری مدرج';
  static const count = ['عدد', 'قرص', 'کپسول', 'ساشه', 'شیاف',
    'چسب دارویی', 'پاف', 'اسپری', 'قطره', 'آمپول', 'ویال', 'ورق', 'بسته'];
  static const liquid = ['میلی‌لیتر', 'سی‌سی', 'لیتر',
    teaSpoon, dessertSpoon, tableSpoon, 'ml'];
  static const mass = ['گرم', 'میلی‌گرم'];
  static const supported = [...count, ...liquid, ...mass];
  static const selectable = ['عدد', 'قرص', 'کپسول', 'ساشه', 'شیاف',
    'چسب دارویی', 'پاف', 'اسپری', 'قطره', 'آمپول', 'ویال',
    'میلی‌لیتر', teaSpoon, dessertSpoon, tableSpoon, ...mass];

  static bool isLiquid(String unit) => liquid.contains(unit);
  static bool isStripCount(String unit) =>
      const ['عدد', 'قرص', 'کپسول'].contains(unit);
  static bool requiresWhole(String unit) => const [
    'قطره', 'پاف', 'اسپری', 'چسب دارویی', 'آمپول', 'ویال',
  ].contains(unit);
  static String stockUnitForDose(String unit) =>
      isLiquid(unit) ? 'میلی‌لیتر' : unit;

  static int? _mlFactor(ScheduledQuantity dose) => switch (dose.unit) {
    'میلی‌لیتر' || 'سی‌سی' || 'ml' => 1000,
    'لیتر' => 1000000,
    teaSpoon => 5000,
    tableSpoon => 15000,
    dessertSpoon => dose.calibratedMlMilliunits,
    _ => null,
  };

  // Exact arithmetic; no guessed drop volume or concentration conversion.
  static int? toPackageMilliunits(ScheduledQuantity dose, String packageUnit) {
    if (dose.milliunits <= 0 || dose.milliunits > 999999999 ||
        (requiresWhole(dose.unit) && dose.milliunits % 1000 != 0)) {
      return null;
    }
    if (dose.unit == packageUnit) {
      return dose.unit == dessertSpoon ? null : dose.milliunits;
    }
    final factor = _mlFactor(dose);
    if (factor == null || factor <= 0 ||
        (dose.unit == dessertSpoon && factor > 30000)) return null;
    final numerator = dose.milliunits * factor;
    final divisor = switch (packageUnit) {
      'میلی‌لیتر' || 'سی‌سی' || 'ml' => 1000,
      'لیتر' => 1000000,
      _ => 0,
    };
    if (divisor == 0 || numerator % divisor != 0) return null;
    final result = numerator ~/ divisor;
    return result > 0 && result <= 999999999 ? result : null;
  }
}

class MedicationSetup {
  const MedicationSetup({
    this.reminderNote = '',
    this.artwork = 'capsule',
    this.localImagePath,
    this.doses = const {},
    this.notificationsEnabled = true,
    this.fullScreenAlert = false,
    this.tabletsPerStrip,
  });

  final String reminderNote;
  final String artwork;
  final String? localImagePath;
  final Map<String, ScheduledQuantity> doses;
  final bool notificationsEnabled;
  final bool fullScreenAlert;
  final int? tabletsPerStrip;

  MedicationSetup copyWith({
    String? reminderNote,
    String? artwork,
    String? localImagePath,
    Map<String, ScheduledQuantity>? doses,
    bool? notificationsEnabled,
    bool? fullScreenAlert,
    int? tabletsPerStrip,
  }) => MedicationSetup(
    reminderNote: reminderNote ?? this.reminderNote,
    artwork: artwork ?? this.artwork,
    localImagePath: localImagePath ?? this.localImagePath,
    doses: doses ?? this.doses,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    fullScreenAlert: fullScreenAlert ?? this.fullScreenAlert,
    tabletsPerStrip: tabletsPerStrip ?? this.tabletsPerStrip,
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
        notificationsEnabled: data['notificationsEnabled'] != false,
        fullScreenAlert: data['fullScreenAlert'] == true,
        tabletsPerStrip: data['tabletsPerStrip'] is int &&
          data['tabletsPerStrip'] > 0 && data['tabletsPerStrip'] <= 1000
            ? data['tabletsPerStrip'] as int : null,
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
          'notificationsEnabled': setup.notificationsEnabled,
          'fullScreenAlert': setup.fullScreenAlert,
          'tabletsPerStrip': setup.tabletsPerStrip,
          'doses': {for (final e in setup.doses.entries) e.key: e.value.toJson()},
        }),
      ),
    );
  }
}
