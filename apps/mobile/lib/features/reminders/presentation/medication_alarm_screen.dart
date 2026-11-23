import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/app_design.dart';

/// Opt-in screen shown when the OS launches the app from a full-screen alarm.
/// The user must still choose an actual dose status in the Today tab.
class MedicationAlarmScreen extends StatelessWidget {
  const MedicationAlarmScreen({super.key,
    required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.primaryDark,
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 25),
      child: Column(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            width: 92, height: 92,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(28)),
            child: const Icon(Icons.medication_rounded,
              size: 52, color: AppColors.accent))),
          const SizedBox(height: 26),
          Text(PersianDate.displayDigits(title),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white,
              fontSize: 29, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF0F6262),
              borderRadius: BorderRadius.circular(20)),
            child: Text(PersianDate.displayDigits(body),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white,
                fontSize: 20, height: 1.65))),
          const SizedBox(height: 18),
          const Text('وضعیت مصرف را در صفحهٔ امروز مشخص کن.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFD0ECE9), fontSize: 13)),
          const SizedBox(height: 38),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.primaryDark,
              minimumSize: const Size.fromHeight(54)),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('متوجه شدم')),
        ]),
    )),
  );
}
