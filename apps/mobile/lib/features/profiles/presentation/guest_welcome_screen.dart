import 'package:material_ui/material_ui.dart';

/// First-launch screen inspired by the approved turquoise ribbon design.
/// Only the ribbon is an image; every control is native and responsive.
class GuestWelcomeScreen extends StatefulWidget {
  const GuestWelcomeScreen({
    super.key,
    required this.onSelf,
    required this.onLovedOne,
    this.onSelfNamed,
  });

  /// Start a local guest profile without asking for a name.
  final VoidCallback? onSelf;
  final VoidCallback? onLovedOne;
  final ValueChanged<String>? onSelfNamed;

  @override
  State<GuestWelcomeScreen> createState() => _GuestWelcomeScreenState();
}

class _GuestWelcomeScreenState extends State<GuestWelcomeScreen> {
  static const _ink = Color(0xFF073C3D);

  final _name = TextEditingController();
  bool _showNameError = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startNamed() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    if (widget.onSelfNamed != null) {
      widget.onSelfNamed!(name);
    } else {
      widget.onSelf?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF9FDFD),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth =
                  constraints.maxWidth.clamp(0.0, 480.0).toDouble();
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final extraForLargeText =
                  ((textScale - 1.0).clamp(0.0, 1.0) * 90.0);
              final heroHeight = (constraints.maxHeight * 0.47 +
                      extraForLargeText)
                  .clamp(290.0, 460.0)
                  .toDouble();
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WelcomeHero(height: heroHeight, width: contentWidth),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 7, 20, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'دوست داری چطور صدات کنیم؟',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                key: const Key('welcome-name-input'),
                                controller: _name,
                                maxLength: 80,
                                textInputAction: TextInputAction.done,
                                textAlign: TextAlign.right,
                                onSubmitted: (_) => _startNamed(),
                                onChanged: (_) {
                                  if (_showNameError) {
                                    setState(() => _showNameError = false);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'نامت رو بنویس',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF8B989D), fontSize: 17),
                                  counterText: '',
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 15),
                                  errorText: _showNameError
                                      ? 'برای شروع، نامت رو بنویس.'
                                      : null,
                                  enabledBorder: _outline(const Color(0xFF7AADB0)),
                                  focusedBorder: _outline(
                                      const Color(0xFF00BFB3), width: 1.8),
                                  errorBorder: _outline(const Color(0xFFD75D57)),
                                  focusedErrorBorder: _outline(
                                      const Color(0xFFD75D57), width: 1.8),
                                ),
                              ),
                              const SizedBox(height: 28),
                              _WelcomeAction(
                                label: 'شروع برای خودم',
                                onPressed: widget.onSelfNamed == null &&
                                        widget.onSelf == null
                                    ? null : _startNamed,
                                colors: const [
                                  Color(0xFF00C6B5), Color(0xFF00B5AC)],
                              ),
                              const SizedBox(height: 13),
                              _WelcomeAction(
                                label: 'برای یکی از عزیزانم',
                                onPressed: widget.onLovedOne,
                                colors: const [
                                  Color(0xFF087681), Color(0xFF00545C)],
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                key: const Key('welcome-guest-button'),
                                onPressed: widget.onSelf,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                  foregroundColor: const Color(0xFF007E77),
                                ),
                                child: const Text(
                                  'ورود به عنوان مهمان',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Color(0xFF00A89F),
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
            },
          ),
        ),
      );

  OutlineInputBorder _outline(Color color, {double width = 1.15}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: color, width: width),
      );
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.height, required this.width});
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFE5FEFC),
                      Color(0xFFFEFFFF),
                      Color(0xFFF7FFFF),
                    ],
                    stops: [0, 0.48, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 27,
              left: -width * 0.115,
              width: width * 1.30,
              height: width * 0.65,
              child: IgnorePointer(
                child: Image.asset(
                  'assets/images/welcome_ribbon_capsule.png',
                  fit: BoxFit.fill,
                ),
              ),
            ),
            const Positioned(
              right: 18,
              top: 23,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WelcomeBrandMark(),
                  SizedBox(width: 8),
                  Text('همراه دارو', style: TextStyle(
                    color: Color(0xFF004948),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  )),
                ],
              ),
            ),
            const Positioned(
              right: 21,
              left: 18,
              bottom: 77,
              child: Text(
                'سلام،\nخوش اومدی!',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Color(0xFF003E3D),
                  fontSize: 35,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: Color(0xB3FFFFFF), blurRadius: 11),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 21,
              child: Column(
                children: [
                  const Text(
                    'مراقبت از خودت، از همین‌جا شروع می‌شه.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF526267), fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 9),
                  CustomPaint(
                    size: Size(width * 0.70, 8),
                    painter: _SoftArcPainter(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _WelcomeBrandMark extends StatelessWidget {
  const _WelcomeBrandMark();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 43, height: 43,
        child: CustomPaint(painter: _WelcomeBrandPainter()),
      );
}

class _WelcomeBrandPainter extends CustomPainter {
  const _WelcomeBrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final green = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF00D4C7), Color(0xFF0BAB66)],
      ).createShader(const Rect.fromLTWH(0, 0, 48, 48));
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(14, 0, 20, 48), const Radius.circular(8)), green);
    canvas.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 14, 48, 20), const Radius.circular(8)), green);
    final leaf = Path()
      ..moveTo(12, 31)
      ..cubicTo(22, 16, 31, 16, 42, 15)
      ..cubicTo(39, 27, 30, 36, 12, 31)
      ..close();
    canvas.drawPath(leaf, Paint()..color = Colors.white);
    final vein = Path()
      ..moveTo(12, 32)
      ..quadraticBezierTo(25, 26, 38, 20);
    canvas.drawPath(vein, Paint()
      ..color = const Color(0xFF009B86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SoftArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.15, 0)
      ..quadraticBezierTo(size.width * 0.50, 14, size.width * 0.85, 0);
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF66DCCB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WelcomeAction extends StatelessWidget {
  const _WelcomeAction({
    required this.label, required this.onPressed, required this.colors,
  });

  final String label;
  final VoidCallback? onPressed;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(21);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 57,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight, end: Alignment.centerLeft,
              colors: onPressed == null
                  ? [const Color(0xFFABCDCA), const Color(0xFF91B6B4)]
                  : colors,
            ),
            borderRadius: radius,
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Center(child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white,
                fontSize: 19, fontWeight: FontWeight.bold),
            )),
          ),
        ),
      ),
    );
  }
}
