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
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite_outline, size: 68, color: _deepTeal),
                const SizedBox(height: 22),
                Text('همراه دارو',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: const Color(0xFF124B49),
                          fontWeight: FontWeight.bold,
                        )),
                const SizedBox(height: 10),
                const Text(
                  'ثبت برنامه و پیگیری مصرف، برای خودتان و عزیزانتان. بدون نیاز به اینترنت یا حساب کاربری.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 34),
                FilledButton.icon(
                  onPressed: onSelf,
                  icon: const Icon(Icons.person_outline),
                  label: const Text('برای خودم'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onLovedOne,
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('برای یکی از عزیزانم'),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ورود / ساخت حساب: در نسخه‌های بعدی',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
      );
}

