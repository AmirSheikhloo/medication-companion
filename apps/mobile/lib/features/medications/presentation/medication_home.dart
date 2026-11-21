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
    final active = _active!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 146),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.lightMint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_rounded, color: _deepTeal, size: 19),
          const SizedBox(width: 5),
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
                        profile.displayName,
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 30),
      children: [
        Row(children: [
          const Expanded(child: Row(children: [
            MedicineArtwork(seed: 'همراه دارو', size: 40),
            SizedBox(width: 8),
            Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('همراه دارو', style: TextStyle(fontSize: 18,
                color: AppColors.primaryDark, fontWeight: FontWeight.w900)),
              Text('مدیریت دارو و سلامت', style: TextStyle(color: AppColors.muted,
                fontSize: 10)),
            ])),
          ])),
          _profileBar(),
        ]),
        const SizedBox(height: 16),
        AppWaveBanner(child: Row(children: [
          const Icon(Icons.wb_sunny_rounded, color: Color(0xFFEAB62D), size: 40),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${now.hour < 12 ? 'صبح بخیر' : now.hour < 18 ? 'روز بخیر' : 'شب بخیر'}، '
              '${_active!.displayName} 👋',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
                color: AppColors.primaryDark)),
            const Text('امروز هم با آرامش داروهایت را ثبت کن.',
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ])),
        ])),
        const SizedBox(height: 10),
        AppSoftHeader(title: 'امروز', icon: Icons.calendar_month_rounded,
          trailing: Flexible(child: Text(persianDateLabel(now),
            maxLines: 2, textAlign: TextAlign.left,
            style: const TextStyle(fontSize: 12, color: AppColors.primaryDark)))),
        const SizedBox(height: 10),
        AppPanel(padding: const EdgeInsets.all(12), child: Row(children: [
          AppProgressRing(
            progress: _doses.isEmpty ? 0 : taken / _doses.length,
            center: PersianDate.persianDigits('$taken/${_doses.length}'), size: 67),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('خلاصه امروز', style: TextStyle(fontWeight: FontWeight.w800,
              color: AppColors.primaryDark)),
            Text(PersianDate.persianDigits('$taken از ${_doses.length} نوبت ثبت شده'),
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 7),
            Row(children: [
              for (final dose in _doses) Expanded(child: Container(
                margin: const EdgeInsetsDirectional.only(end: 3), height: 7,
                decoration: BoxDecoration(
                  color: dose.status == 'taken' ? AppColors.accent :
                    dose.status == 'pending' ? const Color(0xFFD9E2E4) : AppColors.amber,
                  borderRadius: BorderRadius.circular(7)))),
            ]),
            const SizedBox(height: 5),
            Text(PersianDate.persianDigits('ثبت‌نشده: $pending  |  سایر وضعیت‌ها: $other'),
              style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
        ])),
        if (_doses.isEmpty)
          _emptyCard(
            'هنوز دارویی ثبت نکرده‌اید.',
            'برای شروع، دارو و زمان آن را طبق نسخه وارد کنید.',
            'افزودن اولین دارو',
            () => setState(() => _tab = 1),
          ),
        if (_doses.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('برنامهٔ مصرف امروز'),
          const SizedBox(height: 7),
          if (morning.isNotEmpty)
            _todayDoseGroup('صبح', Icons.wb_sunny_outlined, morning),
          if (afternoon.isNotEmpty)
            _todayDoseGroup('ظهر', Icons.light_mode_outlined, afternoon),
          if (evening.isNotEmpty)
            _todayDoseGroup('عصر و شب', Icons.nightlight_outlined, evening),
        ],
        const SizedBox(height: 12),
        AppGradientButton(label: 'افزودن داروی جدید', icon: Icons.add,
          onPressed: _saving ? null : _addMedication, light: true),
        const SizedBox(height: 12),
        TextButton.icon(onPressed: _openCareHub,
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('پیگیری‌ها و چک‌لیست ویزیت')),
      ],
    );
  }

  Widget _todayDoseGroup(String label, IconData icon, List<DailyDose> doses) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.mint, borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, color: label == 'عصر و شب' ? AppColors.primary :
                    const Color(0xFFDBA726), size: 20),
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
            AppPanel(padding: const EdgeInsets.symmetric(horizontal: 10), child: Column(
              children: [
                for (var i = 0; i < doses.length; i++) ...[
                  if (i != 0) const Divider(height: 1, color: AppColors.outline),
                  _doseCard(doses[i]),
                ],
              ],
            )),
          ],
        ),
      );

  Widget _doseCard(DailyDose dose) {
    final status = switch (dose.status) {
      'taken' => ('مصرف شد', Icons.check_circle, AppColors.success),
      'skipped' => ('مصرف نکردم', Icons.cancel_outlined, Colors.deepOrange),
      'unknown' => ('نامشخص', Icons.help_outline, AppColors.muted),
      _ => ('ثبت مصرف', Icons.check, AppColors.primary),
    };
    return InkWell(
      onTap: _saving ? null : () => _showDoseActions(dose),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          MedicineArtwork(seed: dose.medication.name, size: 45),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dose.medication.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            Text('${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))}  ·  '
              '${PersianDate.persianDigits(dose.plan.doseText)}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ])),
          AppStatusPill(text: status.$1, icon: status.$2, color: status.$3),
          const SizedBox(width: 3),
          const Icon(Icons.chevron_left, color: AppColors.muted, size: 18),
        ]),
      ),
    );
  }

  Future<void> _showDoseActions(DailyDose dose) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ثبت مصرف دارو', style: TextStyle(fontWeight: FontWeight.w900,
            fontSize: 19, color: AppColors.primaryDark)),
          const SizedBox(height: 16),
          Row(children: [
            MedicineArtwork(seed: dose.medication.name, size: 58),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dose.medication.name, style: const TextStyle(fontSize: 17,
                fontWeight: FontWeight.w800)),
              Text('نوبت امروز: ${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))}',
                style: const TextStyle(color: AppColors.muted)),
              Text('طبق ثبت شما: ${PersianDate.persianDigits(dose.plan.doseText)}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ])),
          ]),
          const SizedBox(height: 24),
          if (dose.status == 'pending') ...[
            AppGradientButton(label: 'مصرف کردم', icon: Icons.check,
              onPressed: () => Navigator.pop(sheetContext, 'taken'), light: true),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => Navigator.pop(sheetContext, 'skipped'),
              icon: const Icon(Icons.close), label: const Text('مصرف نکردم')),
            TextButton(onPressed: () => Navigator.pop(sheetContext, 'unknown'),
              child: const Text('مطمئن نیستم')),
          ] else ...[
            AppStatusPill(text: 'وضعیت قبلاً ثبت شده است', color: AppColors.primary),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => Navigator.pop(sheetContext, 'undo'),
              icon: const Icon(Icons.undo), label: const Text('بازگرداندن ثبت')),
          ],
          const Text('کسر موجودی فقط با تأیید مقدار واقعی انجام می‌شود.',
            style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    await _mark(dose, action);
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

String _clock(TimeOfDay time) => PersianDate.persianDigits(
  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
);
