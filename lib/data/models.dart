// Modelos que devuelve la API de Golazo.

DateTime _dt(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _dtOrNull(Object? v) => v == null ? null : _dt(v);
int _int(Object? v) => (v as num).toInt();
double _dbl(Object? v) => (v as num).toDouble();

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    ((v as List?) ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

enum Role { player, owner, admin }

Role roleFrom(String s) =>
    Role.values.firstWhere((r) => r.name == s, orElse: () => Role.player);

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.phone,
    this.emailVerified = false,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final Role role;
  final bool emailVerified;

  /// Para reservar hace falta un celular de contacto.
  bool get hasPhone => phone != null && phone!.isNotEmpty;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        role: roleFrom(j['role'] as String),
        emailVerified: j['emailVerified'] as bool? ?? false,
      );
}

class PaymentMethod {
  const PaymentMethod({required this.label, required this.account, required this.holder});

  final String label;
  final String account;
  final String holder;

  factory PaymentMethod.fromJson(Map<String, dynamic> j) => PaymentMethod(
        label: j['label'] as String,
        account: j['account'] as String,
        holder: j['holder'] as String,
      );

  Map<String, dynamic> toJson() => {'label': label, 'account': account, 'holder': holder};
}

enum CourtStatus { pending, active, suspended }

class CourtPhoto {
  const CourtPhoto({required this.url, this.id});
  final String url;

  /// Solo viene en el detalle del dueño (para poder borrarla).
  final String? id;
}

class CourtSubscription {
  const CourtSubscription({this.activeUntil, this.pendingReview = false});

  /// Fecha (YYYY-MM-DD) hasta la que está pagada la mensualidad.
  final String? activeUntil;
  final bool pendingReview;
}

class Court {
  const Court({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.covered,
    required this.pricePerHour,
    required this.openHour,
    required this.closeHour,
    required this.requiresDeposit,
    required this.depositPercent,
    required this.status,
    required this.lat,
    required this.lng,
    this.description,
    this.photoUrl,
    this.rating = 0,
    this.reviewCount = 0,
    this.distanceM,
    this.photos = const [],
    this.paymentMethods = const [],
    this.subscription,
  });

  final String id;
  final String name;
  final String? description;
  final String city;
  final String address;
  final bool covered;
  final int pricePerHour;
  final int openHour;
  final int closeHour;
  final bool requiresDeposit;
  final int depositPercent;
  final CourtStatus status;
  final double lat;
  final double lng;
  final String? photoUrl;
  final double rating;
  final int reviewCount;
  final double? distanceM;
  final List<CourtPhoto> photos;
  final List<PaymentMethod> paymentMethods;
  final CourtSubscription? subscription;

  factory Court.fromJson(Map<String, dynamic> j) {
    final photosRaw = (j['photos'] as List?) ?? const [];
    final sub = j['subscription'] as Map<String, dynamic>?;
    return Court(
      id: j['id'] as String,
      name: j['name'] as String,
      description: j['description'] as String?,
      city: j['city'] as String,
      address: j['address'] as String,
      covered: j['covered'] as bool,
      pricePerHour: _int(j['pricePerHour']),
      openHour: _int(j['openHour']),
      closeHour: _int(j['closeHour']),
      requiresDeposit: j['requiresDeposit'] as bool,
      depositPercent: _int(j['depositPercent']),
      status: CourtStatus.values.firstWhere((s) => s.name == j['status']),
      lat: _dbl(j['lat']),
      lng: _dbl(j['lng']),
      photoUrl: j['photoUrl'] as String?,
      rating: j['rating'] == null ? 0 : _dbl(j['rating']),
      reviewCount: j['reviewCount'] == null ? 0 : _int(j['reviewCount']),
      distanceM: j['distanceM'] == null ? null : _dbl(j['distanceM']),
      // El detalle público trae URLs; el del dueño trae {id, url}.
      photos: photosRaw
          .map((p) => p is String
              ? CourtPhoto(url: p)
              : CourtPhoto(
                  url: (p as Map<String, dynamic>)['url'] as String,
                  id: p['id'] as String?))
          .toList(),
      paymentMethods: _list(j['paymentMethods'], PaymentMethod.fromJson),
      subscription: sub == null
          ? null
          : CourtSubscription(
              activeUntil: sub['activeUntil'] as String?,
              pendingReview: sub['pendingReview'] as bool? ?? false,
            ),
    );
  }
}

enum BookingStatus { pendingPayment, pendingReview, confirmed, rejected, cancelled }

BookingStatus bookingStatusFrom(String s) => switch (s) {
      'pending_payment' => BookingStatus.pendingPayment,
      'pending_review' => BookingStatus.pendingReview,
      'confirmed' => BookingStatus.confirmed,
      'rejected' => BookingStatus.rejected,
      _ => BookingStatus.cancelled,
    };

class Booking {
  const Booking({
    required this.id,
    required this.courtId,
    required this.courtName,
    required this.startAt,
    required this.hours,
    required this.total,
    required this.deposit,
    required this.lastMinute,
    required this.status,
    required this.cancellable,
    this.reviewed = false,
    this.paymentMethods = const [],
  });

  final String id;
  final String courtId;
  final String courtName;
  final DateTime startAt;
  final int hours;
  final int total;
  final int deposit;
  final bool lastMinute;
  final BookingStatus status;
  final bool cancellable;

  /// El jugador ya calificó esta reserva.
  final bool reviewed;

  /// Solo se llena mientras falta pagar.
  final List<PaymentMethod> paymentMethods;

  DateTime get endAt => startAt.add(Duration(hours: hours));
  bool get isPast => endAt.isBefore(DateTime.now());
  bool get needsPayment =>
      status == BookingStatus.pendingPayment || status == BookingStatus.rejected;

  /// Lo que hay que transferir ahora.
  int get amountDue => deposit > 0 ? deposit : total;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as String,
        courtId: j['courtId'] as String,
        courtName: j['courtName'] as String,
        startAt: _dt(j['startAt']),
        hours: _int(j['hours']),
        total: _int(j['total']),
        deposit: _int(j['deposit']),
        lastMinute: j['lastMinute'] as bool? ?? false,
        status: bookingStatusFrom(j['status'] as String),
        cancellable: j['cancellable'] as bool? ?? false,
        reviewed: j['reviewed'] as bool? ?? false,
        paymentMethods: _list(j['paymentMethods'], PaymentMethod.fromJson),
      );
}

class HourSlot {
  const HourSlot(this.hour, this.free);
  final int hour;
  final bool free;
}

class Review {
  const Review({
    required this.id,
    required this.stars,
    required this.createdAt,
    required this.authorName,
    this.body,
  });

  final String id;
  final int stars;
  final String? body;
  final DateTime createdAt;
  final String authorName;

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: j['id'] as String,
        stars: _int(j['stars']),
        body: j['body'] as String?,
        createdAt: _dt(j['createdAt']),
        authorName: j['authorName'] as String? ?? '',
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.data = const {},
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> data;

  bool get unread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        createdAt: _dt(j['createdAt']),
        readAt: _dtOrNull(j['readAt']),
        data: (j['data'] as Map<String, dynamic>?) ?? const {},
      );
}

class NotificationsPage {
  const NotificationsPage({required this.unread, required this.items});
  final int unread;
  final List<AppNotification> items;
}

enum PaymentStatus { pending, approved, rejected }

class Payment {
  const Payment({
    required this.id,
    required this.kind,
    required this.status,
    required this.amount,
    required this.createdAt,
    required this.courtId,
    required this.courtName,
    required this.payerName,
    this.payerPhone,
    this.payerEmail,
    this.rejectReason,
    this.bookingId,
    this.startAt,
    this.hours,
  });

  final String id;

  /// 'booking' o 'subscription'.
  final String kind;
  final PaymentStatus status;
  final int amount;
  final DateTime createdAt;
  final String courtId;
  final String courtName;
  final String payerName;
  final String? payerPhone;
  final String? payerEmail;
  final String? rejectReason;
  final String? bookingId;
  final DateTime? startAt;
  final int? hours;

  bool get isSubscription => kind == 'subscription';

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: j['id'] as String,
        kind: j['kind'] as String,
        status: PaymentStatus.values.firstWhere((s) => s.name == j['status']),
        amount: _int(j['amount']),
        createdAt: _dt(j['createdAt']),
        courtId: j['courtId'] as String,
        courtName: j['courtName'] as String,
        payerName: j['payerName'] as String,
        payerPhone: j['payerPhone'] as String?,
        payerEmail: j['payerEmail'] as String?,
        rejectReason: j['rejectReason'] as String?,
        bookingId: j['bookingId'] as String?,
        startAt: _dtOrNull(j['startAt']),
        hours: j['hours'] == null ? null : _int(j['hours']),
      );
}

class OwnerBooking {
  const OwnerBooking({
    required this.id,
    required this.courtId,
    required this.courtName,
    required this.startAt,
    required this.hours,
    required this.total,
    required this.deposit,
    required this.status,
    required this.isBlock,
    this.note,
    this.playerName,
    this.playerPhone,
  });

  final String id;
  final String courtId;
  final String courtName;
  final DateTime startAt;
  final int hours;
  final int total;
  final int deposit;
  final BookingStatus status;

  /// true = horas que el propio dueño bloqueó (no es un jugador).
  final bool isBlock;
  final String? note;
  final String? playerName;
  final String? playerPhone;

  factory OwnerBooking.fromJson(Map<String, dynamic> j) => OwnerBooking(
        id: j['id'] as String,
        courtId: j['courtId'] as String,
        courtName: j['courtName'] as String,
        startAt: _dt(j['startAt']),
        hours: _int(j['hours']),
        total: _int(j['total']),
        deposit: _int(j['deposit']),
        status: bookingStatusFrom(j['status'] as String),
        isBlock: j['isBlock'] as bool? ?? false,
        note: j['note'] as String?,
        playerName: j['playerName'] as String?,
        playerPhone: j['playerPhone'] as String?,
      );
}

class SubscriptionConfig {
  const SubscriptionConfig({required this.price, required this.periodDays, required this.accounts});
  final int price;
  final int periodDays;
  final List<PaymentMethod> accounts;

  factory SubscriptionConfig.fromJson(Map<String, dynamic> j) => SubscriptionConfig(
        price: _int(j['price']),
        periodDays: _int(j['periodDays']),
        accounts: _list(j['accounts'], PaymentMethod.fromJson),
      );
}

class OwnerStats {
  const OwnerStats({
    required this.days,
    required this.total,
    required this.confirmed,
    required this.cancelled,
    required this.awaitingPayment,
    required this.income,
    required this.bookedHours,
    required this.occupancyPercent,
  });

  final int days;
  final int total;
  final int confirmed;
  final int cancelled;
  final int awaitingPayment;
  final int income;
  final int bookedHours;
  final double occupancyPercent;

  factory OwnerStats.fromJson(Map<String, dynamic> j) {
    final b = j['bookings'] as Map<String, dynamic>;
    return OwnerStats(
      days: _int(j['days']),
      total: _int(b['total']),
      confirmed: _int(b['confirmed']),
      cancelled: _int(b['cancelled']),
      awaitingPayment: _int(b['awaitingPayment']),
      income: _int(j['income']),
      bookedHours: _int(j['bookedHours']),
      occupancyPercent: _dbl(j['occupancyPercent']),
    );
  }
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
    this.email,
    this.phone,
    this.suspended = false,
    this.deleted = false,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final Role role;
  final bool suspended;
  final bool deleted;
  final DateTime createdAt;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        role: roleFrom(j['role'] as String),
        suspended: j['suspendedAt'] != null,
        deleted: j['deletedAt'] != null,
        createdAt: _dt(j['createdAt']),
      );
}

class AdminCourt {
  const AdminCourt({
    required this.id,
    required this.name,
    required this.city,
    required this.status,
    required this.suspendedByAdmin,
    required this.ownerName,
    required this.pendingSubscription,
    this.ownerPhone,
    this.ownerEmail,
    this.activeUntil,
  });

  final String id;
  final String name;
  final String city;
  final CourtStatus status;
  final bool suspendedByAdmin;
  final String ownerName;
  final String? ownerPhone;
  final String? ownerEmail;
  final String? activeUntil;
  final bool pendingSubscription;

  factory AdminCourt.fromJson(Map<String, dynamic> j) => AdminCourt(
        id: j['id'] as String,
        name: j['name'] as String,
        city: j['city'] as String,
        status: CourtStatus.values.firstWhere((s) => s.name == j['status']),
        suspendedByAdmin: j['suspendedByAdmin'] as bool? ?? false,
        ownerName: j['ownerName'] as String,
        ownerPhone: j['ownerPhone'] as String?,
        ownerEmail: j['ownerEmail'] as String?,
        activeUntil: j['activeUntil'] as String?,
        pendingSubscription: j['pendingSubscription'] as bool? ?? false,
      );
}

class ReportedReview {
  const ReportedReview({
    required this.id,
    required this.stars,
    required this.courtName,
    required this.authorName,
    required this.reports,
    this.body,
    this.reasons = const [],
  });

  final String id;
  final int stars;
  final String? body;
  final String courtName;
  final String authorName;
  final int reports;
  final List<String> reasons;

  factory ReportedReview.fromJson(Map<String, dynamic> j) => ReportedReview(
        id: j['id'] as String,
        stars: _int(j['stars']),
        body: j['body'] as String?,
        courtName: j['courtName'] as String,
        authorName: j['authorName'] as String,
        reports: _int(j['reports']),
        reasons: ((j['reasons'] as List?) ?? const []).cast<String>(),
      );
}

class TransactionItem {
  const TransactionItem({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    required this.courtName,
    required this.payerName,
  });

  final String id;
  final String kind;
  final int amount;
  final DateTime date;
  final String courtName;
  final String payerName;

  factory TransactionItem.fromJson(Map<String, dynamic> j) => TransactionItem(
        id: j['id'] as String,
        kind: j['kind'] as String,
        amount: _int(j['amount']),
        date: _dt(j['date']),
        courtName: j['courtName'] as String,
        payerName: j['payerName'] as String,
      );
}

class Transactions {
  const Transactions({required this.count, required this.totalAmount, required this.items});
  final int count;
  final int totalAmount;
  final List<TransactionItem> items;

  factory Transactions.fromJson(Map<String, dynamic> j) => Transactions(
        count: _int(j['count']),
        totalAmount: _int(j['totalAmount']),
        items: _list(j['items'], TransactionItem.fromJson),
      );
}

/// Métricas globales del admin (el servidor devuelve grupos por estado/rol).
class Metrics {
  const Metrics(this.raw);
  final Map<String, dynamic> raw;

  int _g(String group, String key) {
    final g = raw[group];
    final v = g is Map ? g[key] : null;
    return v is num ? v.toInt() : 0;
  }

  int get players => _g('users', 'player');
  int get owners => _g('users', 'owner');
  int get activeCourts => _g('courts', 'active');
  int get pendingCourts => _g('courts', 'pending');
  int get suspendedCourts => _g('courts', 'suspended');
  int get confirmedBookings => _g('bookings', 'confirmed');
  int get pendingSubscriptionPayments => _g('pending', 'subscriptionPayments');
  int get reportedReviews => _g('pending', 'reportedReviews');
  int get subscriptionsTotal => _g('revenue', 'subscriptionsTotal');
  int get subscriptionsThisMonth => _g('revenue', 'subscriptionsThisMonth');
  int get bookings30d => _g('last30Days', 'confirmedBookings');
  int get bookingsValue30d => _g('last30Days', 'bookingsValue');
  int get newUsers30d => _g('last30Days', 'newUsers');
}
