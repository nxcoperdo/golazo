import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/widgets/auth_ui.dart';
import 'package:golazo/data/golazo_api.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/auth/login_screen.dart';
import 'package:golazo/features/auth/password_reset_screens.dart';
import 'package:golazo/features/auth/register_screen.dart';
import 'package:golazo/features/auth/splash_screen.dart';
import 'package:golazo/features/auth/verify_email_screen.dart';

class FakeApi extends Fake implements GolazoApi {
  FakeApi({this.fail = false});
  final bool fail;
  final calls = <String>[];

  @override
  Future<AppUser?> restore() async => null;

  @override
  Future<void> resetPassword(String token, String password) async => calls.add('reset:$token');

  @override
  Future<void> verifyEmail(String token) async {
    if (fail) throw Exception('El enlace venció');
    calls.add('verify:$token');
  }
}

Widget app(Widget home, {FakeApi? api}) => ProviderScope(
      overrides: [if (api != null) apiProvider.overrideWithValue(api)],
      child: MaterialApp(home: home),
    );

Finder field(int i) => find.byType(TextFormField).at(i);

/// Pantalla de teléfono alto (411x891) para que todo el formulario sea tocable sin desplazar.
void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(411, 891);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  // Sin esto los tests dibujan el texto con una fuente de cajas anchas y no miden lo real.
  setUpAll(() async {
    final manrope = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await manrope.load();
  });

  testWidgets('login: campos vacíos muestran los errores y no llaman al servidor', (tester) async {
    tallPhone(tester);
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Correo no válido'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('login: ofrece Google, crear cuenta y recuperar contraseña', (tester) async {
    await tester.pumpWidget(app(const LoginScreen()));
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Crear cuenta nueva'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(find.text('o continúa con'), findsOneWidget);
    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
  });

  testWidgets('login: el ojo muestra y oculta la contraseña', (tester) async {
    tallPhone(tester);
    await tester.pumpWidget(app(const LoginScreen()));
    bool obscured() => tester.widget<TextField>(find.byType(TextField).at(1)).obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.byTooltip('Ver contraseña'));
    await tester.pump();
    expect(obscured(), isFalse);
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pump();
    expect(obscured(), isTrue);
  });

  testWidgets('login: el correo inválido deja el campo en rojo', (tester) async {
    tallPhone(tester);
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.enterText(field(0), 'no-es-correo');
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    final decoration = tester.widget<InputDecorator>(find.byType(InputDecorator).first).decoration;
    expect(decoration.errorText, 'Correo no válido');
  });

  testWidgets('registro: valida celular colombiano y contraseña', (tester) async {
    await tester.pumpWidget(app(const RegisterScreen()));
    await tester.enterText(field(0), 'Ana Gómez');
    await tester.enterText(field(1), 'ana@correo.co');
    await tester.enterText(field(2), '12345');
    await tester.enterText(field(3), 'corta');
    final button = find.text('Crear cuenta').last;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Celular de 10 dígitos que empiece por 3'), findsOneWidget);
    expect(find.text('Mínimo 8 caracteres'), findsWidgets);
  });

  testWidgets('registro: opción de dueño de cancha', (tester) async {
    await tester.pumpWidget(app(const RegisterScreen()));
    expect(find.text('Soy dueño de una cancha'), findsOneWidget);
    bool toggled() => tester
        .widget<Semantics>(find.descendant(of: find.byType(SwitchCard), matching: find.byType(Semantics)).first)
        .properties
        .toggled!;
    final card = find.byType(SwitchCard);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(toggled(), isFalse);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(toggled(), isTrue);
  });

  for (final size in const [Size(320, 568), Size(411, 891)]) {
    testWidgets('las pantallas de acceso caben en ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final screen in <Widget>[
        const LoginScreen(),
        const RegisterScreen(),
        const ForgotPasswordScreen(),
        const ResetPasswordScreen(),
        const VerifyEmailScreen(token: null),
        const SplashScreen(),
      ]) {
        await tester.pumpWidget(app(screen, api: FakeApi()));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
      }
    });
  }

  testWidgets('nueva contraseña: con enlace no pide el código y muestra el éxito', (tester) async {
    tallPhone(tester);
    final api = FakeApi();
    await tester.pumpWidget(app(const ResetPasswordScreen(token: 'abc'), api: api));
    expect(find.text('Código del enlace'), findsNothing);
    await tester.enterText(field(0), 'nueva-clave-1');
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();
    expect(api.calls, ['reset:abc']);
    expect(find.text('Contraseña actualizada'), findsOneWidget);
    expect(find.text('Volver a ingresar'), findsOneWidget);
  });

  testWidgets('nueva contraseña: sin enlace pide el código', (tester) async {
    await tester.pumpWidget(app(const ResetPasswordScreen(), api: FakeApi()));
    expect(find.text('Código del enlace'), findsOneWidget);
  });

  testWidgets('confirmar correo: éxito', (tester) async {
    tallPhone(tester);
    final api = FakeApi();
    await tester.pumpWidget(app(const VerifyEmailScreen(token: 't1'), api: api));
    await tester.pumpAndSettle();
    expect(api.calls, ['verify:t1']);
    expect(find.text('¡Correo confirmado!'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('confirmar correo: enlace vencido', (tester) async {
    tallPhone(tester);
    await tester.pumpWidget(app(const VerifyEmailScreen(token: 't2'), api: FakeApi(fail: true)));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos confirmar tu correo'), findsOneWidget);
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
  });
}
