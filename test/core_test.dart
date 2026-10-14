import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/format.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/features/booking/booking_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 13, 17); // 12:00 p. m. en Colombia

  group('BookingPolicy', () {
    test('reserva a menos de 8 h exige 30% y no es cancelable', () {
      final start = now.add(const Duration(hours: 5));
      expect(BookingPolicy.isLastMinute(start, now), isTrue);
      expect(BookingPolicy.canCancelFree(start, now), isFalse);
      expect(
          BookingPolicy.depositFor(
              total: 100000, courtRequiresDeposit: false, courtDepositPercent: 50, start: start, now: now),
          30000);
    });

    test('cancelación gratis con 24 h o más', () {
      expect(BookingPolicy.canCancelFree(now.add(const Duration(hours: 24)), now), isTrue);
      expect(BookingPolicy.canCancelFree(now.add(const Duration(hours: 12)), now), isFalse);
    });

    test('anticipo configurable por cancha', () {
      final start = now.add(const Duration(days: 2));
      expect(
          BookingPolicy.depositFor(
              total: 100000, courtRequiresDeposit: true, courtDepositPercent: 40, start: start, now: now),
          40000);
      expect(
          BookingPolicy.depositFor(
              total: 100000, courtRequiresDeposit: false, courtDepositPercent: 40, start: start, now: now),
          0);
    });

    group('selección de horas', () {
      test('agrega horas contiguas hasta el máximo', () {
        var sel = <int>{};
        for (final h in [10, 11, 12, 13]) {
          sel = BookingPolicy.toggleHour(sel, h);
        }
        expect(sel, {10, 11, 12, 13});
        expect(BookingPolicy.toggleHour(sel, 14), {14}); // la quinta reinicia
      });

      test('hora no contigua reinicia la selección', () {
        expect(BookingPolicy.toggleHour({10, 11}, 15), {15});
      });

      test('solo se quitan horas de los extremos', () {
        expect(BookingPolicy.toggleHour({10, 11, 12}, 12), {10, 11});
        expect(BookingPolicy.toggleHour({10, 11, 12}, 11), {11});
      });
    });
  });

  group('formato', () {
    test('horas en formato 12 h con AM/PM', () {
      expect(hourLabel(0), '12:00 AM');
      expect(hourLabel(8), '8:00 AM');
      expect(hourLabel(12), '12:00 PM');
      expect(hourLabel(15), '3:00 PM');
      expect(hourLabel(23), '11:00 PM');
      expect(hourLabel(24), '12:00 AM');
    });

    test('pesos colombianos', () {
      expect(cop(90000), r'$90.000');
      expect(cop(1250000), r'$1.250.000');
      expect(cop(0), r'$0');
      expect(cop(999), r'$999');
    });
  });

  group('hora de Colombia (independiente de la zona del teléfono)', () {
    test('03:00 UTC todavía es la noche anterior en Colombia', () {
      final w = coWall(DateTime.utc(2026, 10, 14, 3));
      expect((w.year, w.month, w.day, w.hour), (2026, 10, 13, 22));
    });

    test('las 10:00 a. m. de Colombia son las 15:00 UTC', () {
      final i = coInstant(DateTime.utc(2026, 10, 14), 10);
      expect(i, DateTime.utc(2026, 10, 14, 15));
    });

    test('ida y vuelta: coInstant -> coWall conserva la hora', () {
      for (final h in [0, 5, 12, 23]) {
        expect(coWall(coInstant(DateTime.utc(2026, 10, 14), h)).hour, h);
      }
    });

    test('hoy en Colombia a las 02:00 UTC sigue siendo el día anterior', () {
      expect(coToday(DateTime.utc(2026, 10, 14, 2)), DateTime.utc(2026, 10, 13));
      expect(coToday(DateTime.utc(2026, 10, 14, 6)), DateTime.utc(2026, 10, 14));
    });

    test('etiquetas de fecha y hora', () {
      final start = DateTime.utc(2026, 10, 14, 20); // 3:00 PM Colombia, miércoles
      expect(dayLabel(start), 'mié 14 oct');
      expect(timeLabel(start), '3:00 PM');
      expect(rangeLabel(start, 2), 'mié 14 oct · 3:00 PM – 5:00 PM');
    });

    test('fecha para la API', () {
      expect(dateParam(DateTime.utc(2026, 3, 5)), '2026-03-05');
    });
  });

  group('modelos (formato real de la API)', () {
    test('Court de la lista pública', () {
      final c = Court.fromJson({
        'id': 'c1', 'name': 'La Bombonera', 'description': null, 'city': 'Bogotá', 'address': 'Cra 9',
        'covered': true, 'pricePerHour': 90000, 'openHour': 8, 'closeHour': 23,
        'requiresDeposit': true, 'depositPercent': 40, 'status': 'active', 'lat': 4.7, 'lng': -74.05,
        'photoUrl': '/v1/files/courts/x.jpg', 'rating': 4.5, 'reviewCount': 3, 'distanceM': 1250.5,
      });
      expect(c.status, CourtStatus.active);
      expect(c.distanceM, 1250.5);
      expect(c.photos, isEmpty);
    });

    test('Court del dueño con fotos {id,url} y vigencia', () {
      final c = Court.fromJson({
        'id': 'c1', 'name': 'X', 'city': 'Cali', 'address': 'Av 1', 'covered': false,
        'pricePerHour': 50000, 'openHour': 0, 'closeHour': 24, 'requiresDeposit': false,
        'depositPercent': 30, 'status': 'pending', 'lat': 3.4, 'lng': -76.5, 'rating': 0, 'reviewCount': 0,
        'photos': [{'id': 'p1', 'url': '/v1/files/courts/a.jpg'}],
        'paymentMethods': [{'label': 'Nequi', 'account': '300', 'holder': 'Ana'}],
        'subscription': {'activeUntil': '2026-11-12', 'pendingReview': true},
      });
      expect(c.photos.single.id, 'p1');
      expect(c.paymentMethods.single.label, 'Nequi');
      expect(c.subscription!.pendingReview, isTrue);
    });

    test('Court público con fotos como lista de URLs', () {
      final c = Court.fromJson({
        'id': 'c1', 'name': 'X', 'city': 'Cali', 'address': 'Av 1', 'covered': false,
        'pricePerHour': 50000, 'openHour': 0, 'closeHour': 24, 'requiresDeposit': false,
        'depositPercent': 30, 'status': 'active', 'lat': 3.4, 'lng': -76.5,
        'photos': ['/v1/files/courts/a.jpg', '/v1/files/courts/b.jpg'],
      });
      expect(c.photos.map((p) => p.url), ['/v1/files/courts/a.jpg', '/v1/files/courts/b.jpg']);
      expect(c.photos.first.id, isNull);
    });

    test('Booking con estados en snake_case', () {
      Booking b(String status) => Booking.fromJson({
            'id': 'b', 'courtId': 'c', 'courtName': 'X', 'startAt': '2026-10-14T20:00:00.000Z',
            'hours': 2, 'total': 180000, 'deposit': 72000, 'lastMinute': false, 'status': status,
            'cancellable': true, 'reviewed': false,
            'paymentMethods': [{'label': 'Nequi', 'account': '3', 'holder': 'A'}],
          });
      expect(b('pending_payment').status, BookingStatus.pendingPayment);
      expect(b('pending_review').status, BookingStatus.pendingReview);
      expect(b('confirmed').status, BookingStatus.confirmed);
      expect(b('rejected').needsPayment, isTrue);
      expect(b('cancelled').status, BookingStatus.cancelled);
      expect(b('pending_payment').amountDue, 72000);
      expect(b('pending_payment').endAt, DateTime.utc(2026, 10, 14, 22));
    });

    test('Booking sin anticipo debe el total', () {
      final b = Booking.fromJson({
        'id': 'b', 'courtId': 'c', 'courtName': 'X', 'startAt': '2026-10-14T20:00:00.000Z',
        'hours': 1, 'total': 70000, 'deposit': 0, 'lastMinute': false, 'status': 'confirmed',
        'cancellable': false,
      });
      expect(b.amountDue, 70000);
      expect(b.paymentMethods, isEmpty);
    });

    test('Notificación sin leer y con datos', () {
      final n = AppNotification.fromJson({
        'id': 'n', 'title': 'Pago aprobado', 'body': 'ok', 'createdAt': '2026-10-14T20:00:00.000Z',
        'readAt': null, 'data': {'type': 'booking_confirmed'},
      });
      expect(n.unread, isTrue);
      expect(n.data['type'], 'booking_confirmed');
    });

    test('Métricas con grupos que faltan valen 0', () {
      const m = Metrics({'users': {'player': 4}, 'courts': {}});
      expect(m.players, 4);
      expect(m.owners, 0);
      expect(m.activeCourts, 0);
      expect(m.pendingSubscriptionPayments, 0);
    });

    test('AppUser sin celular', () {
      final u = AppUser.fromJson({'id': 'u', 'name': 'A', 'email': 'a@b.co', 'phone': null, 'role': 'player'});
      expect(u.hasPhone, isFalse);
      expect(u.emailVerified, isFalse);
    });
  });
}
