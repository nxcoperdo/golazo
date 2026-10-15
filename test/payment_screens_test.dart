import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golazo/core/format.dart';
import 'package:golazo/core/widgets/ui.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/booking/court_detail_screen.dart';
import 'package:golazo/features/booking/pay_deposit_screen.dart';

import 'courts_screens_test.dart' show FakeApi, withPhone;

Booking pending({DateTime? payBy, BookingStatus status = BookingStatus.pendingPayment, bool noAccounts = false}) => Booking(
      id: 'b1',
      courtId: '1',
      courtName: 'La Bombonera',
      startAt: DateTime.utc(2026, 10, 20, 20),
      hours: 2,
      total: 180000,
      deposit: 54000,
      lastMinute: false,
      status: status,
      cancellable: true,
      payBy: payBy,
      paymentMethods: noAccounts
          ? const []
          : const [PaymentMethod(label: 'Nequi', account: '300 456 7890', holder: 'Carlos Rodríguez')],
    );

void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// App con las dos rutas del flujo: detalle de la cancha → pagar anticipo → mis reservas.
Future<void> pumpFlow(WidgetTester t, FakeApi api, {String start = '/courts/1'}) async {
  tallPhone(t);
  final router = GoRouter(initialLocation: start, routes: [
    GoRoute(path: '/courts/:id', builder: (_, s) => CourtDetailScreen(courtId: s.pathParameters['id']!)),
    GoRoute(path: '/bookings/:id/pay', builder: (_, s) => PayDepositScreen(bookingId: s.pathParameters['id']!)),
    GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('MIS RESERVAS'))),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api),
      pickImageProvider.overrideWithValue((_) async => PickedImage(Uint8List.fromList([1, 2, 3]), 'comprobante.jpg')),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await manrope.load();
  });

  group('aviso de anticipo', () {
    /// Elige un día a 3 días (no es "último momento") y las horas 8:00 y 9:00 AM, y toca Reservar.
    Future<void> reserve(WidgetTester t) async {
      final day = coToday().add(const Duration(days: 3)).day;
      await t.tap(find.text('$day').first);
      await t.pumpAndSettle();
      await t.tap(find.text('8:00 AM'));
      await t.pump();
      await t.tap(find.text('9:00 AM'));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Reservar'));
      await t.pumpAndSettle();
    }

    testWidgets('muestra el monto, el porcentaje, el resumen y los 30 minutos', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpFlow(t, api);
      await reserve(t);
      expect(find.text('Esta reserva requiere anticipo'), findsOneWidget);
      expect(find.textContaining('equivalente al 30 % del total', findRichText: true), findsOneWidget);
      expect(find.text('Reserva'), findsOneWidget);
      expect(find.text('2 h'), findsOneWidget);
      expect(find.textContaining('30 minutos para subir el comprobante'), findsOneWidget);
      expect(find.text('Pagar anticipo'), findsOneWidget);
      expect(api.created, 0, reason: 'todavía no se crea la reserva');
    });

    testWidgets('Cancelar cierra la hoja y no crea la reserva', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpFlow(t, api);
      await reserve(t);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.text('Esta reserva requiere anticipo'), findsNothing);
      expect(api.created, 0);
    });

    testWidgets('Pagar anticipo crea la reserva y abre la pantalla de pago', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpFlow(t, api);
      await reserve(t);
      await t.tap(find.text('Pagar anticipo'));
      await t.pumpAndSettle();
      expect(api.created, 1);
      expect(find.text('Paso final'), findsOneWidget);
    });
  });

  group('pantalla de pago', () {
    testWidgets('muestra el resumen, la cuenta regresiva y la cuenta del dueño', (t) async {
      final api = FakeApi(user: withPhone)..current = pending(payBy: DateTime.now().add(const Duration(minutes: 29, seconds: 42)));
      await pumpFlow(t, api, start: '/bookings/b1/pay');
      expect(find.text('Pagar anticipo'), findsOneWidget);
      expect(find.textContaining(r'$180.000', findRichText: true), findsOneWidget);
      expect(find.textContaining(r'$54.000', findRichText: true), findsOneWidget);
      expect(find.text('La Bombonera'), findsOneWidget);
      expect(find.text('Tu horario está reservado por 30 minutos'), findsOneWidget);
      expect(find.textContaining('Tiempo restante: 29:'), findsOneWidget);
      expect(find.text('Cuenta del dueño'), findsOneWidget);
      expect(find.text('Nequi'), findsOneWidget);
      expect(find.text('300 456 7890'), findsOneWidget);
      expect(find.text('Carlos Rodríguez'), findsOneWidget);
    });

    testWidgets('Copiar cambia a Copiado y vuelve a Copiar', (t) async {
      final api = FakeApi(user: withPhone)..current = pending();
      await pumpFlow(t, api, start: '/bookings/b1/pay');
      await t.tap(find.text('Copiar'));
      await t.pump();
      expect(find.text('Copiado'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      expect(find.text('Copiar'), findsOneWidget);
    });

    testWidgets('al vencer el tiempo avisa que la hora fue liberada y vuelve a pedir la reserva', (t) async {
      final api = FakeApi(user: withPhone)..current = pending(payBy: DateTime.now().subtract(const Duration(seconds: 1)));
      await pumpFlow(t, api, start: '/bookings/b1/pay');
      final before = api.bookingFetches;
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('Tu horario fue liberado'), findsOneWidget);
      expect(api.bookingFetches, greaterThan(before));
    });

    testWidgets('enviar comprobante: deshabilitado hasta elegir la imagen y luego pasa a revisión', (t) async {
      final api = FakeApi(user: withPhone)..current = pending(payBy: DateTime.now().add(const Duration(minutes: 20)));
      await pumpFlow(t, api, start: '/bookings/b1/pay');
      final send = find.widgetWithText(FilledButton, 'Enviar comprobante');
      expect(t.widget<FilledButton>(send).onPressed, isNull);
      expect(find.text('Subir comprobante'), findsOneWidget);

      await t.tap(find.text('Subir comprobante'));
      await t.pumpAndSettle();
      expect(find.text('comprobante.jpg'), findsOneWidget);
      expect(find.text('Toca para cambiar la imagen'), findsOneWidget);
      expect(api.uploads, isEmpty, reason: 'elegir la imagen no la envía');
      expect(t.widget<FilledButton>(send).onPressed, isNotNull);

      await t.tap(send);
      await t.pumpAndSettle();
      expect(api.uploads, ['comprobante.jpg']);
      expect(find.text('PAGO EN REVISIÓN'), findsOneWidget);
      expect(find.text('Comprobante enviado'), findsOneWidget);
      expect(find.text('Anticipo enviado'), findsOneWidget);
      expect(find.text('Ver mis reservas'), findsOneWidget);
      expect(find.text('Enviar comprobante'), findsNothing);

      await t.tap(find.text('Ver mis reservas'));
      await t.pumpAndSettle();
      expect(find.text('MIS RESERVAS'), findsOneWidget);
    });

    testWidgets('comprobante rechazado: avisa y deja subir uno nuevo, sin cuenta regresiva', (t) async {
      final api = FakeApi(user: withPhone)..current = pending(status: BookingStatus.rejected);
      await pumpFlow(t, api, start: '/bookings/b1/pay');
      expect(find.text('Tu comprobante fue rechazado'), findsOneWidget);
      expect(find.textContaining('Tiempo restante'), findsNothing);
      expect(find.text('Enviar comprobante'), findsOneWidget);
    });

    testWidgets('sin cuentas configuradas pide contactar al dueño', (t) async {
      final api = FakeApi(user: withPhone)..current = pending(noAccounts: true);
      await pumpFlow(t, api, start: '/bookings/b1/pay');
      expect(find.textContaining('no configuró cuentas de pago'), findsOneWidget);
    });

    testWidgets('reserva confirmada y cancelada muestran su estado final', (t) async {
      final api = FakeApi(user: withPhone)..current = pending(status: BookingStatus.confirmed);
      await pumpFlow(t, api, start: '/bookings/b1/pay');
      expect(find.text('¡Reserva confirmada!'), findsOneWidget);
      expect(find.text('Anticipo pagado'), findsOneWidget);
      expect(find.text('Enviar comprobante'), findsNothing);

      final api2 = FakeApi(user: withPhone)..current = pending(status: BookingStatus.cancelled);
      await pumpFlow(t, api2, start: '/bookings/b1/pay');
      expect(find.text('Esta reserva fue cancelada'), findsOneWidget);
      expect(find.text('Anticipo pagado'), findsNothing);
    });
  });

  test('Booking.fromJson lee payBy y lo deja en null si falta', () {
    Map<String, dynamic> json([Object? payBy]) => {
          'id': 'b1', 'courtId': 'c1', 'courtName': 'X', 'startAt': '2026-10-20T20:00:00.000Z', 'hours': 1,
          'total': 90000, 'deposit': 27000, 'status': 'pending_payment',
          'payBy': ?payBy,
        };
    expect(Booking.fromJson(json('2026-10-14T20:30:00.000Z')).payBy, DateTime.utc(2026, 10, 14, 20, 30));
    expect(Booking.fromJson(json()).payBy, isNull);
    expect(Booking.fromJson({...json(), 'payBy': null}).payBy, isNull);
  });
}
