import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

class CircuitPainter extends CustomPainter {
  final String circuitId;
  final Color trackColor;

  CircuitPainter({
    required this.circuitId,
    this.trackColor = AppColors.glassBorder,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = getCircuitPath(circuitId, size);
    final paint = Paint()
      ..color = trackColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    // Glowing track outline
    final glowPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);

    // Draw Start/Finish line
    _drawStartFinishLine(canvas, path, size);
  }

  void _drawStartFinishLine(Canvas canvas, Path path, Size size) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(0.0);
    if (tangent == null) return;

    final pos = tangent.position;
    final dir = tangent.vector;
    
    // Draw a small neon red start/finish line perpendicular to track vector
    final perpX = -dir.dy;
    final perpY = dir.dx;
    
    final paint = Paint()
      ..color = AppColors.f1Red
      ..strokeWidth = 3.0;

    canvas.drawLine(
      Offset(pos.dx - perpX * 8, pos.dy - perpY * 8),
      Offset(pos.dx + perpX * 8, pos.dy + perpY * 8),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CircuitPainter oldDelegate) {
    return oldDelegate.circuitId != circuitId || oldDelegate.trackColor != trackColor;
  }

  /// Exposes precise parametric SVG-like path configurations for F1 tracks
  static Path getCircuitPath(String circuitId, Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    switch (circuitId.toLowerCase()) {
      case 'monaco':
        // Monaco Layout
        path.moveTo(w * 0.15, h * 0.70);
        path.quadraticBezierTo(w * 0.15, h * 0.25, w * 0.35, h * 0.20); // Ste Devote to Beau Rivage
        path.lineTo(w * 0.50, h * 0.30); // Massenet
        path.cubicTo(w * 0.65, h * 0.35, w * 0.70, h * 0.15, w * 0.85, h * 0.25); // Casino to Mirabeau
        path.lineTo(w * 0.88, h * 0.35); // Grand Hotel Hairpin
        path.quadraticBezierTo(w * 0.80, h * 0.45, w * 0.90, h * 0.50); // Portier
        path.lineTo(w * 0.65, h * 0.55); // Tunnel
        path.quadraticBezierTo(w * 0.50, h * 0.58, w * 0.45, h * 0.70); // Chicane
        path.lineTo(w * 0.48, h * 0.82); // Tabac
        path.cubicTo(w * 0.40, h * 0.90, w * 0.28, h * 0.88, w * 0.25, h * 0.78); // Swimming Pool
        path.lineTo(w * 0.28, h * 0.72); // Rascasse
        path.close();
        break;

      case 'monza':
        // Monza Layout (Temple of speed - long straight with chicane & parabolic curves)
        path.moveTo(w * 0.10, h * 0.50);
        path.lineTo(w * 0.80, h * 0.20); // Prima Variante straight
        path.quadraticBezierTo(w * 0.88, h * 0.22, w * 0.90, h * 0.35); // Curva Grande
        path.lineTo(w * 0.85, h * 0.50); // Roggia chicane
        path.cubicTo(w * 0.80, h * 0.62, w * 0.70, h * 0.58, w * 0.65, h * 0.65); // Lesmos
        path.lineTo(w * 0.35, h * 0.80); // Serraglio straight
        path.quadraticBezierTo(w * 0.25, h * 0.85, w * 0.20, h * 0.75); // Ascari Chicane
        path.lineTo(w * 0.12, h * 0.68);
        path.quadraticBezierTo(w * 0.05, h * 0.62, w * 0.10, h * 0.50); // Alboreto / Parabolica
        path.close();
        break;

      case 'silverstone':
        // Silverstone Layout (classic British track)
        path.moveTo(w * 0.25, h * 0.80);
        path.lineTo(w * 0.15, h * 0.50); // Hamilton Straight
        path.quadraticBezierTo(w * 0.12, h * 0.38, w * 0.25, h * 0.32); // Abbey to Farm
        path.lineTo(w * 0.40, h * 0.35); // Loop
        path.quadraticBezierTo(w * 0.45, h * 0.45, w * 0.50, h * 0.38); // Aintree
        path.lineTo(w * 0.75, h * 0.18); // Wellington Straight
        path.quadraticBezierTo(w * 0.88, h * 0.16, w * 0.82, h * 0.32); // Brooklands / Luffield
        path.lineTo(w * 0.65, h * 0.48); // Woodcote
        path.lineTo(w * 0.78, h * 0.52); // Copse
        path.cubicTo(w * 0.90, h * 0.55, w * 0.85, h * 0.72, w * 0.75, h * 0.68); // Maggotts & Becketts
        path.lineTo(w * 0.55, h * 0.82); // Hangar Straight
        path.quadraticBezierTo(w * 0.42, h * 0.90, w * 0.38, h * 0.80); // Stowe
        path.lineTo(w * 0.30, h * 0.82); // Vale / Club
        path.close();
        break;

      case 'spa':
        // Spa-Francorchamps Layout
        path.moveTo(w * 0.25, h * 0.20);
        path.quadraticBezierTo(w * 0.22, h * 0.10, w * 0.32, h * 0.12); // La Source
        path.lineTo(w * 0.42, h * 0.28); // Eau Rouge
        path.lineTo(w * 0.50, h * 0.22); // Raidillon
        path.lineTo(w * 0.80, h * 0.35); // Kemmel Straight
        path.quadraticBezierTo(w * 0.92, h * 0.40, w * 0.85, h * 0.55); // Les Combes
        path.lineTo(w * 0.78, h * 0.68); // Bruxelles
        path.quadraticBezierTo(w * 0.72, h * 0.78, w * 0.65, h * 0.68); // Speaker's Corner
        path.lineTo(w * 0.52, h * 0.60); // Pouhon
        path.cubicTo(w * 0.40, h * 0.55, w * 0.32, h * 0.78, w * 0.22, h * 0.72); // Fagnes to Stavelot
        path.lineTo(w * 0.18, h * 0.58); // Blanchimont
        path.quadraticBezierTo(w * 0.12, h * 0.42, w * 0.22, h * 0.38); // Bus Stop Chicane
        path.close();
        break;

      default:
        // Generic modern F1 track (tilke-drome)
        path.moveTo(w * 0.10, h * 0.30);
        path.lineTo(w * 0.80, h * 0.20); // Main straight
        path.quadraticBezierTo(w * 0.90, h * 0.25, w * 0.85, h * 0.42); // Hairpin 1
        path.lineTo(w * 0.50, h * 0.50); // S curves
        path.cubicTo(w * 0.35, h * 0.55, w * 0.42, h * 0.75, w * 0.55, h * 0.72);
        path.lineTo(w * 0.88, h * 0.68); // Straight 2
        path.quadraticBezierTo(w * 0.92, h * 0.78, w * 0.78, h * 0.88); // Curve 2
        path.lineTo(w * 0.20, h * 0.82); // Straight 3
        path.quadraticBezierTo(w * 0.08, h * 0.72, w * 0.15, h * 0.55); // Final corner
        path.close();
        break;
    }

    return path;
  }

  /// Calculates the coordinate offset (position + heading tangent) at a completion ratio (0.0 to 1.0) along the track path
  static Offset getPointOnPath(String circuitId, Size size, double progress) {
    final path = getCircuitPath(circuitId, size);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return Offset.zero;
    final metric = metrics.first;
    final progressOffset = (progress.clamp(0.0, 1.0) * metric.length);
    final tangent = metric.getTangentForOffset(progressOffset);
    return tangent?.position ?? Offset.zero;
  }
}

class LiveDriverDotsPainter extends CustomPainter {
  final String circuitId;
  final List<Map<String, dynamic>> driverProgress; // list of maps: {'code': 'VER', 'progress': 0.45, 'color': Colors.red, 'isLeader': true}

  LiveDriverDotsPainter({
    required this.circuitId,
    required this.driverProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var dp in driverProgress) {
      final progress = dp['progress'] as double;
      final code = dp['code'] as String;
      final color = dp['color'] as Color;
      final isLeader = dp['isLeader'] as bool? ?? false;

      final offset = CircuitPainter.getPointOnPath(circuitId, size, progress);
      if (offset == Offset.zero) continue;

      // Draw dot glow for leader
      if (isLeader) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
        canvas.drawCircle(offset, 10.0, glowPaint);
      }

      // Draw driver dot
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, isLeader ? 6.0 : 4.5, paint);

      // Draw driver border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(offset, isLeader ? 6.0 : 4.5, borderPaint);

      // Draw code text for leaders/key drivers
      if (isLeader || code == 'VER' || code == 'HAM' || code == 'NOR') {
        const textStyle = TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black,
        );
        final textSpan = TextSpan(
          text: ' $code ',
          style: textStyle,
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        // Position text slightly offset from dot
        textPainter.paint(canvas, Offset(offset.dx + 8, offset.dy - 12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant LiveDriverDotsPainter oldDelegate) {
    return true; // Always repaint as progress ticks
  }
}
