import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/features/auth/login_screen.dart';
import 'package:golazo/features/auth/register_screen.dart';

Widget app(Widget home) => ProviderScope(child: MaterialApp(home: home));

void main() {
  testWidgets('login: campos vacíos muestran los errores y no llaman al servidor', (tester) async {
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Correo no válido'), findsOneWidget);
    expect(find.text('La contraseña es obligatorio'), findsOneWidget);
  });

  testWidgets('login: ofrece Google, crear cuenta y recuperar contraseña', (tester) async {
    await tester.pumpWidget(app(const LoginScreen()));
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Crear cuenta nueva'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });

  testWidgets('registro: valida celular colombiano y contraseña', (tester) async {
    await tester.pumpWidget(app(const RegisterScreen()));
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre completo'), 'Ana Gómez');
    await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), 'ana@correo.co');
    await tester.enterText(find.widgetWithText(TextFormField, 'Celular de contacto'), '12345');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña (mínimo 8 caracteres)'), 'corta');
    final button = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Celular de 10 dígitos que empiece por 3'), findsOneWidget);
    expect(find.text('Mínimo 8 caracteres'), findsOneWidget);
  });

  testWidgets('registro: opción de dueño de cancha', (tester) async {
    await tester.pumpWidget(app(const RegisterScreen()));
    expect(find.text('Soy dueño de una cancha'), findsOneWidget);
    final sw = find.byType(SwitchListTile);
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);
  });
}
