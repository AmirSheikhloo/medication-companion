import 'package:material_ui/material_ui.dart';

import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';

class GuestWelcomeScreen extends StatefulWidget {
  const GuestWelcomeScreen({super.key, required this.onSelf,
    required this.onLovedOne, this.onSelfNamed});

  final VoidCallback? onSelf;
  final VoidCallback? onLovedOne;
  final ValueChanged<String>? onSelfNamed;

  @override
  State<GuestWelcomeScreen> createState() => _GuestWelcomeScreenState();
}

class _GuestWelcomeScreenState extends State<GuestWelcomeScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _start() {
    if (widget.onSelfNamed != null) {
      widget.onSelfNamed!(_name.text.trim());
    } else {
      widget.onSelf?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6FCFC),
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(23, 24, 23, 36),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 450),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 12),
          const Center(child: MedicineArtwork(seed: 'همراه دارو', size: 105)),
          const SizedBox(height: 10),
          const Text('همراه دارو', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.primary, fontSize: 23,
              fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          const Text('به همراه دارو\nخوش آمدید', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.primaryDark, fontSize: 29,
              height: 1.5, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('مدیریت داروها، یادآوری‌ها و سلامت در یک جا',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 26),
          const AppSoftHeader(title: 'اطلاعات فقط روی همین دستگاه ذخیره می‌شود',
            icon: Icons.lock_outline),
          const SizedBox(height: 16),
          AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AppSectionHeading('ایجاد پروفایل', icon: Icons.person_outline),
            const SizedBox(height: 12),
            const Text('نام پروفایل', style: TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
            const SizedBox(height: 7),
            TextField(controller: _name, maxLength: 80,
              decoration: const InputDecoration(hintText: 'نام شما (مثلاً امیر)',
                suffixIcon: Icon(Icons.person_outline))),
            const Text('اگر خالی بگذارید، نام «من» ثبت می‌شود.',
              style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ])),
          const SizedBox(height: 18),
          AppGradientButton(label: 'شروع', icon: Icons.arrow_forward,
            onPressed: widget.onSelf == null ? null : _start, light: true,
            height: 54),
          const SizedBox(height: 9),
          OutlinedButton.icon(onPressed: widget.onLovedOne,
            icon: const Icon(Icons.people_outline),
            label: const Text('برای یکی از عزیزانم')),
          const SizedBox(height: 4),
          TextButton(onPressed: widget.onSelf, child: const Text('بعداً')),
        ])),
    ))),
  );
}
