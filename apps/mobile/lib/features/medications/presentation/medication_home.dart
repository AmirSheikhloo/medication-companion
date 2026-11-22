import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/guest_welcome_screen.dart';
import '../../profiles/presentation/profile_name_dialog.dart';
import 'medication_entry_sheet.dart';
import 'medication_detail_screen.dart';
import 'today_visuals.dart';
import 'settings_screens.dart';
import '../data/medication_repository.dart';
import '../../reminders/data/reminder_coordinator.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../../inventory/presentation/stock_management_sheet.dart';
import '../../inventory/presentation/dose_stock_dialog.dart';
import '../../health/data/health_repository.dart';
import '../../health/presentation/health_tab.dart';
import '../../care/data/care_repository.dart';
import '../../care/presentation/care_hub_screen.dart';
import '../../care/data/care_reminder_coordinator.dart';
import '../../backup/presentation/secure_backup_screen.dart';

const _deepTeal = AppColors.primary;
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
    this.clock,
  });

  final MedicationRepository repository;
  final ProfileRepository profileRepository;
  final ReminderCoordinator? reminderCoordinator;
  final CareReminderCoordinator? careReminderCoordinator;
  /// Injectable clock for daypart and notification widget tests.
  final DateTime Function()? clock;

  @override
  State<MedicationHome> createState() => _MedicationHomeState();
}

class _MedicationHomeState extends State<MedicationHome>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _saving = false;
  int _tab = 0;
  Profile? _active;
  List<Profile> _profiles = [];
  List<Medication> _medications = [];
  List<Medication> _archivedMedications = [];
  bool _showArchived = false;
  bool _searchVisible = false;
  bool _lowStockOnly = false;
  final _medicineSearch = TextEditingController();
  List<DailyDose> _doses = [];
  List<DailyDose> _nextDayDoses = [];
  Map<String, StockSummary> _stocks = {};
  final Set<String> _expandedDoseKeys = {};
  final Set<String> _seenDueAlertKeys = {};
  Timer? _todayClockTicker;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  InventoryRepository get _inventory =>
      InventoryRepository(widget.repository.db);
  String? _error;
  bool _remindersEnabled = false;
  String? _reminderError;
  String? _careReminderError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _todayClockTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _tab == 0) setState(() {});
    });
    _reload();
    _syncReminders();
    _syncCareReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _todayClockTicker?.cancel();
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
      final today = _now;
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final doses = profile == null
          ? <DailyDose>[]
          : await widget.repository.dosesForDay(profile.id, today);
      final nextDayDoses = profile == null
          ? <DailyDose>[]
          : await widget.repository.dosesForDay(profile.id, tomorrow);
      final stocks = <String, StockSummary>{};
      if (profile != null) {
        for (final med in meds) {
          stocks[med.id] = await _inventory.summary(profile.id, med.id);
        }
      }
      final remindersEnabled =
          await widget.reminderCoordinator?.isEnabled() ?? false;
      if (!mounted) return;
      setState(() {
        if (_active?.id != profile?.id) {
          _medicineSearch.clear();
          _searchVisible = false;
          _lowStockOnly = false;
        }
        _active = profile;
        _profiles = profiles;
        _medications = meds;
        _archivedMedications = archivedMeds;
        _doses = doses;
        _nextDayDoses = nextDayDoses;
        _stocks = stocks;
        _remindersEnabled = remindersEnabled;
        _loading = false;
        _error = null;
      });
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

  Future<void> _perform(Future<dynamic> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      try {
        await widget.reminderCoordinator?.refreshIfEnabled();
        if (mounted) setState(() => _reminderError = null);
      } catch (error) {
        if (mounted) {
          setState(() => _reminderError = '$error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تغییر ذخیره شد ولی یادآور به‌روز نشد: $error'),
            ),
          );
        }
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ذخیره انجام نشد: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addMedication() async {
    final profile = _active;
    if (profile == null || _saving) return;
    final draft = await showMedicationEntrySheet(
      context,
      profileName: profile.displayName,
    );
    if (!mounted || draft == null) return;
    await _perform(
      () => widget.repository.addMedicationSchedule(
        profileId: profile.id,
        name: draft.name,
        slots: [
          for (final slot in draft.slots)
            DoseSlotInput(
              doseText: slot.dose,
              time: TimeOfDayValue(slot.time.hour, slot.time.minute),
            ),
        ],
      ),
    );
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
    if (!mounted) return;
    final draft = await showMedicationEntrySheet(
      context,
      profileName: profile.displayName,
      initialName: medication.name,
      initialSlots: [
        for (final dose in doses)
          MedicationSlotDraft(
            dose: dose.plan.doseText,
            time: TimeOfDay.fromDateTime(dose.scheduledAt),
          ),
      ],
    );
    if (!mounted || draft == null) return;
    await _perform(
      () => widget.repository.updateMedicationSchedule(
        profileId: profile.id,
        medicationId: medication.id,
        name: draft.name,
        slots: [
          for (final slot in draft.slots)
            DoseSlotInput(
              doseText: slot.dose,
              time: TimeOfDayValue(slot.time.hour, slot.time.minute),
            ),
        ],
      ),
    );
  }

  Future<void> _archiveMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بایگانی دارو'),
        content: Text(
          '«${medication.name}» از فهرست فعال و نوبت‌های امروز پنهان می‌شود. '
          'سوابق پاک نمی‌شوند و بعداً می‌توانید دارو را بازیابی کنید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('بایگانی شود'),
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
    if (mounted) setState(() => _showArchived = false);
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
          const SnackBar(content: Text('اعلان تستی برای ۵ ثانیه دیگر ثبت شد.')),
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

  Future<void> _mark(DailyDose dose, String action) async {
    final profile = _active;
    if (profile == null || _saving) return;
    DoseStockChoice? choice;
    if (action == 'taken') {
      final stock = await _inventory.summary(profile.id, dose.medication.id);
      if (!mounted) return;
      choice = await askDoseStockChoice(
        context,
        medicationName: dose.medication.name,
        stock: stock,
      );
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
        action: action,
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _tab, children: [
          _todayTab(),
          _medicinesTab(),
          HealthTab(
            key: ValueKey(_active!.id),
            profile: _active!,
            repository: HealthRepository(widget.repository.db),
            onOpenCareHub: _openCareHub,
          ),
          _moreTabRedesigned(),
        ]),
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _tab,
        onSelected: (index) => setState(() => _tab = index),
      ),
    );
  }

  Widget _profileBar() {
    return Material(
      color: AppColors.lightMint,
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
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_outline_rounded, color: _deepTeal, size: 21),
            const SizedBox(width: 6),
            Flexible(child: Text(
              _active!.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Vazirmatn',
                fontSize: 14, fontWeight: FontWeight.bold,
                color: AppColors.primaryDark),
            )),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.primary, size: 20),
          ]),
        ),
      ),
    );
  }

  Future<void> _showProfilePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
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
              const Text('انتخاب شخص', textAlign: TextAlign.right,
                style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 21,
                  fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
              const SizedBox(height: 5),
              const Text('برنامه و اطلاعات هر شخص جدا نگه داشته می‌شود.',
                style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 13,
                  color: AppColors.muted)),
              const SizedBox(height: 16),
              for (final profile in _profiles) ...[
                Material(
                  color: profile.id == _active?.id
                      ? AppColors.mint : AppColors.background,
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: () => Navigator.pop(sheetContext, profile.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 12),
                      child: Row(children: [
                        CircleAvatar(radius: 20, backgroundColor: Colors.white,
                          child: const Icon(Icons.person_outline,
                            color: AppColors.primary)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(profile.displayName,
                          style: const TextStyle(fontFamily: 'Vazirmatn',
                            fontSize: 16, fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark))),
                        Icon(profile.id == _active?.id
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                          color: profile.id == _active?.id
                            ? AppColors.primary : AppColors.muted),
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
    final dueAlerts = waiting
        .where((dose) => !dose.scheduledAt.isAfter(now)).toList();
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Vazirmatn'),
      child: ListView(
        key: const Key('today-scroll-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Row(children: [
            const Expanded(child: Text('همراه دارو',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 18,
                fontWeight: FontWeight.bold, color: AppColors.primaryDark))),
            const SizedBox(width: 10),
            _profileBar(),
            const SizedBox(width: 8),
            _todayNotificationBell(dueAlerts),
          ]),
          const SizedBox(height: 16),
          TodaySkyGreeting(hour: now.hour, name: _active!.displayName),
          const SizedBox(height: 14),
          AppPanel(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
            child: Column(children: [
              Row(key: const Key('today-date-heading'), children: [
                const Expanded(child: Text('خلاصهٔ امروز',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark))),
                const SizedBox(width: 7),
                const Icon(Icons.calendar_today_outlined,
                  color: AppColors.primary, size: 17),
                const SizedBox(width: 5),
                Text(todayReadablePersianDate(now),
                  style: const TextStyle(fontFamily: 'Vazirmatn',
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.muted)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                TodayStatusRing(statuses: [for (final dose in _doses) dose.status],
                  size: 88),
                const SizedBox(width: 17),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(PersianDate.persianDigits(
                      '$taken از ${_doses.length} نوبت مصرف شده'),
                      style: const TextStyle(fontFamily: 'Vazirmatn',
                        fontSize: 13, color: AppColors.ink)),
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
            const Text('برنامهٔ مصرف امروز',
              style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 20,
                fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
            const SizedBox(height: 12),
            if (morning.isNotEmpty)
              _todayDoseGroup('صبح', Icons.wb_sunny_rounded, morning),
            if (afternoon.isNotEmpty)
              _todayDoseGroup('ظهر', Icons.light_mode_rounded, afternoon),
            if (evening.isNotEmpty)
              _todayDoseGroup('عصر و شب', Icons.nightlight_round, evening),
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
      Text(PersianDate.persianDigits(description),
        style: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 11.5,
          color: AppColors.ink)),
    ],
  );

  Widget _todayNotificationBell(List<DailyDose> dueAlerts) {
    final unread = dueAlerts
        .any((dose) => !_seenDueAlertKeys.contains(dose.occurrenceKey));
    return Stack(clipBehavior: Clip.none, children: [
      Material(
        key: const Key('today-bell-surface'),
        color: Colors.white,
        elevation: 1,
        shadowColor: const Color(0x45B89109),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFF0E1B3)),
        ),
        child: IconButton(
          key: const Key('today-notifications-button'),
          tooltip: 'اعلان‌های نوبت مصرف',
          icon: const Icon(Icons.notifications_none_rounded,
            color: Color(0xFFB38706), size: 25),
          onPressed: () => _showTodayNotifications(dueAlerts),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ),
      if (unread)
        PositionedDirectional(
          top: 6, start: 7,
          child: Container(
            key: const Key('today-unread-dot'),
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFFE94E55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
    ]);
  }

  Future<void> _showTodayNotifications(List<DailyDose> dueAlerts) async {
    setState(() {
      _seenDueAlertKeys.addAll(dueAlerts.map((dose) => dose.occurrenceKey));
    });
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 3, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('اعلان‌های امروز', textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 21,
                fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
            const SizedBox(height: 8),
            if (dueAlerts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Text('فعلاً نوبت عقب‌افتاده‌ای نداری 🌿',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Vazirmatn',
                    fontSize: 15, color: AppColors.ink)),
              ),
            for (final dose in dueAlerts)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.lightMint,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(children: [
                    const Icon(Icons.notifications_active_outlined,
                      color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '${dose.medication.name}  •  ${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))}',
                      style: const TextStyle(fontFamily: 'Vazirmatn',
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppColors.ink),
                    )),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _todayDoseGroup(String label, IconData icon,
    List<DailyDose> doses, {bool recorded = false}) {
    final headerColor = recorded
        ? const Color(0xFFEAF0F1)
        : AppColors.mint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: const BorderSide(color: AppColors.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            color: headerColor,
            child: Row(children: [
              Transform.flip(
                flipX: label == 'عصر و شب',
                child: Icon(icon, size: 22,
                  color: recorded ? AppColors.primary
                      : label == 'عصر و شب' ? AppColors.primary
                      : const Color(0xFFBD871F)),
              ),
              const SizedBox(width: 9),
              Text(label, style: const TextStyle(fontFamily: 'Vazirmatn',
                fontSize: 16, fontWeight: FontWeight.bold,
                color: AppColors.primaryDark)),
              const Spacer(),
              Text(PersianDate.persianDigits('${doses.length} نوبت'),
                style: const TextStyle(fontFamily: 'Vazirmatn',
                  color: AppColors.ink, fontSize: 13)),
            ]),
          ),
          for (var i = 0; i < doses.length; i++) ...[
            if (i != 0) const Divider(
              height: 1, indent: 13, endIndent: 13,
              color: AppColors.outline),
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
      'taken' => ('مصرف شد', Icons.check_circle_rounded, AppColors.success),
      'skipped' => ('مصرف نشد', Icons.cancel_rounded,
          const Color(0xFFC23F43)),
      'unknown' => ('مطمئن نیستم', Icons.help_rounded,
          const Color(0xFF996116)),
      _ => ('', Icons.schedule_rounded, AppColors.muted),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      color: todayDoseCardBackground(dose.status),
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
            MedicineArtwork(seed: dose.medication.name, size: 45),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dose.medication.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Vazirmatn',
                    fontSize: 16, fontWeight: FontWeight.bold,
                    height: 1.45, color: AppColors.ink)),
                const SizedBox(height: 2),
                Wrap(spacing: 6, runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.access_time_rounded,
                      size: 15, color: AppColors.muted),
                    Text(_clock(TimeOfDay.fromDateTime(dose.scheduledAt)),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'Vazirmatn',
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                    Text('(${PersianDate.persianDigits(dose.plan.doseText.trim())})',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontFamily: 'Vazirmatn',
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
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
              child: const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary, size: 27),
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
      color: todayDoseCardBackground(dose.status),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Divider(height: 14, color: AppColors.outline),
        Text('ساعت برنامه: ${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))}  |  '
           'مقدار طبق نسخه: ${PersianDate.persianDigits(dose.plan.doseText)}',
          style: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 13,
            color: AppColors.ink)),
        const SizedBox(height: 11),
        if (dose.status == 'pending') ...[
          FilledButton.icon(
            key: Key('today-taken-${dose.occurrenceKey}'),
            onPressed: _saving ? null : () => _mark(dose, 'taken'),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('مصرف کردم'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(fontFamily: 'Vazirmatn',
                fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: FilledButton.icon(
              key: Key('today-skipped-${dose.occurrenceKey}'),
              onPressed: _saving ? null : () => _mark(dose, 'skipped'),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('مصرف نکردم'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFFD34E58),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                textStyle: const TextStyle(fontFamily: 'Vazirmatn',
                  fontSize: 13, fontWeight: FontWeight.bold),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(
              key: Key('today-unknown-${dose.occurrenceKey}'),
              onPressed: _saving ? null : () => _mark(dose, 'unknown'),
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: const Text('مطمئن نیستم'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFFCF8517),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                textStyle: const TextStyle(fontFamily: 'Vazirmatn',
                  fontSize: 13, fontWeight: FontWeight.bold),
              ),
            )),
          ]),
          const SizedBox(height: 8),
          const Text('موجودی فقط با تأیید مقدار مصرف واقعی کم می‌شود.',
            style: TextStyle(fontFamily: 'Vazirmatn',
              fontSize: 12, color: AppColors.muted)),
        ] else ...[
          AppStatusPill(
            text: switch (dose.status) {
              'taken' => 'این نوبت مصرف شده است',
              'skipped' => 'مصرف این نوبت ثبت نشده است',
              _ => 'وضعیت این نوبت نامشخص ثبت شده است',
            },
            icon: dose.status == 'taken'
                ? Icons.check_circle : Icons.info_outline,
            color: dose.status == 'taken' ? AppColors.success
                : dose.status == 'skipped' ? const Color(0xFFC23F43)
                : const Color(0xFF996116),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: Key('today-undo-${dose.occurrenceKey}'),
            onPressed: _saving ? null : () => _mark(dose, 'undo'),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('بازگرداندن ثبت'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF006D70),
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
    final source = _showArchived ? _archivedMedications : _medications;
    final visible = source
        .where((med) =>
            _normalizeMedicineSearch(med.name).contains(query) &&
            (!_lowStockOnly || _showArchived || (_stocks[med.id]?.lowStock ?? false)))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 17, 15, 26),
      children: [
        Row(
          children: [
            Expanded(child: Text('داروها', style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w900))),
            IconButton(
              tooltip: _searchVisible ? 'بستن جست‌وجوی دارو' : 'جست‌وجوی دارو',
              icon: Icon(_searchVisible ? Icons.close : Icons.search),
              color: _deepTeal,
              onPressed: () => setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) _medicineSearch.clear();
              }),
            ),
            const SizedBox(width: 2),
            SizedBox(width: 138, child: AppGradientButton(
              label: 'افزودن دارو', icon: Icons.add, height: 42,
              onPressed: _saving ? null : _addMedication)),
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
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 11),
        ],
        Container(
          decoration: BoxDecoration(color: const Color(0xFFF1F7F8),
            border: Border.all(color: AppColors.outline),
            borderRadius: BorderRadius.circular(13)),
          child: Row(children: [
            for (final filter in ['همه', 'کم‌موجودی', 'بایگانی'])
              Expanded(child: InkWell(
                onTap: () => setState(() {
                  _showArchived = filter == 'بایگانی';
                  _lowStockOnly = filter == 'کم‌موجودی';
                }),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: (_showArchived ? filter == 'بایگانی' :
                        _lowStockOnly ? filter == 'کم‌موجودی' : filter == 'همه')
                      ? const LinearGradient(colors: [AppColors.accent, Color(0xFF89E7E1)])
                      : null,
                    borderRadius: BorderRadius.circular(10)),
                  child: Text(filter, style: const TextStyle(fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark, fontSize: 12)),
                ),
              )),
          ]),
        ),
        const SizedBox(height: 13),
        Text(PersianDate.persianDigits(
          _showArchived ? '${_archivedMedications.length} داروی بایگانی‌شده' :
            '${_medications.length} داروی فعال'),
          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 9),
        if (source.isEmpty && !_showArchived)
          _emptyCard(
            'فهرست دارو خالی است.',
            'نام دارو و ساعت‌های روزانه را طبق نسخه وارد کنید.',
            'افزودن دارو',
            _addMedication,
          )
        else if (visible.isEmpty)
          AppPanel(child: Column(children: [
            const Icon(Icons.search_off, size: 55, color: AppColors.primary),
            const SizedBox(height: 9),
            Text(_showArchived ? 'هنوز دارویی بایگانی نشده است.' :
              'دارویی با این نام پیدا نشد.',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ]))
        else
          AppPanel(padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Column(children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i != 0) const Divider(height: 1, color: AppColors.outline),
                _medicationCard(visible[i]),
              ],
            ])),
        const SizedBox(height: 18),
        if (!_showArchived) AppSoftHeader(
          title: 'موجودی هوشمند داروها', icon: Icons.inventory_2_outlined,
          subtitle: 'مقدار ثبت‌شده، بدون تخمین خودکار یا توصیهٔ مصرف.'),
        const SizedBox(height: 11),
        if (!_showArchived) OutlinedButton.icon(
          onPressed: () => setState(() => _showArchived = true),
          icon: const Icon(Icons.inventory_2_outlined),
          label: Text(PersianDate.persianDigits(
            'نمایش بایگانی (${_archivedMedications.length})'))),
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
        todaySlots.first.plan.version != nextDaySlots.first.plan.version;
    final slots = hasPendingSchedule ? nextDaySlots : todaySlots;
    final stock = _stocks[med.id];
    final selected = stock?.selected;
    final lowStock = stock?.lowStock == true;
    final stockLabel = selected == null
        ? '—'
        : PersianDate.persianDigits('${StockQuantity.format(selected.balanceMilliunits)} ${selected.package.unit}');
    return InkWell(
      onTap: () => _openMedicationDetail(med, slots, todaySlots,
        stock, hasPendingSchedule),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(children: [
          MedicineArtwork(seed: med.name, size: 51),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(med.name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(_showArchived ? 'بایگانی‌شده' : slots.isEmpty ? 'برنامه ثبت شده' :
              PersianDate.persianDigits('${slots.length} نوبت · '
                '${slots.map((d) => '${_clock(TimeOfDay.fromDateTime(d.scheduledAt))} ${d.plan.doseText}').join('، ')}'),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            if (hasPendingSchedule)
              const Text('برنامه جدید — از فردا', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
          ])),
          const SizedBox(width: 5),
          if (!_showArchived) Container(
            constraints: const BoxConstraints(minWidth: 46, maxWidth: 75),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            decoration: BoxDecoration(
              color: lowStock ? AppColors.amberLight : AppColors.mint,
              borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(stockLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  color: lowStock ? const Color(0xFF99520A) : AppColors.primaryDark)),
              if (lowStock) const Text('کم‌موجودی',
                style: TextStyle(fontSize: 9, color: Color(0xFF99520A))),
              if (selected == null && !lowStock) const Text('ثبت نشده',
                style: TextStyle(fontSize: 9, color: AppColors.muted)),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'گزینه‌های دارو',
            enabled: !_saving,
            icon: const Icon(Icons.more_vert, size: 21, color: AppColors.muted),
            onSelected: (value) {
              if (value == 'stock') _openStock(med);
              if (value == 'edit') _editMedication(med);
              if (value == 'archive') _archiveMedication(med);
              if (value == 'restore') _restoreMedication(med);
            },
            itemBuilder: (_) => _showArchived
                ? const [PopupMenuItem(value: 'restore', child: Text('بازیابی'))]
                : const [
                    PopupMenuItem(value: 'stock', child: Text('موجودی و بسته‌ها')),
                    PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                    PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                  ],
          ),
          const Icon(Icons.chevron_left, size: 16, color: AppColors.muted),
        ]),
      ),
    );
  }

  Future<void> _openMedicationDetail(Medication med, List<DailyDose> slots,
      List<DailyDose> todaySlots, StockSummary? stock, bool pendingSchedule) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (detailContext) => MedicationDetailScreen(
        medication: med,
        slots: slots,
        todaySlots: todaySlots,
        stock: stock,
        pendingSchedule: pendingSchedule,
        archived: _showArchived,
        onEdit: () { Navigator.pop(detailContext); _editMedication(med); },
        onStock: () { Navigator.pop(detailContext); _openStock(med); },
        onArchive: () { Navigator.pop(detailContext); _archiveMedication(med); },
        onRestore: () { Navigator.pop(detailContext); _restoreMedication(med); },
      ),
    ));
  }

  Widget _moreTabRedesigned() => ListView(
    padding: const EdgeInsets.fromLTRB(15, 18, 15, 30),
    children: [
      Text('بیشتر', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColors.primaryDark, fontWeight: FontWeight.w900)),
      const SizedBox(height: 15),
      AppWaveBanner(child: Row(children: [
        const MedicineArtwork(seed: 'همراه دارو', size: 58),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('همراه دارو', style: TextStyle(color: AppColors.primaryDark,
            fontWeight: FontWeight.w900, fontSize: 19)),
          Text('مدیریت هوشمند داروهای شما',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ])),
      ])),
      const SizedBox(height: 17),
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
      trailing: const Icon(Icons.chevron_left_rounded, color: AppColors.muted),
      onTap: onTap,
    ),
  );
}

String _clock(TimeOfDay time) => PersianDate.persianDigits(
  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
);
