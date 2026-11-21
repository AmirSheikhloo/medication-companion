import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'app_design.dart';

/// Components shared by the rebuilt screens. Layout and illustration are
/// intentionally native Flutter, not flattened mockup screenshots.
class MedicineArtwork extends StatelessWidget {
  const MedicineArtwork({super.key, required this.seed, this.size = 48});

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = seed.runes.fold<int>(0, (sum, code) => sum + code);
    final palette = <Color>[
      const Color(0xFFE3F1F5),
      const Color(0xFFFFE9DF),
      const Color(0xFFFFF0BB),
      const Color(0xFFDCF2ED),
      const Color(0xFFE7E6FC),
    ];
    final color = palette[value % palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(size * .26),
      ),
      child: Transform.rotate(
        angle: value.isEven ? -.55 : .45,
        child: Container(
          width: size * .59,
          height: size * .31,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size),
            border: Border.all(color: Colors.white, width: 1.8),
            boxShadow: const [
              BoxShadow(color: Color(0x330B5051), blurRadius: 5, offset: Offset(1, 3)),
            ],
            gradient: LinearGradient(
              colors: [Colors.white, Colors.white, color, color],
              stops: const [0, .48, .49, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class AppGradientButton extends StatelessWidget {
  const AppGradientButton({super.key, required this.label, required this.icon, required this.onPressed,
    this.light = false, this.height = 48});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool light;
  final double height;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .5 : 1,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: LinearGradient(colors: light
                ? const [Color(0xFFA8F7EF), AppColors.accent]
                : const [AppColors.primary, Color(0xFF01847E)]),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 21, color: light ? AppColors.primaryDark : Colors.white),
              const SizedBox(width: 8),
              Flexible(child: Text(label, style: TextStyle(
                color: light ? AppColors.primaryDark : Colors.white,
                fontWeight: FontWeight.w800, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppSoftHeader extends StatelessWidget {
  const AppSoftHeader({super.key, required this.title, this.icon = Icons.medication_outlined,
    this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.mint, Color(0xFFF1FBFC)]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: const Color(0xFFBEF1EC),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppColors.primary, size: 23),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.primaryDark,
          fontWeight: FontWeight.w800, fontSize: 16)),
        if (subtitle != null) Text(subtitle!, style: const TextStyle(color: AppColors.muted,
          fontSize: 11)),
      ])),
      ?trailing,
    ]),
  );
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({super.key, required this.text, required this.color,
    this.icon, this.background});
  final String text;
  final Color color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: background ?? color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(18)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 4)],
      Text(text, style: TextStyle(color: color, fontSize: 11,
        fontWeight: FontWeight.w700)),
    ]),
  );
}

class AppProgressRing extends StatelessWidget {
  const AppProgressRing({super.key, required this.progress, required this.center,
    this.size = 78});
  final double progress;
  final String center;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: Stack(alignment: Alignment.center, children: [
      SizedBox.expand(child: CircularProgressIndicator(
        value: progress.clamp(0, 1), strokeWidth: 8,
        strokeCap: StrokeCap.round,
        color: AppColors.primary,
        backgroundColor: const Color(0xFFC5EAE8),
      )),
      Text(center, style: const TextStyle(fontWeight: FontWeight.w800,
        fontSize: 16, color: AppColors.primaryDark)),
    ]),
  );
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.selectedIndex, required this.onSelected});
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const entries = <(String, IconData)>[
      ('امروز', Icons.calendar_month_outlined),
      ('داروها', Icons.medication_outlined),
      ('سلامت', Icons.favorite_border_rounded),
      ('بیشتر', Icons.more_horiz_rounded),
    ];
    return SafeArea(top: false, child: Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
      decoration: const BoxDecoration(color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.outline))),
      child: Row(children: [
        for (var i = 0; i < entries.length; i++)
          Expanded(child: InkWell(
            onTap: () => onSelected(i),
            borderRadius: BorderRadius.circular(15),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 64, height: 37,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: selectedIndex == i
                        ? const LinearGradient(colors: [AppColors.primary, Color(0xFF007A76)])
                        : null,
                  ),
                  child: Icon(entries[i].$2, size: 22,
                    color: selectedIndex == i ? Colors.white : AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(entries[i].$1, style: TextStyle(fontSize: 11,
                  fontWeight: selectedIndex == i ? FontWeight.w800 : FontWeight.w500,
                  color: selectedIndex == i ? AppColors.primaryDark : AppColors.ink)),
              ])),
          )),
      ]),
    ));
  }
}

class AppWaveBanner extends StatelessWidget {
  const AppWaveBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Stack(children: [
      Container(height: 84, decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFDAF9F6), Color(0xFFF4FAFA)]))),
      Positioned.directional(textDirection: Directionality.of(context),
        start: -36, bottom: -54,
        child: Transform.rotate(angle: -math.pi / 10,
          child: Container(width: 190, height: 112,
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: .24),
              borderRadius: BorderRadius.circular(80))))),
      Padding(padding: const EdgeInsets.all(14), child: child),
    ]),
  );
}
