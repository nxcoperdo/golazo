import 'package:intl/intl.dart';

final _cop = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
String cop(int v) => _cop.format(v);

/// Hora en formato 12 h con AM/PM: 0 y 24 → "12:00 AM", 12 → "12:00 PM".
String hourLabel(int hour24) {
  final h = hour24 % 24;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:00 ${h < 12 ? 'AM' : 'PM'}';
}
