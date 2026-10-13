import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/format.dart';
import 'package:golazo/data/mock_data.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/features/booking/booking_policy.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);

  test('reserva a menos de 8 h exige 30% y no es cancelable', () {
    final start = now.add(const Duration(hours: 5));
    expect(BookingPolicy.isLastMinute(start, now), isTrue);
    expect(BookingPolicy.canCancelFree(start, now), isFalse);
    expect(
        BookingPolicy.depositFor(
            total: 100000,
            courtRequiresDeposit: false,
            courtDepositPercent: 50,
            start: start,
            now: now),
        30000);
  });

  test('cancelación gratis con 24 h o más', () {
    expect(BookingPolicy.canCancelFree(now.add(const Duration(hours: 24)), now),
        isTrue);
    expect(BookingPolicy.canCancelFree(now.add(const Duration(hours: 12)), now),
        isFalse);
  });

  test('anticipo configurable por cancha', () {
    final start = now.add(const Duration(days: 2));
    expect(
        BookingPolicy.depositFor(
            total: 100000,
            courtRequiresDeposit: true,
            courtDepositPercent: 40,
            start: start,
            now: now),
        40000);
    expect(
        BookingPolicy.depositFor(
            total: 100000,
            courtRequiresDeposit: false,
            courtDepositPercent: 40,
            start: start,
            now: now),
        0);
  });

  group('selección de horas', () {
    test('agrega horas contiguas hasta el máximo', () {
      var sel = <int>{};
      for (final h in [10, 11, 12, 13]) {
        sel = BookingPolicy.toggleHour(sel, h);
      }
      expect(sel, {10, 11, 12, 13});
      // Una quinta hora contigua reinicia la selección.
      expect(BookingPolicy.toggleHour(sel, 14), {14});
    });

    test('hora no contigua reinicia la selección', () {
      expect(BookingPolicy.toggleHour({10, 11}, 15), {15});
    });

    test('solo se quitan horas de los extremos', () {
      expect(BookingPolicy.toggleHour({10, 11, 12}, 12), {10, 11});
      expect(BookingPolicy.toggleHour({10, 11, 12}, 11), {11});
    });
  });

  test('horas en formato 12 h con AM/PM', () {
    expect(hourLabel(0), '12:00 AM');
    expect(hourLabel(8), '8:00 AM');
    expect(hourLabel(12), '12:00 PM');
    expect(hourLabel(15), '3:00 PM');
    expect(hourLabel(23), '11:00 PM');
    expect(hourLabel(24), '12:00 AM');
  });

  group('horas ocupadas', () {
    final court = mockCourts.first;
    final day = DateTime(2026, 10, 20);
    Booking b(BookingStatus st) => Booking(
        id: 'x',
        courtId: court.id,
        start: DateTime(2026, 10, 20, 10),
        total: 1,
        deposit: 0,
        status: st,
        refundable: false,
        hours: 2);

    test('una reserva viva bloquea todas sus horas', () {
      final occ = occupiedHours(court, day, [b(BookingStatus.pendingReview)]);
      expect(occ.containsAll([10, 11]), isTrue);
    });

    test('una reserva cancelada libera las horas', () {
      expect(occupiedHours(court, day, [b(BookingStatus.cancelled)]),
          busyHours(court, day));
    });

    test('reserva de otro día no bloquea', () {
      final other = Booking(
          id: 'y',
          courtId: court.id,
          start: DateTime(2026, 10, 21, 10),
          total: 1,
          deposit: 0,
          status: BookingStatus.confirmed,
          refundable: false);
      expect(occupiedHours(court, day, [other]), busyHours(court, day));
    });
  });
}
