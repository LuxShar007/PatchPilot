import 'package:flutter/material.dart';
import '../models/ocr_box.dart';

/// Custom Painter that renders OCR bounding boxes and error badges
/// dynamically overlaid across the camera viewfinder.
class OcrOverlayPainter extends CustomPainter {
  final List<OcrBoundingBox> boxes;
  final Size previewSize;
  final Size widgetSize;

  OcrOverlayPainter({
    required this.boxes,
    required this.previewSize,
    required this.widgetSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty) return;

    final double scaleX = widgetSize.width / (previewSize.width > 0 ? previewSize.width : widgetSize.width);
    final double scaleY = widgetSize.height / (previewSize.height > 0 ? previewSize.height : widgetSize.height);

    for (final box in boxes) {
      final rect = Rect.fromLTRB(
        box.boundingBox.left * scaleX,
        box.boundingBox.top * scaleY,
        box.boundingBox.right * scaleX,
        box.boundingBox.bottom * scaleY,
      );

      final Paint borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = box.isErrorSignature ? 2.5 : 1.5;

      final Paint fillPaint = Paint()..style = PaintingStyle.fill;

      if (box.isErrorSignature) {
        borderPaint.color = const Color(0xFFEF4444); // Crimson red
        fillPaint.color = const Color(0xFFEF4444).withOpacity(0.2);
      } else if (box.isStackTrace) {
        borderPaint.color = const Color(0xFFF59E0B); // Amber
        fillPaint.color = const Color(0xFFF59E0B).withOpacity(0.15);
      } else {
        borderPaint.color = const Color(0xFF0EA5E9).withOpacity(0.6); // Cyan
        fillPaint.color = const Color(0xFF0EA5E9).withOpacity(0.06);
      }

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, borderPaint);

      // Draw small badge indicator if error signature
      if (box.isErrorSignature) {
        final textPainter = TextPainter(
          text: const TextSpan(
            text: ' ERROR DETECTED ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0xFFEF4444),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(canvas, Offset(rect.left, rect.top - 14));
      }
    }
  }

  @override
  bool shouldRepaint(covariant OcrOverlayPainter oldDelegate) {
    return oldDelegate.boxes != boxes;
  }
}
