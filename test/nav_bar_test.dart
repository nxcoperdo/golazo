import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/widgets/liquid_nav_bar.dart';

void main() {
  testWidgets('6 pestañas caben en 320 px sin cortar ni desbordar', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const labels = ['Pagos', 'Canchas', 'Usuarios', 'Reseñas', 'Resumen', 'Soporte'];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: LiquidGlassNavBar(
          items: [for (final l in labels) NavItem(label: l, icon: Icons.circle, badge: l == 'Soporte' ? 3 : 0)],
          index: 0,
          onChanged: (_) {},
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    for (final l in labels) {
      final text = find.text(l);
      expect(text, findsOneWidget);
      // El texto completo cabe dentro del ancho de su pestaña.
      final slot = tester.getSize(find.ancestor(of: text, matching: find.byType(Expanded)).first);
      expect(tester.getSize(find.ancestor(of: text, matching: find.byType(FittedBox)).first).width,
          lessThanOrEqualTo(slot.width));
    }
  });
}
