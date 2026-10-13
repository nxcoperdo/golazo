/// Reglas de reserva: cancelación gratis hasta 24 h antes; reservas con
/// menos de 8 h de anticipación exigen anticipo del 30 % y no son cancelables.
class BookingPolicy {
  const BookingPolicy._();

  static const lastMinuteWindow = Duration(hours: 8);
  static const freeCancelWindow = Duration(hours: 24);
  static const lastMinuteDepositPercent = 30;

  /// Máximo de horas seguidas en una sola reserva.
  static const maxHours = 4;

  /// Nueva selección de horas al tocar [h]: solo bloques contiguos de hasta
  /// [maxHours]; si el toque no es contiguo, empieza una selección nueva.
  static Set<int> toggleHour(Set<int> selected, int h) {
    if (selected.isEmpty) return {h};
    final lo = selected.reduce((a, b) => a < b ? a : b);
    final hi = selected.reduce((a, b) => a > b ? a : b);
    if (selected.contains(h)) {
      return (h == lo || h == hi) && selected.length > 1
          ? (Set.of(selected)..remove(h))
          : {h};
    }
    if ((h == lo - 1 || h == hi + 1) && selected.length < maxHours) {
      return Set.of(selected)..add(h);
    }
    return {h};
  }

  static bool isLastMinute(DateTime start, DateTime now) =>
      start.difference(now) < lastMinuteWindow;

  static bool canCancelFree(DateTime start, DateTime now) =>
      !isLastMinute(start, now) &&
      start.difference(now) >= freeCancelWindow;

  /// Monto de anticipo a pagar (0 si no se exige).
  static int depositFor({
    required int total,
    required bool courtRequiresDeposit,
    required int courtDepositPercent,
    required DateTime start,
    required DateTime now,
  }) {
    if (isLastMinute(start, now)) {
      return (total * lastMinuteDepositPercent / 100).round();
    }
    if (courtRequiresDeposit) return (total * courtDepositPercent / 100).round();
    return 0;
  }
}
