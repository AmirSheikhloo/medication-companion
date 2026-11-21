import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_database.dart';
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

const _deepTeal = Color(0xFF075F60);
const _mint = Color(0xFF40E0D0);
const _paleMint = Color(0xFFE1F8F6);
const _betaRunNumber = String.fromEnvironment('BETA_RUN_NUMBER', defaultValue: 'محلی');
const _keyboardSettings = MethodChannel('medication_companion/keyboard_settings');

String _normalizeMedicineSearch(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک');

enum _MedicineFilter { all, lowStock, archived }

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
  _MedicineFilter _medicineFilter = _MedicineFilter.all;
  String? _expandedMedicationId;
  bool _searchVisible = false;
  final _medicineSearch = TextEditingController();
  List<DailyDose> _doses = [];
  Map<String, StockSummary> _stocks = {};

  InventoryRepository get _inventory => InventoryRepository(widget.repository.db);
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
          const SnackBar(content: Text('بازکردن تنظیمات کیبورد ممکن نشد؛ از تنظیمات اندروید وارد شوید.')),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تنظیمات کیبورد فقط در نسخهٔ اندروید در دسترس است.')),
        );
      }
    }
  }

  Future<void> _openCareHub() async {
    final profile = _active;
    if (profile == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CareHubScreen(
        profile: profile,
        repository: CareRepository(widget.repository.db),
        reminderCoordinator: widget.careReminderCoordinator,
      ),
    ));
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
      final doses = profile == null
          ? <DailyDose>[]
          : await widget.repository.dosesForDay(profile.id, DateTime.now());
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
          _medicineFilter = _MedicineFilter.all;
          _expandedMedicationId = null;
        }
        _active = profile;
        _profiles = profiles;
        _medications = meds;
        _archivedMedications = archivedMeds;
        _doses = doses;
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
    await _perform(() => widget.profileRepository.createGuestProfile(
          forSelf: forSelf,
          displayName: name,
        ));
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
            SnackBar(content: Text('تغییر ذخیره شد ولی یادآور به‌روز نشد: $error')),
          );
        }
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ذخیره انجام نشد: $error')),
      );
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
    await _perform(() => widget.repository.addMedicationSchedule(
          profileId: profile.id,
          name: draft.name,
          slots: [
            for (final slot in draft.slots)
              DoseSlotInput(
                doseText: slot.dose,
                time: TimeOfDayValue(slot.time.hour, slot.time.minute),
              ),
          ],
        ));
  }

  Future<void> _editMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final doses = await widget.repository
        .dosesForMedicationOnDay(profile.id, medication.id, tomorrow);
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
    await _perform(() => widget.repository.updateMedicationSchedule(
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
        ));
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
    await _perform(() => widget.repository.setArchived(
          profileId: profile.id,
          medicationId: medication.id,
          archived: true,
        ));
  }

  Future<void> _restoreMedication(Medication medication) async {
    final profile = _active;
    if (profile == null || _saving) return;
    await _perform(() => widget.repository.setArchived(
          profileId: profile.id,
          medicationId: medication.id,
          archived: false,
        ));
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
        context, medicationName: dose.medication.name, stock: stock);
      if (!mounted || choice == null) return;
    }
    await _perform(() => widget.repository.recordDose(
          dose: dose,
          profileId: profile.id,
          action: action,
          stockPackageId: choice?.packageId,
          stockQuantityMilliunits: choice?.quantityMilliunits,
        ));
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
                FilledButton(onPressed: _reload, child: const Text('تلاش مجدد')),
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
        title: const Text('همراه دارو'),
        actions: [
          IconButton(
            tooltip: 'تازه‌سازی',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
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
          NavigationDestination(icon: Icon(Icons.today_outlined), label: 'امروز'),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined), label: 'داروها',
          ),
          NavigationDestination(icon: Icon(Icons.favorite_outline), label: 'سلامت'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'بیشتر'),
        ],
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _addMedication,
              backgroundColor: _mint,
              foregroundColor: _deepTeal,
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _paleMint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: _deepTeal),
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
                      child: Text('پروفایل: ${profile.displayName}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (id) {
                        if (id != null) {
                          _perform(() => widget.profileRepository.selectActiveProfile(id));
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
    DailyDose? nextDose;
    for (final dose in _doses) {
      if (dose.status == 'pending' && dose.scheduledAt.isAfter(now)) {
        nextDose = dose;
        break;
      }
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          _sectionTitle('نوبت‌های امروز'),
          const SizedBox(height: 5),
          Text(
            'ثبت‌های این بخش فقط اعلام شما هستند، نه تأیید پزشکی مصرف.',
            style: TextStyle(color: Colors.blueGrey.shade700),
          ),
          const SizedBox(height: 12),
          if (_doses.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('خلاصه امروز',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: taken / _doses.length,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFE4F0EE),
                        color: _deepTeal,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      Chip(label: Text('مصرف‌شده: $taken')),
                      Chip(label: Text('ثبت‌نشده: $pending')),
                      Chip(label: Text('سایر وضعیت‌ها: $other')),
                    ]),
                    if (nextDose != null) ...[
                      const SizedBox(height: 8),
                      Text('نوبت بعدی: ${nextDose.medication.name} — '
                          '${_clock(TimeOfDay.fromDateTime(nextDose.scheduledAt))}'),
                    ],
                  ],
                ),
              ),
            ),
          if (_doses.isEmpty)
            _emptyCard(
              'هنوز دارویی ثبت نکرده‌اید.',
              'برای شروع، دارو و زمان آن را طبق نسخه وارد کنید.',
              'افزودن اولین دارو',
              () => setState(() => _tab = 1),
            ),
          for (final dose in _doses) _doseCard(dose),
          if (_doses.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _saving ? null : _addMedication,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('افزودن داروی جدید'),
            ),
          const SizedBox(height: 16),
          const _InfoNote(
            'یادآوری را از «بیشتر» فعال کنید. کسر موجودی فقط پس از تأیید مقدار واقعی انجام می‌شود.',
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

  Widget _doseCard(DailyDose dose) {
    final status = switch (dose.status) {
      'taken' => ('مصرف ثبت شد', Icons.check_circle_outline, Colors.green),
      'skipped' => ('مصرف نکردم', Icons.remove_circle_outline, Colors.orange),
      'unknown' => ('نامشخص', Icons.help_outline, Colors.blueGrey),
      _ => ('ثبت نشده', Icons.schedule, Colors.blueGrey),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medication_outlined, color: _deepTeal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(dose.medication.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(_clock(TimeOfDay.fromDateTime(dose.scheduledAt))),
              ],
            ),
            const SizedBox(height: 8),
            Text('طبق ثبت شما: ${dose.plan.doseText}'),
            if (dose.status == 'taken')
              Text(
                dose.stockDebited
                    ? 'از موجودی بسته انتخاب‌شده کسر شد.'
                    : 'مصرف بدون کسر موجودی ثبت شده است.',
                style: TextStyle(color: Colors.blueGrey.shade700),
              ),
            if (_stocks[dose.medication.id]?.lowStock == true)
              const Text('هشدار: موجودی بسته انتخاب‌شده کم است.',
                  style: TextStyle(color: Colors.deepOrange)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(status.$2, color: status.$3, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(status.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: status.$3)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text('برای ${_active!.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end),
              ),
            ]),
            const SizedBox(height: 12),
            if (dose.status == 'pending') ...[
              FilledButton.icon(
                onPressed: _saving ? null : () => _mark(dose, 'taken'),
                icon: const Icon(Icons.check),
                label: const Text('مصرف کردم'),
              ),
              Wrap(spacing: 8, children: [
                TextButton(
                  onPressed: _saving ? null : () => _mark(dose, 'skipped'),
                  child: const Text('مصرف نکردم'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _mark(dose, 'unknown'),
                  child: const Text('مطمئن نیستم'),
                ),
              ]),
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
    final source = _medicineFilter == _MedicineFilter.archived
        ? _archivedMedications
        : _medications.where((med) =>
            _medicineFilter != _MedicineFilter.lowStock ||
            _stocks[med.id]?.lowStock == true).toList();
    final visible = source
        .where((med) => _normalizeMedicineSearch(med.name).contains(query))
        .toList();
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('داروها'),
                  Text(
                    '${_medications.length} داروی فعال برای ${_active!.displayName}',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  ),
                ],
              ),
            ),
            if (_medications.isNotEmpty)
              IconButton(
                tooltip: _searchVisible ? 'بستن جست‌وجوی دارو' : 'جست‌وجوی دارو',
                icon: Icon(_searchVisible ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searchVisible = !_searchVisible;
                  if (!_searchVisible) _medicineSearch.clear();
                }),
              ),
          ]),
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
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ChoiceChip(
              label: Text('همه (${_medications.length})'),
              selected: _medicineFilter == _MedicineFilter.all,
              onSelected: (_) => setState(() {
                _medicineFilter = _MedicineFilter.all;
                _expandedMedicationId = null;
              }),
            ),
            ChoiceChip(
              label: const Text('کم‌موجودی'),
              selected: _medicineFilter == _MedicineFilter.lowStock,
              onSelected: (_) => setState(() {
                _medicineFilter = _MedicineFilter.lowStock;
                _expandedMedicationId = null;
              }),
            ),
            ChoiceChip(
              label: Text('بایگانی (${_archivedMedications.length})'),
              selected: _medicineFilter == _MedicineFilter.archived,
              onSelected: (_) => setState(() {
                _medicineFilter = _MedicineFilter.archived;
                _expandedMedicationId = null;
              }),
            ),
          ]),
          const SizedBox(height: 12),
          if (_medications.isEmpty &&
              _archivedMedications.isEmpty &&
              query.isEmpty)
            _emptyCard(
              'فهرست دارو خالی است.',
              'نام دارو و ساعت‌های روزانه را طبق نسخه وارد کنید.',
              'افزودن دارو',
              _addMedication,
            )
          else if (visible.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(query.isNotEmpty
                    ? 'دارویی با این نام پیدا نشد.'
                    : _medicineFilter == _MedicineFilter.lowStock
                        ? 'داروی کم‌موجودی در فهرست فعال پیدا نشد.'
                        : _medicineFilter == _MedicineFilter.archived
                            ? 'هنوز دارویی بایگانی نشده است.'
                            : 'داروی فعالی وجود ندارد.'),
              ),
            ),
          if (visible.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        indent: 14,
                        endIndent: 14,
                        color: Color(0xFFE1ECEB),
                      ),
                    _medicationCard(
                      visible[i],
                      archived: _medicineFilter == _MedicineFilter.archived,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() {
              _medicineFilter = _medicineFilter == _MedicineFilter.archived
                  ? _MedicineFilter.all
                  : _MedicineFilter.archived;
              _expandedMedicationId = null;
            }),
            icon: Icon(_medicineFilter == _MedicineFilter.archived
                ? Icons.arrow_back
                : Icons.inventory_2_outlined),
            label: Text(_medicineFilter == _MedicineFilter.archived
                ? 'بازگشت به داروهای فعال'
                : 'نمایش بایگانی (${_archivedMedications.length})'),
          ),
          const SizedBox(height: 12),
          const _InfoNote(
            'ویرایش برنامه روزانه از فردا اعمال می‌شود. '
            'ثبت‌های قبلی حفظ می‌شوند؛ یادآورها با فعال‌سازی در بخش «بیشتر» هماهنگ می‌شوند.',
          ),
        ],
      );
  }

  Widget _medicationCard(Medication med, {bool archived = false}) {
    final slots = _doses
        .where((dose) => dose.medication.id == med.id)
        .toList();
    final stock = _stocks[med.id];
    final selected = stock?.selected;
    final stockLine = selected == null
        ? 'موجودی بسته انتخاب نشده'
        : 'بسته: ${selected.package.label} — '
          '${StockQuantity.format(selected.balanceMilliunits)} ${selected.package.unit}'
          '${selected.expired ? ' (منقضی)' : ''}'
          '${stock!.lowStock ? ' (هشدار کمبود)' : ''}';
    final lowStock = stock?.lowStock == true;
    final expanded = _expandedMedicationId == med.id;
    final times = slots.isEmpty
        ? 'برای مشاهدهٔ برنامه، باز کنید'
        : slots.map((dose) =>
            _clock(TimeOfDay.fromDateTime(dose.scheduledAt))).join('، ');
    final stockBrief = selected == null
        ? 'بدون بسته'
        : '${StockQuantity.format(selected.balanceMilliunits)} ${selected.package.unit}';
    return Column(children: [
      InkWell(
        key: ValueKey('medication-row-${med.id}'),
        onTap: () => setState(() =>
            _expandedMedicationId = expanded ? null : med.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: _paleMint,
              child: Icon(Icons.medication_outlined, color: _deepTeal),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    med.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _deepTeal,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    archived ? 'بایگانی‌شده؛ سوابق حفظ شده‌اند' : times,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (!archived)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 78),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (lowStock)
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: Color(0xFFAD6600)),
                    Text(
                      stockBrief,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        color: lowStock
                            ? const Color(0xFF9A6400)
                            : Colors.blueGrey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            if (archived)
              TextButton(
                onPressed: _saving ? null : () => _restoreMedication(med),
                child: const Text('بازیابی'),
              )
            else
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
                  PopupMenuItem(value: 'stock', child: Text('موجودی و بسته‌ها')),
                  PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                  PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                ],
              ),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: !expanded
            ? const SizedBox.shrink()
            : Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _paleMint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (slots.isEmpty)
                      const Text('برنامهٔ روزانه ثبت شده است.')
                    else
                      for (final dose in slots)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            const Icon(Icons.schedule_outlined,
                                size: 18, color: _deepTeal),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))} — '
                                '${dose.plan.doseText}',
                              ),
                            ),
                          ]),
                        ),
                    if (!archived) ...[
                      const SizedBox(height: 4),
                      Text(stockLine, softWrap: true),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : () => _openStock(med),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('موجودی'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : () => _editMedication(med),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('ویرایش'),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
      ),
    ]);
  }

  Widget _moreTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('پشتیبان‌گیری'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) =>
                          SecureBackupScreen(database: widget.repository.db),
                    )),
            icon: const Icon(Icons.enhanced_encryption_outlined),
            label: const Text('ساخت پشتیبان رمزگذاری‌شده'),
          ),
          const Text('در نسخهٔ بتا ساخت پشتیبان و بررسی فایل امکان‌پذیر است؛ بازیابی اطلاعات هنوز فعال نیست.'),
          const SizedBox(height: 20),
          _sectionTitle('پیگیری‌ها و ویزیت‌ها'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openCareHub,
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('باز کردن کارها و چک‌لیست ویزیت'),
          ),
          if (_careReminderError != null)
            Text('اشکال در اعلان‌های پیگیری: $_careReminderError',
                style: const TextStyle(color: Colors.deepOrange)),
          const SizedBox(height: 20),
          _sectionTitle('پروفایل‌های محلی'),
          const SizedBox(height: 12),
          for (final profile in _profiles)
            Card(
              child: ListTile(
                title: Text(profile.displayName),
                subtitle: Text(profile.kind == 'self' ? 'برای خودم' : 'تحت مدیریت من'),
                trailing: profile.id == _active?.id
                    ? const Icon(Icons.check_circle, color: _deepTeal)
                    : const Icon(Icons.chevron_left),
                onTap: profile.id == _active?.id || _saving
                    ? null
                    : () => _perform(() =>
                        widget.profileRepository.selectActiveProfile(profile.id)),
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
          Text(_remindersEnabled
              ? 'فعال: یادآورها برای همه پروفایل‌های محلی تنظیم می‌شوند.'
              : 'غیرفعال: تا اجازه ندهید، یادآور دارو ثبت نمی‌شود.'),
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
          ),
          const SizedBox(height: 20),
          _sectionTitle('ورود متن فارسی'),
          const SizedBox(height: 8),
          const Text(
            'فیلدهای برنامه حروف فارسی را می‌پذیرند. اگر فقط انگلیسی می‌بینید، '
            'در کیبورد گوشی زبان فارسی را فعال کنید. '
            'پس از افزودن فارسی در Gboard، با نگه‌داشتن کلید فاصله زبان را عوض کنید.',
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
          Text(_betaRunNumber == 'محلی'
              ? 'ساخت محلی'
              : 'شماره ساخت آزمایشی: CI$_betaRunNumber'),
          const SizedBox(height: 12),
          const _InfoNote(
            'این نسخهٔ بتای خصوصی است؛ داده‌ها فقط روی همین دستگاه‌اند. حساب آنلاین، همگام‌سازی و بازیابی پشتیبان فعال نیستند. برای مصرف دارو به اعلان برنامه به‌تنهایی تکیه نکنید.',
          ),
        ],
      );

  Widget _emptyCard(String title, String description, String button,
      VoidCallback onTap) => Card(
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

  Widget _sectionTitle(String title) => Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF124B49),
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

String _clock(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
