import 'package:flutter/material.dart';

/// Fondo oscuro del logo (el PNG es transparente y está pensado para verse sobre negro).
const logoBackground = Color(0xFF040806);

/// Logo de Golazo (arco, cancha y balón) sobre su fondo oscuro, con esquinas redondeadas.
class GolazoLogo extends StatelessWidget {
  const GolazoLogo({super.key, this.width = 280});
  final double width;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: logoBackground,
          child: Image.asset('assets/images/logo.png', width: width, semanticLabel: 'Golazo'),
        ),
      );
}
