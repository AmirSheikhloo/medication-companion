import 'package:material_ui/material_ui.dart';

/// Design tokens from the approved four-screen «همراه دارو» reference.
/// Keep the palette in one place so sheets and feature screens stay consistent.
abstract final class AppColors {
  static const primary = Color(0xFF075F60);
  static const primaryDark = Color(0xFF03494B);
  static const accent = Color(0xFF40E0D0);
  static const mint = Color(0xFFE1F8F6);
  static const lightMint = Color(0xFFF0FBFA);
  static const background = Color(0xFFF8FAFA);
  static const ink = Color(0xFF163D43);
  static const muted = Color(0xFF627881);
  static const outline = Color(0xFFD8E8E9);
  static const amber = Color(0xFFF8D37A);
  static const amberLight = Color(0xFFFFF4DC);
  static const success = Color(0xFF16995E);
}

enum AppThemeChoice {
  blue('آبی مدرن', Color(0xFF1D4ED8), Color(0xFF93C5FD), Color(0xFFE8F0FF)),
  cyan('فیروزه‌ای', Color(0xFF0E7490), Color(0xFF67E8F9), Color(0xFFE3F5FA)),
  emerald('سبز زمردی', Color(0xFF047857), Color(0xFF6EE7B7), Color(0xFFE4F6EF)),
  violet('بنفش', Color(0xFF6D28D9), Color(0xFFC4B5FD), Color(0xFFF0E9FF));

  const AppThemeChoice(this.label, this.primary, this.darkAccent, this.tint);
  final String label;
  final Color primary, darkAccent, tint;
  static AppThemeChoice parse(String? name) => values.firstWhere(
    (choice) => choice.name == name, orElse: () => blue);
  Color get page => Color.lerp(const Color(0xFFE8EDF4), tint, .62)!;
  Color get darkTint => Color.lerp(const Color(0xFF202B3A), primary, .40)!;
  Color get outline => Color.lerp(const Color(0xFFB6C4D4), primary, .19)!;
  Color get darkPage => Color.lerp(const Color(0xFF101722), primary, .10)!;
  Color get darkCard => Color.lerp(const Color(0xFF202B3A), primary, .10)!;
  Color get darkBorder => Color.lerp(const Color(0xFF526175), darkAccent, .16)!;
}

class AppAppearance extends ThemeExtension<AppAppearance> {
  const AppAppearance(this.choice);
  final AppThemeChoice choice;
  @override
  AppAppearance copyWith({AppThemeChoice? choice}) => AppAppearance(choice ?? this.choice);
  @override
  AppAppearance lerp(covariant AppAppearance? other, double t) =>
    other == null || t < .5 ? this : other;
}

/// Context-dependent colors keep the light design intact and adapt each
/// semantic surface/foreground separately. Artwork is never color-inverted.
abstract final class AppPalette {
  static bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

  static AppThemeChoice? selected(BuildContext context) =>
    Theme.of(context).extension<AppAppearance>()?.choice;
  static Color brand(BuildContext context) => selected(context)?.primary ?? AppColors.primary;
  static Color brandInk(BuildContext context) => isDark(context)
    ? selected(context)?.darkAccent ?? darkAccent : brand(context);
  static Color card(BuildContext context) => isDark(context)
    ? selected(context)?.darkCard ?? darkSurface : Colors.white;
  static Color border(BuildContext context) => isDark(context)
    ? selected(context)?.darkBorder ?? darkOutline : selected(context)?.outline ?? AppColors.outline;
  static Color tint(BuildContext context) => isDark(context)
    ? selected(context)?.darkTint ?? darkMint : selected(context)?.tint ?? AppColors.mint;
  static const danger = Color(0xFFBE123C);
  static const attention = Color(0xFF1D4ED8);
  static const dangerSurface = Color(0xFFFFE4E9);
  static const attentionSurface = Color(0xFFE5EFFF);
  static const darkBackground = Color(0xFF111827);
  static const darkSurface = Color(0xFF202B3A);
  static const darkMint = Color(0xFF315257);
  static const darkOutline = Color(0xFF46566C);
  static const darkInk = Color(0xFFE7F2F2);
  static const darkMuted = Color(0xFFB1C5C8);
  static const darkAccent = Color(0xFF75DAD1);

  static Color ink(BuildContext context, Color color) {
    final choice = selected(context);
    if (choice != null && color.a != 0) {
      if (color == AppColors.ink || color == AppColors.primaryDark) {
        return isDark(context) ? darkInk : const Color(0xFF1E293B);
      }
      if (color == AppColors.muted) {
        return isDark(context) ? darkMuted : const Color(0xFF526176);
      }
      if (color == AppColors.primary || color == AppColors.accent || color == darkAccent) {
        return isDark(context) ? choice.darkAccent : choice.primary;
      }
    }
    if (!isDark(context) || color.a == 0) return color;
    if (color == Colors.white || color == darkInk || color == darkMuted ||
        color == darkAccent) {
      return color;
    }
    if (color == AppColors.ink || color == AppColors.primaryDark) {
      return darkInk;
    }
    if (color == AppColors.muted) return darkMuted;
    if (color == AppColors.primary) return darkAccent;
    if (color.computeLuminance() >= .48) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(.76).withSaturation(
      hsl.saturation.clamp(.08, .68)).toColor();
  }

  static Color surface(BuildContext context, Color color) {
    final choice = selected(context);
    if (choice != null && color.a != 0) {
      final dark = isDark(context);
      if (color == AppColors.background || color == const Color(0xFFF1F8F8)) {
        return dark ? choice.darkPage : choice.page;
      }
      if (color == Colors.white) { return card(context); }
      if (color == AppColors.primary) { return choice.primary; }
      if (color == AppColors.accent) {
        return dark ? choice.darkAccent : Color.lerp(choice.primary, Colors.white, .55)!;
      }
      if (color == AppColors.outline) {
        return border(context);
      }
      if (color == AppColors.amberLight) {
        return dark ? const Color(0xFF203752) : attentionSurface;
      }
      if (color == dangerSurface || color == const Color(0xFFFFEBEF)) {
        return dark ? const Color(0xFF482434) : dangerSurface;
      }
      if (color == attentionSurface || color == const Color(0xFFFFF5E4)) {
        return dark ? const Color(0xFF223A5D) : attentionSurface;
      }
      final hsl = HSLColor.fromColor(color);
      // Retheme legacy teal decorative surfaces, but never semantic
      // green success, red danger, or blue attention.
      if (color == AppColors.mint || color == AppColors.lightMint ||
          (hsl.hue >= 155 && hsl.hue <= 205 && hsl.lightness > .67 && hsl.saturation > .10)) {
        return dark ? choice.darkTint : Color.lerp(choice.tint, Colors.white,
          color == AppColors.lightMint ? .45 : 0)!;
      }
    }
    if (!isDark(context) || color.a == 0) return color;
    if (color == AppColors.background) return darkBackground;
    if (color == Colors.white) return darkSurface;
    if (color == AppColors.mint) return darkMint;
    if (color == AppColors.lightMint) return const Color(0xFF293E48);
    if (color == AppColors.outline) return darkOutline;
    if (color.computeLuminance() < .15) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(.20).withSaturation(
      hsl.saturation.clamp(.06, .38)).toColor();
  }

  static Color solid(BuildContext context, Color color) {
    if (!isDark(context) || color.a == 0) return color;
    if (color.computeLuminance() < .18) return color;
    return HSLColor.fromColor(color).withLightness(.30).toColor();
  }

  static Color tone(BuildContext context, Color color) {
    if (color == AppColors.outline || color == AppColors.background ||
        color == AppColors.mint || color == AppColors.lightMint ||
        color == AppColors.amberLight || color == Colors.white ||
        color.computeLuminance() >= .55) {
      return surface(context, color);
    }
    return ink(context, color);
  }
}

/// Dark teal headers need an explicit title style: ThemeData.appBarTheme's
/// dark text color otherwise overrides AppBar.foregroundColor.
abstract final class AppTypography {
  static const onPrimaryAppBar = TextStyle(
    fontFamily: 'NotoSansArabic',
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.w800,
  );
}

class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading(this.title, {super.key, this.icon, this.action});

  final String title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ...?(icon == null
          ? null
          : <Widget>[
              Icon(icon!, color: AppPalette.ink(context, AppColors.primary), size: 21),
              const SizedBox(width: 8),
            ]),
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppPalette.ink(context, AppColors.primaryDark),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ?action,
    ],
  );
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
    this.raised = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool raised;

  @override
  Widget build(BuildContext context) => Material(
    color: AppPalette.surface(context, color),
    elevation: raised ? 2 : 0,
    shadowColor: const Color(0x33172740),
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: AppPalette.border(context)),
    ),
    child: SizedBox(width: double.infinity,
      child: Padding(padding: padding, child: child)),
  );
}

class AppIconTile extends StatelessWidget {
  const AppIconTile(this.icon, {super.key, this.color = AppColors.primary});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: AppPalette.surface(context, AppColors.mint),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: AppPalette.ink(context, color), size: 23),
  );
}
