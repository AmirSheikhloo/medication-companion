import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/calendar/persian_date.dart';
import '../../../core/calendar/persian_date_picker.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/guest_welcome_screen.dart';
import '../../profiles/presentation/profile_name_dialog.dart';
import 'medication_entry_sheet.dart';
import 'medication_detail_screen.dart';
import '../data/medication_course_repository.dart';
import '../../../core/ui/medication_controls.dart';
import 'medication_artwork.dart';
import 'medication_expiry_dialog.dart';
import 'today_visuals.dart';
import 'settings_screens.dart';
import '../data/medication_repository.dart';
import '../data/notification_inbox_repository.dart';
import '../data/medication_setup_repository.dart';
import '../data/medication_photo_storage.dart';
import '../../reminders/data/reminder_coordinator.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/data/stock_attention_repository.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../../inventory/presentation/stock_management_sheet.dart';
import '../../inventory/presentation/dose_stock_dialog.dart';
import '../../health/data/health_repository.dart';
import '../../health/presentation/health_tab.dart';
import '../../care/data/care_repository.dart';
import '../../care/presentation/care_hub_screen.dart';
import '../../care/data/care_reminder_coordinator.dart';
import '../../backup/presentation/secure_backup_screen.dart';

const _betaRunNumber = String.fromEnvironment(
  'BETA_RUN_NUMBER',
  defaultValue: 'محلی',
);
const _keyboardSettings = MethodChannel(
  'medication_companion/keyboard_settings',
);

String _normalizeMedicineSearch(String value) =>
    value.trim().toLowerCase().replaceAll('ي', 'ی').replaceAll('ك', 'ک');

class MedicationHome extends StatefulWidget {
  const MedicationHome({
    super.key,
    required this.repository,
    required this.profileRepository,
    this.reminderCoordinator,
    this.careReminderCoordinator,
    this.onThemeChanged,
    this.onPaletteChanged,
    this.clock,
  });

  final MedicationRepository repository;
  final ProfileRepository profileRepository;
  final ReminderCoordinator? reminderCoordinator;
  final CareReminderCoordinator? careReminderCoordinator;
  final Future<void> Function(bool dark)? onThemeChanged;
  final Future<void> Function(AppThemeChoice)? onPaletteChanged;
  /// Injectable clock for daypart and notification widget tests.
  final DateTime Function()? clock;

  @override
  State<MedicationHome> createState() => _MedicationHomeState();
}

class _MedicationHomeState extends State<MedicationHome>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  int _tab = 0;
  late final AnimationController _tabMotion;
  int _tabMotionDirection = 1;

  void _selectTab(int next) {
    if (next == 3) { _openMenu(); return; }
    if (_tab == next) return;
    setState(() {
      _tabMotionDirection = next > _tab ? 1 : -1;
      _tab = next;
    });
    _tabMotion.forward(from: 0);
  }
  Profile? _active;
  List<Profile> _profiles = [];
  List<Medication> _medications = [];
  List<Medication> _archivedMedications = [];
  List<Medication> _hiddenMedications = [];
  bool _showHidden = false;
  bool _showArchived = false;
  bool _searchVisible = false;
  bool _lowStockOnly = false;
  final _medicineSearch = TextEditingController();
  List<DailyDose> _doses = [];
  List<DailyDose> _nextDayDoses = [];
  Map<String, StockSummary> _stocks = {};
  Map<String, MedicationSetup> _setups = {};
  final Set<String> _expandedDoseKeys = {};
  Map<String, List<StockAttention>> _stockAttentions = {};
  Map<String, Set<String>> _dismissedAttentions = {};
  List<InboxNotice> _inbox = [];
  Future<void> _inboxTail = Future<void>.value();

  StockAttentionRepository get _attentionRepository =>
      StockAttentionRepository(widget.repository.db);
  NotificationInboxRepository get _inboxRepository =>
      NotificationInboxRepository(widget.repository.db);

  List<StockAttention> _visibleAttentions(String medicationId) =>
    _stockAttentions[medicationId] ?? [];

  int _attentionRank(Medication med) {
    final alerts = _visibleAttentions(med.id);
    return alerts.isEmpty ? 100 : alerts.first.priority;
  }

  Future<void> _refreshInbox() {
    final next = _inboxTail.then((_) => _reconcileInbox());
    _inboxTail = next;
    return next;
  }

  Future<void> _reconcileInbox() async {
    if (!mounted) return;
    final profile = _active;
    if (profile == null) return;
    try {
      final old = await _inboxRepository.load(profile.id);
      final dates = <String, DateTime>{};
      final today = _now;
      // Discover recent missed occurrences; keep checking older open notices
      // until the user resolves them, not merely until they age out.
      for (var offset = 1; offset <= 7; offset++) {
        final day = DateTime(today.year, today.month, today.day - offset);
        dates[_dayKey(day)] = day;
      }
      for (final notice in old.where((n) => n.active && n.condition.startsWith('past:'))) {
        final day = _noticeDay(notice);
        if (day != null) { dates[_dayKey(day)] = day; }
      }
      final past = <DailyDose>[];
      for (final day in dates.values) {
        past.addAll((await widget.repository.dosesForDay(profile.id, day, historical: true))
          .where((dose) => dose.status == 'pending'));
      }
      final current = <InboxNotice>[
        for (final med in _medications)
          for (final alert in _visibleAttentions(med.id))
            InboxNotice(condition: 'stock:${med.id}:${alert.key}',
              medicationId: med.id, title: '${med.name} — ${alert.title}',
              message: alert.message, urgent: alert.urgent),
        for (final dose in past)
          InboxNotice(condition: 'past:${_dayKey(dose.scheduledAt)}:${dose.occurrenceKey}',
            medicationId: dose.medication.id,
            title: '${dose.medication.name} — نوبت تعیین‌وضعیت‌نشده',
            message: '${persianDateLabel(dose.scheduledAt)}، ساعت ${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))}',
            urgent: false),
      ];
      final rows = await _inboxRepository.reconcile(profile.id, current);
      if (mounted && _active?.id == profile.id) setState(() => _inbox = rows);
    } catch (_) {
      // An inbox write failure must never block the medication screen.
    }
  }

  String _dayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  DateTime? _noticeDay(InboxNotice notice) => notice.condition.startsWith('past:')
    ? DateTime.tryParse(notice.condition.split(':')[1]) : null;

  Future<void> _chooseReviewDay() async {
    final now = _now;
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final selected = await showPersianDatePicker(context: context,
      initialDate: yesterday, firstDate: DateTime(2000),
      lastDate: yesterday, title: 'انتخاب روز گذشته');
    if (mounted && selected != null) { await _openDoseReview(selected); }
  }

  Future<void> _openDoseReview(DateTime initial, {String? target}) async {
    final profile = _active;
    if (profile == null) return;
    await Navigator.of(context).push<void>(medicationPageRoute(context,
      _PastDoseReview(
        repository: widget.repository, profileId: profile.id,
        initialDay: initial, lastDay: DateTime(_now.year, _now.month, _now.day - 1),
        target: target, onMark: _mark,
      )));
    if (mounted) { await _reload(); }
  }

  Timer? _todayClockTicker;
  String? _lastLoadedDay;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  InventoryRepository get _inventory =>
      InventoryRepository(widget.repository.db);
  MedicationSetupRepository get _setupRepository =>
      MedicationSetupRepository(widget.repository.db);
  String? _error;
  bool _remindersEnabled = false;
  String? _reminderError;
  String? _careReminderError;

  @override
  void initState() {
    super.initState();
    _tabMotion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260),
      value: 1);
    WidgetsBinding.instance.addObserver(this);
    _todayClockTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        if (_lastLoadedDay != _dayKey(_now)) {
          unawaited(_reload());
        } else if (_tab == 0) {
          setState(() {});
        }
      }
    });
    _reload();
    _syncReminders();
    _syncCareReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _todayClockTicker?.cancel();
    _tabMotion.dispose();
    _medicineSearch.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The local day may have changed while the app was in the background.
      // Refresh both today's and tomorrow's schedule, not only notifications.
      _reload();
      _syncReminders();
      _syncCareReminders();
    }
  }

  Future<void> _syncReminders() async {
    final service = widget.reminderCoordinator;
    if (service == null) return;
    try {
      await service.refreshIfEnabled();
      if (mounted) setState(() => _reminderError = null);
    } catch (error) {
      if (mounted) setState(() => _reminderError = '$error');
    }
  }

  Future<void> _syncCareReminders() async {
    final service = widget.careReminderCoordinator;
    if (service == null) return;
    try {
      await service.refreshIfEnabled();
      if (mounted) setState(() => _careReminderError = null);
    } catch (error) {
      if (mounted) setState(() => _careReminderError = '$error');
    }
  }

  Future<void> _openKeyboardSettings() async {
    try {
      await _keyboardSettings.invokeMethod<bool>('openLanguageSettings');
    } on PlatformException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'بازکردن تنظیمات کیبورد ممکن نشد؛ از تنظیمات اندروید وارد شوید.',
            ),
          ),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تنظیمات کیبورد فقط در نسخهٔ اندروید در دسترس است.'),
          ),
        );
      }
    }
  }

  Future<void> _openCareHub() async {
    final profile = _active;
    if (profile == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CareHubScreen(
          profile: profile,
          repository: CareRepository(widget.repository.db),
          reminderCoordinator: widget.careReminderCoordinator,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _reload() async {
    // Keep the current list mounted during dose updates: its scroll position
    // and expansion animation should survive the reordering of saved doses.
    try {
      final profile = await widget.profileRepository.activeProfile();
      final profiles = await widget.profileRepository.profiles();
      final meds = profile == null
          ? <Medication>[]
          : await widget.repository.medicationsFor(profile.id);
      final archivedMeds = profile == null
          ? <Medication>[]
          : await widget.repository.medicationsFor(profile.id, archived: true);
      final hiddenMeds = profile == null
          ? <Medication>[] : await widget.repository.hiddenMedicationsFor(
              profile.id);
      final today = _now;
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final doses = profile == null
          ? <DailyDose>[]
          : await widget.repository.dosesForDay(profile.id, today);
      final nextDayDoses = profile == null
          ? <DailyDose>[]
          : await widget.repository.dosesForDay(profile.id, tomorrow);
      final stocks = <String, StockSummary>{};
      final setups = <String, MedicationSetup>{};
      if (profile != null) {
        for (final med in meds) {
          stocks[med.id] = await _inventory.summary(profile.id, med.id);
          setups[med.id] = await _setupRepository.read(profile.id, med.id);
        }
        for (final med in [...archivedMeds, ...hiddenMeds]) {
          stocks[med.id] = await _inventory.summary(profile.id, med.id);
          setups[med.id] = await _setupRepository.read(profile.id, med.id);
        }
      }
      final attentions = <String, List<StockAttention>>{};
      final dismissed = <String, Set<String>>{};
      if (profile != null) {
        for (final med in meds) {
          final alerts = StockAttention.evaluate(stocks[med.id],
            setups[med.id]?.expiryLeadDays, today);
          attentions[med.id] = alerts;
          dismissed[med.id] = await _attentionRepository.reconcile(
            profile.id, med.id, alerts);
        }
      }
      final remindersEnabled =
          await widget.reminderCoordinator?.isEnabled() ?? false;
      if (!mounted) return;
      setState(() {
        if (_active?.id != profile?.id) {
          _inbox = [];
          _medicineSearch.clear();
          _searchVisible = false;
          _lowStockOnly = false;
          _showHidden = false;
          _showArchived = false;
        }
        _active = profile;
        _profiles = profiles;
        _medications = meds;
        _archivedMedications = archivedMeds;
        _hiddenMedications = hiddenMeds;
        _doses = doses;
        _lastLoadedDay = _dayKey(today);
        _nextDayDoses = nextDayDoses;
        _stocks = stocks;
        _stockAttentions = attentions;
        _dismissedAttentions = dismissed;
        _setups = setups;
        _remindersEnabled = remindersEnabled;
        _loading = false;
        _error = null;
      });
      await _refreshInbox();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاری اطلاعات انجام نشد: $error';
        _loading = false;
      });
    }
  }

  Future<void> _startGuest(bool forSelf, {String? selfName}) async {
    if (_saving) return;
    String? name = selfName;
    if (!forSelf) {
      name = await askProfileNameDialog(context);
      if (!mounted || name == null) return;
    }
    await _perform(
      () => widget.profileRepository.createGuestProfile(
        forSelf: forSelf,
        displayName: name,
      ),
    );
  }

  Future<void> _reminderTail = Future<void>.value();

  void _queueReminderRefresh() {
    _reminderTail = _reminderTail.then((_) async {
      try {
        await widget.reminderCoordinator?.refreshIfEnabled();
        if (mounted) setState(() => _reminderError = null);
      } catch (error) {
        if (mounted) {
          setState(() => _reminderError = '$error');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تغییر ذخیره شد ولی یادآور به‌روز نشد: $error')));
        }
      }
    });
  }

  Future<void> _perform(Future<dynamic> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      await _reload();
      _queueReminderRefresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ذخیره انجام نشد: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _requestMedicationReminderPermission(
      {bool fullScreen = false}) async {
    final coordinator = widget.reminderCoordinator;
    if (coordinator == null) return false;
    return coordinator.requestPermissionsForDraft(fullScreen: fullScreen);
  }

  /// Saving a medication is authoritative; OS reminder permission errors must
  /// not turn an already committed medication into a misleading save failure.
  Future<void> _activateSavedMedicationReminders() async {
    try {
      await widget.reminderCoordinator?.enable();
      if (mounted) setState(() => _reminderError = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _reminderError = '$error');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('دارو ذخیره شد؛ اما یادآور فعال نشد: $error'),
      ));
    }
  }

  Future<void> _addMedication() async {
    final profile = _active;
    if (profile == null || _saving) return;
    final draft = await showMedicationEntrySheet(
      context,
      profileName: profile.displayName,
      requestReminderPermission: _requestMedicationReminderPermission,
      suggestedMedicationNames: [
        for (final med in [..._medications, ..._archivedMedications,
          ..._hiddenMedications]) med.name,
      ],
    );
    if (!mounted || draft == null) return;
    await _perform(() async {
      // Photos must survive the temporary Android gallery cache.
      final photoPath = draft.imagePath == null ? null
          : await const MedicationPhotoStorage().store(draft.imagePath!);
      await widget.repository.db.transaction(() async {
        final medicationId = await widget.repository.addMedicationSchedule(
          profileId: profile.id,
          name: draft.name,
          slots: _slotInputs(draft),
        );
        if (draft.packages.isNotEmpty) {
          await (widget.repository.db.update(widget.repository.db.medications)
                ..where((m) => m.id.equals(medicationId) &
                    m.profileId.equals(profile.id)))
              .write(MedicationsCompanion(
                unit: Value(draft.packages.first.unit)));
        }
        for (final package in draft.packages) {
          await _inventory.addPackage(
            profileId: profile.id,
            medicationId: medicationId,
            label: package.label,
            unit: package.unit,
            initialMilliunits: package.initialMilliunits,
            expiryIso: package.expiry == null ? null
                : StockQuantity.isoDate(package.expiry!),
            expiryPrecision: package.expiry == null ? 'none' : 'day',
          );
        }
        await _saveSetupForPlan(profile.id, medicationId, draft,
          const MedicationSetup(), localPhotoPath: photoPath);
        if (draft.lowStockThresholdMilliunits != null) {
          await _inventory.setLowStockThreshold(profileId: profile.id,
            medicationId: medicationId,
            thresholdMilliunits: draft.lowStockThresholdMilliunits);
        }
      });
    });
    if (draft.notificationsEnabled || draft.fullScreenAlert) {
      await _activateSavedMedicationReminders();
    }
  }

  List<DoseSlotInput> _slotInputs(MedicationDraft draft) => [
    for (final slot in draft.slots) DoseSlotInput(
      doseText: slot.dose,
      time: TimeOfDayValue(slot.time.hour, slot.time.minute),
    ),
  ];

  /// Bind exact quantities to immutable plan IDs, never merely to a clock.
  /// A changed schedule starts tomorrow; previous recorded doses keep their
  /// original quantity, even after a later edit.
  Future<void> _saveSetupForPlan(String profileId, String medicationId,
      MedicationDraft draft, MedicationSetup previous,
      {String? localPhotoPath}) async {
    final db = widget.repository.db;
    final plans = await (db.select(db.medicationPlanVersions)
          ..where((p) => p.medicationId.equals(medicationId)))
        .get();
    final version = plans.map((p) => p.version).reduce(
      (a, b) => a > b ? a : b);
    final doses = Map<String, ScheduledQuantity>.of(previous.doses);
    for (final slot in draft.slots) {
      final matched = plans.where((p) => p.version == version &&
          p.hour == slot.time.hour && p.minute == slot.time.minute);
      if (matched.length != 1) {
        throw StateError('برنامهٔ مصرف ذخیره شد اما شناسهٔ نوبت یکتا نیست.');
      }
      if (slot.quantity != null) {
        doses.putIfAbsent(matched.single.id, () => slot.quantity!);
      }
    }
    await _setupRepository.save(profileId: profileId,
      medicationId: medicationId,
      setup: MedicationSetup(
        doses: doses,
        artwork: draft.artwork,
        localImagePath: localPhotoPath ?? previous.localImagePath,
        reminderNote: draft.reminderNote,
        notificationsEnabled: draft.notificationsEnabled,
        fullScreenAlert: draft.fullScreenAlert,
        expiryLeadDays: draft.expiryLeadDays,
        tabletsPerStrip: draft.tabletsPerStrip ?? previous.tabletsPerStrip,
      ));
  }

  Future<void> _editMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final doses = await widget.repository.dosesForMedicationOnDay(
      profile.id,
      medication.id,
      tomorrow,
    );
    final previous = await _setupRepository.read(profile.id, medication.id);
    if (!mounted) return;
    final draft = await showMedicationEntrySheet(
      context,
      profileName: profile.displayName,
      requestReminderPermission: _requestMedicationReminderPermission,
      initialName: medication.name,
      initialSetup: previous,
      initialThresholdMilliunits: _stocks[medication.id]?.thresholdMilliunits,
      initialBaseUnit: medication.unit,
      initialExpiryDates: [
        for (final package in _stocks[medication.id]?.packages ?? <PackageBalance>[])
          if (!package.archived && package.package.expiryIso != null)
            StockQuantity.expiryDay(package.package.expiryIso!,
              package.package.expiryPrecision),
      ],
      initialSlots: [
        for (final dose in doses)
          MedicationSlotDraft(
            dose: dose.plan.doseText,
            time: TimeOfDay.fromDateTime(dose.scheduledAt),
            quantity: previous.doses[dose.plan.id],
          ),
      ],
    );
    if (!mounted || draft == null) return;
    if (draft.name.trim() != medication.name.trim()) {
      final sameIdentity = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('اصلاح نام یا داروی متفاوت؟'),
          content: const Text('فقط اگر نام همان دارو با همان ماده مؤثره، '
            'قدرت و شکل دارویی را اصلاح می‌کنی، ادامه بده. '
            'برای داروی متفاوت یا قدرت دیگر، یک داروی جدید ثبت کن؛ '
            'بسته‌ها و سوابق قدیمی نباید منتقل شوند.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('داروی متفاوت / قدرت دیگر')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('اصلاح نام همان دارو')),
          ]));
      if (!mounted || sameIdentity == null) return;
      if (!sameIdentity) {
        await _addMedication();
        return;
      }
    }
    await _perform(() async {
      final photoPath = draft.imagePath == null ? null
          : await const MedicationPhotoStorage().store(draft.imagePath!);
      await widget.repository.db.transaction(() async {
        await widget.repository.updateMedicationSchedule(
          profileId: profile.id,
          medicationId: medication.id,
          name: draft.name,
          slots: _slotInputs(draft),
        );
        await _saveSetupForPlan(profile.id, medication.id, draft,
          previous, localPhotoPath: photoPath);
        await _inventory.setLowStockThreshold(profileId: profile.id,
          medicationId: medication.id,
          thresholdMilliunits: draft.lowStockThresholdMilliunits);
      });
    });
    if (draft.notificationsEnabled || draft.fullScreenAlert) {
      await _activateSavedMedicationReminders();
    }
  }

  Future<void> _archiveMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پایان مصرف دارو'),
        content: Text(
          'با پایان مصرف «${medication.name}»، نوبت‌های آینده متوقف می‌شوند. '
          'سوابق پاک نمی‌شوند و بعداً می‌توانید دارو را بازیابی کنید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('پایان مصرف'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _perform(
      () => widget.repository.setArchived(
        profileId: profile.id,
        medicationId: medication.id,
        archived: true,
      ),
    );
    // Verify the write committed before presenting any summary.
    final updated = await (widget.repository.db.select(
      widget.repository.db.medications)
      ..where((t) => t.id.equals(medication.id) &
        t.profileId.equals(profile.id))).getSingleOrNull();
    if (!mounted || updated == null || !updated.archived) return;
    final report = await MedicationCourseRepository(
      widget.repository.db).report(updated);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppPalette.surface(context, AppColors.background),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25)),
        title: Row(children: [
          Icon(Icons.verified_rounded, color: AppPalette.ink(context, AppColors.success)),
          SizedBox(width: 8),
          Expanded(child: Text('خلاصهٔ پایان مصرف',
            style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
              fontWeight: FontWeight.w900))),
        ]),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(PersianDate.displayDigits(updated.name),
              style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
                fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 10),
            Text('از ${persianDateLabel(report.started)}'
              ' تا ${persianDateLabel(report.ended ?? DateTime.now())}'),
            const SizedBox(height: 7),
            Text('${report.days} روز از شروع دوره',
              style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
                fontWeight: FontWeight.w800)),
            const Divider(height: 25),
            Text('ثبت مصرف‌شده: ${report.taken} نوبت'),
            Text('ثبت مصرف‌نشده: ${report.skipped} نوبت'),
            Text('وضعیت نامطمئن: ${report.unknown} نوبت'),
            const SizedBox(height: 10),
            Text('کسر واقعی از موجودی: '
              '${StockQuantity.format(report.stockDebitedMilliunits)} '
              '${updated.unit}',
              style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
                fontWeight: FontWeight.w800)),
            if (updated.unit == 'عدد' &&
                report.tabletsPerStrip != null) ...[
              const SizedBox(height: 5),
              Text('تقریباً ${(report.stockDebitedMilliunits / 1000 / report.tabletsPerStrip!).toStringAsFixed(1)} '
                'ورق (${report.tabletsPerStrip} عدد در هر ورق)'),
            ],
            const SizedBox(height: 10),
            Text('این گزارش از ثبت‌های واقعی استخراج شده است؛ '
              'مصرف بدون کسر موجودی به مقدار کسرشده اضافه نمی‌شود. '
              'سوابق برای گزارش پزشک محفوظ هستند.',
              style: TextStyle(color: AppPalette.ink(context, AppColors.muted), fontSize: 12)),
          ],
        )),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('مشاهده بعداً در پرونده'),
          ),
        ],
      ),
    );
  }

  Future<void> _hideMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppPalette.surface(context, AppColors.background),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
        title: const Text('حذف دارو از فهرست'),
        content: Text('«${medication.name}» از فهرست فعال و پایان‌یافته '
          'پنهان می‌شود، اما سوابق مصرف، بسته‌ها و گزارش پزشک محفوظ می‌مانند. '
          'هر زمان می‌توانی از بخش حذف‌شده‌ها آن را بازیابی کنی.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.surface(context, const Color(0xFFB6374C)),
              foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف از فهرست')),
        ],
      ),
    );
    if (!mounted || allowed != true) return;
    await _perform(() => widget.repository.setHidden(
      profileId: profile.id,
      medicationId: medication.id, hidden: true));
    if (!mounted || !_hiddenMedications.any((m) => m.id == medication.id)) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('دارو از فهرست حذف شد؛ سوابق محفوظ است.'),
      action: SnackBarAction(label: 'بازگردانی', onPressed: () async {
        if (_active?.id != profile.id || _saving) return;
        await _perform(() => widget.repository.db.transaction(() async {
          await widget.repository.setHidden(profileId: profile.id,
            medicationId: medication.id, hidden: false);
          await widget.repository.setArchived(profileId: profile.id,
            medicationId: medication.id, archived: medication.archived);
        }));
      })));
  }

  Future<void> _unhideMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    await _perform(() => widget.repository.setHidden(
      profileId: profile.id, medicationId: medication.id, hidden: false));
    if (mounted) {
      setState(() {
        _showHidden = false;
        _showArchived = true;
      });
    }
  }

  Future<void> _restoreMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    await _perform(
      () => widget.repository.setArchived(
        profileId: profile.id,
        medicationId: medication.id,
        archived: false,
      ),
    );
    if (mounted) setState(() { _showArchived = false; _showHidden = false; });
  }

  Future<void> _enableReminders() async {
    final service = widget.reminderCoordinator;
    if (service == null) return;
    await _perform(() => service.enable());
  }

  Future<void> _disableReminders() async {
    final service = widget.reminderCoordinator;
    if (service == null) return;
    await _perform(() => service.disable());
  }

  Future<void> _testReminders() async {
    final service = widget.reminderCoordinator;
    if (service == null) return;
    await _perform(() async {
      await service.demoInFiveSeconds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اعلان تستی برای 5 ثانیه دیگر ثبت شد.')),
        );
      }
    });
  }

  Future<void> _openStock(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    await showStockManagementSheet(
      context,
      repository: _inventory,
      medication: medication,
      profileId: profile.id,
    );
    if (mounted) await _reload();
  }

  Future<void> _packageAction(Medication medication, PackageBalance balance,
      String action) async {
    final profile = _active;
    if (!mounted || profile == null || _saving) return;
    final package = balance.package;
    if (action == 'stock') {
      await _openStock(medication);
      return;
    }
    if (action == 'edit') {
      final name = TextEditingController(text: package.label);
      DateTime? expiry = package.expiryIso == null
          ? null : StockQuantity.parseIso(package.expiryIso!);
      final edited = await showDialog<({String label, DateTime? expiry})>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) =>
          AlertDialog(
            title: const Text('ویرایش مشخصات بسته'),
            content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: name, maxLength: 80,
                  decoration: const InputDecoration(labelText: 'نام بسته')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final chosen = await showMedicationExpiryDialog(context,
                      initialDate: expiry);
                    if (chosen != null) setDialogState(() => expiry = chosen);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(expiry == null ? 'افزودن تاریخ انقضا' :
                    'تاریخ انقضا: ${persianDateLabel(expiry!)}'),
                ),
                if (expiry != null) TextButton(
                  onPressed: () => setDialogState(() => expiry = null),
                  child: const Text('برداشتن تاریخ انقضا')),
              ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext,
                (label: name.text.trim(), expiry: expiry)),
                child: const Text('ذخیره تغییرات')),
            ],
          )),
      );
      name.dispose();
      if (!mounted || edited == null) return;
      await _perform(() => _inventory.editPackage(
        profileId: profile.id, medicationId: medication.id,
        packageId: package.id, label: edited.label,
        expiryIso: edited.expiry == null ? null :
          StockQuantity.isoDate(edited.expiry!),
        expiryPrecision: edited.expiry == null ? 'none' : 'day'));
      return;
    }
    if (action == 'delete' && (await _inventory.movementsForPackage(
      profileId: profile.id, medicationId: medication.id,
      packageId: package.id)).isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('این بسته سابقهٔ موجودی یا مصرف دارد. برای حفظ سوابق '
            'آن را بایگانی کن؛ حذف دائمی مجاز نیست.')));
      }
      return;
    }
    if (!mounted) { return; }
    if (action == 'archive' || action == 'delete') {
      final confirm = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(action == 'archive' ? 'بایگانی بسته؟' : 'حذف بسته؟'),
          content: Text(action == 'archive'
            ? 'سوابق باقی می‌ماند و دیگر از این بسته موجودی کسر نمی‌شود.'
            : 'این بسته سابقه‌ای ندارد و به‌صورت دائمی حذف خواهد شد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأیید')),
          ]));
      if (!mounted || confirm != true) return;
    }
    await _perform(() => switch (action) {
      'archive' => _inventory.archivePackage(profileId: profile.id,
        medicationId: medication.id, packageId: package.id),
      'restore' => _inventory.restorePackage(profileId: profile.id,
        medicationId: medication.id, packageId: package.id),
      'delete' => _inventory.deleteUnusedPackage(profileId: profile.id,
        medicationId: medication.id, packageId: package.id),
      _ => Future<void>.value(),
    });
  }

  Future<void> _mark(DailyDose dose, String action) async {
    final profile = _active;
    if (profile == null || _saving || dose.medication.profileId != profile.id) return;
    final noStockDeduction = action == 'takenWithoutStock';
    DoseStockChoice? choice;
    if (action == 'taken') {
      final stock = await _inventory.summary(profile.id, dose.medication.id);
      if (!mounted) return;
      final configured = _setups[dose.medication.id]?.doses[dose.plan.id];
      if (configured == null) {
        // Legacy free-text instructions cannot safely imply a quantity.
        choice = await askDoseStockChoice(context,
          medicationName: dose.medication.name, stock: stock);
      } else {
        final selected = stock.selected;
        if (selected == null || selected.expired) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('بستهٔ معتبر برای کسر موجودی انتخاب نشده است. '
              'از جزئیات دارو بستهٔ مناسب را انتخاب کن.')));
          return;
        }
        final quantity = MedicationUnits.toPackageMilliunits(
          configured, selected.package.unit);
        if (quantity == null || quantity <= 0 ||
            quantity > StockQuantity.maxMilliunits) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('واحد مصرف با واحد بسته سازگار نیست؛ '
              'موجودی را بررسی کن.')));
          return;
        }
        if (quantity > selected.balanceMilliunits) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('موجودی بسته برای این نوبت کافی نیست؛ '
              'بسته را تغییر بده یا مصرف را بدون کسر ثبت کن.')));
          return;
        }
        choice = DoseStockChoice.debit(selected.package.id, quantity);
      }
      if (!mounted || choice == null) return;
    }
    // A saved dose moves to the completed section in its compact state.
    // Undo deliberately keeps the panel open, ready for a corrected choice.
    if (action != 'undo') {
      setState(() => _expandedDoseKeys.remove(dose.occurrenceKey));
    }
    await _perform(
      () => widget.repository.recordDose(
        dose: dose,
        profileId: profile.id,
        action: noStockDeduction ? 'taken' : action,
        stockPackageId: choice?.packageId,
        stockQuantityMilliunits: choice?.quantityMilliunits,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('تلاش مجدد'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_active == null) {
      return GuestWelcomeScreen(
        onSelf: _saving ? null : () => _startGuest(true),
        onSelfNamed: _saving ? null : (name) => _startGuest(true, selfName: name),
        onLovedOne: _saving ? null : () => _startGuest(false),
      );
    }
    return Scaffold(
      backgroundColor: AppPalette.selected(context) != null
        ? AppPalette.surface(context, AppColors.background)
        : AppPalette.isDark(context) ? AppPalette.darkBackground :
          _tab == 0 ? TodayPalette.page : AppColors.background,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _tabMotion,
          builder: (context, child) {
            if (MediaQuery.of(context).disableAnimations) return child!;
            final progress = Curves.easeOutCubic.transform(_tabMotion.value);
            return Opacity(
              opacity: .4 + .6 * progress,
              child: Transform.translate(
                offset: Offset((1 - progress) * 14 * _tabMotionDirection, 0),
                child: child),
            );
          },
          child: IndexedStack(index: _tab, children: [
            _todayTab(),
            _medicinesTab(),
            HealthTab(
              key: ValueKey(_active!.id),
              profile: _active!,
              repository: HealthRepository(widget.repository.db),
              onOpenCareHub: _openCareHub,
            ),
          ]),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _tab,
        onSelected: _selectTab,
      ),
    );
  }

  Widget _profileBar() {
    return Material(
      color: AppPalette.surface(context, AppColors.lightMint),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const Key('today-profile-selector'),
        onTap: _saving ? null : _showProfilePicker,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 176, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppPalette.surface(context, AppColors.outline)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_outline_rounded, color: AppPalette.ink(context, AppColors.primary), size: 21),
            const SizedBox(width: 6),
            Flexible(child: Text(
              _active!.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Vazirmatn',
                fontSize: 14, fontWeight: FontWeight.bold,
                color: AppPalette.ink(context, AppColors.primaryDark)),
            )),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded,
              color: AppPalette.ink(context, AppColors.primary), size: 20),
          ]),
        ),
      ),
    );
  }

  Future<void> _showProfilePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppPalette.surface(context, Colors.white),
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('انتخاب شخص', textAlign: TextAlign.right,
                style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 21,
                  fontWeight: FontWeight.bold, color: AppPalette.ink(context, AppColors.primaryDark))),
              const SizedBox(height: 5),
              Text('برنامه و اطلاعات هر شخص جدا نگه داشته می‌شود.',
                style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 13,
                  color: AppPalette.ink(context, AppColors.muted))),
              const SizedBox(height: 16),
              for (final profile in _profiles) ...[
                Material(
                  color: profile.id == _active?.id
                      ? AppPalette.surface(context, AppColors.mint) : AppPalette.surface(context, AppColors.background),
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: () => Navigator.pop(sheetContext, profile.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 12),
                      child: Row(children: [
                        CircleAvatar(radius: 20, backgroundColor: AppPalette.surface(context, Colors.white),
                          child: Icon(Icons.person_outline,
                            color: AppPalette.ink(context, AppColors.primary))),
                        const SizedBox(width: 10),
                        Expanded(child: Text(PersianDate.displayDigits(profile.displayName),
                          style: TextStyle(fontFamily: 'Vazirmatn',
                            fontSize: 16, fontWeight: FontWeight.bold,
                            color: AppPalette.ink(context, AppColors.primaryDark)))),
                        Icon(profile.id == _active?.id
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                          color: profile.id == _active?.id
                            ? AppPalette.ink(context, AppColors.primary) : AppPalette.ink(context, AppColors.muted)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
              ],
            ]),
        ),
      ),
    );
    if (!mounted || selected == null || selected == _active?.id) return;
    setState(() => _expandedDoseKeys.clear());
    await _perform(() => widget.profileRepository.selectActiveProfile(selected));
  }

  Future<void> _toggleTheme() async {
    try {
      await widget.onThemeChanged?.call(!AppPalette.isDark(context));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تنظیم ظاهر ذخیره نشد.')));
      }
    }
  }

  Widget _themeToggle() => IconButton.filledTonal(
    key: const Key('app-theme-toggle'),
    tooltip: AppPalette.isDark(context) ? 'حالت روشن' : 'حالت تاریک',
    onPressed: _toggleTheme,
    icon: Icon(AppPalette.isDark(context)
      ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      color: AppPalette.ink(context, AppColors.primary)),
  );

  Widget _todayTab() {
    final taken = _doses.where((dose) => dose.status == 'taken').length;
    final pending = _doses.where((dose) => dose.status == 'pending').length;
    final skipped = _doses.where((dose) => dose.status == 'skipped').length;
    final unknown = _doses.where((dose) => dose.status == 'unknown').length;
    final now = _now;
    final waiting = _doses.where((dose) => dose.status == 'pending').toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final finished = _doses.where((dose) => dose.status != 'pending').toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final morning = waiting
        .where((dose) => dose.scheduledAt.hour >= 5 && dose.scheduledAt.hour < 11)
        .toList();
    final afternoon = waiting
        .where((dose) => dose.scheduledAt.hour >= 11 && dose.scheduledAt.hour < 17)
        .toList();
    final evening = waiting
        .where((dose) => dose.scheduledAt.hour >= 17 || dose.scheduledAt.hour < 5)
        .toList();
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Vazirmatn'),
      child: ListView(
        key: const Key('today-scroll-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Row(children: [
            Expanded(child: Text('همراه دارو',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 18,
                fontWeight: FontWeight.bold, color: AppPalette.ink(context, AppColors.primaryDark)))),
            const SizedBox(width: 10),
            _profileBar(),
            const SizedBox(width: 8),
            _todayNotificationBell(),
          ]),
          const SizedBox(height: 16),
          TodaySkyGreeting(hour: now.hour, name: _active!.displayName),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _chooseReviewDay,
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('بررسی نوبت‌های روزهای گذشته')),
          const SizedBox(height: 14),
          AppPanel(
            key: const Key('today-summary-panel'),
            color: TodayPalette.summary,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
            child: Column(children: [
              Row(key: const Key('today-date-heading'), children: [
                Expanded(child: Text('خلاصهٔ امروز',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppPalette.ink(context, AppColors.primaryDark)))),
                const SizedBox(width: 7),
                Icon(Icons.calendar_today_outlined,
                  color: AppPalette.ink(context, AppColors.primary), size: 17),
                const SizedBox(width: 5),
                Text(todayReadablePersianDate(now),
                  style: TextStyle(fontFamily: 'Vazirmatn',
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppPalette.ink(context, AppColors.muted))),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                TodayStatusRing(statuses: [for (final dose in _doses) dose.status],
                  size: 88),
                const SizedBox(width: 17),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(PersianDate.displayDigits(
                      '$taken از ${_doses.length} نوبت مصرف شده'),
                      style: TextStyle(fontFamily: 'Vazirmatn',
                        fontSize: 13, color: AppPalette.ink(context, AppColors.ink))),
                    const SizedBox(height: 12),
                    Row(children: [
                      for (final dose in _doses)
                        Expanded(child: Container(
                          height: 8,
                          margin: const EdgeInsetsDirectional.only(end: 4),
                          decoration: BoxDecoration(
                            color: todayDoseStatusColor(dose.status),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        )),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, runSpacing: 4, children: [
                      if (pending > 0 || _doses.isEmpty)
                        _todayStatusLegend('$pending ثبت‌نشده',
                          todayDoseStatusColor('pending')),
                      if (taken > 0)
                        _todayStatusLegend('$taken مصرف شد',
                          todayDoseStatusColor('taken')),
                      if (skipped > 0)
                        _todayStatusLegend('$skipped مصرف نشد',
                          todayDoseStatusColor('skipped')),
                      if (unknown > 0)
                        _todayStatusLegend('$unknown نامشخص',
                          todayDoseStatusColor('unknown')),
                    ]),
                  ],
                )),
              ]),
            ]),
          ),
          if (_doses.isEmpty) ...[
            const SizedBox(height: 14),
            _emptyCard(
              'هنوز دارویی ثبت نکرده‌اید.',
              'برای شروع، دارو و زمان آن را طبق نسخه وارد کنید.',
              'افزودن اولین دارو',
              () => setState(() => _tab = 1),
            ),
          ] else ...[
            const SizedBox(height: 21),
            Text('برنامهٔ مصرف امروز',
              style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 20,
                fontWeight: FontWeight.bold, color: AppPalette.ink(context, AppColors.primaryDark))),
            const SizedBox(height: 12),
            if (morning.isNotEmpty)
              _todayDoseGroup('صبح', Icons.wb_sunny_rounded, morning),
            if (afternoon.isNotEmpty)
              _todayDoseGroup('ظهر', Icons.light_mode_rounded, afternoon),
            if (evening.isNotEmpty)
              _todayDoseGroup('عصر و شب', Icons.nights_stay_rounded, evening),
            if (finished.isNotEmpty)
              _todayDoseGroup('ثبت‌شده‌ها', Icons.task_alt_rounded,
                finished, recorded: true),
          ],
          const SizedBox(height: 7),
          AppGradientButton(label: 'افزودن داروی جدید', icon: Icons.add_rounded,
            onPressed: _saving ? null : _addMedication, light: false,
            height: 52),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: _openCareHub,
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('پیگیری‌ها و چک‌لیست ویزیت')),
        ],
      ),
    );
  }

  Widget _todayStatusLegend(String description, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 7, height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(PersianDate.displayDigits(description),
        style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 11.5,
          color: AppPalette.ink(context, AppColors.ink))),
    ],
  );

  Widget _todayNotificationBell() {
    final unread = _inbox.where((n) => n.active && !n.read).length;
    return Stack(clipBehavior: Clip.none, children: [
      Material(
        key: const Key('today-bell-surface'),
        color: Colors.transparent, borderRadius: BorderRadius.circular(17),
        child: Ink(
          key: const Key('today-bell-fill'),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              TodayPalette.bellHighlight, TodayPalette.bellShadow]),
            borderRadius: BorderRadius.circular(17)),
          child: IconButton(
            key: const Key('today-notifications-button'),
            tooltip: 'اعلان‌ها',
            icon: const Icon(Icons.notifications_rounded,
              color: Color(0xFF966000), size: 26),
            onPressed: _showTodayNotifications,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ))),
      if (unread > 0)
        Positioned(top: -4, left: -4, child: Container(
          key: const Key('today-unread-dot'),
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFC5223B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 1.5)),
          child: Text(unread > 99 ? '99+' : '$unread',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.bold)))),
    ]);
  }

  Future<void> _showTodayNotifications() async {
    final profile = _active;
    if (profile == null) return;
    await _refreshInbox();
    if (!mounted || _active?.id != profile.id) return;
    var limit = 20;
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true, useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (ctx, update) {
        final sorted = [..._inbox]..sort((a, b) {
          final active = (b.active ? 1 : 0).compareTo(a.active ? 1 : 0);
          if (active != 0) { return active; }
          final read = (a.read ? 1 : 0).compareTo(b.read ? 1 : 0);
          return read != 0 ? read : int.parse(b.id).compareTo(int.parse(a.id));
        });
        return SizedBox(height: MediaQuery.sizeOf(ctx).height * .76,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text('اعلان‌ها', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (sorted.isEmpty) const Text('اعلانی برای نمایش وجود ندارد.'),
              for (final notice in sorted.take(limit))
                Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: AppPanel(color: !notice.active ? const Color(0xFFE7EBF0)
                    : notice.urgent ? const Color(0xFFFFE4E9)
                    : const Color(0xFFE5EFFF), child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(PersianDate.displayDigits(notice.title),
                          style: TextStyle(fontWeight: FontWeight.w800,
                            color: AppPalette.ink(ctx, !notice.active ? AppColors.muted
                              : notice.urgent ? const Color(0xFFBE123C) : const Color(0xFF1D4ED8)))),
                        const SizedBox(height: 6),
                        Text(PersianDate.displayDigits(notice.message),
                          style: TextStyle(color: AppPalette.ink(ctx,
                            notice.active ? AppColors.ink : AppColors.muted))),
                        if (!notice.active) const Text('برطرف شده؛ نیاز به اقدام ندارد'),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                            onPressed: !notice.active ? null : () async {
                              await _reload();
                              if (!mounted || !sheetContext.mounted ||
                                  _active?.id != profile.id) { return; }
                              if (!_inbox.any((n) => n.id == notice.id && n.active)) {
                                update(() {}); return;
                              }
                              final day = _noticeDay(notice);
                              if (day != null) {
                                Navigator.pop(sheetContext);
                                await _openDoseReview(day, target: notice.condition.split(':').skip(2).join(':'));
                                return;
                              }
                              final meds = _medications.where((m) => m.id == notice.medicationId);
                              if (meds.isEmpty) { return; }
                              final med = meds.first;
                              Navigator.pop(sheetContext);
                              final today = _doses.where((d) => d.medication.id == med.id).toList();
                              final next = _nextDayDoses.where((d) => d.medication.id == med.id).toList();
                              await _openMedicationDetail(med, next.isNotEmpty ? next : today,
                                today, _stocks[med.id], next.isNotEmpty &&
                                next.first.plan.effectiveFrom.toLocal().isAfter(_now));
                            },
                            icon: Icon(notice.condition.startsWith('past:')
                              ? Icons.edit_calendar_outlined : Icons.medication_outlined),
                            label: Text(notice.condition.startsWith('past:') ? 'تعیین وضعیت' : 'جزئیات دارو')),
                          OutlinedButton(
                            onPressed: notice.read || !notice.active ? null : () async {
                              try {
                                await _inboxRepository.markRead(profile.id, notice.id);
                                await _refreshInbox();
                                if (ctx.mounted) { update(() {}); }
                              } catch (_) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('وضعیت خواندن ذخیره نشد.')));
                                }
                              }
                            },
                            child: Text(!notice.active ? 'برطرف شده' : notice.read ? 'خوانده شده' : 'خواندم')),
                        ]),
                      ]))),
              if (sorted.length > limit) OutlinedButton(
                onPressed: () => update(() => limit += 20),
                child: const Text('نمایش 20 مورد بیشتر')),
            ]));
      }));
  }

  Widget _todayDoseGroup(String label, IconData icon,
    List<DailyDose> doses, {bool recorded = false}) {
    final headerColor = recorded
        ? AppPalette.tone(context, const Color(0xFFEAF0F1))
        : AppPalette.surface(context, TodayPalette.dayPartHeader);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppPalette.surface(context, Colors.white),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: BorderSide(color: AppPalette.surface(context, AppColors.outline)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            key: Key('today-group-header-$label'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            color: headerColor,
            child: Row(children: [
              Transform.flip(
                flipX: label == 'عصر و شب',
                child: Icon(icon, size: 22,
                  color: recorded ? AppPalette.ink(context, AppColors.primary)
                      : label == 'عصر و شب' ? AppPalette.ink(context, AppColors.primary)
                      : AppPalette.tone(context, const Color(0xFFBD871F))),
              ),
              const SizedBox(width: 9),
              Text(label, style: TextStyle(fontFamily: 'Vazirmatn',
                fontSize: 16, fontWeight: FontWeight.bold,
                color: AppPalette.ink(context, AppColors.primaryDark))),
              const Spacer(),
              Text(PersianDate.displayDigits('${doses.length} نوبت'),
                style: TextStyle(fontFamily: 'Vazirmatn',
                  color: AppPalette.ink(context, AppColors.ink), fontSize: 13)),
            ]),
          ),
          for (var i = 0; i < doses.length; i++) ...[
            if (i != 0) Divider(
              height: 1, indent: 13, endIndent: 13,
              color: AppPalette.surface(context, AppColors.outline)),
            _doseCard(doses[i]),
          ],
        ]),
      ),
    );
  }

  Widget _doseCard(DailyDose dose) {
    final due = !dose.scheduledAt.isAfter(_now);
    final expanded = _expandedDoseKeys.contains(dose.occurrenceKey);
    final status = switch (dose.status) {
      'taken' => ('مصرف شد', Icons.check_circle_rounded, AppPalette.ink(context, AppColors.success)),
      'skipped' => ('مصرف نشد', Icons.cancel_rounded,
          AppPalette.tone(context, const Color(0xFFC23F43))),
      'unknown' => ('مطمئن نیستم', Icons.help_rounded,
          AppPalette.tone(context, const Color(0xFF1D4ED8))),
      _ => ('', Icons.schedule_rounded, AppPalette.ink(context, AppColors.muted)),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      color: AppPalette.surface(context, todayDoseCardBackground(dose.status)),
      child: Column(children: [
        InkWell(
        key: Key('today-dose-${dose.occurrenceKey}'),
        onTap: _saving ? null : () => setState(() {
          if (expanded) {
            _expandedDoseKeys.remove(dose.occurrenceKey);
          } else {
            _expandedDoseKeys.add(dose.occurrenceKey);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(children: [
            MedicationArtwork(name: dose.medication.name,
              setup: _setups[dose.medication.id], size: 45),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(PersianDate.displayDigits(dose.medication.name),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Vazirmatn',
                    fontSize: 16, fontWeight: FontWeight.bold,
                    height: 1.45, color: AppPalette.ink(context, AppColors.ink))),
                const SizedBox(height: 2),
                Wrap(spacing: 6, runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.access_time_rounded,
                      size: 15, color: AppPalette.ink(context, AppColors.muted)),
                    Text(_clock(TimeOfDay.fromDateTime(dose.scheduledAt)),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontFamily: 'Vazirmatn',
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppPalette.ink(context, AppColors.ink))),
                    Text('(${PersianDate.displayDigits(dose.plan.doseText.trim())})',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontFamily: 'Vazirmatn',
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppPalette.ink(context, AppColors.ink))),
                  ]),
              ],
            )),
            const SizedBox(width: 6),
            if (dose.status == 'pending' && due)
              TodayDueAttentionBadge(
                key: Key('today-due-attention-${dose.occurrenceKey}'),
              )
            else if (dose.status != 'pending')
              AppStatusPill(
                text: status.$1, icon: status.$2, color: status.$3,
                fontSize: 11.5,
                background: status.$3.withValues(alpha: .14),
              ),
            const SizedBox(width: 5),
            AnimatedRotation(
              turns: expanded ? .5 : 0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: Icon(Icons.keyboard_arrow_down_rounded,
                color: AppPalette.ink(context, AppColors.primary), size: 27),
            ),
          ]),
        ),
      ),
      AnimatedSize(
        key: Key('today-dose-details-${dose.occurrenceKey}'),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: expanded
            ? _inlineDoseActions(dose)
            : const SizedBox(width: double.infinity),
      ),
      ]),
    );
  }

  Widget _inlineDoseActions(DailyDose dose) {
    return AnimatedContainer(
      key: Key('today-expanded-actions-${dose.occurrenceKey}'),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      color: AppPalette.surface(context, todayDoseCardBackground(dose.status)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Divider(height: 14, color: AppPalette.surface(context, AppColors.outline)),
        Text('ساعت برنامه: ${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))}  |  '
           'مقدار طبق نسخه: ${PersianDate.displayDigits(dose.plan.doseText)}',
          style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 13,
            color: AppPalette.ink(context, AppColors.ink))),
        const SizedBox(height: 11),
        if (dose.status == 'pending') ...[
          Row(children: [
            Expanded(child: FilledButton.icon(
              key: Key('today-taken-${dose.occurrenceKey}'),
              onPressed: _saving ? null : () => _mark(dose, 'taken'),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
              label: const Text('مصرف کردم', textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.surface(context, AppColors.success),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 51),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800)),
            )),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(
              key: Key('today-skipped-${dose.occurrenceKey}'),
              onPressed: _saving ? null : () => _mark(dose, 'skipped'),
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('مصرف نکردم', textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.surface(context, const Color(0xFFD34E58)),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 51),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800)),
            )),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: FilledButton.icon(
              key: Key('today-unknown-${dose.occurrenceKey}'),
              onPressed: _saving ? null : () => _mark(dose, 'unknown'),
              icon: const Icon(Icons.help_outline_rounded, size: 17),
              label: const Text('مطمئن نیستم', textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.surface(context, const Color(0xFFCF8517)),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 53),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800)),
            )),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(
              onPressed: _saving ? null :
                () => _mark(dose, 'takenWithoutStock'),
              icon: const Icon(Icons.inventory_2_outlined, size: 16),
              label: const Text('مصرف بدون کسر موجودی',
                maxLines: 2, textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.surface(context, const Color(0xFFE4ECEE)),
                foregroundColor: AppPalette.ink(context, const Color(0xFF38515A)),
                minimumSize: const Size(0, 53),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800)),
            )),
          ]),
          const SizedBox(height: 8),
          Text('فقط با انتخاب «مصرف کردم» موجودی بسته کم می‌شود.',
            style: TextStyle(fontFamily: 'Vazirmatn',
              fontSize: 12, color: AppPalette.ink(context, AppColors.muted))),
        ] else ...[
          TodayRecordedOutcomeBanner(status: dose.status),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: Key('today-undo-${dose.occurrenceKey}'),
            onPressed: _saving ? null : () => _mark(dose, 'undo'),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('بازگرداندن ثبت'),
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.surface(context, const Color(0xFF006D70)),
              foregroundColor: Colors.white,
              elevation: 1,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)),
              textStyle: const TextStyle(fontFamily: 'Vazirmatn',
                fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _medicinesTab() {
    final query = _normalizeMedicineSearch(_medicineSearch.text);
    final source = _showHidden ? _hiddenMedications :
        _showArchived ? _archivedMedications : _medications;
    final visible = source
        .where((med) =>
            _normalizeMedicineSearch(med.name).contains(query) &&
            (!_lowStockOnly || _showArchived || (_stocks[med.id]?.lowStock ?? false)))
        .toList();
    if (!_showArchived && !_showHidden) {
      visible.sort((a, b) {
        final priority = _attentionRank(a).compareTo(_attentionRank(b));
        return priority != 0 ? priority :
          _normalizeMedicineSearch(a.name).compareTo(_normalizeMedicineSearch(b.name));
      });
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 17, 15, 26),
      children: [
        Row(
          children: [
            Expanded(child: Text('داروها', style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: AppPalette.ink(context, AppColors.primaryDark), fontWeight: FontWeight.w900))),
            SizedBox(width: 138, child: AppGradientButton(
              label: 'افزودن دارو', icon: Icons.add, height: 44,
              onPressed: _saving ? null : _addMedication)),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: _searchVisible ? 'بستن جست‌وجوی دارو' : 'جست‌وجوی دارو',
              icon: Icon(_searchVisible ? Icons.close : Icons.search),
              style: IconButton.styleFrom(
                backgroundColor: AppPalette.surface(context, AppColors.mint),
                foregroundColor: AppPalette.ink(context, AppColors.primaryDark),
                minimumSize: const Size(46, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) _medicineSearch.clear();
              }),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_searchVisible) ...[
          TextField(
            key: const ValueKey('medication-search-field'),
            controller: _medicineSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'جست‌وجوی نام دارو...',
              suffixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 11),
        ],
        Container(
          decoration: BoxDecoration(color: AppPalette.surface(context, const Color(0xFFF1F7F8)),
            border: Border.all(color: AppPalette.surface(context, AppColors.outline)),
            borderRadius: BorderRadius.circular(13)),
          child: Row(children: [
            for (final filter in ['همه', 'کم‌موجودی', 'بایگانی', 'حذف‌شده‌ها'])
              Expanded(child: InkWell(
                onTap: () => setState(() {
                  _showArchived = filter == 'بایگانی';
                  _showHidden = filter == 'حذف‌شده‌ها';
                  _lowStockOnly = filter == 'کم‌موجودی';
                }),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: (_showHidden ? filter == 'حذف‌شده‌ها' :
                        _showArchived ? filter == 'بایگانی' :
                        _lowStockOnly ? filter == 'کم‌موجودی' : filter == 'همه')
                      ? LinearGradient(colors: [AppPalette.surface(context, AppColors.accent), AppPalette.surface(context, const Color(0xFF89E7E1))])
                      : null,
                    borderRadius: BorderRadius.circular(10)),
                  child: Text(filter, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700,
                    color: AppPalette.ink(context, AppColors.primaryDark), fontSize: 11)),
                ),
              )),
          ]),
        ),
        const SizedBox(height: 13),
        AppSoftHeader(
          title: 'فهرست داروها', icon: Icons.medication_outlined,
          subtitle: PersianDate.displayDigits(
            _showHidden ? '(${visible.length} داروی حذف‌شده)' :
            _showArchived ? '(${visible.length} دوره پایان‌یافته)' :
              '(${visible.length} داروی فعال)')),
        const SizedBox(height: 9),
        if (source.isEmpty && !_showArchived && !_showHidden)
          _emptyCard(
            'فهرست دارو خالی است.',
            'نام دارو و ساعت‌های روزانه را طبق نسخه وارد کنید.',
            'افزودن دارو',
            _addMedication,
          )
        else if (visible.isEmpty)
          AppPanel(child: Column(children: [
            Icon(Icons.search_off, size: 55, color: AppPalette.ink(context, AppColors.primary)),
            const SizedBox(height: 9),
            Text(_showHidden ? 'داروی حذف‌شده‌ای وجود ندارد.' :
              _showArchived ? 'هنوز دوره‌ای پایان نیافته است.' :
              'دارویی با این نام پیدا نشد.',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ]))
        else
          AppPanel(padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Column(children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i != 0) Divider(height: 1, color: AppPalette.surface(context, AppColors.outline)),
                _medicationCard(visible[i]),
              ],
            ])),
      ],
    );
  }

  Widget _medicationCard(Medication med) {
    final todaySlots = _doses
        .where((dose) => dose.medication.id == med.id)
        .toList();
    final nextDaySlots = _nextDayDoses
        .where((dose) => dose.medication.id == med.id)
        .toList();
    // A schedule edit intentionally takes effect tomorrow. Show the newly
    // saved schedule on the card immediately, while keeping today's original
    // occurrence keys and dose history unchanged.
    final hasPendingSchedule =
        todaySlots.isNotEmpty &&
        nextDaySlots.isNotEmpty &&
        nextDaySlots.first.plan.effectiveFrom.toLocal().isAfter(_now) &&
        nextDaySlots.first.plan.version != todaySlots.first.plan.version;
    final slots = nextDaySlots.isNotEmpty ? nextDaySlots : todaySlots;
    final clockLabels = slots.take(3).map((d) =>
      _clock(TimeOfDay.fromDateTime(d.scheduledAt))).join('، ');
    final extraClocks = slots.length > 3 ? ' +${slots.length - 3}' : '';
    final stock = _stocks[med.id];
    final selected = stock?.selected;
    final alerts = med.archived ? <StockAttention>[] : _visibleAttentions(med.id);
    final urgent = alerts.any((a) => a.urgent);
    final lowStock = stock?.lowStock == true;
    final stockLabel = selected == null
        ? '—'
        : PersianDate.displayDigits('${StockQuantity.format(selected.balanceMilliunits)} ${selected.package.unit}');
    return InkWell(
      onTap: () => _openMedicationDetail(med, slots, todaySlots,
        stock, hasPendingSchedule),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 7),
        decoration: BoxDecoration(
          color: alerts.isEmpty ? Colors.transparent : urgent
            ? AppPalette.tone(context, const Color(0xFFFFE4E9)) : AppPalette.tone(context, const Color(0xFFE5EFFF)),
          borderRadius: BorderRadius.circular(15)),
        child: Row(children: [
          MedicationArtwork(name: med.name, setup: _setups[med.id], size: 51),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(PersianDate.displayDigits(med.name), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, height: 1.45,
                color: AppPalette.ink(context, AppColors.ink), fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(_showHidden ? 'حذف‌شده از فهرست' :
              _showArchived ? 'بایگانی‌شده' : slots.isEmpty ? 'بدون نوبت فعال' :
              PersianDate.displayDigits('${slots.length} نوبت در روز'),
              style: TextStyle(color: AppPalette.ink(context, AppColors.muted), fontSize: 12)),
            if (!_showArchived && !_showHidden && slots.isNotEmpty)
              Text(PersianDate.displayDigits('ساعت: $clockLabels$extraClocks'),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppPalette.ink(context, AppColors.muted), fontSize: 12)),
            if (!_showArchived && !_showHidden && slots.isNotEmpty)
              Text(slots.map((d) => d.plan.doseText).toSet().length == 1
                ? 'مقدار هر نوبت: ${PersianDate.displayDigits(slots.first.plan.doseText)}'
                : 'مقدار: متفاوت در هر نوبت',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppPalette.ink(context, AppColors.muted), fontSize: 11)),
            if (alerts.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 5),
                child: Wrap(spacing: 5, runSpacing: 4, children: [
                  for (final alert in alerts.take(2))
                    AppStatusPill(text: alert.title,
                      color: Colors.white,
                      background: alert.urgent ? const Color(0xFFC5223B)
                        : const Color(0xFF1D4ED8), fontSize: 10),
                  if (alerts.length > 2)
                    Text('+${alerts.length - 2}',
                      style: const TextStyle(fontSize: 11)),
                ])),
            if (hasPendingSchedule)
              Text('برنامه جدید — از فردا', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.ink(context, AppColors.primary))),
          ])),
          const SizedBox(width: 5),
          if (!_showArchived) Container(
            constraints: const BoxConstraints(minWidth: 46, maxWidth: 75),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            decoration: BoxDecoration(
              color: lowStock ? AppPalette.surface(context, AppColors.amberLight) : AppPalette.surface(context, AppColors.mint),
              borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('موجودی', style: TextStyle(fontSize: 9,
                color: AppPalette.ink(context, AppColors.muted))),
              Text(stockLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  color: lowStock ? AppPalette.ink(context, const Color(0xFF1D4ED8)) : AppPalette.ink(context, AppColors.primaryDark))),
              if (lowStock) Text('کم‌موجودی',
                style: TextStyle(fontSize: 9, color: AppPalette.ink(context, const Color(0xFF1D4ED8)))),
              if (selected == null && !lowStock) Text('ثبت نشده',
                style: TextStyle(fontSize: 9, color: AppPalette.ink(context, AppColors.muted))),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'گزینه‌های دارو',
            enabled: !_saving,
            icon: Icon(Icons.more_vert, size: 21, color: AppPalette.ink(context, AppColors.muted)),
            onSelected: (value) {
              if (value == 'stock') _openStock(med);
              if (value == 'edit') _editMedication(med);
              if (value == 'archive') _archiveMedication(med);
              if (value == 'restore') _restoreMedication(med);
              if (value == 'unhide') _unhideMedication(med);
            },
            itemBuilder: (_) => _showHidden
                ? const [PopupMenuItem(value: 'unhide', child: Text('بازگردانی'))]
                : _showArchived
                ? const [PopupMenuItem(value: 'restore', child: Text('بازیابی'))]
                : const [
                    PopupMenuItem(value: 'stock', child: Text('موجودی و بسته‌ها')),
                    PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                    PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                  ],
          ),
        ]),
      ),
    );
  }

  Future<void> _openMedicationDetail(Medication med, List<DailyDose> slots,
      List<DailyDose> todaySlots, StockSummary? stock, bool pendingSchedule) async {
    await Navigator.of(context).push(medicationPageRoute<void>(context,
      Builder(builder: (detailContext) => MedicationDetailScreen(
        medication: med,
        slots: slots,
        todaySlots: todaySlots,
        stock: stock,
        setup: _setups[med.id],
        dismissedAttentionKeys: _dismissedAttentions[med.id] ?? const {},
        medicationRepository: widget.repository,
        inventoryRepository: _inventory,
        pendingSchedule: pendingSchedule,
        archived: med.archived,
        hidden: _hiddenMedications.any((m) => m.id == med.id),
        onHide: () { Navigator.pop(detailContext); _hideMedication(med); },
        onUnhide: () { Navigator.pop(detailContext); _unhideMedication(med); },
        onOpenCourse: (related) {
          Navigator.of(detailContext).pop();
          _openMedicationDetail(related, const [], const [],
            _stocks[related.id], false);
        },
        onEdit: () { Navigator.pop(detailContext); _editMedication(med); },
        onStock: () { Navigator.pop(detailContext); _openStock(med); },
        onPackageAction: (balance, action) {
          Navigator.pop(detailContext);
          _packageAction(med, balance, action);
        },
        onArchive: () { Navigator.pop(detailContext); _archiveMedication(med); },
        onRestore: () { Navigator.pop(detailContext); _restoreMedication(med); },
      )),
    ));
    if (mounted) await _reload();
  }

  Future<void> _openMenu() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('منو'), actions: [
        if (widget.onThemeChanged != null) _themeToggle(),
      ]),
      body: _moreTabRedesigned(),
    )));

  Future<void> _choosePalette() async {
    final selected = await showModalBottomSheet<AppThemeChoice>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('پالت رنگی برنامه', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final choice in AppThemeChoice.values)
            Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: choice.primary),
              title: Text(choice.label),
              trailing: Icon(AppPalette.selected(ctx) == choice
                ? Icons.check_circle : Icons.radio_button_unchecked,
                color: choice.primary),
              onTap: () => Navigator.pop(ctx, choice))),
        ]))));
    if (selected != null && mounted) {
      try {
        await widget.onPaletteChanged?.call(selected);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('پالت رنگی ذخیره نشد.')));
        }
      }
    }
  }

  Widget _moreTabRedesigned() => ListView(
    padding: const EdgeInsets.fromLTRB(15, 18, 15, 30),
    children: [
      AppWaveBanner(child: Row(children: [
        const MedicineArtwork(seed: 'همراه دارو', size: 58),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('همراه دارو', style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
            fontWeight: FontWeight.w900, fontSize: 19)),
          Text('مدیریت هوشمند داروهای شما',
            style: TextStyle(color: AppPalette.ink(context, AppColors.muted), fontSize: 12)),
        ])),
      ])),
      const SizedBox(height: 17),
      if (widget.onThemeChanged != null)
        _settingsTile(icon: AppPalette.isDark(context)
          ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          title: 'حالت روشن و تاریک',
          subtitle: AppPalette.isDark(context) ? 'تاریک' : 'روشن',
          onTap: _toggleTheme),
      if (widget.onPaletteChanged != null)
        _settingsTile(icon: Icons.palette_outlined,
          title: 'پالت رنگی', subtitle: 'انتخاب رنگ اصلی برنامه',
          onTap: _choosePalette),
      _settingsTile(icon: Icons.people_outline_rounded,
        title: 'پروفایل‌ها', subtitle: 'مدیریت اعضای خانواده',
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => ProfilesScreen(
            profiles: _profiles, activeId: _active!.id,
            onSelect: (id) => _perform(
              () => widget.profileRepository.selectActiveProfile(id)),
            onAdd: () => _startGuest(false),
          )))),
      _settingsTile(icon: Icons.notifications_active_outlined,
        title: 'یادآوری‌ها', subtitle: 'تنظیم هشدار مصرف و اعلان‌ها',
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => ReminderSettingsScreen(
            initiallyEnabled: _remindersEnabled,
            available: widget.reminderCoordinator != null,
            onEnable: _enableReminders, onDisable: _disableReminders,
            onTest: _testReminders, errorMessage: _reminderError,
          )))),
      _settingsTile(icon: Icons.cloud_upload_outlined,
        title: 'پشتیبان‌گیری', subtitle: 'ساخت و بررسی فایل رمزگذاری‌شده',
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => SecureBackupScreen(database: widget.repository.db)))),
      _settingsTile(icon: Icons.event_available_outlined,
        title: 'پیگیری‌ها و ویزیت‌ها', subtitle: 'چک‌لیست و کارهای مراقبتی',
        onTap: _openCareHub),
      _settingsTile(icon: Icons.keyboard_outlined,
        title: 'تنظیمات زبان و صفحه‌کلید', subtitle: 'راهنمای ورود متن فارسی',
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => KeyboardHelpScreen(onOpenSettings: _openKeyboardSettings)))),
      _settingsTile(icon: Icons.help_outline_rounded,
        title: 'راهنما', subtitle: 'راهنمای استفاده از همراه دارو',
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => const AboutScreen(buildNumber: _betaRunNumber)))),
      _settingsTile(icon: Icons.info_outline_rounded,
        title: 'درباره برنامه', subtitle: 'نسخه و اطلاعات حریم خصوصی',
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => const AboutScreen(buildNumber: _betaRunNumber)))),
      if (_careReminderError != null)
        Text('اشکال در اعلان‌های پیگیری: $_careReminderError',
          style: const TextStyle(color: Colors.deepOrange)),
    ],
  );

  Widget _emptyCard(
    String title,
    String description,
    String button,
    VoidCallback onTap,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(description),
          const SizedBox(height: 14),
          FilledButton(onPressed: onTap, child: Text(button)),
        ],
      ),
    ),
  );

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: AppIconTile(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Icon(Icons.chevron_left_rounded, color: AppPalette.ink(context, AppColors.muted)),
      onTap: onTap,
    ),
  );
}

String _clock(TimeOfDay time) => PersianDate.displayDigits(
  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
);

class _PastDoseReview extends StatefulWidget {
  const _PastDoseReview({required this.repository, required this.profileId,
    required this.initialDay, required this.lastDay, required this.onMark, this.target});
  final MedicationRepository repository;
  final String profileId;
  final DateTime initialDay, lastDay;
  final String? target;
  final Future<void> Function(DailyDose, String) onMark;
  @override
  State<_PastDoseReview> createState() => _PastDoseReviewState();
}

class _PastDoseReviewState extends State<_PastDoseReview> {
  late DateTime _day = widget.initialDay;
  late Future<List<DailyDose>> _future = _load();
  bool _busy = false;
  Future<List<DailyDose>> _load() async {
    final rows = await widget.repository.dosesForDay(widget.profileId, _day, historical: true);
    rows.sort((a, b) {
      if (a.occurrenceKey == b.occurrenceKey) { return 0; }
      if (a.occurrenceKey == widget.target) { return -1; }
      if (b.occurrenceKey == widget.target) { return 1; }
      return a.scheduledAt.compareTo(b.scheduledAt);
    });
    return rows;
  }
  void _setDay(DateTime date) {
    setState(() { _day = date; _future = _load(); });
  }
  Future<void> _markPast(DailyDose dose, String action) async {
    if (_busy) return;
    if (action == 'takenWithoutStock' || action == 'taken') {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) =>
        AlertDialog(title: const Text('ثبت مصرف گذشته'),
          content: Text(action == 'taken'
            ? 'این ثبت از بسته منتخب فعلی کم می‌کند. فقط اگر موجودی قبلاً کسر نشده، تأیید کن.'
            : 'این ثبت موجودی فعلی را تغییر نمی‌دهد. فقط اگر واقعاً دارو را مصرف کردی، تأیید کن.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید')),
          ]));
      if (!mounted || confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await widget.onMark(dose, action);
      if (mounted) { setState(() => _future = _load()); }
    } finally {
      if (mounted) { setState(() => _busy = false); }
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('نوبت‌های روزهای گذشته')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      AppPanel(child: Column(children: [
        Row(children: [
          IconButton(tooltip: 'روز قبل', onPressed: _busy ? null : () =>
            _setDay(DateTime(_day.year, _day.month, _day.day - 1)),
            icon: const Icon(Icons.chevron_right)),
          Expanded(child: OutlinedButton.icon(
            onPressed: _busy ? null : () async {
              final date = await showPersianDatePicker(context: context,
                initialDate: _day, firstDate: DateTime(2000), lastDate: widget.lastDay);
              if (mounted && date != null) { _setDay(date); }
            }, icon: const Icon(Icons.calendar_month_outlined),
            label: Text(persianDateLabel(_day)))),
          IconButton(tooltip: 'روز بعد', onPressed: _busy || !_day.isBefore(widget.lastDay)
            ? null : () => _setDay(DateTime(_day.year, _day.month, _day.day + 1)),
            icon: const Icon(Icons.chevron_left)),
        ]),
        const Text('ثبت گذشته بر اساس یادآوری خودت است؛ مصرف اضافی انجام نده.'),
      ])),
      const SizedBox(height: 12),
      FutureBuilder<List<DailyDose>>(future: _future, builder: (ctx, snapshot) {
        if (snapshot.hasError) { return const Text('بارگذاری نوبت‌ها انجام نشد.'); }
        if (!snapshot.hasData) { return const Center(child: CircularProgressIndicator()); }
        final rows = snapshot.requireData;
        if (rows.isEmpty) { return const Text('برای این روز نوبت فعالی وجود ندارد.'); }
        return Column(children: [
          for (final dose in rows) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(PersianDate.displayDigits(dose.medication.name),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))} — ${PersianDate.displayDigits(dose.plan.doseText)}'),
              if (dose.medication.archived) const Text('دوره پایان‌یافته؛ فقط اصلاح سابقه'),
              const SizedBox(height: 8),
              Text(switch (dose.status) {
                'taken' => 'مصرف شده', 'skipped' => 'مصرف نشده',
                'unknown' => 'نامطمئن', _ => 'تعیین وضعیت نشده',
              }),
              const SizedBox(height: 8),
              if (dose.status == 'pending') Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: _busy ? null : () => _markPast(dose, 'takenWithoutStock'),
                  child: const Text('مصرف کردم (بدون کسر)')),
                if (!dose.medication.archived)
                  OutlinedButton(onPressed: _busy ? null : () => _markPast(dose, 'taken'),
                    child: const Text('مصرف با کسر موجودی')),
                OutlinedButton(onPressed: _busy ? null : () => _markPast(dose, 'skipped'),
                  child: const Text('مصرف نکردم')),
                OutlinedButton(onPressed: _busy ? null : () => _markPast(dose, 'unknown'),
                  child: const Text('مطمئن نیستم')),
              ]) else OutlinedButton(onPressed: _busy ? null : () => _markPast(dose, 'undo'),
                child: const Text('بازگرداندن ثبت')),
            ]))),
        ]);
      }),
    ]),
  );
}
