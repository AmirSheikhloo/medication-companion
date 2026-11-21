import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_quantity.dart';

class DoseStockChoice {
  const DoseStockChoice.withoutDebit()
    : packageId = null,
      quantityMilliunits = null;

  const DoseStockChoice.debit(this.packageId, this.quantityMilliunits);

  final String? packageId;
  final int? quantityMilliunits;
}

/// The user explicitly confirms the amount actually used, or chooses
/// "taken without debit". Textual dose instructions never become a quantity.
Future<DoseStockChoice?> askDoseStockChoice(
  BuildContext context, {
  required String medicationName,
  required StockSummary stock,
}) => showDialog<DoseStockChoice>(
  context: context,
  builder: (_) =>
      _DoseStockDialog(medicationName: medicationName, stock: stock),
);

class _DoseStockDialog extends StatefulWidget {
  const _DoseStockDialog({required this.medicationName, required this.stock});

  final String medicationName;
  final StockSummary stock;

  @override
  State<_DoseStockDialog> createState() => _DoseStockDialogState();
}

class _DoseStockDialogState extends State<_DoseStockDialog> {
  final _quantity = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.stock.selected;
    final usable =
        selected != null && !selected.expired && selected.balanceMilliunits > 0;
    return AlertDialog(
      title: const Text('ثبت مصرف و موجودی'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('دارو: ${widget.medicationName}'),
            const SizedBox(height: 8),
            const Text(
              'آیا می‌خواهید مقدار واقعی مصرف‌شده را از بسته انتخابی کسر کنید؟',
            ),
            const SizedBox(height: 10),
            if (selected == null)
              const Text('هیچ بسته‌ای برای کسر انتخاب نشده است.')
            else ...[
              Text('بسته: ${selected.package.label}'),
              Text(
                PersianDate.persianDigits(
                  'باقی‌مانده: ${StockQuantity.format(selected.balanceMilliunits)} '
                  '${selected.package.unit}',
                ),
              ),
              if (selected.expired)
                const Text(
                  'این بسته طبق تاریخ واردشده منقضی است؛ کسر موجودی مجاز نیست.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
            ],
            if (usable) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'مقدار واقعی مصرف‌شده (${selected.package.unit})',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'ثبت مصرف بدون کسر نیز ممکن است؛ در این حالت '
              'موجودی تغییر نمی‌کند و صریحاً مشخص می‌شود.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const DoseStockChoice.withoutDebit()),
          child: const Text('ثبت بدون کسر'),
        ),
        if (usable)
          FilledButton(
            onPressed: () {
              try {
                final amount = StockQuantity.parsePositive(_quantity.text);
                if (amount > selected.balanceMilliunits) {
                  throw StateError('موجودی این بسته کافی نیست.');
                }
                Navigator.of(context)
                    .pop(DoseStockChoice.debit(selected.package.id, amount));
              } catch (error) {
                setState(() => _error = '$error');
              }
            },
            child: const Text('ثبت و کسر موجودی'),
          ),
      ],
    );
  }
}
