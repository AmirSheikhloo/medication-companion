import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/guest_welcome_screen.dart';
import '../data/medication_repository.dart';

const _teal = Color(0xFF40E0D0);
const _deepTeal = Color(0xFF008F87);

class MedicationHome extends StatefulWidget {
  const MedicationHome({
    super.key,
    required this.repository,
    required this.profileRepository,
  });

  final MedicationRepository repository;
  final ProfileRepository profileRepository;

  @override
  State<MedicationHome> createState() => _MedicationHomeState();
}

class _MedicationHomeState extends State<MedicationHome> {
  bool _loading = true;
  bool _saving = false;
  int _tab = 0;
  Profile? _active;
  List<Profile> _profiles = [];
  List<Medication> _medications = [];
  List<DailyDose> _doses = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profile = await widget.profileRepository.activeProfile();
      final profiles = await widget.profileRepository.profiles();
      final meds = profile == null
          ? <Medication>[]
          : await widget.repository.medicationsFor(profile.id);
      final doses = profile == null
          ? <DailyDose>[]
          : await widget.repository.dosesForDay(profile.id, DateTime.now());
      if (!mounted) return;
      setState(() {
        _active = profile;
        _profiles = profiles;
        _medications = meds;
        _doses = doses;
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
      name = await _askProfileName();
      if (name == null) return;
    }
    await _perform(() => widget.profileRepository.createGuestProfile(
          forSelf: forSelf,
          displayName: name,
        ));
  }

  Future<String?> _askProfileName() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('پروفایل عزیزتان'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('نام دلخواه؛ می‌توانید از نام مستعار استفاده کنید.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'نام نمایشی',
                  hintText: 'مثلاً مادر',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('ادامه'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _perform(Future<dynamic> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
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
    if (profile == null) return;
    final nameController = TextEditingController();
    final doseController = TextEditingController();
    TimeOfDay selected = const TimeOfDay(hour: 8, minute: 0);
    _MedicationForm? result;
    try {
      result = await showModalBottomSheet<_MedicationForm>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, updateSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'افزودن دارو برای ${profile.displayName}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'فقط اطلاعات تجویزشده را ثبت کنید؛ برنامه مقدار مصرفی پیشنهاد نمی‌کند.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    maxLength: 160,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'نام دارو',
                      hintText: 'نام روی نسخه یا جعبه',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: doseController,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'شرح مصرف طبق نسخه',
                      hintText: 'مثلاً ۱ عدد؛ مقدار را خودتان وارد کنید',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label: Text('زمان روزانه: ${_clock(selected)}'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selected,
                      );
                      if (picked != null) updateSheet(() => selected = picked);
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('ذخیره دارو'),
                    onPressed: () {
                      if (nameController.text.trim().isEmpty ||
                          doseController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('نام و شرح مصرف را کامل کنید.'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(
                        sheetContext,
                        _MedicationForm(
                          nameController.text,
                          doseController.text,
                          selected,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      nameController.dispose();
      doseController.dispose();
    }
    if (result == null) return;
    final data = result;
    await _perform(() => widget.repository.addDailyMedication(
          profileId: profile.id,
          name: data.name,
          doseText: data.dose,
          time: TimeOfDayValue(data.time.hour, data.time.minute),
        ));
  }

  Future<void> _mark(DailyDose dose, String action) async {
    final profile = _active;
    if (profile == null) return;
    await _perform(() => widget.repository.recordDose(
          dose: dose,
          profileId: profile.id,
          action: action,
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
            'این نسخه فقط ثبت مصرف را نگه می‌دارد. اعلان خودکار برنامه دارویی و کسر موجودی در M2 فعال می‌شوند.',
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
          const SizedBox(height: 16),
          if (_medications.isEmpty)
            _emptyCard(
              'فهرست دارو خالی است.',
              'نام دارو، شرح مصرف و زمان روزانه را خودتان وارد کنید.',
              'افزودن دارو',
              _addMedication,
            ),
          for (final med in _medications)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0F8F5),
                  child: Icon(Icons.medication, color: _deepTeal),
                ),
                title: Text(med.name),
                subtitle: Text(() {
                  for (final dose in _doses) {
                    if (dose.medication.id == med.id) {
                      return '${dose.plan.doseText} — ${_clock(TimeOfDay.fromDateTime(dose.scheduledAt))}';
                    }
                  }
                  return 'برنامه روزانه ثبت‌شده';
                }()),
              ),
            ),
        ],
      );

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

class _MedicationForm {
  const _MedicationForm(this.name, this.dose, this.time);
  final String name;
  final String dose;
  final TimeOfDay time;
}

String _clock(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
