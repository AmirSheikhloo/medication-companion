import 'package:material_ui/material_ui.dart';

Future<String?> askProfileNameDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _ProfileNameDialog(),
    );

class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog();

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('پروفایل عزیزتان'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('نام دلخواه؛ می‌توانید از نام مستعار استفاده کنید.'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_name.text),
            child: const Text('ادامه'),
          ),
        ],
      );
}
