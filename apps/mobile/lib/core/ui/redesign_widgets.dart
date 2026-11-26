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
    final color = AppPalette.selected(context)?.tint ??
      (seed.contains('همراه') ? AppColors.accent : palette[value % palette.length]);
    final roundTablet = !seed.contains('همراه') && value % 3 == 0;
    final goldenSoftgel = seed.contains('ویتامین') || seed.contains('امگا');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppPalette.surface(context, AppColors.mint),
        borderRadius: BorderRadius.circular(size * .26),
      ),
      child: roundTablet
        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 2; i++)
              Container(
                width: size * .27, height: size * .27,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, color]),
                  border: Border.all(color: Colors.white, width: 1),
                  boxShadow: const [BoxShadow(color: Color(0x330B5051),
                    blurRadius: 4, offset: Offset(1, 2))],
                ),
              ),
          ])
        : Transform.rotate(
            angle: value.isEven ? -.55 : .45,
            child: Container(
              width: size * .59,
              height: size * .31,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                border: Border.all(color: Colors.white, width: 1.8),
                boxShadow: const [BoxShadow(color: Color(0x330B5051),
                  blurRadius: 5, offset: Offset(1, 3))],
                gradient: LinearGradient(
                  colors: goldenSoftgel
                      ? [Colors.white, color]
                      : [Colors.white, Colors.white, color, color],
                  stops: goldenSoftgel ? null : const [0, .48, .49, 1],
                ),
              ),
            ),
          ),
    );
  }
}

class AppGradientButton extends StatelessWidget {
  const AppGradientButton({super.key, required this.label, required this.icon, required this.onPressed,
    this.light = false, this.height = 48, this.iconAfterLabel = false});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool light;
  final double height;
  final bool iconAfterLabel;

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
                ? [AppPalette.tint(context), AppPalette.tint(context)]
                : [AppPalette.brand(context), AppPalette.brand(context)]),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!iconAfterLabel) ...[
                Icon(icon, size: 21, color: light ? AppPalette.ink(context, AppColors.primaryDark) : Colors.white),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, style: TextStyle(
                color: light ? AppPalette.ink(context, AppColors.primaryDark) : Colors.white,
                fontWeight: FontWeight.w800, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (iconAfterLabel) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 21, color: light ? AppPalette.ink(context, AppColors.primaryDark) : Colors.white),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class AppSoftHeader extends StatelessWidget {
  const AppSoftHeader({super.key, required this.title, this.icon = Icons.medication_outlined,
    this.subtitle, this.trailing, this.tinted = false});
  final bool tinted;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: tinted ? 12 : 2, vertical: tinted ? 9 : 12),
    decoration: tinted ? BoxDecoration(color: AppPalette.tint(context),
      borderRadius: BorderRadius.circular(10)) : null,
    child: Row(children: [
      Container(
        padding: EdgeInsets.all(tinted ? 3 : 9),
        decoration: BoxDecoration(color: tinted ? Colors.transparent : AppPalette.tint(context),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppPalette.ink(context, AppColors.primary), size: 23),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
          fontWeight: FontWeight.w800, fontSize: 16)),
        if (subtitle != null) Text(subtitle!, style: TextStyle(color: AppPalette.ink(context, AppColors.muted),
          fontSize: 11)),
      ])),
      ?trailing,
    ]),
  );
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({super.key, required this.text, required this.color,
    this.icon, this.background, this.fontSize = 12});
  final String text;
  final Color color;
  final Color? background;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: background == null ? AppPalette.ink(context, color).withValues(alpha: .12)
      : background == AppPalette.warningSurface || background == AppPalette.dangerSurface
        ? AppPalette.alertFill(context, background == AppPalette.dangerSurface)
        : color == Colors.white ? background! : AppPalette.surface(context, background!),
      borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 15, color: AppPalette.ink(context, color)), const SizedBox(width: 4)],
      Flexible(child: Text(text, softWrap: true,
        style: TextStyle(fontFamily: 'Vazirmatn', color: AppPalette.ink(context, color),
          fontSize: fontSize, fontWeight: FontWeight.w700))),
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
        color: AppPalette.ink(context, AppColors.primary),
        backgroundColor: AppPalette.surface(context, const Color(0xFFC5EAE8)),
      )),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Text(center,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Vazirmatn',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: AppPalette.ink(context, AppColors.primaryDark),
          ),
        ),
      ),
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
      ('بیشتر', Icons.menu_rounded),
    ];
    return Material(
      color: AppPalette.card(context), elevation: 1,
      shadowColor: const Color(0x24172740), surfaceTintColor: Colors.transparent,
      child: SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Row(children: [
        for (var i = 0; i < entries.length; i++)
          Expanded(child: InkWell(
            onTap: () => onSelected(i),
            borderRadius: BorderRadius.circular(15),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                  duration: AppMotion.duration(context, AppMotion.quick),
                  curve: AppMotion.curve,
                  width: 76, height: 58,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: selectedIndex == i ? AppPalette.brand(context) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(entries[i].$2, size: 22,
                      color: selectedIndex == i ? Colors.white : AppPalette.ink(context, AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(entries[i].$1, style: TextStyle(fontSize: 11,
                      fontWeight: selectedIndex == i ? FontWeight.w800 : FontWeight.w500,
                      color: selectedIndex == i ? Colors.white : AppPalette.ink(context, AppColors.ink))),
                  ]),
                ),
              ),
          )),
      ]),
    )));
  }
}

class AppWaveBanner extends StatelessWidget {
  const AppWaveBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Stack(children: [
      Container(height: 84, decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppPalette.brand(context),
          Color.lerp(AppPalette.brand(context), const Color(0xFF0F172A), .25)!]))),
      Positioned.directional(textDirection: Directionality.of(context),
        start: -36, bottom: -54,
        child: Transform.rotate(angle: -math.pi / 10,
          child: Container(width: 190, height: 112,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(80))))),
      Padding(padding: const EdgeInsets.all(14), child: child),
    ]),
  );
}
