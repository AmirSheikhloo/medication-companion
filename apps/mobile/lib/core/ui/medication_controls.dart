import 'package:material_ui/material_ui.dart';

import 'app_design.dart';

/// Shared RTL-safe medication form choice control.
/// The rounded bottom sheet replaces platform-default square popup menus.
class MedicationChoiceField extends StatefulWidget {
  const MedicationChoiceField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label = 'واحد',
    this.enabled = true,
    this.optionLabels = const {},
    this.commonOptions = const {},
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String label;
  final bool enabled;
  final Map<String, String> optionLabels;
  final Set<String> commonOptions;

  @override
  State<MedicationChoiceField> createState() => _MedicationChoiceFieldState();
}

class _MedicationChoiceFieldState extends State<MedicationChoiceField> {
  bool _open = false;

  Future<void> _choose() async {
    if (!widget.enabled || widget.options.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _open = true);
    try {
      final value = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppPalette.surface(context, AppColors.background),
        showDragHandle: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.label,
                  style: TextStyle(
                    color: AppPalette.ink(context, AppColors.primaryDark),
                    fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * .54),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final option in widget.options)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: option == widget.value
                              ? AppPalette.surface(context, AppColors.mint) : AppPalette.surface(context, Colors.white),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.pop(sheetContext, option),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                                child: Row(children: [
                                  Expanded(child: Text(widget.optionLabels[option] ?? option,
                                    style: TextStyle(
                                      color: AppPalette.ink(context, AppColors.primaryDark),
                                      fontWeight: FontWeight.w700))),
                                  if (widget.commonOptions.contains(option)) ...[
                                    const SizedBox(width: 8),
                                    Flexible(child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppPalette.isDark(context)
                                          ? const Color(0xFF234866) : const Color(0xFFDBF1FF),
                                        borderRadius: BorderRadius.circular(12)),
                                      child: Text('پرکاربرد',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                          color: AppPalette.isDark(context)
                                            ? const Color(0xFFB7E5FF) : const Color(0xFF145B86))))),
                                  ],
                                  if (option == widget.value)
                                    Icon(Icons.check_circle_rounded,
                                      color: AppPalette.ink(context, AppColors.primary)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (mounted && value != null && value != widget.value) {
        widget.onChanged(value);
      }
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${widget.label}، ${widget.value}',
    child: Material(
      color: widget.enabled ? AppPalette.surface(context, AppColors.mint) : AppPalette.tone(context, const Color(0xFFEAF0F0)),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: widget.enabled ? _choose : null,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Expanded(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppPalette.ink(context, AppColors.muted),
                      fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(widget.optionLabels[widget.value] ?? widget.value,
                    style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
                      fontWeight: FontWeight.w800)),
                ])),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _open ? .5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppPalette.ink(context, AppColors.primary), size: 21)),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// Destructive and edit actions remain visually recognizable at small sizes.
class MedicationActionIcon extends StatelessWidget {
  const MedicationActionIcon({super.key,
    required this.icon, required this.onPressed,
    required this.tooltip, this.destructive = false,
    this.iconSize = 20});
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool destructive;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: destructive ? AppPalette.surface(context, const Color(0xFFFCE0E4)) : AppPalette.surface(context, AppColors.mint),
      borderRadius: BorderRadius.circular(13),
      child: IconButton(
        visualDensity: VisualDensity.standard,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        color: destructive ? AppPalette.tone(context, const Color(0xFFAE3149)) : AppPalette.ink(context, AppColors.primaryDark),
      ),
    ),
  );
}

/// Shared gentle navigation motion; respects the OS reduce-motion setting.
Route<T> medicationPageRoute<T>(BuildContext context, Widget child) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotion ? Duration.zero :
      const Duration(milliseconds: 300),
    reverseTransitionDuration: reduceMotion ? Duration.zero :
      const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => child,
    transitionsBuilder: (_, animation, secondary, page) {
      final curved = CurvedAnimation(
        parent: animation, curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-.07, 0), end: Offset.zero).animate(curved),
          child: page,
        ),
      );
    },
  );
}
