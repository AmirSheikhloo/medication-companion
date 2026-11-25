import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key, required this.profiles, required this.activeId,
    required this.onSelect, required this.onAdd});

  final List<Profile> profiles;
  final String activeId;
  final Future<void> Function(String) onSelect;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.surface(context, AppColors.background),
    appBar: AppBar(title: const Text('پروفایل‌ها')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const AppSoftHeader(title: 'پروفایل‌های محلی', icon: Icons.shield_outlined,
        subtitle: 'اطلاعات هر پروفایل جداگانه نگهداری می‌شود.'),
      const SizedBox(height: 16),
      for (final profile in profiles)
        Padding(padding: const EdgeInsets.only(bottom: 9), child: AppPanel(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            leading: CircleAvatar(backgroundColor: profile.id == activeId
                ? AppColors.primary : AppColors.mint,
              foregroundColor: profile.id == activeId ? Colors.white : AppColors.primary,
              child: Text(PersianDate.displayDigits(profile.displayName).characters.first)),
            title: Text(PersianDate.displayDigits(profile.displayName), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(profile.id == activeId ? 'پروفایل فعلی' :
              profile.kind == 'self' ? 'برای خودم' : 'تحت مدیریت من'),
            trailing: Icon(profile.id == activeId ? Icons.check_circle : Icons.radio_button_unchecked,
              color: profile.id == activeId ? AppColors.primary : AppColors.muted),
            onTap: profile.id == activeId ? null : () async {
              await onSelect(profile.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        )),
      const SizedBox(height: 10),
      AppGradientButton(label: 'افزودن پروفایل', icon: Icons.person_add_alt_1_outlined,
        onPressed: () async {
          await onAdd();
          if (context.mounted) Navigator.pop(context);
        }),
    ]),
  );
}

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key, required this.initiallyEnabled,
    required this.onEnable, required this.onDisable, required this.onTest,
    this.errorMessage, required this.available});

  final bool initiallyEnabled;
  final bool available;
  final Future<void> Function() onEnable;
  final Future<void> Function() onDisable;
  final Future<void> Function() onTest;
  final String? errorMessage;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  late bool _enabled;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _enabled = widget.initiallyEnabled;
  }

  Future<void> _change(bool enable) async {
    setState(() => _busy = true);
    try {
      if (enable) { await widget.onEnable(); } else { await widget.onDisable(); }
      if (mounted) setState(() => _enabled = enable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.surface(context, AppColors.background),
    appBar: AppBar(title: const Text('یادآوری‌ها')),
    body: ListView(padding: const EdgeInsets.all(15), children: [
      AppSoftHeader(title: _enabled ? 'مجوز اعلان‌ها: فعال' : 'مجوز اعلان‌ها: غیرفعال',
        icon: _enabled ? Icons.check_circle_outline : Icons.notifications_off_outlined),
      const SizedBox(height: 15),
      AppPanel(padding: EdgeInsets.zero, child: Column(children: [
        SwitchListTile.adaptive(
          secondary: const AppIconTile(Icons.medication_outlined),
          title: const Text('یادآوری مصرف', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('اعلان برای نوبت‌های مصرف داروها'),
          value: _enabled, onChanged: !_busy && widget.available ? _change : null),
        const Divider(height: 1),
        ListTile(leading: const AppIconTile(Icons.calendar_month_outlined),
          title: const Text('تنظیمات یادآوری'),
          subtitle: const Text('زمان‌بندی طبق برنامه داروهای هر پروفایل')),
        const Divider(height: 1),
        const ListTile(leading: AppIconTile(Icons.battery_std_outlined),
          title: Text('بررسی تنظیمات باتری'),
          subtitle: Text('محدودیت باتری ممکن است اعلان‌ها را به تأخیر بیندازد.')),
      ])),
      const SizedBox(height: 20),
      OutlinedButton.icon(onPressed: _enabled && !_busy ? widget.onTest : null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('تست اعلان — 5 ثانیه دیگر')),
      if (_enabled) TextButton.icon(onPressed: _busy ? null : () => _change(false),
        icon: const Icon(Icons.notifications_off_outlined),
        label: const Text('خاموش کردن یادآورها')),
      if (widget.errorMessage != null)
        Text(widget.errorMessage!, style: const TextStyle(color: Colors.deepOrange)),
      const SizedBox(height: 12),
      const AppSoftHeader(title: 'یادآوری، جایگزین مراقبت پزشکی نیست',
        subtitle: 'نمایش اعلان به تنظیمات دستگاه و مجوزهای سیستم بستگی دارد.',
        icon: Icons.info_outline),
    ]),
  );
}

class KeyboardHelpScreen extends StatelessWidget {
  const KeyboardHelpScreen({super.key, required this.onOpenSettings});
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.surface(context, AppColors.background),
    appBar: AppBar(title: const Text('تنظیمات زبان و صفحه‌کلید')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const AppSoftHeader(title: 'ورود متن فارسی', icon: Icons.keyboard_outlined,
        subtitle: 'راهنمای فعال‌کردن کیبورد فارسی'),
      const SizedBox(height: 14),
      const AppPanel(child: Text('فیلدهای برنامه فارسی را می‌پذیرند. '
        'اگر فقط انگلیسی می‌بینید، زبان فارسی را در تنظیمات کیبورد فعال کنید. '
        'در Gboard، پس از افزودن فارسی، با نگه‌داشتن کلید فاصله زبان را عوض کنید.')),
      const SizedBox(height: 17),
      AppGradientButton(label: 'بازکردن تنظیمات زبان کیبورد',
        icon: Icons.keyboard_outlined, onPressed: onOpenSettings),
    ]),
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.buildNumber});
  final String buildNumber;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.surface(context, AppColors.background),
    appBar: AppBar(title: const Text('درباره برنامه')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const AppSoftHeader(title: 'همراه دارو', icon: Icons.medication_outlined,
        subtitle: 'مدیریت دارو، موجودی و پیگیری سلامت'),
      const SizedBox(height: 13),
      AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('نسخهٔ آزمایشی 0.3.0',
          style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(buildNumber == 'محلی' ? 'ساخت محلی' : 'شماره ساخت آزمایشی: CI$buildNumber'),
        const SizedBox(height: 12),
        const Text('اطلاعات روی همین دستگاه ذخیره می‌شوند. حساب آنلاین، '
          'همگام‌سازی و بازیابی فایل پشتیبان هنوز فعال نیستند. '
          'این برنامه جایگزین توصیه پزشک یا داروساز نیست.'),
      ])),
    ]),
  );
}
