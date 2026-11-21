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
              Icon(icon!, color: AppColors.primary, size: 21),
              const SizedBox(width: 8),
            ]),
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.primaryDark,
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
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.outline),
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
      color: AppColors.mint,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: color, size: 23),
  );
}
