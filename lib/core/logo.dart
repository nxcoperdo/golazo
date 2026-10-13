import 'package:flutter/material.dart';

/// Logo de Golazo: césped verde con la cancha marcada y un balón entrando al arco.
class GolazoLogo extends StatelessWidget {
  const GolazoLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final grass = Paint()..color = const Color(0xFF1B8A3A);
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025;

    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * 0.22)), grass);

    // Cancha: borde, línea central, círculo y área del arco.
    final field = Rect.fromLTWH(w * 0.1, w * 0.1, w * 0.8, w * 0.8);
    canvas.drawRect(field, line);
    canvas.drawLine(Offset(field.left, w * 0.5), Offset(field.right, w * 0.5), line);
    canvas.drawCircle(Offset(w * 0.5, w * 0.5), w * 0.12, line);
    canvas.drawRect(Rect.fromLTWH(w * 0.3, field.top, w * 0.4, w * 0.16), line);

    // Balón.
    final c = Offset(w * 0.5, w * 0.62);
    final r = w * 0.15;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.015);
    final pent = Path();
    for (var i = 0; i < 5; i++) {
      final a = -1.5708 + i * 1.2566;
      final p = c + Offset.fromDirection(a, r * 0.45);
      i == 0 ? pent.moveTo(p.dx, p.dy) : pent.lineTo(p.dx, p.dy);
    }
    pent.close();
    canvas.drawPath(pent, Paint()..color = Colors.black87);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
