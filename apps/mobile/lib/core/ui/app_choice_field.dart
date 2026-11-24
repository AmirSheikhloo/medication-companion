import 'package:material_ui/material_ui.dart';

import 'app_design.dart';

/// Typed choices for forms, including intentionally nullable selections.
class AppChoiceOption<T> {
  const AppChoiceOption(this.value, this.label);
  final T? value;
  final String label;
}

/// Accessible, rounded, animated choice sheet for app-wide forms.
/// Unlike a platform dropdown, null is a real selectable option.
class AppChoiceField<T> extends StatefulWidget {
  const AppChoiceField({super.key, required this.value,
    required this.options, required this.onChanged,
    required this.label, this.enabled = true});

  final T? value;
  final List<AppChoiceOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String label;
  final bool enabled;

  @override
  State<AppChoiceField<T>> createState() => _AppChoiceFieldState<T>();
}

class _AppChoiceFieldState<T> extends State<AppChoiceField<T>> {
  bool _expanded = false;

  Future<void> _show() async {
    if (!widget.enabled) return;
    FocusScope.of(context).unfocus();
    setState(() => _expanded = true);
    try {
      final index = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: AppPalette.surface(context, AppColors.background),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetContext) => SafeArea(top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.label, style: TextStyle(
                  fontSize: 19, color: AppPalette.ink(context, AppColors.primaryDark),
                  fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * .55),
                  child: ListView(shrinkWrap: true,
                    children: [
                      for (var i = 0; i < widget.options.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: widget.options[i].value == widget.value
                              ? AppPalette.surface(context, AppColors.mint) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.pop(sheetContext, i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 15),
                                child: Row(children: [
                                  Expanded(child: Text(widget.options[i].label,
                                    style: TextStyle(
                                      color: AppPalette.ink(context, AppColors.primaryDark),
                                      fontWeight: FontWeight.w700))),
                                  if (widget.options[i].value == widget.value)
                                    Icon(Icons.check_circle_rounded,
                                      color: AppPalette.ink(context, AppColors.primary)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                    ]),
                ),
              ]),
          )),
      );
      if (mounted && index != null) {
        widget.onChanged(widget.options[index].value);
      }
    } finally {
      if (mounted) setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options.where((o) => o.value == widget.value);
    final name = selected.isEmpty ? 'انتخاب کنید' : selected.first.label;
    return Semantics(
      button: true,
      label: '${widget.label}، $name',
      child: Material(
        color: widget.enabled ? AppPalette.surface(context, AppColors.mint) : AppPalette.tone(context, const Color(0xFFE9EFF0)),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: widget.enabled ? _show : null,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(children: [
                Expanded(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppPalette.ink(context, AppColors.muted),
                        fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(name, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
                        fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(width: 5),
                AnimatedRotation(
                  turns: _expanded ? .5 : 0,
                  duration: const Duration(milliseconds: 230),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppPalette.ink(context, AppColors.primary))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
