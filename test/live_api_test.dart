// Prueba de integración: el cliente y los modelos REALES de la app contra el backend real.
//
// Requisitos: backend arriba (docker compose up -d) y un administrador de prueba:
//   docker compose run --rm migrate node dist/scripts/create-admin.js admin@itest.co "Admin Test" "clave-admin-larga-1"
// Ejecutar:
//   flutter test test/live_api_test.dart --dart-define=GOLAZO_LIVE=true
// Crea usuarios @itest.co (los borran los scripts de backend/scripts/integration-test*.ps1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/api/api_client.dart';
import 'package:golazo/core/api/token_store.dart';
import 'package:golazo/core/format.dart';
import 'package:golazo/data/golazo_api.dart';
import 'package:golazo/data/models.dart';

const _live = bool.fromEnvironment('GOLAZO_LIVE');
const _base = String.fromEnvironment('GOLAZO_API', defaultValue: 'http://127.0.0.1:3000/v1');

class Session {
  Session() : tokens = MemoryTokenStore() {
    api = GolazoApi(ApiClient(baseUrl: _base, tokens: tokens));
  }
  final MemoryTokenStore tokens;
  late final GolazoApi api;
}

/// Comprueba que [f] falle con un ApiException del código indicado.
Future<void> expectApiError(Future<Object?> f, String code) async {
  try {
    await f;
  } on ApiException catch (e) {
    expect(e.code, code, reason: e.toString());
    return;
  }
  fail('Se esperaba un ApiException con código $code');
}

void main() {
  setUpAll(() => HttpOverrides.global = null); // flutter_test bloquea la red por defecto

  group('API real', skip: _live ? false : 'Usa --dart-define=GOLAZO_LIVE=true con el backend arriba', () {
    final tag = DateTime.now().millisecondsSinceEpoch;
    final city = 'Live$tag';
    final proof = File('test/fixtures/proof.png').readAsBytesSync();

    final owner = Session(), admin = Session(), player = Session(), player2 = Session();
    late AppUser ownerUser, playerUser;
    late Court court;
    late Booking booking;
    late String paymentId;
    // 10:00 a. m. (hora Colombia) dentro de 3 días.
    final day = coToday().add(const Duration(days: 3));
    final start = coInstant(day, 10);

    test('registro de dueño y de jugador', () async {
      ownerUser = await owner.api.register(
          name: 'Dueno Live', email: 'owner$tag@itest.co', password: 'clave-segura-1', phone: '3001112233', asOwner: true);
      expect(ownerUser.role, Role.owner);
      expect(ownerUser.emailVerified, isFalse);
      playerUser = await player.api
          .register(name: 'Pablo Live', email: 'p$tag@itest.co', password: 'clave-segura-1', phone: '3002223344');
      expect(playerUser.role, Role.player);
      await player2.api.register(name: 'Maria Live', email: 'p2$tag@itest.co', password: 'clave-segura-1', phone: '3003334455');
    });

    test('login con clave mala devuelve BAD_CREDENTIALS; el correo repetido EMAIL_TAKEN', () async {
      await expectApiError(Session().api.login('owner$tag@itest.co', 'incorrecta-123'), 'BAD_CREDENTIALS');
      await expectApiError(
          Session().api.register(name: 'Otro', email: 'owner$tag@itest.co', password: 'clave-segura-1', phone: '3001112233'),
          'EMAIL_TAKEN');
    });

    test('la sesión guardada se restaura y, con el access token vencido, se renueva sola', () async {
      final fresh = Session();
      await fresh.tokens.save(await owner.tokens.readAccess() ?? '', await owner.tokens.readRefresh() ?? '');
      expect((await fresh.api.restore())?.id, ownerUser.id);

      final expired = Session();
      await expired.tokens.save('token-vencido-o-basura', (await owner.tokens.readRefresh())!);
      final u = await expired.api.restore(); // 401 -> refresh -> reintento
      expect(u?.id, ownerUser.id);
      expect(await expired.tokens.readAccess(), isNot('token-vencido-o-basura'));
      // El refresh token rotó: lo guardamos para el resto de pruebas.
      await owner.tokens.save(await expired.tokens.readAccess() ?? '', await expired.tokens.readRefresh() ?? '');
    });

    test('dueño crea la cancha (pendiente), cuentas y foto', () async {
      court = await owner.api.createCourt({
        'name': 'Cancha Live', 'city': city, 'address': 'Cra 9 # 9-9', 'lat': 4.7, 'lng': -74.05,
        'covered': true, 'pricePerHour': 100000, 'openHour': 0, 'closeHour': 24,
        'requiresDeposit': true, 'depositPercent': 40,
      });
      expect(court.status, CourtStatus.pending);
      expect(court.depositPercent, 40);
      court = await owner.api.setPaymentMethods(
          court.id, [const PaymentMethod(label: 'Nequi', account: '300 111 2233', holder: 'Dueno Live')]);
      expect(court.paymentMethods.single.account, '300 111 2233');
      court = await owner.api.addCourtPhoto(court.id, proof, 'foto.png');
      expect(court.photos.single.id, isNotNull);
      expect(court.photos.single.url, startsWith('/v1/files/courts/'));
      expect((await owner.api.ownerCourts()).any((c) => c.id == court.id), isTrue);
    });

    test('mensualidad: dueño sube comprobante, admin lo ve (imagen real) y lo aprueba', () async {
      final cfg = await owner.api.subscriptionConfig();
      expect(cfg.price, 100000);
      expect(cfg.periodDays, 30);
      await owner.api.uploadSubscriptionProof(court.id, proof, 'pago.png');
      expect((await owner.api.ownerCourt(court.id)).subscription!.pendingReview, isTrue);

      await admin.api.login(const String.fromEnvironment('GOLAZO_ADMIN', defaultValue: 'admin@itest.co'),
          const String.fromEnvironment('GOLAZO_ADMIN_PASS', defaultValue: 'clave-admin-larga-1'));
      final pending = await admin.api.adminPayments(kind: 'subscription', status: PaymentStatus.pending);
      final mine = pending.firstWhere((p) => p.courtId == court.id);
      expect(mine.isSubscription, isTrue);
      expect(mine.amount, 100000);

      final img = await admin.api.proofImage(mine.id);
      expect(img.length, greaterThan(100));
      expect(img.sublist(0, 2), [0xFF, 0xD8], reason: 'el servidor re-codifica a JPEG');

      await admin.api.approveSubscription(mine.id);
      court = await owner.api.ownerCourt(court.id);
      expect(court.status, CourtStatus.active);
      expect(court.subscription!.activeUntil, isNotNull);
    });

    test('jugador: ciudades, listado con filtros, detalle y disponibilidad', () async {
      expect(await player.api.cities(), contains(city));
      final list = await player.api.courts(city: city);
      expect(list.single.id, court.id);
      expect(list.single.photoUrl, startsWith('/v1/files/courts/'));
      expect(await player.api.courts(city: city, covered: false), isEmpty);
      expect(await player.api.courts(city: city, maxPrice: 50000), isEmpty);
      final near = await player.api.courts(lat: 4.7, lng: -74.05, radiusKm: 5);
      expect(near.where((c) => c.id == court.id), isNotEmpty);
      expect(near.firstWhere((c) => c.id == court.id).distanceM, isNotNull);

      final detail = await player.api.court(court.id);
      expect(detail.photos.single.url, startsWith('/v1/files/courts/'));
      expect(detail.photos.single.id, isNull, reason: 'el detalle público no expone ids de fotos');

      final slots = await player.api.availability(court.id, day);
      expect(slots.length, 24);
      expect(slots.every((s) => s.free), isTrue);
    });

    test('reserva con anticipo: crea, sube comprobante, el dueño aprueba', () async {
      booking = await player.api.createBooking(court.id, start, 2);
      expect(booking.status, BookingStatus.pendingPayment);
      expect(booking.total, 200000);
      expect(booking.deposit, 80000);
      expect(booking.startAt, start);
      expect(booking.paymentMethods.single.label, 'Nequi');

      final slots = await player.api.availability(court.id, day);
      expect(slots.where((s) => s.hour == 10 || s.hour == 11).every((s) => !s.free), isTrue);
      expect(slots.firstWhere((s) => s.hour == 12).free, isTrue);

      await expectApiError(player2.api.createBooking(court.id, start.add(const Duration(hours: 1)), 1), 'SLOT_TAKEN');

      await player.api.uploadBookingProof(booking.id, proof, 'comprobante.png');
      booking = await player.api.booking(booking.id);
      expect(booking.status, BookingStatus.pendingReview);

      final pending = await owner.api.ownerPayments(status: PaymentStatus.pending);
      final p = pending.firstWhere((x) => x.bookingId == booking.id);
      paymentId = p.id;
      expect(p.payerPhone, '3002223344');
      expect(p.amount, 80000);
      expect(p.startAt, start);
      expect((await owner.api.proofImage(paymentId)).length, greaterThan(100));
      await expectApiError(player2.api.proofImage(paymentId), 'PAYMENT_NOT_FOUND');

      final ownerView = await owner.api.ownerBookings(from: day, to: day);
      final row = ownerView.firstWhere((b) => b.id == booking.id);
      expect(row.playerName, 'Pablo Live');
      expect(row.isBlock, isFalse);

      await owner.api.approvePayment(paymentId);
      booking = await player.api.booking(booking.id);
      expect(booking.status, BookingStatus.confirmed);
      expect(booking.reviewed, isFalse);
    });

    test('rechazo con motivo y nuevo comprobante', () async {
      final b = await player2.api.createBooking(court.id, coInstant(day, 15), 1);
      await player2.api.uploadBookingProof(b.id, proof, 'a.png');
      final p = (await owner.api.ownerPayments(status: PaymentStatus.pending)).firstWhere((x) => x.bookingId == b.id);
      await owner.api.rejectPayment(p.id, reason: 'Monto incorrecto');
      final after = await player2.api.booking(b.id);
      expect(after.status, BookingStatus.rejected);
      expect(after.needsPayment, isTrue);
      expect(after.paymentMethods, isNotEmpty);
      final history = await owner.api.ownerPayments();
      expect(history.firstWhere((x) => x.id == p.id).rejectReason, 'Monto incorrecto');
      await player2.api.cancelBooking(b.id); // libera la hora
    });

    test('notificaciones llegan y se marcan como leídas', () async {
      final ownerPage = await owner.api.notifications();
      expect(ownerPage.items.any((n) => n.title == 'Nuevo comprobante de pago'), isTrue);
      final playerPage = await player.api.notifications();
      final approved = playerPage.items.firstWhere((n) => n.title == 'Pago aprobado');
      expect(approved.data['type'], 'booking_confirmed');
      expect(playerPage.unread, greaterThan(0));
      await player.api.markNotificationRead(approved.id);
      await player.api.markAllNotificationsRead();
      expect((await player.api.notifications()).unread, 0);
      await player.api.registerDevice('android', 't' * 40);
      await player.api.removeDevice('android', 't' * 40);
    });

    test('dueño: bloquear y desbloquear horas, estadísticas, pausar y reanudar', () async {
      await owner.api.blockHours(court.id, coInstant(day.add(const Duration(days: 1)), 9), 2, note: 'WhatsApp');
      final next = day.add(const Duration(days: 1));
      final rows = await owner.api.ownerBookings(from: next, to: next);
      final block = rows.firstWhere((b) => b.isBlock);
      expect(block.note, 'WhatsApp');
      expect(block.playerName, isNull);
      await expectApiError(player.api.createBooking(court.id, coInstant(next, 9), 1), 'SLOT_TAKEN');
      await owner.api.unblockHours(block.id);
      expect((await owner.api.ownerBookings(from: next, to: next)).where((b) => b.isBlock), isEmpty);

      final stats = await owner.api.ownerStats(from: coToday(), to: day.add(const Duration(days: 5)));
      expect(stats.confirmed, 1);
      expect(stats.income, 200000);
      expect(stats.bookedHours, 2);

      expect((await owner.api.pauseCourt(court.id)).status, CourtStatus.suspended);
      expect(await player.api.courts(city: city), isEmpty);
      expect((await owner.api.resumeCourt(court.id)).status, CourtStatus.active);
    });

    test('jugador: cancelar una reserva confirmada con más de 24 h', () async {
      final b = await player.api.createBooking(court.id, coInstant(day.add(const Duration(days: 2)), 18), 1);
      expect(b.status, BookingStatus.pendingPayment); // la cancha exige anticipo
      expect(b.cancellable, isTrue);
      final c = await player.api.cancelBooking(b.id);
      expect(c.status, BookingStatus.cancelled);
      final mine = await player.api.myBookings();
      expect(mine.any((x) => x.id == booking.id), isTrue);
    });

    test('reseñas: no se puede calificar una reserva futura', () async {
      await expectApiError(player.api.reviewBooking(booking.id, 5, 'Muy buena'), 'NOT_PLAYED');
      expect(await player.api.reviews(court.id), isEmpty);
    });

    test('admin: usuarios, canchas, métricas, transacciones y reseñas reportadas', () async {
      final users = await admin.api.adminUsers(search: 'Pablo Live');
      expect(users.single.role, Role.player);
      expect(users.single.phone, '3002223344');

      final courts = await admin.api.adminCourts(search: city);
      final c = courts.single;
      expect(c.status, CourtStatus.active);
      expect(c.ownerName, 'Dueno Live');
      expect(c.activeUntil, isNotNull);
      expect(c.pendingSubscription, isFalse);

      final m = await admin.api.metrics();
      expect(m.activeCourts, greaterThanOrEqualTo(1));
      expect(m.players, greaterThanOrEqualTo(2));
      expect(m.subscriptionsTotal, greaterThanOrEqualTo(100000));

      final tx = await admin.api.transactions();
      expect(tx.count, greaterThanOrEqualTo(2));
      expect(tx.items.any((i) => i.kind == 'subscription' && i.courtName == 'Cancha Live'), isTrue);
      expect(tx.items.any((i) => i.kind == 'booking'), isTrue);

      expect(await admin.api.reportedReviews(), isA<List<ReportedReview>>());

      await admin.api.suspendUser(playerUser.id);
      await expectApiError(Session().api.login('p$tag@itest.co', 'clave-segura-1'), 'SUSPENDED');
      await admin.api.restoreUser(playerUser.id);
    });

    test('perfil, contraseña y cierre de sesión', () async {
      final u = await player.api.updateProfile(name: 'Pablo Perez', phone: '3109998877');
      expect((u.name, u.phone), ('Pablo Perez', '3109998877'));
      await expectApiError(player.api.changePassword('mala-clave-123', 'nueva-clave-segura-1'), 'BAD_CREDENTIALS');
      await player.api.forgotPassword('nadie@itest.co'); // responde igual aunque no exista
      await player.api.logout();
      expect(await player.tokens.readAccess(), isNull);
      expect(await player.api.restore(), isNull);
    });
  });
}
