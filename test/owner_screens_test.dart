import 'dart:convert';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golazo/core/format.dart';
import 'package:golazo/core/location.dart';
import 'package:golazo/core/widgets/design.dart' show PillSwitch;
import 'package:golazo/core/widgets/ui.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/owner/court_form_screen.dart';
import 'package:golazo/features/owner/court_manage_screen.dart';
import 'package:golazo/features/owner/owner_bookings_tab.dart';
import 'package:golazo/features/owner/owner_courts_tab.dart';
import 'package:golazo/features/owner/owner_payments_tab.dart';
import 'package:golazo/features/owner/stats_screen.dart';

import 'courts_screens_test.dart' show FakeApi, mkCourt;

/// PNG de 1x1 píxel para las miniaturas de comprobantes.
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

const owner = AppUser(id: 'o1', name: 'Carlos Rodríguez', email: 'carlos@correo.com', role: Role.owner, phone: '3004567890', emailVerified: true);

Payment mkPayment(String id, {PaymentStatus status = PaymentStatus.pending, String payer = 'Laura Méndez', int amount = 54000, String? reason}) => Payment(
      id: id,
      kind: 'booking',
      status: status,
      amount: amount,
      createdAt: DateTime.utc(2026, 10, 14, 15),
      courtId: 'c1',
      courtName: 'La Bombonera 5',
      payerName: payer,
      payerPhone: '3004567821',
      rejectReason: reason,
      startAt: DateTime.utc(2026, 10, 20, 23),
      hours: 2,
    );

OwnerBooking mkOwnerBooking(String id, DateTime start, {String court = 'La Bombonera 5', String courtId = 'c1', String? player = 'Laura Méndez', BookingStatus status = BookingStatus.confirmed, bool block = false, String? note}) =>
    OwnerBooking(
      id: id,
      courtId: courtId,
      courtName: court,
      startAt: start,
      hours: 2,
      total: 180000,
      deposit: 54000,
      status: status,
      isBlock: block,
      note: note,
      playerName: block ? null : player,
      playerPhone: block ? null : '3004567821',
    );

class OwnerApi extends FakeApi {
  OwnerApi({super.user = owner, List<Court>? courts, List<OwnerBooking>? bookings, List<Payment>? payments})
      : ownerCourtList = courts ?? [],
        bookingList = bookings ?? [],
        paymentList = payments ?? [];

  List<Court> ownerCourtList;
  List<OwnerBooking> bookingList;
  List<Payment> paymentList;
  final calls = <String>[];
  Map<String, dynamic>? createdCourt;
  Map<String, dynamic>? updated;
  List<PaymentMethod>? methods;

  @override
  Future<List<Court>> ownerCourts() async => ownerCourtList;

  @override
  Future<Court> ownerCourt(String id) async => ownerCourtList.firstWhere((c) => c.id == id);

  @override
  Future<List<OwnerBooking>> ownerBookings({DateTime? from, DateTime? to, String? courtId}) async => bookingList;

  @override
  Future<List<Payment>> ownerPayments({PaymentStatus? status}) async =>
      status == null ? paymentList : paymentList.where((p) => p.status == status).toList();

  @override
  Future<void> approvePayment(String id) async {
    calls.add('approve:$id');
    paymentList = [for (final p in paymentList) p.id == id ? mkPayment(id, status: PaymentStatus.approved) : p];
  }

  @override
  Future<void> rejectPayment(String id, {String? reason}) async {
    calls.add('reject:$id:$reason');
    paymentList = [for (final p in paymentList) p.id == id ? mkPayment(id, status: PaymentStatus.rejected, reason: reason) : p];
  }

  @override
  Future<void> blockHours(String courtId, DateTime startAt, int hours, {String? note}) async =>
      calls.add('block:$courtId:$hours:${note ?? ''}');

  @override
  Future<void> unblockHours(String blockId) async {
    calls.add('unblock:$blockId');
    bookingList = bookingList.where((b) => b.id != blockId).toList();
  }

  @override
  Future<OwnerStats> ownerStats({DateTime? from, DateTime? to, String? courtId}) async {
    final days = to!.difference(from!).inDays + 1;
    calls.add('stats:$days');
    return OwnerStats(days: days, total: 35, confirmed: 28, cancelled: 3, awaitingPayment: 4, income: 1840000, bookedHours: 46, occupancyPercent: 68);
  }

  @override
  Future<Uint8List> proofImage(String paymentId) async => Uint8List.fromList(png);

  @override
  Future<Court> createCourt(Map<String, dynamic> data) async {
    createdCourt = data;
    return mkCourt('new', data['name'] as String, data['city'] as String);
  }

  @override
  Future<Court> updateCourt(String id, Map<String, dynamic> data) async {
    updated = data;
    return ownerCourtList.firstWhere((c) => c.id == id);
  }

  @override
  Future<Court> setPaymentMethods(String courtId, List<PaymentMethod> m) async {
    methods = m;
    return ownerCourtList.firstWhere((c) => c.id == courtId);
  }

  @override
  Future<Court> pauseCourt(String id) async {
    calls.add('pause:$id');
    return ownerCourtList.firstWhere((c) => c.id == id);
  }

  @override
  Future<Court> removeCourtPhoto(String courtId, String photoId) async {
    calls.add('rmphoto:$photoId');
    return ownerCourtList.firstWhere((c) => c.id == courtId);
  }

  @override
  Future<SubscriptionConfig> subscriptionConfig() async => const SubscriptionConfig(
      price: 100000, periodDays: 30, accounts: [PaymentMethod(label: 'Nequi', account: '300 999 0011', holder: 'Golazo SAS')]);

  @override
  Future<void> uploadSubscriptionProof(String courtId, Uint8List bytes, String filename) async =>
      calls.add('sub:$courtId:$filename');
}

Court mkOwnerCourt(String id, String name, {CourtStatus status = CourtStatus.active, CourtSubscription? sub, List<PaymentMethod> methods = const [], List<int> types = const [7]}) => Court(
      id: id,
      name: name,
      city: 'Bogotá',
      address: 'Cra 7 # 10-20',
      covered: true,
      types: types,
      pricePerHour: 90000,
      openHour: 8,
      closeHour: 23,
      requiresDeposit: true,
      depositPercent: 30,
      status: status,
      lat: 4.7,
      lng: -74,
      subscription: sub,
      paymentMethods: methods,
      photos: const [CourtPhoto(url: '/v1/files/courts/a.jpg', id: 'p1')],
    );

void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> pumpScreen(WidgetTester t, Widget screen, FakeApi api, {Locate? locate}) async {
  tallPhone(t);
  await t.pumpWidget(ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api),
      pickImageProvider.overrideWithValue((_) async => PickedImage(Uint8List.fromList([1]), 'captura.jpg')),
      if (locate != null) locationProvider.overrideWithValue(locate),
    ],
    child: MaterialApp(home: screen),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await manrope.load();
  });

  group('reservas del dueño', () {
    OwnerApi api0() {
      final today = coToday();
      final later = coInstant(today, 18);
      return OwnerApi(
        courts: [mkOwnerCourt('c1', 'La Bombonera 5'), mkOwnerCourt('c2', 'Golazo Arena')],
        bookings: [
          mkOwnerBooking('b1', later),
          mkOwnerBooking('b2', coInstant(today, 20), court: 'Golazo Arena', courtId: 'c2', player: 'Andrés Pérez', status: BookingStatus.pendingReview),
          mkOwnerBooking('b3', coInstant(today, 21), block: true, note: 'Partido de empresa'),
          mkOwnerBooking('b4', coInstant(today.add(const Duration(days: 2)), 19), player: 'María López'),
        ],
      );
    }

    testWidgets('muestra el día de hoy con sus reservas y estados', (t) async {
      await pumpScreen(t, const OwnerBookingsTab(), api0());
      expect(find.text('Reservas'), findsOneWidget);
      expect(find.text('Todas las canchas'), findsOneWidget);
      expect(find.textContaining('Laura Méndez', findRichText: true), findsOneWidget);
      expect(find.textContaining('Andrés Pérez', findRichText: true), findsOneWidget);
      expect(find.text('Confirmada'), findsOneWidget);
      expect(find.text('En revisión'), findsOneWidget);
      expect(find.text('Bloqueada'), findsOneWidget);
      expect(find.text('Partido de empresa'), findsOneWidget);
      expect(find.text('Quitar bloqueo'), findsOneWidget);
      // La reserva de dentro de dos días no se ve hoy.
      expect(find.textContaining('María López', findRichText: true), findsNothing);
    });

    testWidgets('elegir otro día cambia la lista', (t) async {
      await pumpScreen(t, const OwnerBookingsTab(), api0());
      final d = coToday().add(const Duration(days: 2));
      await t.tap(find.text('${weekdayShort(d)[0].toUpperCase()}${weekdayShort(d).substring(1)} ${d.day}'));
      await t.pumpAndSettle();
      expect(find.textContaining('María López', findRichText: true), findsOneWidget);
      expect(find.textContaining('Laura Méndez', findRichText: true), findsNothing);
    });

    testWidgets('filtrar por cancha en una hoja', (t) async {
      await pumpScreen(t, const OwnerBookingsTab(), api0());
      await t.tap(find.text('Todas las canchas'));
      await t.pumpAndSettle();
      await t.tap(find.text('Golazo Arena').last);
      await t.pumpAndSettle();
      expect(find.textContaining('Andrés Pérez', findRichText: true), findsOneWidget);
      expect(find.textContaining('Laura Méndez', findRichText: true), findsNothing);
    });

    testWidgets('Quitar bloqueo pide confirmación y lo quita', (t) async {
      final api = api0();
      await pumpScreen(t, const OwnerBookingsTab(), api);
      await t.tap(find.text('Quitar bloqueo'));
      await t.pumpAndSettle();
      expect(find.text('¿Quitar el bloqueo?'), findsOneWidget);
      await t.tap(find.text('Quitar bloqueo').last);
      await t.pumpAndSettle();
      expect(api.calls, ['unblock:b3']);
    });

    testWidgets('Bloquear horas: hoja con cuatro cajas y nota; guarda con los valores elegidos', (t) async {
      final api = api0();
      await pumpScreen(t, const OwnerBookingsTab(), api);
      await t.tap(find.text('+ Bloquear horas'));
      await t.pumpAndSettle();
      expect(find.text('Bloquear horas'), findsOneWidget);
      for (final l in ['Cancha', 'Día', 'Desde', 'Duración']) {
        expect(find.text(l), findsOneWidget);
      }
      await t.tap(find.text('Duración'));
      await t.pumpAndSettle();
      await t.tap(find.text('3 horas'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Partido de empresa');
      await t.tap(find.text('Guardar bloqueo'));
      await t.pumpAndSettle();
      expect(api.calls, ['block:c1:3:Partido de empresa']);
      expect(find.text('Horas bloqueadas'), findsOneWidget);
    });
  });

  group('pagos del dueño', () {
    testWidgets('por revisar: miniatura, monto y botones; aprobar pide confirmación', (t) async {
      final api = OwnerApi(payments: [mkPayment('p1'), mkPayment('p2', payer: 'Andrés Pérez', amount: 14000)]);
      await pumpScreen(t, const OwnerPaymentsTab(), api);
      expect(find.text('Pagos'), findsOneWidget);
      expect(find.text('Laura Méndez'), findsOneWidget);
      expect(find.text(r'$54.000'), findsOneWidget);
      expect(find.byType(Image), findsWidgets); // miniaturas
      await t.tap(find.text('Aprobar').first);
      await t.pumpAndSettle();
      expect(find.text('¿Aprobar este pago?'), findsOneWidget);
      await t.tap(find.text('Aprobar').last);
      await t.pumpAndSettle();
      expect(api.calls, ['approve:p1']);
      expect(find.text('Pago aprobado'), findsOneWidget);
      expect(find.text('Laura Méndez'), findsNothing); // pasó al historial
    });

    testWidgets('rechazar pide el motivo en una hoja', (t) async {
      final api = OwnerApi(payments: [mkPayment('p1')]);
      await pumpScreen(t, const OwnerPaymentsTab(), api);
      await t.tap(find.text('Rechazar'));
      await t.pumpAndSettle();
      expect(find.text('Rechazar comprobante'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'El valor no coincide');
      await t.tap(find.text('Rechazar').last);
      await t.pumpAndSettle();
      expect(api.calls, ['reject:p1:El valor no coincide']);
    });

    testWidgets('historial muestra los resueltos con su estado y motivo', (t) async {
      final api = OwnerApi(payments: [
        mkPayment('p1'),
        mkPayment('p2', status: PaymentStatus.approved, payer: 'Carla Ruiz'),
        mkPayment('p3', status: PaymentStatus.rejected, payer: 'Mateo R.', reason: 'Borroso'),
      ]);
      await pumpScreen(t, const OwnerPaymentsTab(), api);
      await t.tap(find.text('Historial'));
      await t.pumpAndSettle();
      expect(find.text('Carla Ruiz'), findsOneWidget);
      expect(find.text('Aprobado'), findsOneWidget);
      expect(find.text('Rechazado'), findsOneWidget);
      expect(find.textContaining('Motivo del rechazo: Borroso'), findsOneWidget);
      expect(find.text('Laura Méndez'), findsNothing);
      expect(find.text('Aprobar'), findsNothing);
    });

    testWidgets('sin comprobantes por revisar', (t) async {
      await pumpScreen(t, const OwnerPaymentsTab(), OwnerApi());
      expect(find.text('No hay comprobantes por revisar.'), findsOneWidget);
    });
  });

  group('mis canchas', () {
    testWidgets('lista las canchas con su estado y accesos', (t) async {
      final api = OwnerApi(courts: [
        mkOwnerCourt('c1', 'La Bombonera 5'),
        mkOwnerCourt('c2', 'Golazo Arena', status: CourtStatus.pending),
        mkOwnerCourt('c3', 'El Potrero', status: CourtStatus.suspended),
      ]);
      await pumpScreen(t, const OwnerCourtsTab(), api);
      expect(find.text('Mis canchas'), findsOneWidget);
      expect(find.text('Ver estadísticas'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('Mensualidad pendiente'), findsOneWidget);
      expect(find.text('Oculta'), findsOneWidget);
      expect(find.text('Administrar cancha'), findsNWidgets(3));
      expect(find.text('+ Nueva cancha'), findsOneWidget);
      expect(find.textContaining('Fútbol 7'), findsWidgets);
    });

    testWidgets('sin canchas invita a crear la primera', (t) async {
      await pumpScreen(t, const OwnerCourtsTab(), OwnerApi());
      expect(find.textContaining('Aún no tienes canchas'), findsOneWidget);
    });
  });

  group('estadísticas', () {
    testWidgets('muestra las cifras y cambia de rango', (t) async {
      final api = OwnerApi();
      await pumpScreen(t, const StatsScreen(), api);
      expect(find.text('Estadísticas'), findsOneWidget);
      expect(find.text('Ingresos confirmados'), findsOneWidget);
      expect(find.text(r'$1.840.000'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
      expect(find.text('46 h'), findsOneWidget);
      expect(find.text('68.0%'), findsOneWidget);
      expect(api.calls.last, 'stats:30');
      await t.tap(find.text('7 días'));
      await t.pumpAndSettle();
      expect(api.calls.last, 'stats:7');
    });
  });

  group('nueva cancha', () {
    testWidgets('crea la cancha con ubicación, tipo y anticipo', (t) async {
      final api = OwnerApi();
      tallPhone(t);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const CourtFormScreen()),
        GoRoute(path: '/owner/courts/:id', builder: (_, s) => Scaffold(body: Text('GESTION ${s.pathParameters['id']}'))),
      ]);
      await t.pumpWidget(ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
          locationProvider.overrideWithValue(() async => (lat: 4.711, lng: -74.072)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await t.pumpAndSettle();
      expect(find.text('Crear cancha'), findsWidgets);

      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'La Bombonera 5');
      await t.enterText(fields.at(1), 'Bogotá');
      await t.enterText(fields.at(2), 'Cra 7 # 10-20');
      await t.tap(find.text('Usar mi ubicación actual'));
      await t.pumpAndSettle();
      expect(find.text('Ubicación lista · usar otra vez'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, '90000'), '90000');
      await t.tap(find.text('Fútbol 7'));
      await t.pump();
      await t.ensureVisible(find.text('Exigir anticipo'));
      await t.tap(find.text('Exigir anticipo'));
      await t.pumpAndSettle();
      expect(find.text('Porcentaje de anticipo'), findsOneWidget);
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Crear cancha'));
      await t.tap(find.widgetWithText(FilledButton, 'Crear cancha'));
      await t.pumpAndSettle();

      expect(api.createdCourt, isNotNull);
      expect(api.createdCourt!['name'], 'La Bombonera 5');
      expect(api.createdCourt!['lat'], 4.711);
      expect(api.createdCourt!['courtTypes'], [5, 7]); // Fútbol 5 (por defecto) + el 7 marcado
      expect(api.createdCourt!['pricePerHour'], 90000);
      expect(api.createdCourt!['requiresDeposit'], true);
      expect(api.createdCourt!['depositPercent'], 30);
      expect(find.text('GESTION new'), findsOneWidget);
    });

    testWidgets('sin ubicación pide usarla o escribir las coordenadas', (t) async {
      final api = OwnerApi();
      await pumpScreen(t, const CourtFormScreen(), api);
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'La Bombonera 5');
      await t.enterText(fields.at(1), 'Bogotá');
      await t.enterText(fields.at(2), 'Cra 7 # 10-20');
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Crear cancha'));
      await t.tap(find.widgetWithText(FilledButton, 'Crear cancha'));
      await t.pumpAndSettle();
      expect(find.text('Usa tu ubicación actual o escribe las coordenadas.'), findsOneWidget);
      expect(find.text('Latitud'), findsOneWidget);
      expect(api.createdCourt, isNull);
    });

    testWidgets('si falla el GPS ofrece las coordenadas a mano', (t) async {
      await pumpScreen(t, const CourtFormScreen(), OwnerApi(), locate: () async => throw const LocationUnavailable());
      await t.tap(find.text('Usar mi ubicación actual'));
      await t.pumpAndSettle();
      expect(find.textContaining('No se pudo obtener la ubicación'), findsOneWidget);
      expect(find.text('Latitud'), findsOneWidget);
    });
  });

  group('administrar cancha', () {
    OwnerApi api0({CourtStatus status = CourtStatus.active, CourtSubscription? sub, List<PaymentMethod> methods = const [PaymentMethod(label: 'Nequi', account: '300 456 7890', holder: 'Carlos Rodríguez')]}) =>
        OwnerApi(courts: [mkOwnerCourt('c1', 'La Bombonera 5', status: status, sub: sub, methods: methods)]);

    testWidgets('muestra fotos, datos, estado, cuentas y mensualidad', (t) async {
      final api = api0(sub: CourtSubscription(activeUntil: dateParam(coToday().add(const Duration(days: 3)))));
      await pumpScreen(t, CourtManageScreen(courtId: 'c1'), api);
      expect(find.text('ADMINISTRAR'), findsOneWidget);
      expect(find.text('La Bombonera 5'), findsWidgets);
      expect(find.text('Fotos'), findsOneWidget);
      expect(find.text('Datos de la cancha'), findsOneWidget);
      expect(find.text('Editar datos'), findsOneWidget);
      expect(find.text('Activa y visible'), findsOneWidget);
      expect(find.text('Cuentas para pagos'), findsOneWidget);
      expect(find.text('Nequi · 300 456 7890'), findsOneWidget);
      expect(find.text('Vence en 3 días'), findsOneWidget);
      expect(find.textContaining(r'Mensualidad · $100.000'), findsOneWidget);
      expect(find.text('Renovar mensualidad'), findsOneWidget);
    });

    testWidgets('ocultar la cancha pide confirmación', (t) async {
      final api = api0();
      await pumpScreen(t, CourtManageScreen(courtId: 'c1'), api);
      await t.tap(find.byType(PillSwitch));
      await t.pumpAndSettle();
      expect(find.text('¿Ocultar la cancha?'), findsOneWidget);
      await t.tap(find.text('Ocultar'));
      await t.pumpAndSettle();
      expect(api.calls, ['pause:c1']);
    });

    testWidgets('agregar una cuenta de cobro desde la hoja', (t) async {
      final api = api0(methods: const []);
      await pumpScreen(t, CourtManageScreen(courtId: 'c1'), api);
      await t.tap(find.text('Agregar'));
      await t.pumpAndSettle();
      expect(find.text('Nueva cuenta de cobro'), findsOneWidget);
      final f = find.byType(TextFormField);
      await t.enterText(f.at(0), 'Nequi');
      await t.enterText(f.at(1), '300 000 0000');
      await t.enterText(f.at(2), 'Carlos');
      await t.tap(find.text('Agregar cuenta'));
      await t.pumpAndSettle();
      expect(api.methods!.single.label, 'Nequi');
      expect(api.methods!.single.holder, 'Carlos');
    });

    testWidgets('editar datos en una hoja y guardar', (t) async {
      final api = api0();
      await pumpScreen(t, CourtManageScreen(courtId: 'c1'), api);
      await t.tap(find.text('Editar datos'));
      await t.pumpAndSettle();
      expect(find.text('Guardar cambios'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextFormField, 'La Bombonera 5'), 'La Bombonera 6');
      await t.tap(find.text('Guardar cambios'));
      await t.pumpAndSettle();
      expect(api.updated!['name'], 'La Bombonera 6');
      expect(api.updated!['courtTypes'], [7]);
      expect(api.updated!['requiresDeposit'], true);
    });

    testWidgets('pagar la mensualidad: cuenta de la plataforma y envío del comprobante', (t) async {
      final api = api0(status: CourtStatus.pending);
      await pumpScreen(t, CourtManageScreen(courtId: 'c1'), api);
      expect(find.text('Pendiente'), findsOneWidget);
      await t.ensureVisible(find.text('Pagar mensualidad'));
      await t.pumpAndSettle();
      await t.tap(find.text('Pagar mensualidad'));
      await t.pumpAndSettle();
      expect(find.text('Transfiere a la cuenta de la plataforma'), findsOneWidget);
      expect(find.text('Nequi · 300 999 0011'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Enviar comprobante');
      expect(t.widget<FilledButton>(send).onPressed, isNull);
      await t.tap(find.text('Subir comprobante'));
      await t.pumpAndSettle();
      expect(find.text('captura.jpg'), findsOneWidget);
      await t.tap(send);
      await t.pumpAndSettle();
      expect(api.calls, ['sub:c1:captura.jpg']);
      expect(find.textContaining('Comprobante enviado'), findsOneWidget);
    });

    testWidgets('mensualidad en revisión: estado azul y botón deshabilitado', (t) async {
      final api = api0(status: CourtStatus.pending, sub: const CourtSubscription(pendingReview: true));
      await pumpScreen(t, CourtManageScreen(courtId: 'c1'), api);
      expect(find.text('En revisión'), findsOneWidget);
      await t.ensureVisible(find.text('Pagar mensualidad'));
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Pagar mensualidad')).onPressed, isNull);
    });
  });

  testWidgets('selector de tipos: se pueden marcar varios y siempre queda uno', (t) async {
    var value = [5];
    await t.pumpWidget(StatefulBuilder(builder: (context, setState) => MaterialApp(
          home: Scaffold(body: CourtTypePicker(value: value, onChanged: (v) => setState(() => value = v))),
        )));
    await t.tap(find.text('Fútbol 7'));
    await t.pump();
    await t.tap(find.text('Fútbol 11'));
    await t.pump();
    expect(value, [5, 7, 11]);
    await t.tap(find.text('Fútbol 5'));
    await t.pump();
    expect(value, [7, 11]);
    await t.tap(find.text('Fútbol 11'));
    await t.pump();
    await t.tap(find.text('Fútbol 7')); // intento quitar el último: no se deja
    await t.pump();
    expect(value, [7]);
  });

  test('longDayLabel y monthShort', () {
    final today = DateTime.utc(2026, 5, 18);
    expect(longDayLabel(today, DateTime.utc(2026, 5, 18, 18)), 'Hoy · 18 de mayo');
    expect(longDayLabel(DateTime.utc(2026, 5, 19), DateTime.utc(2026, 5, 18, 18)), 'Martes 19 de mayo');
  });
}
