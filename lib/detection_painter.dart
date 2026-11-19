import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_vision/flutter_vision.dart' show BoxMapper, Detection;

import 'bill_info.dart';

/// What the overlay needs to draw one frame.
class ScanFrame {
  const ScanFrame({required this.imageSize, required this.best});

  /// Size of the upright camera image the detection coordinates refer to.
  final Size imageSize;

  /// The single best bill detection in this frame (null = none).
  final Detection? best;
}

/// Draws the box + label around the detected bill on top of the preview.
class DetectionPainter extends CustomPainter {
  DetectionPainter(this.frame);

  final ScanFrame? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    final d = f?.best;
    if (f == null || d == null) return;

    // Same BoxFit as the camera preview widget, so boxes line up.
    final mapper = BoxMapper(
      imageSize: f.imageSize,
      widgetSize: size,
      fit: BoxFit.cover,
      mirror: false,
    );
    final rect = mapper.mapRect(d.box);
    final info = billInfoFor(d.label);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = info.color,
    );

    final text = TextPainter(
      text: TextSpan(
        text: '${info.symbol}  ${(d.confidence * 100).round()}%',
        style: TextStyle(
          color: info.color.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tag = Rect.fromLTWH(
      rect.left,
      math.max(0, rect.top - text.height - 8),
      text.width + 16,
      text.height + 8,
    );
    canvas.drawRect(tag, Paint()..color = info.color);
    text.paint(canvas, Offset(tag.left + 8, tag.top + 4));
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
