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

/// Context-dependent colors keep the light design intact and adapt each
/// semantic surface/foreground separately. Artwork is never color-inverted.
abstract final class AppPalette {
  static bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

  static const darkBackground = Color(0xFF101820);
  static const darkSurface = Color(0xFF202E38);
  static const darkMint = Color(0xFF315257);
  static const darkOutline = Color(0xFF526873);
  static const darkInk = Color(0xFFE7F2F2);
  static const darkMuted = Color(0xFFB1C5C8);
  static const darkAccent = Color(0xFF75DAD1);

  static Color ink(BuildContext context, Color color) {
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
    if (!isDark(context)) return color;
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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: AppPalette.surface(context, color),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: AppPalette.surface(context, AppColors.outline)),
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
