import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/guest_welcome_screen.dart';
import '../../profiles/presentation/profile_name_dialog.dart';
import 'medication_entry_sheet.dart';
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

const _teal = AppColors.primary;
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
  });

  final MedicationRepository repository;
  final ProfileRepository profileRepository;
  final ReminderCoordinator? reminderCoordinator;
  final CareReminderCoordinator? careReminderCoordinator;

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
    _reload();
    _syncReminders();
    _syncCareReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (mounted) setState(() => _loading = true);
    try {
      final profile = await widget.profileRepository.activeProfile();
      final profiles = await widget.profileRepository.profiles();
      final meds = profile == null
          ? <Medication>[]
          : await widget.repository.medicationsFor(profile.id);
      final archivedMeds = profile == null
          ? <Medication>[]
          : await widget.repository.medicationsFor(profile.id, archived: true);
      final today = DateTime.now();
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

  Future<void> _startGuest(bool forSelf) async {
    if (_saving) return;
    String? name;
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
        onLovedOne: _saving ? null : () => _startGuest(false),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconTile(Icons.medication_rounded),
            SizedBox(width: 10),
            Text('همراه دارو'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تازه‌سازی',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _profileBar(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _todayTab(),
                _medicinesTab(),
                HealthTab(
                  key: ValueKey(_active!.id),
                  profile: _active!,
                  repository: HealthRepository(widget.repository.db),
                ),
                _moreTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: 'امروز',
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication_rounded),
            label: 'داروها',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'سلامت',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_horiz_rounded),
            label: 'بیشتر',
          ),
        ],
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _addMedication,
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('افزودن دارو'),
            )
          : null,
    );
  }

  Widget _profileBar() {
    final active = _active!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle_outlined, color: _deepTeal),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: active.id,
                items: [
                  for (final profile in _profiles)
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(
                        'پروفایل: ${profile.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (id) {
                        if (id != null) {
                          _perform(
                            () => widget.profileRepository.selectActiveProfile(
                              id,
                            ),
                          );
                        }
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayTab() {
    final taken = _doses.where((dose) => dose.status == 'taken').length;
    final pending = _doses.where((dose) => dose.status == 'pending').length;
    final other = _doses.length - taken - pending;
    final now = DateTime.now();
    final morning = _doses
        .where((dose) => dose.scheduledAt.hour >= 5 && dose.scheduledAt.hour < 11)
        .toList();
    final afternoon = _doses
        .where((dose) => dose.scheduledAt.hour >= 11 && dose.scheduledAt.hour < 17)
        .toList();
    final evening = _doses
        .where((dose) => dose.scheduledAt.hour >= 17 || dose.scheduledAt.hour < 5)
        .toList();
    DailyDose? nextDose;
    for (final dose in _doses) {
      if (dose.status == 'pending' && dose.scheduledAt.isAfter(now)) {
        nextDose = dose;
        break;
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        Text(
          '${now.hour < 12 ? 'صبح بخیر' : now.hour < 18 ? 'روز بخیر' : 'شب بخیر'}، '
          '${_active!.kind == 'self' ? 'دوست من' : _active!.displayName} 👋',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.primaryDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'امروز هم با آرامش برنامهٔ ثبت داروهایت را دنبال کن.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_available_outlined, color: _deepTeal),
              const SizedBox(width: 9),
              const Text('امروز', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                persianDateLabel(now),
                style: const TextStyle(color: AppColors.primaryDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_doses.isNotEmpty)
          AppPanel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'خلاصه امروز',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        PersianDate.persianDigits('$taken / ${_doses.length}'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _deepTeal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var index = 0; index < _doses.length; index++) ...[
                        if (index != 0) const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: index < taken
                                  ? AppColors.accent
                                  : const Color(0xFFDCE5E6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(
                          PersianDate.persianDigits('مصرف‌شده: $taken'),
                        ),
                      ),
                      Chip(
                        label: Text(
                          PersianDate.persianDigits('ثبت‌نشده: $pending'),
                        ),
                      ),
                      Chip(
                        label: Text(
                          PersianDate.persianDigits('سایر وضعیت‌ها: $other'),
                        ),
                      ),
                    ],
                  ),
                  if (nextDose != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'نوبت بعدی: ${nextDose.medication.name} — '
                      '${_clock(TimeOfDay.fromDateTime(nextDose.scheduledAt))}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
            ),
          ),
        if (_doses.isEmpty)
          _emptyCard(
            'هنوز دارویی ثبت نکرده‌اید.',
            'برای شروع، دارو و زمان آن را طبق نسخه وارد کنید.',
            'افزودن اولین دارو',
            () => setState(() => _tab = 1),
          ),
        if (_doses.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('برنامهٔ مصرف امروز'),
          const SizedBox(height: 10),
          if (morning.isNotEmpty)
            _todayDoseGroup('صبح', Icons.wb_sunny_outlined, morning),
          if (afternoon.isNotEmpty)
            _todayDoseGroup('ظهر', Icons.light_mode_outlined, afternoon),
          if (evening.isNotEmpty)
            _todayDoseGroup('عصر و شب', Icons.nightlight_outlined, evening),
        ],
        if (_doses.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _saving ? null : _addMedication,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('افزودن داروی جدید'),
          ),
        const SizedBox(height: 16),
        const _InfoNote(
          'ثبت‌های این صفحه اعلام شما هستند، نه تأیید پزشکی مصرف. '
          'کسر موجودی فقط پس از تأیید مقدار واقعی انجام می‌شود.',
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _openCareHub,
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('کارهای پیگیری، ویزیت‌ها و سؤال‌های پزشک'),
        ),
      ],
    );
  }

  Widget _todayDoseGroup(String label, IconData icon, List<DailyDose> doses) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(icon, color: _deepTeal, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    PersianDate.persianDigits('${doses.length} نوبت'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final dose in doses) _doseCard(dose),
          ],
        ),
      );

  Widget _doseCard(DailyDose dose) {
    final status = switch (dose.status) {
      'taken' => ('مصرف ثبت شد', Icons.check_circle_outline, AppColors.success),
      'skipped' => ('مصرف نکردم', Icons.remove_circle_outline, Colors.deepOrange),
      'unknown' => ('نامشخص', Icons.help_outline, AppColors.muted),
      _ => ('ثبت نشده', Icons.schedule, AppColors.muted),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AppIconTile(Icons.medication_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dose.medication.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _clock(TimeOfDay.fromDateTime(dose.scheduledAt)),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: status.$3.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.$2, color: status.$3, size: 16),
                      const SizedBox(width: 5),
                      Text(
                        status.$1,
                        style: TextStyle(
                          color: status.$3,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'طبق ثبت شما: ',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  TextSpan(
                    text: PersianDate.persianDigits(dose.plan.doseText),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            if (dose.status == 'taken')
              Text(
                dose.stockDebited
                    ? 'از موجودی بسته انتخاب‌شده کسر شد.'
                    : 'مصرف بدون کسر موجودی ثبت شده است.',
                style: TextStyle(color: Colors.blueGrey.shade700),
              ),
            if (_stocks[dose.medication.id]?.lowStock == true)
              const Text(
                'هشدار: موجودی بسته انتخاب‌شده کم است.',
                style: TextStyle(color: Colors.deepOrange),
              ),
            const SizedBox(height: 10),
            if (dose.status == 'pending') ...[
              Wrap(
                spacing: 8,
                runSpacing: 3,
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _mark(dose, 'taken'),
                    icon: const Icon(Icons.check),
                    label: const Text('مصرف کردم'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => _mark(dose, 'skipped'),
                    child: const Text('مصرف نکردم'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => _mark(dose, 'unknown'),
                    child: const Text('مطمئن نیستم'),
                  ),
                ],
              ),
            ] else
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _mark(dose, 'undo'),
                icon: const Icon(Icons.undo),
                label: const Text('بازگرداندن ثبت'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _medicinesTab() {
    final query = _normalizeMedicineSearch(_medicineSearch.text);
    final visible = _medications
        .where((med) =>
            _normalizeMedicineSearch(med.name).contains(query) &&
            (!_lowStockOnly || (_stocks[med.id]?.lowStock ?? false)))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('داروهای ${_active!.displayName}')),
            if (_medications.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: IconButton(
                  tooltip: _searchVisible
                      ? 'بستن جست‌وجوی دارو'
                      : 'جست‌وجوی دارو',
                  icon: Icon(_searchVisible ? Icons.close : Icons.search),
                  color: _deepTeal,
                  onPressed: () => setState(() {
                    _searchVisible = !_searchVisible;
                    if (!_searchVisible) _medicineSearch.clear();
                  }),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          PersianDate.persianDigits('${_medications.length} داروی فعال'),
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        if (_searchVisible) ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('medication-search-field'),
            controller: _medicineSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'جست‌وجوی نام دارو',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_medications.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('همه'),
                selected: !_lowStockOnly,
                onSelected: (_) => setState(() => _lowStockOnly = false),
              ),
              ChoiceChip(
                label: const Text('کم‌موجودی'),
                selected: _lowStockOnly,
                onSelected: (_) => setState(() => _lowStockOnly = true),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (_medications.isEmpty)
          _emptyCard(
            'فهرست دارو خالی است.',
            'نام دارو و ساعت‌های روزانه را طبق نسخه وارد کنید.',
            'افزودن دارو',
            _addMedication,
          )
        else if (visible.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('دارویی با این نام پیدا نشد.'),
            ),
          ),
        for (final med in visible) _medicationCard(med),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => setState(() => _showArchived = !_showArchived),
          icon: Icon(
            _showArchived ? Icons.expand_less : Icons.inventory_2_outlined,
          ),
          label: Text(
            _showArchived
                ? 'پنهان کردن بایگانی'
                : PersianDate.persianDigits(
                    'نمایش بایگانی (${_archivedMedications.length})',
                  ),
          ),
        ),
        if (_showArchived) ...[
          if (_archivedMedications.isEmpty)
            const ListTile(title: Text('هنوز دارویی بایگانی نشده است.')),
          for (final med in _archivedMedications)
            Card(
              child: ListTile(
                title: Text(med.name),
                subtitle: const Text('بایگانی‌شده؛ سوابق مصرف نگهداری می‌شوند'),
                trailing: TextButton(
                  onPressed: _saving ? null : () => _restoreMedication(med),
                  child: const Text('بازیابی'),
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        const _InfoNote(
          'برای ویرایش یا بایگانی از منوی سه‌نقطه هر دارو استفاده کنید. '
          'ویرایش برنامه از فردا اعمال می‌شود؛ سوابق قبلی محفوظ می‌مانند.',
        ),
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
    final stockLine = selected == null
        ? 'موجودی بسته انتخاب نشده'
        : PersianDate.persianDigits(
            'بسته: ${selected.package.label} — '
            '${StockQuantity.format(selected.balanceMilliunits)} ${selected.package.unit}'
            '${selected.expired ? ' (منقضی)' : ''}'
            '${stock!.lowStock ? ' (هشدار کمبود)' : ''}',
          );
    final lowStock = stock?.lowStock == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AppIconTile(Icons.medication_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        hasPendingSchedule ? 'برنامه جدید — از فردا' : 'فعال',
                        style: const TextStyle(
                          color: _deepTeal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'گزینه‌های دارو',
                  enabled: !_saving,
                  onSelected: (value) {
                    if (value == 'stock') {
                      _openStock(med);
                    } else if (value == 'edit') {
                      _editMedication(med);
                    } else if (value == 'archive') {
                      _archiveMedication(med);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'stock',
                      child: Text('موجودی و بسته‌ها'),
                    ),
                    PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                    PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            if (slots.isEmpty)
              const Text('برنامهٔ روزانه ثبت شده است.')
            else
              for (final dose in slots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.schedule_outlined,
                        size: 18,
                        color: _deepTeal,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _clock(TimeOfDay.fromDateTime(dose.scheduledAt)),
                          style: const TextStyle(
                            color: _deepTeal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Text(PersianDate.persianDigits(dose.plan.doseText))),
                    ],
                  ),
                ),
            if (hasPendingSchedule)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'نوبت‌های امروز طبق برنامه قبلی ثبت می‌شوند.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: lowStock
                    ? const Color(0xFFFFF1E6)
                    : const Color(0xFFEAF7F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: lowStock ? Colors.deepOrange : _deepTeal,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(stockLine)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moreTab() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.medication_rounded, color: AppColors.accent, size: 36),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'همراه دارو',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'مدیریت دارو و سلامت، روی همین دستگاه',
                    style: TextStyle(color: AppColors.mint, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionTitle('پشتیبان‌گیری'),
      const SizedBox(height: 8),
      _settingsTile(
        icon: Icons.cloud_upload_outlined,
        title: 'ساخت پشتیبان رمزگذاری‌شده',
        subtitle: 'خروجی امن و بررسی فایل پشتیبان',
        onTap: _saving
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SecureBackupScreen(database: widget.repository.db),
                ),
              ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'در نسخهٔ بتا ساخت و بررسی پشتیبان امکان‌پذیر است؛ بازیابی هنوز فعال نیست.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
      const SizedBox(height: 20),
      _sectionTitle('پیگیری‌ها و ویزیت‌ها'),
      const SizedBox(height: 8),
      _settingsTile(
        icon: Icons.event_available_outlined,
        title: 'باز کردن کارها و چک‌لیست ویزیت',
        subtitle: 'کارهای پیگیری، نوبت‌های پزشک و سؤال‌ها',
        onTap: _openCareHub,
      ),
      if (_careReminderError != null)
        Text(
          'اشکال در اعلان‌های پیگیری: $_careReminderError',
          style: const TextStyle(color: Colors.deepOrange),
        ),
      const SizedBox(height: 20),
      _sectionTitle('پروفایل‌های محلی'),
      const SizedBox(height: 12),
      for (final profile in _profiles)
        Card(
          child: ListTile(
            leading: AppIconTile(
              profile.kind == 'self'
                  ? Icons.person_outline_rounded
                  : Icons.people_outline_rounded,
            ),
            title: Text(profile.displayName),
            subtitle: Text(
              profile.kind == 'self' ? 'برای خودم' : 'تحت مدیریت من',
            ),
            trailing: profile.id == _active?.id
                ? const Icon(Icons.check_circle, color: _deepTeal)
                : const Icon(Icons.chevron_left),
            onTap: profile.id == _active?.id || _saving
                ? null
                : () => _perform(
                    () => widget.profileRepository.selectActiveProfile(
                      profile.id,
                    ),
                  ),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: _saving ? null : () => _startGuest(false),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('افزودن پروفایل عزیزانم'),
      ),
      const SizedBox(height: 24),
      _sectionTitle('یادآوری دارو'),
      const SizedBox(height: 8),
      Text(
        _remindersEnabled
            ? 'فعال: یادآورها برای همه پروفایل‌های محلی تنظیم می‌شوند.'
            : 'غیرفعال: تا اجازه ندهید، یادآور دارو ثبت نمی‌شود.',
      ),
      const SizedBox(height: 10),
      if (_reminderError != null)
        Text(
          'اشکال در یادآوری: $_reminderError',
          style: const TextStyle(color: Colors.deepOrange),
        ),
      const SizedBox(height: 8),
      if (widget.reminderCoordinator != null) ...[
        if (!_remindersEnabled)
          FilledButton.icon(
            onPressed: _saving ? null : _enableReminders,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('فعال‌سازی یادآوری دارو'),
          )
        else ...[
          FilledButton.tonalIcon(
            onPressed: _saving ? null : _testReminders,
            icon: const Icon(Icons.timer_outlined),
            label: const Text('تست اعلان — ۵ ثانیه دیگر'),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _disableReminders,
            icon: const Icon(Icons.notifications_off_outlined),
            label: const Text('خاموش کردن یادآورها'),
          ),
        ],
      ],
      const SizedBox(height: 8),
      const Text(
        'آلارم دقیق و مجوز اعلان لازم‌اند. اعلان‌ها معمولی و خصوصی‌اند؛ '
        'به‌صورت تمام‌صفحه باز نمی‌شوند. '
        'یادآورها ممکن است با محدودیت باتری یا تنظیمات گوشی به تأخیر بیفتند؛ جایگزین مراقبت پزشکی نیستند.',
        style: TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      _sectionTitle('ورود متن فارسی'),
      const SizedBox(height: 8),
      const Text(
        'فیلدهای برنامه حروف فارسی را می‌پذیرند. اگر فقط انگلیسی می‌بینید، '
        'در کیبورد گوشی زبان فارسی را فعال کنید. '
        'پس از افزودن فارسی در Gboard، با نگه‌داشتن کلید فاصله زبان را عوض کنید.',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _openKeyboardSettings,
        icon: const Icon(Icons.keyboard_outlined),
        label: const Text('بازکردن تنظیمات زبان کیبورد'),
      ),
      const SizedBox(height: 20),
      _sectionTitle('درباره برنامه'),
      const SizedBox(height: 8),
      const Text('همراه دارو — بتا ۰.۳.۰'),
      Text(
        _betaRunNumber == 'محلی'
            ? 'ساخت محلی'
            : 'شماره ساخت آزمایشی: CI$_betaRunNumber',
      ),
      const SizedBox(height: 12),
      const _InfoNote(
        'این نسخهٔ بتای خصوصی است؛ داده‌ها فقط روی همین دستگاه‌اند. حساب آنلاین، همگام‌سازی و بازیابی پشتیبان فعال نیستند. برای مصرف دارو به اعلان برنامه به‌تنهایی تکیه نکنید.',
      ),
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

  Widget _sectionTitle(String title) => AppSectionHeading(title);

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

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6E7),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: Color(0xFF9A6400)),
        const SizedBox(width: 9),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

String _clock(TimeOfDay time) => PersianDate.persianDigits(
  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
);
