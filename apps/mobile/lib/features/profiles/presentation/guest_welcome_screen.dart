import 'package:material_ui/material_ui.dart';

const _deepTeal = Color(0xFF008F87);

class GuestWelcomeScreen extends StatelessWidget {
  const GuestWelcomeScreen({
    super.key,
    required this.onSelf,
    required this.onLovedOne,
  });

  final VoidCallback? onSelf;
  final VoidCallback? onLovedOne;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.favorite_outline,
                        size: 64, color: _deepTeal),
                    const SizedBox(height: 18),
                    Text(
                      'همراه دارو',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: const Color(0xFF124B49),
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'برنامهٔ دارو، ثبت مصرف و پیگیری سلامت برای شما و عزیزانتان.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    const Card(
                      color: Color(0xFFEAF7F4),
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, color: _deepTeal),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'شروع بدون حساب کاربری؛ اطلاعات روی همین دستگاه می‌مانند.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: onSelf,
                      icon: const Icon(Icons.person_outline),
                      label: const Text('برای خودم'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onLovedOne,
                      icon: const Icon(Icons.groups_outlined),
                      label: const Text('برای یکی از عزیزانم'),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'نسخهٔ بتا: بازیابی اطلاعات حذف‌شده فعلاً فعال نیست.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
