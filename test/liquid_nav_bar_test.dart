import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/widgets/design.dart';
import 'package:golazo/core/widgets/liquid_nav_bar.dart';

Widget _app(ValueChanged<int> onChanged, {int index = 0}) => MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: Builder(builder: (c) => Scaffold(body: Text('inset=${MediaQuery.paddingOf(c).bottom}'))),
        bottomNavigationBar: LiquidGlassNavBar(
          index: index,
          onChanged: onChanged,
          items: const [
            NavItem(label: 'Canchas', icon: Icons.sports_soccer),
            NavItem(label: 'Reservas', icon: Icons.receipt_long),
            NavItem(label: 'Avisos', icon: Icons.notifications, badge: 3),
            NavItem(label: 'Perfil', icon: Icons.person),
          ],
        ),
      ),
    );

void main() {
  testWidgets('el contenido recibe el alto de la barra como padding inferior', (t) async {
    await t.pumpWidget(_app((_) {}));
    final inset = double.parse((t.widget(find.textContaining('inset=')) as Text).data!.split('=').last);
    expect(inset, greaterThanOrEqualTo(LiquidGlassNavBar.height));
  });

  testWidgets('un toque cambia de pestaña', (t) async {
    final picked = <int>[];
    await t.pumpWidget(_app(picked.add));
    await t.tap(find.text('Reservas'));
    await t.pumpAndSettle();
    expect(picked, [1]);
  });

  testWidgets('mantener y arrastrar mueve la burbuja y selecciona al soltar', (t) async {
    final picked = <int>[];
    await t.pumpWidget(_app(picked.add));
    final start = t.getCenter(find.text('Canchas'));
    final end = t.getCenter(find.text('Perfil'));
    final g = await t.startGesture(start);
    await t.pump(const Duration(milliseconds: 100));
    await g.moveTo(end, timeStamp: const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 100));
    expect(picked, isEmpty, reason: 'no selecciona mientras el dedo sigue abajo');
    await g.up();
    await t.pumpAndSettle();
    expect(picked, [3]);
  });

  testWidgets('muestra el contador de avisos', (t) async {
    await t.pumpWidget(_app((_) {}));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('el botón flotante de AppPage queda por encima de la barra de cristal', (t) async {
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: AppPage(
          title: 'Reservas',
          fab: PillFab(label: '+ Bloquear horas', onTap: () {}),
          child: const SizedBox.expand(),
        ),
        bottomNavigationBar: LiquidGlassNavBar(
          index: 0,
          onChanged: (_) {},
          items: const [
            NavItem(label: 'Canchas', icon: Icons.sports_soccer),
            NavItem(label: 'Perfil', icon: Icons.person),
          ],
        ),
      ),
    ));
    await t.pumpAndSettle();
    final fab = t.getRect(find.text('+ Bloquear horas'));
    final nav = t.getRect(find.byType(LiquidGlassNavBar));
    expect(fab.bottom, lessThanOrEqualTo(nav.top), reason: 'el botón no debe quedar debajo de la barra');
  });
}
