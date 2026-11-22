import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'scanner_page.dart';

/// Short animated intro: a phone scans a 1000-peso bill, locks on to it, and
/// then the scanner opens. Tap anywhere to skip.
///
/// Everything is drawn with Flutter widgets, so no image files are needed.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Length of the animation. Make it shorter or longer here.
  static const _length = Duration(milliseconds: 3400);

  late final AnimationController _controller;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _length);
    _controller.forward().whenComplete(() {
      // Hold the finished picture for a moment, then open the scanner.
      Future<void>.delayed(const Duration(milliseconds: 350), _openScanner);
    });
  }

  void _openScanner() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ScannerPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final phoneHeight = math.min(size.height * 0.5, 430.0);
    final phoneWidth = phoneHeight * 0.5;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openScanner,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 0.9,
              colors: [Color(0xFF16304F), Color(0xFF0B1220)],
            ),
          ),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final intro = Curves.easeOutCubic.transform(_seg(t, 0.0, 0.22));
                final words = Curves.easeOut.transform(_seg(t, 0.15, 0.40));
                final scan = _seg(t, 0.28, 0.80); // one sweep: down and back up
                final lock = _seg(t, 0.80, 0.92); // detection box appears

                return Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Opacity(
                            opacity: intro,
                            child: Transform.translate(
                              offset: Offset(0, 50 * (1 - intro)),
                              child: _Phone(
                                width: phoneWidth,
                                height: phoneHeight,
                                scan: scan,
                                lock: lock,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Opacity(
                            opacity: words,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Bill Scanner',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Peso \u00B7 Dollar \u00B7 Euro',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Opacity(
                          opacity: words * 0.6,
                          child: const Text(
                            'Tap to skip',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps [t] (0..1) to the part of the animation between [start] and [end].
double _seg(double t, double start, double end) =>
    ((t - start) / (end - start)).clamp(0.0, 1.0).toDouble();

const _scanColor = Color(0xFF69F0AE);

/// A phone whose screen shows the camera looking at a bill.
class _Phone extends StatelessWidget {
  const _Phone({
    required this.width,
    required this.height,
    required this.scan,
    required this.lock,
  });

  final double width;
  final double height;

  /// 0..1: progress of the scanning sweep.
  final double scan;

  /// 0..1: how far the detection box has appeared.
  final double lock;

  @override
  Widget build(BuildContext context) {
    const bezel = 10.0;
    final outerRadius = width * 0.14;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2433),
        borderRadius: BorderRadius.circular(outerRadius),
        border: Border.all(color: const Color(0xFF3A4660), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(outerRadius - bezel),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The camera "picture": a dark table.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF263445), Color(0xFF111A26)],
                ),
              ),
            ),
            LayoutBuilder(builder: _buildScene),
            // Front camera pill.
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 44,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScene(BuildContext context, BoxConstraints c) {
    final billW = c.maxWidth * 0.62;
    final billH = billW * 2.3;
    final left = (c.maxWidth - billW) / 2;
    final top = (c.maxHeight - billH) / 2 + 8;

    final sweep = 0.5 - 0.5 * math.cos(scan * 2 * math.pi); // 0 -> 1 -> 0
    final glow = math.sin(scan * math.pi).clamp(0.0, 1.0).toDouble();
    final lockScale = 1.12 - 0.12 * Curves.easeOutBack.transform(lock);

    return Stack(
      children: [
        // The bill, turned sideways so it fills the portrait screen.
        Positioned(
          left: left,
          top: top,
          width: billW,
          height: billH,
          child: const RotatedBox(quarterTurns: 1, child: _Bill()),
        ),
        // Scanning line.
        Positioned(
          left: left - 14,
          width: billW + 28,
          top: top + sweep * billH - 2,
          height: 4,
          child: Opacity(
            opacity: glow,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _scanColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: _scanColor.withValues(alpha: 0.8),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Detection corners.
        Positioned(
          left: left - 12,
          top: top - 12,
          width: billW + 24,
          height: billH + 24,
          child: Opacity(
            opacity: lock,
            child: Transform.scale(
              scale: lockScale,
              child: CustomPaint(painter: _BracketsPainter()),
            ),
          ),
        ),
        // Label above the detection box.
        Positioned(
          left: left - 12,
          top: top - 12 - 28,
          child: Opacity(
            opacity: lock,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '\u20B11000',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A simple, stylised blue 1000-peso bill (landscape; the caller rotates it).
class _Bill extends StatelessWidget {
  const _Bill();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        const white = Colors.white;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h * 0.07),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF64B5F6), Color(0xFF1565C0)],
            ),
            border: Border.all(color: white.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Padding(
            padding: EdgeInsets.all(h * 0.09),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Stylised portrait oval.
                Container(
                  width: h * 0.52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(h),
                    border: Border.all(
                      color: white.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.person,
                    size: h * 0.4,
                    color: white.withValues(alpha: 0.55),
                  ),
                ),
                SizedBox(width: h * 0.09),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'ONE THOUSAND PESOS',
                          style: TextStyle(
                            color: white.withValues(alpha: 0.85),
                            fontSize: h * 0.085,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '\u20B11000',
                          style: TextStyle(
                            color: white,
                            fontSize: h * 0.36,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: h * 0.05,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(h),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Four green corner marks, like a camera focus frame.
class _BracketsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _scanColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final len = math.min(w, h) * 0.18;

    final path = Path()
      ..moveTo(0, len)
      ..lineTo(0, 0)
      ..lineTo(len, 0)
      ..moveTo(w - len, 0)
      ..lineTo(w, 0)
      ..lineTo(w, len)
      ..moveTo(w, h - len)
      ..lineTo(w, h)
      ..lineTo(w - len, h)
      ..moveTo(len, h)
      ..lineTo(0, h)
      ..lineTo(0, h - len);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
