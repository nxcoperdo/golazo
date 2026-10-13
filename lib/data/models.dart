enum Role { player, owner, admin }

enum CourtStatus { pending, active }

enum BookingStatus { pendingPayment, pendingReview, confirmed, rejected, cancelled }

class PaymentMethod {
  const PaymentMethod({required this.label, required this.account, required this.holder});
  final String label;
  final String account;
  final String holder;
}

class Court {
  const Court({
    required this.id,
    required this.name,
    required this.city,
    required this.photoUrl,
    required this.pricePerHour,
    required this.covered,
    required this.requiresDeposit,
    this.depositPercent = 30,
    this.rating = 4.5,
    this.status = CourtStatus.active,
    this.openHour = 8,
    this.closeHour = 23,
    this.paymentMethods = const [],
  });

  final String id;
  final String name;
  final String city;
  final String photoUrl;
  final int pricePerHour;
  final bool covered;
  final bool requiresDeposit;
  final int depositPercent;
  final double rating;
  final CourtStatus status;
  final int openHour;
  final int closeHour;
  final List<PaymentMethod> paymentMethods;

  Court copyWith({
    String? name,
    int? pricePerHour,
    bool? covered,
    bool? requiresDeposit,
    int? depositPercent,
    CourtStatus? status,
    int? openHour,
    int? closeHour,
    List<PaymentMethod>? paymentMethods,
  }) =>
      Court(
        id: id,
        name: name ?? this.name,
        city: city,
        photoUrl: photoUrl,
        pricePerHour: pricePerHour ?? this.pricePerHour,
        covered: covered ?? this.covered,
        requiresDeposit: requiresDeposit ?? this.requiresDeposit,
        depositPercent: depositPercent ?? this.depositPercent,
        rating: rating,
        status: status ?? this.status,
        openHour: openHour ?? this.openHour,
        closeHour: closeHour ?? this.closeHour,
        paymentMethods: paymentMethods ?? this.paymentMethods,
      );
}

class Booking {
  const Booking({
    required this.id,
    required this.courtId,
    required this.start,
    required this.total,
    required this.deposit,
    required this.status,
    required this.refundable,
    this.proofPath,
    this.hours = 1,
  });

  final String id;
  final String courtId;
  final DateTime start;
  final int total;
  final int deposit;
  final BookingStatus status;
  final bool refundable;
  final String? proofPath;
  final int hours;

  Booking copyWith({BookingStatus? status, String? proofPath}) => Booking(
        id: id,
        courtId: courtId,
        start: start,
        total: total,
        deposit: deposit,
        status: status ?? this.status,
        refundable: refundable,
        proofPath: proofPath ?? this.proofPath,
        hours: hours,
      );
}

enum ReviewState { pending, approved, rejected }

class Subscription {
  const Subscription({
    required this.id,
    required this.courtId,
    this.amount = 100000,
    this.state = ReviewState.pending,
    this.proofPath,
  });

  final String id;
  final String courtId;
  final int amount;
  final ReviewState state;
  final String? proofPath;

  Subscription copyWith({ReviewState? state}) => Subscription(
        id: id,
        courtId: courtId,
        amount: amount,
        state: state ?? this.state,
        proofPath: proofPath,
      );
}

class AppUser {
  const AppUser({required this.id, required this.name, required this.email, this.suspended = false});
  final String id;
  final String name;
  final String email;
  final bool suspended;

  AppUser copyWith({bool? suspended}) => AppUser(
      id: id, name: name, email: email, suspended: suspended ?? this.suspended);
}

class Review {
  const Review({required this.id, required this.courtId, required this.author, required this.text, required this.stars});
  final String id;
  final String courtId;
  final String author;
  final String text;
  final int stars;
}
