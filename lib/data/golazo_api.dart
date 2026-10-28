import 'dart:typed_data';

import '../core/api/api_client.dart';
import '../core/format.dart';
import 'models.dart';

/// Todas las llamadas al backend, devolviendo modelos ya tipados.
/// Los errores salen como [ApiException].
class GolazoApi {
  GolazoApi(this._c);
  final ApiClient _c;

  static List<Map<String, dynamic>> _rows(dynamic d) =>
      ((d as List?) ?? const []).cast<Map<String, dynamic>>();
  static Map<String, dynamic> _map(dynamic d) => (d as Map).cast<String, dynamic>();

  // ---------------- Cuenta ----------------

  Future<AppUser> _session(dynamic data) async {
    final m = _map(data);
    await _c.tokens.save(m['accessToken'] as String, m['refreshToken'] as String);
    return AppUser.fromJson(_map(m['user']));
  }

  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    bool asOwner = false,
  }) async =>
      _session(await _c.post('/auth/register', body: {
        'name': name,
        'email': email,
        'password': password,
        'phone': phone,
        if (asOwner) 'asOwner': true,
        // La casilla de la pantalla es obligatoria: sin ella no se llama a esta función.
        'acceptTerms': true,
      }));

  /// Registra que el usuario aceptó los términos y la política de datos vigentes.
  Future<void> acceptTerms() async => _c.post('/auth/consent', body: {'accept': true});

  Future<AppUser> login(String email, String password) async =>
      _session(await _c.post('/auth/login', body: {'email': email, 'password': password}));

  Future<AppUser> loginWithGoogle(String idToken, {String? phone}) async =>
      _session(await _c.post('/auth/google', body: {
        'idToken': idToken,
        'phone': ?phone,
      }));

  Future<void> logout() async {
    final refresh = await _c.tokens.readRefresh();
    try {
      if (refresh != null) await _c.post('/auth/logout', body: {'refreshToken': refresh});
    } on ApiException {
      // Si no hay conexión igual se cierra la sesión local.
    }
    await _c.tokens.clear();
  }

  /// Usuario de la sesión guardada, o null si no hay sesión válida.
  Future<AppUser?> restore() async {
    if (await _c.tokens.readAccess() == null) return null;
    try {
      return AppUser.fromJson(_map(await _c.get('/auth/me')));
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _c.tokens.clear();
        return null;
      }
      rethrow; // sin conexión: la sesión sigue, se puede reintentar
    }
  }

  Future<AppUser> updateProfile({String? name, String? phone}) async => AppUser.fromJson(
      _map(await _c.patch('/auth/me', body: {
        'name': ?name,
        'phone': ?phone,
      })));

  Future<void> changePassword(String current, String next) async =>
      _session(await _c.post('/auth/change-password', body: {'current': current, 'next': next}));

  Future<void> forgotPassword(String email) =>
      _c.post('/auth/forgot-password', body: {'email': email});

  Future<void> resetPassword(String token, String next) =>
      _c.post('/auth/reset-password', body: {'token': token, 'next': next});

  Future<void> verifyEmail(String token) => _c.post('/auth/verify-email', body: {'token': token});

  Future<void> resendVerification() => _c.post('/auth/resend-verification');

  Future<void> deleteAccount({String? password}) async {
    await _c.delete('/auth/me', body: {'password': ?password});
    await _c.tokens.clear();
  }

  // ---------------- Canchas (público) ----------------

  Future<List<String>> cities() async =>
      _rows(await _c.get('/cities')).map((r) => r['city'] as String).toList();

  Future<List<Court>> courts({
    String? city,
    int? maxPrice,
    bool? covered,
    int? courtType,
    double? lat,
    double? lng,
    double? radiusKm,
    int limit = 50,
    int offset = 0,
  }) async =>
      _rows(await _c.get('/courts', query: {
        'city': ?city,
        'maxPrice': ?maxPrice,
        'covered': ?covered,
        'courtType': ?courtType,
        if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
        'radiusKm': ?radiusKm,
        'limit': limit,
        'offset': offset,
      })).map(Court.fromJson).toList();

  Future<Court> court(String id) async => Court.fromJson(_map(await _c.get('/courts/$id')));

  /// Horas del día [coDay] (fecha de Colombia) de la cancha.
  Future<List<HourSlot>> availability(String courtId, DateTime coDay, {int? courtType}) async {
    final m = _map(await _c.get('/courts/$courtId/availability',
        query: {'date': dateParam(coDay), 'courtType': ?courtType}));
    return _rows(m['hours']).map((h) => HourSlot(h['hour'] as int, h['free'] as bool)).toList();
  }

  Future<List<Review>> reviews(String courtId) async =>
      _rows(await _c.get('/courts/$courtId/reviews')).map(Review.fromJson).toList();

  // ---------------- Reservas del jugador ----------------

  Future<Booking> createBooking(String courtId, DateTime startAt, int hours, {int? courtType}) async =>
      Booking.fromJson(_map(await _c.post('/bookings', body: {
        'courtId': courtId,
        'startAt': startAt.toUtc().toIso8601String(),
        'hours': hours,
        'courtType': ?courtType,
      })));

  Future<List<Booking>> myBookings() async =>
      _rows(await _c.get('/bookings/mine')).map(Booking.fromJson).toList();

  Future<Booking> booking(String id) async => Booking.fromJson(_map(await _c.get('/bookings/$id')));

  Future<Booking> cancelBooking(String id) async =>
      Booking.fromJson(_map(await _c.post('/bookings/$id/cancel')));

  Future<void> uploadBookingProof(String bookingId, Uint8List bytes, String filename) =>
      _c.upload('/bookings/$bookingId/payment', field: 'proof', bytes: bytes, filename: filename);

  Future<void> reviewBooking(String bookingId, int stars, String? body) =>
      _c.post('/bookings/$bookingId/review', body: {
        'stars': stars,
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      });

  Future<void> reportReview(String reviewId, {String? reason}) =>
      _c.post('/reviews/$reviewId/report', body: {'reason': ?reason});

  // ---------------- Notificaciones ----------------

  Future<NotificationsPage> notifications({int limit = 50}) async {
    final m = _map(await _c.get('/notifications', query: {'limit': limit}));
    return NotificationsPage(
      unread: m['unread'] as int,
      items: _rows(m['items']).map(AppNotification.fromJson).toList(),
    );
  }

  Future<void> markNotificationRead(String id) => _c.post('/notifications/$id/read');
  Future<void> markAllNotificationsRead() => _c.post('/notifications/read-all');
  Future<void> registerDevice(String platform, String token) =>
      _c.post('/devices', body: {'platform': platform, 'token': token});
  Future<void> removeDevice(String platform, String token) =>
      _c.delete('/devices', body: {'platform': platform, 'token': token});

  // ---------------- Dueño ----------------

  Future<List<Court>> ownerCourts() async =>
      _rows(await _c.get('/owner/courts')).map(Court.fromJson).toList();

  Future<Court> ownerCourt(String id) async =>
      Court.fromJson(_map(await _c.get('/owner/courts/$id')));

  Future<Court> createCourt(Map<String, dynamic> data) async =>
      Court.fromJson(_map(await _c.post('/owner/courts', body: data)));

  Future<Court> updateCourt(String id, Map<String, dynamic> data) async =>
      Court.fromJson(_map(await _c.patch('/owner/courts/$id', body: data)));

  Future<Court> setPaymentMethods(String courtId, List<PaymentMethod> methods) async =>
      Court.fromJson(_map(await _c.put('/owner/courts/$courtId/payment-methods',
          body: {'methods': methods.map((m) => m.toJson()).toList()})));

  Future<Court> addCourtPhoto(String courtId, Uint8List bytes, String filename) async =>
      Court.fromJson(_map(await _c.upload('/owner/courts/$courtId/photos',
          field: 'photo', bytes: bytes, filename: filename)));

  Future<Court> removeCourtPhoto(String courtId, String photoId) async =>
      Court.fromJson(_map(await _c.delete('/owner/courts/$courtId/photos/$photoId')));

  Future<Court> pauseCourt(String id) async =>
      Court.fromJson(_map(await _c.post('/owner/courts/$id/pause')));

  Future<Court> resumeCourt(String id) async =>
      Court.fromJson(_map(await _c.post('/owner/courts/$id/resume')));

  Future<List<Payment>> ownerPayments({PaymentStatus? status}) async =>
      _rows(await _c.get('/owner/payments', query: {if (status != null) 'status': status.name}))
          .map(Payment.fromJson)
          .toList();

  /// Devoluciones de anticipos de las canchas del dueño (pendientes primero).
  Future<List<Refund>> ownerRefunds() async =>
      _rows(await _c.get('/owner/refunds')).map(Refund.fromJson).toList();

  Future<void> markRefundDone(String id, {String? note}) =>
      _c.post('/owner/refunds/$id/done', body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()});

  Future<void> approvePayment(String id) => _c.post('/owner/payments/$id/approve');
  Future<void> rejectPayment(String id, {String? reason}) =>
      _c.post('/owner/payments/$id/reject', body: {if (reason != null && reason.isNotEmpty) 'reason': reason});

  Future<SubscriptionConfig> subscriptionConfig() async =>
      SubscriptionConfig.fromJson(_map(await _c.get('/config/subscription')));

  Future<void> uploadSubscriptionProof(String courtId, Uint8List bytes, String filename) =>
      _c.upload('/owner/courts/$courtId/subscription-payment',
          field: 'proof', bytes: bytes, filename: filename);

  Future<List<OwnerBooking>> ownerBookings({
    DateTime? from,
    DateTime? to,
    String? courtId,
  }) async =>
      _rows(await _c.get('/owner/bookings', query: {
        if (from != null) 'from': dateParam(from),
        if (to != null) 'to': dateParam(to),
        'courtId': ?courtId,
      })).map(OwnerBooking.fromJson).toList();

  Future<void> blockHours(String courtId, DateTime startAt, int hours, {String? note}) =>
      _c.post('/owner/courts/$courtId/blocks', body: {
        'startAt': startAt.toUtc().toIso8601String(),
        'hours': hours,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<void> unblockHours(String blockId) => _c.delete('/owner/blocks/$blockId');

  Future<OwnerStats> ownerStats({DateTime? from, DateTime? to, String? courtId}) async =>
      OwnerStats.fromJson(_map(await _c.get('/owner/stats', query: {
        if (from != null) 'from': dateParam(from),
        if (to != null) 'to': dateParam(to),
        'courtId': ?courtId,
      })));

  /// Imagen del comprobante (requiere sesión).
  Future<Uint8List> proofImage(String paymentId) => _c.getBytes('/payments/$paymentId/proof');

  // ---------------- Chat ----------------

  Future<List<ChatThread>> chatThreads() async =>
      _rows(await _c.get('/chat/threads')).map(ChatThread.fromJson).toList();

  /// Abre (o crea) el chat de una reserva: lo pueden pedir el jugador o el dueño.
  Future<ChatThread> openBookingChat(String bookingId) async =>
      ChatThread.fromJson(_map(await _c.post('/chat/bookings/$bookingId')));

  Future<ChatThread> openSupportChat() async => ChatThread.fromJson(_map(await _c.post('/chat/support')));

  /// Sin [after] trae los últimos mensajes; con [after] solo los nuevos. [admin] usa las rutas del administrador.
  Future<ChatPage> chatMessages(String threadId, {int? after, bool admin = false}) async => ChatPage.fromJson(
      _map(await _c.get('${admin ? '/admin' : ''}/chat/threads/$threadId/messages', query: {'after': ?after})));

  Future<ChatMessage> sendChatMessage(
    String threadId, {
    String? body,
    Uint8List? image,
    String? filename,
    bool admin = false,
  }) async {
    final path = '${admin ? '/admin' : ''}/chat/threads/$threadId/messages';
    final dynamic data = image == null
        ? await _c.post(path, body: {'body': body})
        : await _c.upload(path,
            field: 'image',
            bytes: image,
            filename: filename ?? 'foto.jpg',
            fields: {if (body != null && body.isNotEmpty) 'body': body});
    return ChatMessage.fromJson(_map(data));
  }

  Future<Uint8List> chatImage(String messageId) => _c.getBytes('/chat/images/$messageId');

  Future<void> reportChatMessage(String messageId, {String? reason}) => _c.post('/chat/messages/$messageId/report',
      body: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});

  Future<void> blockChatUser(String userId) => _c.post('/chat/blocks/$userId');
  Future<void> unblockChatUser(String userId) => _c.delete('/chat/blocks/$userId');

  Future<List<SupportInboxItem>> adminSupportInbox() async =>
      _rows(await _c.get('/admin/chat/support')).map(SupportInboxItem.fromJson).toList();

  Future<List<AdminChatThread>> adminCourtChats({String? search}) async =>
      _rows(await _c.get('/admin/chat/threads', query: {if (search != null && search.isNotEmpty) 'search': search}))
          .map(AdminChatThread.fromJson)
          .toList();

  Future<List<ChatReport>> adminChatReports() async =>
      _rows(await _c.get('/admin/chat/reports')).map(ChatReport.fromJson).toList();

  Future<void> resolveChatReport(String id) => _c.post('/admin/chat/reports/$id/resolve');
  Future<void> hideChatMessage(String messageId) => _c.post('/admin/chat/messages/$messageId/hide');

  // ---------------- Administrador ----------------

  Future<List<Payment>> adminPayments({String? kind, PaymentStatus? status}) async =>
      _rows(await _c.get('/admin/payments', query: {
        'kind': ?kind,
        if (status != null) 'status': status.name,
      })).map(Payment.fromJson).toList();

  Future<void> approveSubscription(String id) => _c.post('/admin/payments/$id/approve');
  Future<void> rejectSubscription(String id, {String? reason}) =>
      _c.post('/admin/payments/$id/reject', body: {if (reason != null && reason.isNotEmpty) 'reason': reason});

  Future<List<AdminUser>> adminUsers({String? search, Role? role}) async =>
      _rows(await _c.get('/admin/users', query: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (role != null) 'role': role.name,
      })).map(AdminUser.fromJson).toList();

  Future<void> suspendUser(String id) => _c.post('/admin/users/$id/suspend');
  Future<void> restoreUser(String id) => _c.post('/admin/users/$id/restore');
  Future<void> deleteUser(String id) => _c.delete('/admin/users/$id');

  Future<List<AdminCourt>> adminCourts({CourtStatus? status, String? search}) async =>
      _rows(await _c.get('/admin/courts', query: {
        if (status != null) 'status': status.name,
        if (search != null && search.isNotEmpty) 'search': search,
      })).map(AdminCourt.fromJson).toList();

  Future<void> suspendCourt(String id) => _c.post('/admin/courts/$id/suspend');
  Future<void> reactivateCourt(String id) => _c.post('/admin/courts/$id/reactivate');

  /// Mensualidad cobrada fuera de la app: abre 30 días y activa la cancha.
  Future<void> registerSubscription(String courtId, {int? amount, String? note}) =>
      _c.post('/admin/courts/$courtId/subscription-payment', body: {
        'amount': ?amount,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<List<ReportedReview>> reportedReviews() async =>
      _rows(await _c.get('/admin/review-reports')).map(ReportedReview.fromJson).toList();

  Future<void> hideReview(String id) => _c.post('/admin/reviews/$id/hide');
  Future<void> dismissReview(String id) => _c.post('/admin/reviews/$id/dismiss');

  Future<Transactions> transactions({String? kind}) async =>
      Transactions.fromJson(_map(await _c.get('/admin/transactions', query: {'kind': ?kind})));

  Future<Metrics> metrics() async => Metrics(_map(await _c.get('/admin/metrics')));
}
