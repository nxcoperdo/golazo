import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/token_store.dart';
import '../core/config.dart';
import '../core/format.dart';
import '../core/push.dart';
import 'golazo_api.dart';
import 'models.dart';

// ---------------- Infraestructura ----------------

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      baseUrl: AppConfig.apiBase,
      tokens: ref.watch(tokenStoreProvider),
      // Si la sesión no se puede renovar, se vuelve al login.
      onSessionExpired: () => ref.read(sessionProvider.notifier).expired(),
    ));

final apiProvider = Provider<GolazoApi>((ref) => GolazoApi(ref.watch(apiClientProvider)));

// ---------------- Sesión ----------------

/// Usuario con sesión iniciada (null = sin sesión). Mientras carga o si no hay
/// conexión al abrir la app, queda en AsyncLoading/AsyncError.
final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, AppUser?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<AppUser?> {
  GolazoApi get _api => ref.read(apiProvider);

  @override
  Future<AppUser?> build() => _api.restore();

  Future<void> login(String email, String password) async =>
      state = AsyncData(await _api.login(email.trim(), password));

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    required bool asOwner,
  }) async =>
      state = AsyncData(await _api.register(
        name: name.trim(),
        email: email.trim(),
        password: password,
        phone: phone.trim(),
        asOwner: asOwner,
      ));

  Future<void> loginWithGoogle(String idToken, {String? phone}) async =>
      state = AsyncData(await _api.loginWithGoogle(idToken, phone: phone));

  Future<void> logout() async {
    await ref.read(pushProvider).stop();
    await _api.logout();
    state = const AsyncData(null);
  }

  /// El refresh token venció o la cuenta fue suspendida.
  void expired() => state = const AsyncData(null);

  /// Reintenta cargar la sesión (p. ej. tras volver la conexión).
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_api.restore);
  }

  /// Guarda la aceptación de los textos legales y refresca al usuario.
  Future<void> acceptTerms() async {
    await _api.acceptTerms();
    await reload();
  }

  /// Vuelve a pedir los datos del usuario (celular, verificación de correo…).
  Future<void> reload() async {
    final u = await _api.restore();
    state = AsyncData(u);
  }

  void setUser(AppUser u) => state = AsyncData(u);

  Future<void> deleteAccount({String? password}) async {
    await _api.deleteAccount(password: password);
    state = const AsyncData(null);
  }
}

/// Id del usuario actual. Los datos por usuario lo observan para recargarse al cambiar de cuenta.
final userIdProvider = Provider<String?>((ref) => ref.watch(sessionProvider).value?.id);

// ---------------- Jugador ----------------

class CourtFilters {
  const CourtFilters({this.city, this.maxPrice, this.covered, this.courtType, this.lat, this.lng});
  final String? city;
  final int? maxPrice;
  final bool? covered;
  final int? courtType;
  final double? lat;
  final double? lng;

  bool get hasLocation => lat != null && lng != null;

  CourtFilters copyWith({
    String? city,
    bool clearCity = false,
    int? maxPrice,
    bool clearPrice = false,
    bool? covered,
    bool clearCovered = false,
    int? courtType,
    bool clearCourtType = false,
    double? lat,
    double? lng,
    bool clearLocation = false,
  }) =>
      CourtFilters(
        city: clearCity ? null : (city ?? this.city),
        maxPrice: clearPrice ? null : (maxPrice ?? this.maxPrice),
        covered: clearCovered ? null : (covered ?? this.covered),
        courtType: clearCourtType ? null : (courtType ?? this.courtType),
        lat: clearLocation ? null : (lat ?? this.lat),
        lng: clearLocation ? null : (lng ?? this.lng),
      );
}

final courtFiltersProvider =
    NotifierProvider<CourtFiltersNotifier, CourtFilters>(CourtFiltersNotifier.new);

class CourtFiltersNotifier extends Notifier<CourtFilters> {
  @override
  CourtFilters build() => const CourtFilters();
  void set(CourtFilters f) => state = f;
}

final citiesProvider = FutureProvider.autoDispose<List<String>>((ref) => ref.watch(apiProvider).cities());

final courtsProvider = FutureProvider.autoDispose<List<Court>>((ref) {
  final f = ref.watch(courtFiltersProvider);
  return ref.watch(apiProvider).courts(
        city: f.city,
        maxPrice: f.maxPrice,
        covered: f.covered,
        courtType: f.courtType,
        lat: f.lat,
        lng: f.lng,
      );
});

final courtDetailProvider = FutureProvider.autoDispose.family<Court, String>(
    (ref, id) => ref.watch(apiProvider).court(id));

/// Clave: cancha + día de Colombia (fecha UTC medianoche).
typedef AvailabilityKey = ({String courtId, DateTime day});

final availabilityProvider = FutureProvider.autoDispose.family<List<HourSlot>, AvailabilityKey>(
    (ref, k) => ref.watch(apiProvider).availability(k.courtId, k.day));

final courtReviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>(
    (ref, id) => ref.watch(apiProvider).reviews(id));

final myBookingsProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).myBookings();
});

final bookingProvider = FutureProvider.autoDispose.family<Booking, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).booking(id);
});

final notificationsProvider = FutureProvider.autoDispose<NotificationsPage>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).notifications();
});

// ---------------- Dueño ----------------

final ownerCourtsProvider = FutureProvider.autoDispose<List<Court>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).ownerCourts();
});

final ownerCourtProvider = FutureProvider.autoDispose.family<Court, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).ownerCourt(id);
});

/// null = todos los estados.
final ownerPaymentsProvider =
    FutureProvider.autoDispose.family<List<Payment>, PaymentStatus?>((ref, status) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).ownerPayments(status: status);
});

typedef DateRange = ({DateTime from, DateTime to});

/// Reservas de las canchas del dueño en los próximos [days] días (desde hoy).
final ownerBookingsProvider = FutureProvider.autoDispose.family<List<OwnerBooking>, int>((ref, days) {
  ref.watch(userIdProvider);
  final today = coToday();
  return ref.watch(apiProvider).ownerBookings(from: today, to: today.add(Duration(days: days - 1)));
});

/// Estadísticas de los últimos [days] días.
final ownerStatsProvider = FutureProvider.autoDispose.family<OwnerStats, int>((ref, days) {
  ref.watch(userIdProvider);
  final today = coToday();
  return ref.watch(apiProvider).ownerStats(from: today.subtract(Duration(days: days - 1)), to: today);
});

final proofImageProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, paymentId) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).proofImage(paymentId);
});

// ---------------- Administrador ----------------

final adminPaymentsProvider = FutureProvider.autoDispose.family<List<Payment>, PaymentStatus?>((ref, status) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).adminPayments(kind: 'subscription', status: status);
});

final adminUsersProvider = FutureProvider.autoDispose.family<List<AdminUser>, String>((ref, search) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).adminUsers(search: search);
});

final adminCourtsProvider = FutureProvider.autoDispose<List<AdminCourt>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).adminCourts();
});

final reportedReviewsProvider = FutureProvider.autoDispose<List<ReportedReview>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).reportedReviews();
});

final transactionsProvider = FutureProvider.autoDispose<Transactions>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).transactions();
});

final metricsProvider = FutureProvider.autoDispose<Metrics>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(apiProvider).metrics();
});

/// Mensaje legible para mostrar al usuario a partir de cualquier error.
String errorMessage(Object e) {
  if (e is ApiException) return e.message;
  return 'Algo salió mal. Inténtalo de nuevo.';
}
