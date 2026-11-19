import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../data/read_only_import_retention.dart';
import '../data/restore_read_only_preflight.dart';
import '../data/secure_backup_inspector.dart';
import '../data/secure_backup_snapshot.dart';
import '../domain/backup_password_policy.dart';

class SecureBackupScreen extends StatefulWidget {
  const SecureBackupScreen({super.key, required this.database});

  final AppDatabase database;

  @override
  State<SecureBackupScreen> createState() => _SecureBackupScreenState();
}

class _SecureBackupScreenState extends State<SecureBackupScreen> with WidgetsBindingObserver {
  static const _channel = MethodChannel('medication_companion/secure_backup');
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _importPassword = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String _phase = '';
  String? _error;
  String? _result;
  Map<String, int>? _importCounts;
  Map<String, int>? _currentCounts;
  ReadOnlyImportRetention? _retainedPreview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<bool> _nativeClearImport(String path) async =>
      await _channel.invokeMethod<bool>('clearImport', {'path': path}) == true;

  Future<void> _clearRetainedPreview() async {
    final retained = _retainedPreview;
    if (retained == null) return;
    await retained.close();
    if (identical(_retainedPreview, retained)) _retainedPreview = null;
  }

  void _invalidateForLifecycle() {
    final retained = _retainedPreview;
    if (retained == null) return;
    // Close is idempotent and invalidates synchronously, before the
    // platform-channel deletion is acknowledged.
    unawaited(retained.close().then((_) {
      if (mounted && identical(_retainedPreview, retained)) {
        setState(() {
          _retainedPreview = null;
          _importCounts = null;
          _currentCounts = null;
          _result = 'پیش‌نمایش با خروج از صفحه یا پس‌زمینه رفتن برنامه لغو شد.';
        });
      }
    }, onError: (Object _) {
      if (mounted) {
        setState(() {
          _importCounts = null;
          _currentCounts = null;
          _error = 'پاکسازی فایل موقت تأیید نشد؛ برنامه را ببندید و دوباره باز کنید.';
        });
      }
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // A decrypt operation may be awaiting Android's document picker.
      // Only an already completed retained preview can be invalidated.
      _invalidateForLifecycle();
    }
  }

  Future<void> _cancelPreview() async {
    if (_busy || _retainedPreview == null) return;
    setState(() => _busy = true);
    try {
      await _clearRetainedPreview();
      if (mounted) {
        setState(() {
          _importCounts = null;
          _currentCounts = null;
          _result = 'پیش‌نمایش لغو شد؛ فایل موقت پاک شد.';
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'حذف فایل موقت تأیید نشد؛ برنامه را ببندید و دوباره باز کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recheckPreview() async {
    if (_busy) return;
    final retained = _retainedPreview;
    if (retained == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _phase = 'بازبینی مجدد اطلاعات (فقط خواندنی)...';
    });
    try {
      final status = await retained.recheckReadOnly();
      if (!mounted || !identical(_retainedPreview, retained)) return;
      if (status == RestorePreviewRecheck.unchanged) {
        setState(() {
          _result = 'اطلاعات در این بازبینی تغییر نکرده‌اند؛ این نتیجه '
              'مجوز بازیابی یا جایگزینی اطلاعات نیست.';
        });
      } else {
        setState(() {
          _retainedPreview = null;
          _importCounts = null;
          _currentCounts = null;
          _result = null;
          _error = 'پیش‌نمایش قبلی دیگر معتبر نیست (${status.name}). '
              'برای مقایسه دوباره، فایل را از ابتدا انتخاب کنید.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _importCounts = null;
          _currentCounts = null;
          _error = 'بازبینی یا پاکسازی ایمن ناموفق بود؛ برنامه را ببندید '
              'و دوباره باز کنید.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _phase = '';
        });
      }
    }
  }


  static const _tableLabels = <String, String>{
    'profiles': 'پروفایل‌ها',
    'medications': 'داروها',
    'dose_events': 'رویدادهای مصرف',
    'stock_movements': 'تغییرات موجودی',
    'health_measurements': 'اندازه‌گیری‌های سلامت',
    'care_visits': 'ویزیت‌ها',
    'care_tasks': 'کارهای پیگیری',
    'visit_questions': 'سؤالات پزشک',
  };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final retained = _retainedPreview;
    _retainedPreview = null;
    if (retained != null) {
      unawaited(retained.close().catchError((Object _) {
        // Cold-start staging sweep is the crash/failure fallback.
      }));
    }
    _password.clear();
    _confirmation.clear();
    _importPassword.clear();
    _password.dispose();
    _confirmation.dispose();
    _importPassword.dispose();
    super.dispose();
  }

  Future<void> _previewImport() async {
    if (_busy) return;
    if (_importPassword.text.isEmpty) {
      setState(() => _error = 'رمز فایل پشتیبان را وارد کنید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _importCounts = null;
      _currentCounts = null;
      _phase = 'در انتظار انتخاب فایل رمزگذاری‌شده...';
    });
    String? quarantinedPath;
    try {
      await _clearRetainedPreview(); // close previous plaintext staging first
      final selected = await _channel.invokeMethod<bool>('chooseImport');
      if (selected != true) {
        if (mounted) setState(() => _phase = 'انتخاب فایل لغو شد.');
        return;
      }
      if (mounted) {
        setState(() => _phase = 'بررسی قالب، رمز و اصالت کامل فایل...');
      }
      quarantinedPath = await _channel.invokeMethod<String>(
        'decryptImport',
        {'password': _importPassword.text},
      );
      if (quarantinedPath == null) throw const FormatException('No import file');
      if (mounted) setState(() => _phase = 'بازرسی امن دیتابیس، ساختار و تمامیت داده‌ها...');

      // The schema comes from the installed and migrated v5 database itself;
      // input files may not introduce objects, SQL, columns or indexes.
      final baselineRows = await widget.database.customSelect(
        'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name',
      ).get();
      final baseline = schemaTemplate(baselineRows.map((row) => <String, Object?>{
        'type': row.read<String>('type'),
        'name': row.read<String>('name'),
        'tbl_name': row.read<String>('tbl_name'),
        'sql': row.readNullable<String>('sql'),
      }));
      final backupCounts = await inspectAuthenticatedBackup(quarantinedPath, baseline);
      final location = await widget.database.customSelect('PRAGMA database_list').get();
      final mainFiles = location.where((row) => row.read<String>('name') == 'main');
      if (mainFiles.isEmpty) throw const FormatException('Main database not found');
      final path = mainFiles.first.read<String>('file');
      // The eight visible counts and the fingerprint of all 17 tables share
      // one consistent SQLite read snapshot. This fingerprint will be checked
      // again under the exclusive native Phase B lease before any mutations.
      final evidence = await RestoreReadOnlyPreviewEvidence.captureReadOnly(
        liveDatabasePath: path,
        validatedCandidatePath: quarantinedPath,
      );
      if (mounted) {
        late final ReadOnlyImportRetention retained;
        retained = ReadOnlyImportRetention(
          evidence: evidence,
          liveDatabasePath: path,
          validatedCandidatePath: quarantinedPath,
          clearNative: _nativeClearImport,
          onExpiry: (cleaned) {
            if (!mounted || !identical(_retainedPreview, retained)) return;
            setState(() {
              if (cleaned) _retainedPreview = null;
              _importCounts = null;
              _currentCounts = null;
              _result = null;
              _error = cleaned
                  ? 'اعتبار پیش‌نمایش پایان یافت و فایل موقت پاک شد.'
                  : 'اعتبار پیش‌نمایش پایان یافت؛ پاکسازی فایل موقت تأیید نشد.';
            });
          },
        );
        setState(() {
          _retainedPreview = retained;
          _importCounts = backupCounts;
          _currentCounts = evidence.liveCounts;
          _phase = '';
          _result = 'رمز، اصالت و ساختار نسخه ۵ بررسی شدند. فایل موقت '
              'فقط تا پنج دقیقه برای بازبینی دوباره نگهداری می‌شود. '
              'هیچ اطلاعاتی بازیابی یا جایگزین نشده است.';
        });
        quarantinedPath = null; // the retained session now owns cleanup
      } else {
        evidence.invalidate();
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'خواندن فایل پشتیبان ناموفق بود.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'فایل پشتیبان معتبر یا سازگار نیست؛ '
            'اطلاعات فعلی گوشی تغییر نکرد. فایل و رمز را بررسی کنید.');
      }
    } finally {
      if (quarantinedPath != null) {
        try {
          if (!await _nativeClearImport(quarantinedPath)) {
            throw StateError('Native cleanup not acknowledged');
          }
        } catch (_) {
          if (mounted) {
            setState(() => _error = 'پاکسازی فایل موقت تأیید نشد؛ '
                'برنامه را کاملاً ببندید و دوباره باز کنید.');
          }
        }
      }
      if (mounted) {
        _importPassword.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _startExport() async {
    if (_busy) return;
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
    Directory? prepared;
    try {
      await _clearRetainedPreview();
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
      if (mounted) setState(() => _phase = 'آماده‌سازی تصویر یکپارچه و خواندنی دیتابیس...');
      final info = await widget.database.customSelect('PRAGMA database_list').get();
      final files = info.where((row) => row.read<String>('name') == 'main');
      if (files.isEmpty) throw StateError('مسیر پایگاه داده پیدا نشد');
      final databasePath = files.first.read<String>('file');
      if (databasePath.isEmpty) throw StateError('مسیر پایگاه داده خالی است');
      final stagingRoot = await _channel.invokeMethod<String>(
        'prepareExport',
        {'databasePath': databasePath},
      );
      if (stagingRoot == null || stagingRoot.isEmpty) {
        throw StateError('فضای موقت خصوصی تأیید نشد');
      }
      prepared = await Directory('$stagingRoot/${const Uuid().v4()}').create();
      final snapshotPath = '${prepared.path}/snapshot.sqlite';
      await createReadOnlySnapshot(databasePath, snapshotPath);
      if (mounted) setState(() => _phase = 'رمزگذاری و راستی‌آزمایی تصویر امن...');
      final output = await _channel.invokeMapMethod<String, dynamic>(
        'export',
        {
          'databasePath': databasePath,
          'snapshotPath': snapshotPath,
          'password': password,
        },
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
    } on SnapshotSqliteFailure catch (error) {
      if (mounted) {
        setState(() => _error = 'ساخت تصویر یکپارچه SQLite ناموفق بود '
            '(کد تشخیصی ${error.sqliteCode}). اطلاعات فعلی تغییر نکرد.');
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'ساخت پشتیبان انجام نشد.');
    } catch (_) {
      if (mounted) setState(() => _error = 'ساخت پشتیبان انجام نشد؛ داده‌های فعلی تغییری نکردند.');
    } finally {
      if (prepared != null) {
        try {
          if (await prepared.exists()) {
            await prepared.delete(recursive: true);
          }
        } catch (_) {
          if (mounted) {
            setState(() => _error = 'پاکسازی تصویر موقت تأیید نشد؛ '
                'برنامه را ببندید و دوباره اجرا کنید.');
          }
        }
      }
      try {
        await _channel.invokeMethod<bool>('discardDestination');
      } catch (_) { /* Android cold-start sweep handles abandoned staging. */ }
      if (mounted) {
        setState(() {
          _busy = false;
          if (_error != null) _phase = '';
        });
      }
    }
  }

  Future<void> _testCryptoEngine() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _phase = 'بررسی مستقل Argon2id و AES-GCM روی همین گوشی...';
    });
    try {
      final valid = await _channel.invokeMethod<bool>('testCryptoProvider');
      if (mounted) {
        setState(() {
          _phase = '';
          _result = valid == true
              ? 'آزمون تطبیق رمزنگاری با بردار مرجع مستقل موفق بود.'
              : 'آزمون رمزنگاری ناموفق بود؛ از این نسخه برای پشتیبان استفاده نکنید.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'آزمون رمزنگاری انجام نشد.');
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
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 12),
            Text('بررسی پشتیبان پیش از بازیابی',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('فایل را انتخاب کنید و رمز همان فایل را وارد کنید. '
                'پس از تأیید اصالت رمزنگاری، فقط تعداد رکوردها با اطلاعات فعلی '
                'مقایسه می‌شود؛ بازیابی و جایگزینی اطلاعات فعلاً غیرفعال است.'),
            const SizedBox(height: 14),
            TextField(
              controller: _importPassword,
              enabled: !_busy,
              obscureText: !_showPassword,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'رمز فایل موجود',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _previewImport,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('انتخاب فایل و نمایش پیش‌نمایش امن'),
            ),
            if (_retainedPreview != null) ...[
              const SizedBox(height: 10),
              const Text('پیش‌نمایش موقت، فقط برای مقایسه مجدد. '
                  'بازگردانی اطلاعات همچنان غیرفعال است.'),
              OutlinedButton.icon(
                onPressed: _busy ? null : _recheckPreview,
                icon: const Icon(Icons.refresh),
                label: const Text('بازبینی دوباره بدون تغییر اطلاعات'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _cancelPreview,
                icon: const Icon(Icons.delete_outline),
                label: const Text('لغو پیش‌نمایش و پاک‌سازی فایل موقت'),
              ),
            ],
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testCryptoEngine,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('تست موتور رمزنگاری — نسخه آزمایشی'),
              ),
            ],
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
            if (_importCounts != null && _currentCounts != null) ...[
              const SizedBox(height: 16),
              const Text('مقایسه اطلاعات (فقط خواندنی)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Row(children: [
                Expanded(flex: 3, child: Text('بخش')),
                Expanded(child: Text('گوشی')),
                Expanded(child: Text('فایل')),
              ]),
              const Divider(),
              for (final table in _tableLabels.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(table.value)),
                    Expanded(child: Text('${_currentCounts![table.key] ?? 0}')),
                    Expanded(child: Text('${_importCounts![table.key] ?? 0}')),
                  ]),
                ),
              const SizedBox(height: 10),
              const Card(child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('جایگزینی اطلاعات در مرحلهٔ M4-01D و تنها '
                    'پس از آزمون بازیابی ضدکرش فعال خواهد شد.'),
              )),
            ],
          ],
        ),
      );
}
