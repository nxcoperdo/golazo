import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'models.dart';

const _img = 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=800';

const mockCourts = <Court>[
  Court(id: 'c1', name: 'La Bombonera Sintética', city: 'Bogotá', photoUrl: _img, pricePerHour: 90000, covered: true, requiresDeposit: true, rating: 4.8, paymentMethods: [PaymentMethod(label: 'Nequi', account: '300 123 4567', holder: 'Carlos Ramírez'), PaymentMethod(label: 'Bancolombia Ahorros', account: '123-456789-01', holder: 'Carlos Ramírez')]),
  Court(id: 'c2', name: 'Golazo Arena', city: 'Bogotá', photoUrl: _img, pricePerHour: 70000, covered: false, requiresDeposit: false, rating: 4.4, paymentMethods: [PaymentMethod(label: 'Nequi', account: '320 555 0000', holder: 'Marta Díaz')]),
  Court(id: 'c3', name: 'Canchas El Potrero', city: 'Medellín', photoUrl: _img, pricePerHour: 80000, covered: false, requiresDeposit: true, rating: 4.6, paymentMethods: [PaymentMethod(label: 'Daviplata', account: '311 765 4321', holder: 'Luis Gómez')]),
  Court(id: 'c4', name: 'Fútbol 5 Premium', city: 'Cali', photoUrl: _img, pricePerHour: 100000, covered: true, requiresDeposit: false, rating: 4.9, paymentMethods: [PaymentMethod(label: 'Nequi', account: '310 222 3344', holder: 'Pedro Sánchez')]),
  Court(id: 'c5', name: 'Cancha Nueva (pendiente)', city: 'Bogotá', photoUrl: _img, pricePerHour: 60000, covered: false, requiresDeposit: false, status: CourtStatus.pending),
];

class CourtFilters {
  const CourtFilters({this.city, this.maxPrice, this.covered});
  final String? city;
  final int? maxPrice;
  final bool? covered;
}

final courtsProvider = StateProvider<List<Court>>((_) => mockCourts);

/// Cancha que administra el dueño en el mock.
const ownerCourtId = 'c1';

final filtersProvider = StateProvider<CourtFilters>((_) => const CourtFilters());

/// Solo canchas activas son visibles para jugadores.
final visibleCourtsProvider = Provider<List<Court>>((ref) {
  final f = ref.watch(filtersProvider);
  return ref.watch(courtsProvider).where((c) {
    if (c.status != CourtStatus.active) return false;
    if (f.city != null && c.city != f.city) return false;
    if (f.maxPrice != null && c.pricePerHour > f.maxPrice!) return false;
    if (f.covered != null && c.covered != f.covered) return false;
    return true;
  }).toList();
});

/// Cuentas de Golazo donde los dueños pagan la mensualidad.
const platformPaymentMethods = [
  PaymentMethod(label: 'Nequi', account: '300 000 0000', holder: 'Golazo S.A.S.'),
];

/// Estados que mantienen ocupada una hora. "Rechazado" también: el jugador
/// puede volver a subir el comprobante, así que la hora no se libera hasta
/// que cancele.
bool holdsSlot(BookingStatus s) => s != BookingStatus.cancelled;

/// Horas ocupadas: las simuladas del mock más las de reservas vivas.
Set<int> occupiedHours(Court c, DateTime day, List<Booking> bookings) => {
      ...busyHours(c, day),
      for (final b in bookings)
        if (b.courtId == c.id &&
            holdsSlot(b.status) &&
            DateUtils.isSameDay(b.start, day))
          for (var i = 0; i < b.hours; i++) b.start.hour + i,
    };

/// Horas ocupadas simuladas (determinista por cancha y día).
Set<int> busyHours(Court c, DateTime day) {
  final seed = c.id.hashCode ^ day.day;
  return {for (var h = c.openHour; h < c.closeHour; h++) if ((h * 7 + seed) % 4 == 0) h};
}

/// Incluye una reserva ya jugada para poder probar las reseñas.
final bookingsProvider = StateProvider<List<Booking>>((_) => [
      Booking(
        id: 'b0',
        courtId: 'c2',
        start: DateTime.now().subtract(const Duration(days: 1)),
        total: 70000,
        deposit: 0,
        status: BookingStatus.confirmed,
        refundable: false,
      ),
    ]);

const _r1 = Review(id: 'r1', courtId: 'c2', author: 'Andrés Gómez', stars: 1, text: 'Texto reportado por lenguaje ofensivo.');
const _r2 = Review(id: 'r2', courtId: 'c1', author: 'Camila Rojas', stars: 2, text: 'Reseña reportada por el dueño como falsa.');

final reviewsProvider = StateProvider<List<Review>>((_) => const [
      _r1,
      _r2,
      Review(id: 'r3', courtId: 'c1', author: 'Juan Pérez', stars: 5, text: 'Excelente cancha, el césped está perfecto.'),
    ]);

final notificationsProvider = StateProvider<List<String>>((_) => const []);

/// Coordenadas de referencia para asignar la ciudad más cercana.
const cityCoords = {
  'Bogotá': (4.711, -74.072),
  'Medellín': (6.244, -75.581),
  'Cali': (3.452, -76.532),
};

final subscriptionsProvider = StateProvider<List<Subscription>>((_) => const [
      Subscription(id: 's1', courtId: 'c5'),
    ]);

final usersProvider = StateProvider<List<AppUser>>((_) => const [
      AppUser(id: 'u1', name: 'Juan Pérez', email: 'juan@correo.com'),
      AppUser(id: 'u2', name: 'Camila Rojas', email: 'camila@correo.com'),
      AppUser(id: 'u3', name: 'Andrés Gómez', email: 'andres@correo.com'),
    ]);

final reportedReviewsProvider = StateProvider<List<Review>>((_) => const [_r1, _r2]);
