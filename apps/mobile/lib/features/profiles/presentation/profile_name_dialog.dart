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
  bool _showNameError = false;

  void _continue() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('برای یکی از عزیزانم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('دوست داری چطور صداش کنیم؟ می‌تونی نام مستعار بنویسی.'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 80,
              onChanged: (_) {
                if (_showNameError) setState(() => _showNameError = false);
              },
              onSubmitted: (_) => _continue(),
              decoration: const InputDecoration(
                labelText: 'نام عزیزت',
                hintText: 'مثلاً مادر',
              ),
              // Validation feedback stays next to the field, never as a card.
            ),
            if (_showNameError)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('برای ادامه، نام عزیزت رو بنویس.',
                    style: TextStyle(color: Color(0xFFD75D57), fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: _continue,
            child: const Text('ادامه'),
          ),
        ],
      );
}
