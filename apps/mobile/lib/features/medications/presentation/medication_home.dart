import 'package:material_ui/material_ui.dart';

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

const _teal = Color(0xFF40E0D0);
const _deepTeal = Color(0xFF008F87);

class MedicationHome extends StatefulWidget {
  const MedicationHome({
    super.key,
    required this.repository,
    required this.profileRepository,
    this.reminderCoordinator,
  });

  final MedicationRepository repository;
  final ProfileRepository profileRepository;
  final ReminderCoordinator? reminderCoordinator;

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
  List<DailyDose> _doses = [];
  Map<String, StockSummary> _stocks = {};

  InventoryRepository get _inventory => InventoryRepository(widget.repository.db);
  String? _error;
  bool _remindersEnabled = false;
  String? _reminderError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
    _syncReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncReminders();
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
                _placeholder(
                  Icons.favorite_border,
                  'سلامت',
                  'ثبت شاخص‌ها، نمودار و گزارش پزشک در بسته بعدی می‌آیند.',
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
              backgroundColor: _teal,
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
        color: const Color(0xFFE0F8F5),
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
                      child: Text('پروفایل: ${profile.displayName}'),
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

  Widget _todayTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          _sectionTitle('نوبت‌های امروز'),
          const SizedBox(height: 5),
          Text(
            'ثبت‌های این بخش فقط اعلام شما هستند، نه تأیید پزشکی مصرف.',
            style: TextStyle(color: Colors.blueGrey.shade700),
          ),
          const SizedBox(height: 12),
          if (_doses.isEmpty)
            _emptyCard(
              'هنوز دارویی ثبت نکرده‌اید.',
              'برای شروع، دارو و زمان آن را طبق نسخه وارد کنید.',
              'افزودن اولین دارو',
              () => setState(() => _tab = 1),
            ),
          for (final dose in _doses) _doseCard(dose),
          const SizedBox(height: 16),
          const _InfoNote(
            'یادآوری را از «بیشتر» فعال کنید. کسر موجودی فقط پس از تأیید مقدار واقعی انجام می‌شود.',
          ),
        ],
      );

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
              Text(status.$1, style: TextStyle(color: status.$3)),
              const Spacer(),
              Text('برای ${_active!.displayName}'),
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

  Widget _medicinesTab() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _sectionTitle('داروهای ${_active!.displayName}'),
          const SizedBox(height: 10),
          const Text(
            'برای ویرایش یا بایگانی، منوی سه‌نقطه هر دارو را باز کنید.',
          ),
          const SizedBox(height: 12),
          if (_medications.isEmpty)
            _emptyCard(
              'فهرست دارو خالی است.',
              'نام دارو و ساعت‌های روزانه را طبق نسخه وارد کنید.',
              'افزودن دارو',
              _addMedication,
            ),
          for (final med in _medications) _medicationCard(med),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() => _showArchived = !_showArchived),
            icon: Icon(_showArchived
                ? Icons.expand_less
                : Icons.inventory_2_outlined),
            label: Text(_showArchived
                ? 'پنهان کردن بایگانی'
                : 'نمایش بایگانی (${_archivedMedications.length})'),
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
            'ویرایش برنامه روزانه از فردا اعمال می‌شود. '
            'ثبت‌های قبلی حفظ می‌شوند؛ یادآورها با فعال‌سازی در بخش «بیشتر» هماهنگ می‌شوند.',
          ),
        ],
      );

  Widget _medicationCard(Medication med) {
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
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE0F8F5),
          child: Icon(Icons.medication, color: _deepTeal),
        ),
        title: Text(med.name),
        subtitle: Text([
          if (slots.isEmpty)
            'برنامه روزانه ثبت‌شده'
          else
            for (final dose in slots)
              '${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))} — '
                  '${dose.plan.doseText}',
          stockLine,
        ].join('\n')),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
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
      ),
    );
  }

  Widget _moreTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          _sectionTitle('یادآوری دارو — آزمایشی'),
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
            'این قابلیت برای تست است و جایگزین مراقبت پزشکی نیست.',
          ),
          const SizedBox(height: 20),
          const _InfoNote(
            'حالت مهمان کاملاً محلی است. هنوز حساب آنلاین، همگام‌سازی، پشتیبان رمزنگاری‌شده و پنل مدیریتی فعال نیستند. برای داده پزشکی واقعی تا تکمیل امنیت و پشتیبان‌گیری از این نسخه آزمایشی استفاده نکنید.',
          ),
        ],
      );

  Widget _placeholder(IconData icon, String title, String description) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: _deepTeal),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
            ],
          ),
        ),
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
