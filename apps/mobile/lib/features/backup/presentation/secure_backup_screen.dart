import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_database.dart';
import '../domain/backup_password_policy.dart';

class SecureBackupScreen extends StatefulWidget {
  const SecureBackupScreen({super.key, required this.database});

  final AppDatabase database;

  @override
  State<SecureBackupScreen> createState() => _SecureBackupScreenState();
}

class _SecureBackupScreenState extends State<SecureBackupScreen> {
  static const _channel = MethodChannel('medication_companion/secure_backup');
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String _phase = '';
  String? _error;
  String? _result;

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _startExport() async {
    final password = _password.text;
    final problem = backupPasswordError(password, _confirmation.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _phase = 'در انتظار انتخاب محل ذخیره...';
    });
    try {
      final now = DateTime.now();
      final date = '${now.year}${_two(now.month)}${_two(now.day)}';
      final time = '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      final name = 'medication-backup-$date-$time.medbackup';
      final chosen = await _channel.invokeMethod<bool>(
        'chooseDestination',
        {'filename': name},
      );
      if (chosen != true) {
        if (mounted) setState(() => _phase = 'انتخاب فایل لغو شد؛ هیچ داده‌ای تغییر نکرد.');
        return;
      }
      if (mounted) setState(() => _phase = 'ساخت تصویر امن، رمزگذاری و راستی‌آزمایی...');
      final info = await widget.database.customSelect('PRAGMA database_list').get();
      final files = info.where((row) => row.read<String>('name') == 'main');
      if (files.isEmpty) throw StateError('مسیر پایگاه داده پیدا نشد');
      final databasePath = files.first.read<String>('file');
      if (databasePath.isEmpty) throw StateError('مسیر پایگاه داده خالی است');
      final output = await _channel.invokeMapMethod<String, dynamic>(
        'export',
        {'databasePath': databasePath, 'password': password},
      );
      if (!mounted) return;
      final verified = output?['verified'] == true;
      final bytes = output?['bytes'] as num?;
      setState(() {
        _result = verified
            ? 'ذخیره شد و قابل‌خواندن تأیید شد. حجم فایل: ${bytes ?? '?'} بایت.'
            : 'ذخیره شد، اما امکان بازخوانی فایل از محل انتخابی وجود نداشت؛ '
                'صحت فایل در مقصد تأیید نشد. لطفاً آن را در یک محل دیگر نیز ذخیره و بررسی کنید.';
        _phase = '';
        _password.clear();
        _confirmation.clear();
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'ساخت پشتیبان انجام نشد.');
    } catch (_) {
      if (mounted) setState(() => _error = 'ساخت پشتیبان انجام نشد؛ داده‌های فعلی تغییری نکردند.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('پشتیبان رمزگذاری‌شده')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.enhanced_encryption_outlined,
                size: 56, color: Color(0xff008f87)),
            const SizedBox(height: 16),
            Text('ساخت فایل پشتیبان آفلاین',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              'از تمام پروفایل‌ها، برنامه‌های دارویی، رویدادهای مصرف، موجودی، '
              'اندازه‌گیری‌های سلامت و پیگیری‌ها در یک فایل رمزگذاری‌شده پشتیبان گرفته می‌شود. '
              'اعلان‌های سیستم از روی اطلاعات بازسازی می‌شوند و در خود فایل ذخیره نمی‌شوند.',
            ),
            const SizedBox(height: 12),
            const Card(
              color: Color(0xfffff4df),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'مهم: اگر رمز را فراموش کنید، هیچ‌کس نمی‌تواند فایل را بازیابی کند. '
                  'فایل را در یک محل مطمئن نگه دارید. '
                  'این قابلیت هنوز دیتابیس داخل گوشی را رمزگذاری نمی‌کند و '
                  'بازگردانی اطلاعات در مرحله بعد فعال خواهد شد.',
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'رمز پشتیبان (حداقل ۱۲ نویسه)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'پنهان‌کردن رمز' : 'نمایش رمز',
                  onPressed: _busy ? null : () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              enabled: !_busy,
              obscureText: !_showPassword,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'تکرار رمز پشتیبان',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _startExport,
              icon: const Icon(Icons.save_alt),
              label: const Text('انتخاب محل و ساخت پشتیبان'),
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_phase.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_phase),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              SelectableText(_result!, style: const TextStyle(color: Color(0xff007b66))),
            ],
          ],
        ),
      );
}
