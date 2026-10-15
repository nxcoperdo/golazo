import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/admin/admin_tabs.dart';

import 'courts_screens_test.dart' show FakeApi;
import 'owner_screens_test.dart' show png;

const admin = AppUser(id: 'a1', name: 'Admin', email: 'admin@golazo.co', role: Role.admin, emailVerified: true);

Payment mkSub(String id, {PaymentStatus status = PaymentStatus.pending, String payer = 'Carlos Rodríguez', String court = 'La Bombonera 5'}) => Payment(
      id: id,
      kind: 'subscription',
      status: status,
      amount: 100000,
      createdAt: DateTime.utc(2026, 10, 14, 15),
      courtId: 'c1',
      courtName: court,
      payerName: payer,
    );

class AdminApi extends FakeApi {
  AdminApi({
    List<Payment>? payments,
    List<AdminCourt>? courts,
    List<AdminUser>? users,
    List<ReportedReview>? reviews,
  })  : paymentList = payments ?? [],
        courtList = courts ?? [],
        userList = users ?? [],
        reviewList = reviews ?? [],
        super(user: admin);

  List<Payment> paymentList;
  List<AdminCourt> courtList;
  List<AdminUser> userList;
  List<ReportedReview> reviewList;
  final calls = <String>[];

  @override
  Future<NotificationsPage> notifications({int limit = 50}) async => const NotificationsPage(unread: 3, items: []);

  @override
  Future<List<Payment>> adminPayments({String? kind, PaymentStatus? status}) async =>
      status == null ? paymentList : paymentList.where((p) => p.status == status).toList();

  @override
  Future<Uint8List> proofImage(String paymentId) async => Uint8List.fromList(png);

  @override
  Future<void> approveSubscription(String id) async {
    calls.add('approve:$id');
    paymentList = [for (final p in paymentList) p.id == id ? mkSub(id, status: PaymentStatus.approved) : p];
  }

  @override
  Future<void> rejectSubscription(String id, {String? reason}) async {
    calls.add('reject:$id:$reason');
    paymentList = [for (final p in paymentList) p.id == id ? mkSub(id, status: PaymentStatus.rejected) : p];
  }

  @override
  Future<List<AdminCourt>> adminCourts({CourtStatus? status, String? search}) async => courtList;

  @override
  Future<void> suspendCourt(String id) async => calls.add('suspendCourt:$id');

  @override
  Future<void> reactivateCourt(String id) async => calls.add('reactivateCourt:$id');

  @override
  Future<List<AdminUser>> adminUsers({String? search, Role? role}) async {
    calls.add('users:${search ?? ''}');
    final q = (search ?? '').toLowerCase();
    return q.isEmpty ? userList : userList.where((u) => u.name.toLowerCase().contains(q) || (u.email ?? '').contains(q)).toList();
  }

  @override
  Future<void> suspendUser(String id) async => calls.add('suspendUser:$id');

  @override
  Future<void> restoreUser(String id) async => calls.add('restoreUser:$id');

  @override
  Future<void> deleteUser(String id) async => calls.add('deleteUser:$id');

  @override
  Future<List<ReportedReview>> reportedReviews() async => reviewList;

  @override
  Future<void> hideReview(String id) async => calls.add('hide:$id');

  @override
  Future<void> dismissReview(String id) async => calls.add('dismiss:$id');

  @override
  Future<Metrics> metrics() async => const Metrics({
        'users': {'player': 1200, 'owner': 48},
        'courts': {'active': 84, 'pending': 5, 'suspended': 1},
        'bookings': {'confirmed': 3420},
        'pending': {'subscriptionPayments': 2, 'reportedReviews': 2},
        'revenue': {'subscriptionsTotal': 5000000, 'subscriptionsThisMonth': 800000},
        'last30Days': {'confirmedBookings': 300, 'bookingsValue': 20000000, 'newUsers': 40},
      });

  @override
  Future<Transactions> transactions({String? kind}) async => Transactions(count: 128, totalAmount: 12840000, items: [
        TransactionItem(id: 't1', kind: 'subscription', amount: 100000, date: DateTime.now().toUtc(), courtName: 'La Bombonera 5', payerName: 'Carlos Rodríguez'),
        TransactionItem(id: 't2', kind: 'booking', amount: 54000, date: DateTime.now().toUtc(), courtName: 'Golazo Arena', payerName: 'Laura Méndez'),
      ]);
}

AdminCourt mkAdminCourt(String id, String name, CourtStatus status, {bool pending = false, bool byAdmin = false}) => AdminCourt(
      id: id,
      name: name,
      city: 'Bogotá',
      status: status,
      suspendedByAdmin: byAdmin,
      ownerName: 'Carlos Rodríguez',
      ownerPhone: '3004567890',
      pendingSubscription: pending,
    );

AdminUser mkUser(String id, String name, Role role, {bool suspended = false}) => AdminUser(
      id: id,
      name: name,
      email: '${name.split(' ').first.toLowerCase()}@correo.com',
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
      suspended: suspended,
    );

ReportedReview mkReported(String id, {int stars = 2, int reports = 3}) => ReportedReview(
      id: id,
      stars: stars,
      courtName: 'La Bombonera 5',
      authorName: 'Juan P.',
      reports: reports,
      body: 'La atención fue muy mala.',
      reasons: const ['Lenguaje ofensivo', 'Información falsa'],
    );

void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(411, 1500);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> pumpScreen(WidgetTester t, Widget screen, FakeApi api) async {
  tallPhone(t);
  await t.pumpWidget(ProviderScope(
    overrides: [apiProvider.overrideWithValue(api)],
    child: MaterialApp(home: screen),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await manrope.load();
  });

  group('pagos de mensualidad', () {
    testWidgets('por revisar: Mensualidad, dueño y botones; aprobar pide confirmación', (t) async {
      final api = AdminApi(payments: [mkSub('s1'), mkSub('s2', payer: 'María López', court: 'Golazo Arena')]);
      await pumpScreen(t, const AdminPaymentsTab(), api);
      expect(find.text('ADMINISTRACIÓN'), findsOneWidget);
      expect(find.text('Pagos'), findsOneWidget);
      expect(find.text('Mensualidad'), findsNWidgets(2));
      expect(find.text('Carlos Rodríguez'), findsOneWidget);
      expect(find.textContaining(r'$100.000'), findsWidgets);
      await t.tap(find.text('Aprobar').first);
      await t.pumpAndSettle();
      expect(find.text('¿Aprobar la mensualidad?'), findsOneWidget);
      await t.tap(find.text('Aprobar').last);
      await t.pumpAndSettle();
      expect(api.calls, ['approve:s1']);
      expect(find.text('Mensualidad aprobada'), findsOneWidget);
    });

    testWidgets('rechazar con motivo', (t) async {
      final api = AdminApi(payments: [mkSub('s1')]);
      await pumpScreen(t, const AdminPaymentsTab(), api);
      await t.tap(find.text('Rechazar'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Comprobante ilegible');
      await t.tap(find.text('Rechazar').last);
      await t.pumpAndSettle();
      expect(api.calls, ['reject:s1:Comprobante ilegible']);
    });

    testWidgets('el encabezado trae la campana con el contador y el perfil', (t) async {
      await pumpScreen(t, const AdminPaymentsTab(), AdminApi());
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.text('No hay mensualidades por revisar.'), findsOneWidget);
    });
  });

  group('canchas del admin', () {
    AdminApi api0() => AdminApi(courts: [
          mkAdminCourt('c1', 'La Bombonera 5', CourtStatus.active, pending: true),
          mkAdminCourt('c2', 'Golazo Arena', CourtStatus.suspended, byAdmin: true),
          mkAdminCourt('c3', 'El Potrero', CourtStatus.pending),
        ]);

    testWidgets('muestra dueño, avisos y acciones según el estado', (t) async {
      await pumpScreen(t, const AdminCourtsTab(), api0());
      expect(find.text('Canchas'), findsOneWidget);
      expect(find.text('Dueño: Carlos Rodríguez · 3004567890'), findsNWidgets(3));
      expect(find.text('Tiene una mensualidad por revisar'), findsOneWidget);
      expect(find.text('Suspendida por el administrador'), findsOneWidget);
      expect(find.text('Suspender'), findsOneWidget);
      expect(find.text('Reactivar'), findsOneWidget);
    });

    testWidgets('suspender pide confirmación y reactivar actúa directo', (t) async {
      final api = api0();
      await pumpScreen(t, const AdminCourtsTab(), api);
      await t.tap(find.text('Suspender'));
      await t.pumpAndSettle();
      expect(find.text('¿Suspender la cancha?'), findsOneWidget);
      await t.tap(find.text('Suspender').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Reactivar'));
      await t.pumpAndSettle();
      expect(api.calls, ['suspendCourt:c1', 'reactivateCourt:c2']);
    });
  });

  group('usuarios', () {
    AdminApi api0() => AdminApi(users: [
          mkUser('u1', 'Laura Méndez', Role.player),
          mkUser('u2', 'Carlos Rodríguez', Role.owner),
          mkUser('u3', 'Andrés Pérez', Role.player, suspended: true),
          mkUser('a1', 'Admin', Role.admin),
        ]);

    testWidgets('lista con rol, estado y acciones (sin acciones para admin)', (t) async {
      await pumpScreen(t, const AdminUsersTab(), api0());
      expect(find.text('Usuarios'), findsOneWidget);
      expect(find.text('laura@correo.com · Jugador'), findsOneWidget);
      expect(find.text('carlos@correo.com · Dueño'), findsOneWidget);
      expect(find.textContaining('Suspendido'), findsOneWidget);
      expect(find.text('Eliminar'), findsNWidgets(3));
      expect(find.text('Restaurar'), findsOneWidget);
    });

    testWidgets('buscar por nombre o correo', (t) async {
      final api = api0();
      await pumpScreen(t, const AdminUsersTab(), api);
      await t.enterText(find.byType(TextField), 'carlos');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(find.text('Carlos Rodríguez'), findsOneWidget);
      expect(find.text('Laura Méndez'), findsNothing);
    });

    testWidgets('eliminar pide confirmación; suspender y restaurar actúan directo', (t) async {
      final api = api0();
      await pumpScreen(t, const AdminUsersTab(), api);
      await t.tap(find.text('Eliminar').first);
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar a Laura Méndez?'), findsOneWidget);
      await t.tap(find.text('Eliminar').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Restaurar'));
      await t.pumpAndSettle();
      expect(api.calls.where((c) => !c.startsWith('users:')), ['deleteUser:u1', 'restoreUser:u3']);
    });
  });

  group('reseñas reportadas', () {
    testWidgets('muestra el reporte con motivos; conservar y ocultar', (t) async {
      final api = AdminApi(reviews: [mkReported('r1'), mkReported('r2', stars: 1, reports: 1)]);
      await pumpScreen(t, const AdminReviewsTab(), api);
      expect(find.text('Reseñas'), findsOneWidget);
      expect(find.text('2 estrellas'), findsOneWidget);
      expect(find.text('1 estrella'), findsOneWidget);
      expect(find.text('Por Juan P. · 3 reportes'), findsOneWidget);
      expect(find.text('Por Juan P. · 1 reporte'), findsOneWidget);
      expect(find.text('Motivos: Lenguaje ofensivo, Información falsa'), findsNWidgets(2));

      await t.tap(find.text('Conservar').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Ocultar').first);
      await t.pumpAndSettle();
      expect(find.text('¿Ocultar la reseña?'), findsOneWidget);
      await t.tap(find.text('Ocultar').last);
      await t.pumpAndSettle();
      expect(api.calls, ['dismiss:r1', 'hide:r1']);
    });

    testWidgets('sin reseñas reportadas', (t) async {
      await pumpScreen(t, const AdminReviewsTab(), AdminApi());
      expect(find.text('No hay reseñas reportadas.'), findsOneWidget);
    });
  });

  group('resumen', () {
    testWidgets('métricas y transacciones aprobadas', (t) async {
      await pumpScreen(t, const AdminSummaryTab(), AdminApi());
      expect(find.text('Resumen'), findsOneWidget);
      expect(find.text('1.248'), findsOneWidget); // jugadores + dueños
      expect(find.text('84'), findsOneWidget);
      expect(find.text('3.420'), findsOneWidget);
      expect(find.text('Ingresos aprobados'), findsOneWidget);
      expect(find.text(r'$12.840.000'), findsWidgets);
      expect(find.text('Transacciones aprobadas'), findsOneWidget);
      expect(find.text('128 transacciones'), findsOneWidget);
      expect(find.textContaining('Carlos Rodríguez', findRichText: true), findsOneWidget);
      expect(find.textContaining('Mensualidad', findRichText: true), findsWidgets);
    });
  });
}
