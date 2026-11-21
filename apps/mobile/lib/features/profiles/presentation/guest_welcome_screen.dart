import 'package:material_ui/material_ui.dart';
import '../../../core/ui/app_design.dart';

const _deepTeal = AppColors.primary;

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
                    Center(
                      child: Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(34),
                        ),
                        child: const Icon(Icons.medication_rounded,
                            size: 64, color: _deepTeal),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'همراه دارو',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'به همراه دارو خوش آمدید',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'برنامهٔ دارو، ثبت مصرف و پیگیری سلامت برای شما و عزیزانتان.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    const Card(
                      color: AppColors.mint,
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
