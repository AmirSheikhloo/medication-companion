import 'package:material_ui/material_ui.dart';

import '../../../core/input/persian_quantity_formatter.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_quantity.dart';

class DoseStockChoice {
  const DoseStockChoice.withoutDebit()
      : packageId = null, quantityMilliunits = null;

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
      builder: (_) => _DoseStockDialog(
        medicationName: medicationName, stock: stock),
    );

class _DoseStockDialog extends StatefulWidget {
  const _DoseStockDialog({
    required this.medicationName,
    required this.stock,
  });

  final String medicationName;
  final StockSummary stock;

  @override
  State<_DoseStockDialog> createState() => _DoseStockDialogState();
}

class _DoseStockDialogState extends State<_DoseStockDialog> {
  late final TextEditingController _quantity;
  String? _error;

  @override
  void initState() {
    super.initState();
    final balance = widget.stock.selected?.balanceMilliunits ?? 0;
    final initial = widget.stock.selectedDebitQuantity;
    final suggested = initial != null && initial <= balance
        ? initial : balance >= 1000 ? 1000 : balance;
    _quantity = TextEditingController(text: suggested == 0 ? '' :
        PersianQuantityFormatter.display(StockQuantity.format(suggested)));
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.stock.selected;
    final usable = selected != null && !selected.expired &&
        selected.balanceMilliunits > 0;
    return AlertDialog(
      title: const Text('ثبت مصرف و موجودی'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('دارو: ${widget.medicationName}'),
            const SizedBox(height: 8),
            const Text('آیا می‌خواهید مقدار واقعی مصرف‌شده را از بسته انتخابی کسر کنید؟'),
            const SizedBox(height: 10),
            if (selected == null)
              const Text('هیچ بسته‌ای برای کسر انتخاب نشده است.')
            else ...[
              Text('بسته: ${selected.package.label}'),
              Text('باقی‌مانده: ${PersianQuantityFormatter.display(StockQuantity.format(selected.balanceMilliunits))} '
                  '${selected.package.unit}'),
              if (selected.expired)
                const Text('این بسته طبق تاریخ واردشده منقضی است؛ کسر موجودی مجاز نیست.',
                    style: TextStyle(color: Colors.deepOrange)),
            ],
            if (usable) ...[
              const SizedBox(height: 10),
              TextField(
                  key: const ValueKey('dose-debit-quantity-input'),
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: const [PersianQuantityFormatter()],
                  decoration: InputDecoration(
                    labelText: 'مقدار کسر از بسته (${selected.package.unit})',
                    border: const OutlineInputBorder(),
                    helperText: 'عدد مثبت وارد کنید؛ حداکثر موجودی همین بسته.',
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
              ),
              if (widget.stock.debitPreset != null &&
                  widget.stock.selectedDebitQuantity == null)
                const Text('واحد پیش‌فرض دارو با واحد این بسته متفاوت است؛ '
                    'مقدار کسر را از گزینه‌های همین بسته انتخاب کنید.'),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.deepOrange)),
              ),
            const SizedBox(height: 8),
            const Text('ثبت مصرف بدون کسر نیز ممکن است؛ در این حالت '
                'موجودی تغییر نمی‌کند و صریحاً مشخص می‌شود.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context)
              .pop(const DoseStockChoice.withoutDebit()),
          child: const Text('ثبت بدون کسر'),
        ),
        if (usable)
          FilledButton(
            onPressed: () {
              try {
                final amount = StockQuantity.parsePositive(_quantity.text);
                if (amount > PersianQuantityFormatter.maxMilliunits) {
                  throw ArgumentError('مقدار بسیار بزرگ است.');
                }
                if (amount > selected.balanceMilliunits) {
                  throw StateError('موجودی این بسته کافی نیست.');
                }
                Navigator.of(context).pop(
                  DoseStockChoice.debit(selected.package.id, amount));
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
