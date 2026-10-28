import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/router.dart';
import 'package:golazo/data/golazo_api.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/auth/consent_screen.dart';
import 'package:golazo/features/auth/login_screen.dart';

class _Api extends Fake implements GolazoApi {
  _Api(this.user);
  AppUser? user;

  @override
  Future<AppUser?> restore() async => user;

  @override
  Future<void> acceptTerms() async {
    user = const AppUser(id: 'u1', name: 'Ana', role: Role.player);
  }
}

Future<void> _pumpApp(WidgetTester t, _Api api) async {
  t.view.physicalSize = const Size(411, 891);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [apiProvider.overrideWithValue(api)],
    child: Consumer(builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider))),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await manrope.load();
  });

  testWidgets('sesión sin consentimiento vigente: el router manda a /consent', (t) async {
    await _pumpApp(t, _Api(const AppUser(id: 'u1', name: 'Ana', role: Role.player, consentRequired: true)));
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(find.text('Antes de seguir'), findsOneWidget);
  });

  testWidgets('sin sesión: /consent no se puede abrir y va al login', (t) async {
    await _pumpApp(t, _Api(null));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ConsentScreen), findsNothing);
  });
}
