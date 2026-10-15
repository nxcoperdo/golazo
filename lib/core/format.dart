/// Entero con puntos de miles: 1.248.
String fmtInt(int v) {
  final digits = v.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return '${v < 0 ? '-' : ''}$grouped';
}

/// Pesos colombianos: $90.000 (el formato es_CO de intl pone el símbolo al final: 90.000$).
String cop(int v) => v < 0 ? '-\$${fmtInt(-v)}' : '\$${fmtInt(v)}';

/// Hora en formato 12 h con AM/PM: 0 y 24 → "12:00 AM", 12 → "12:00 PM".
String hourLabel(int hour24) {
  final h = hour24 % 24;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:00 ${h < 12 ? 'AM' : 'PM'}';
}

// ---- Hora de Colombia (UTC-5, sin horario de verano) ----
//
// Las canchas y sus horarios están en hora de Colombia sin importar la zona
// horaria del teléfono, así que nunca se usa `DateTime.local` para mostrarlos.

const _coOffset = Duration(hours: 5);

/// "Hora de pared" de Colombia de un instante: devuelve un DateTime UTC cuyos
/// campos (year, month, day, hour…) son los que se ven en Colombia.
DateTime coWall(DateTime instant) => instant.toUtc().subtract(_coOffset);

/// Hoy en Colombia, como fecha (UTC medianoche) sin hora.
DateTime coToday([DateTime? now]) {
  final w = coWall(now ?? DateTime.now());
  return DateTime.utc(w.year, w.month, w.day);
}

/// Instante real de las [hour] horas (hora Colombia) del día [coDay].
DateTime coInstant(DateTime coDay, int hour) =>
    DateTime.utc(coDay.year, coDay.month, coDay.day, hour).add(_coOffset);

/// YYYY-MM-DD de una fecha de Colombia (para la API).
String dateParam(DateTime coDay) =>
    '${coDay.year.toString().padLeft(4, '0')}-${coDay.month.toString().padLeft(2, '0')}-${coDay.day.toString().padLeft(2, '0')}';

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
];

/// "mié 14 oct" para un instante, en hora de Colombia.
String dayLabel(DateTime instant) {
  final w = coWall(instant);
  return '${_weekdays[w.weekday - 1]} ${w.day} ${_months[w.month - 1]}';
}

/// "lun" … "dom" de una fecha de Colombia (UTC medianoche, como `coToday`).
String weekdayShort(DateTime coDay) => _weekdays[coDay.weekday - 1];

/// "ene" … "dic" de una fecha de Colombia.
String monthShort(DateTime coDay) => _months[coDay.month - 1];

/// "Hoy", "Ayer", "Hace 3 días", "Hace 2 semanas", "Hace 4 meses" o "Hace 2 años".
String agoLabel(DateTime instant, [DateTime? now]) {
  final days = coToday(now).difference(coToday(instant)).inDays;
  if (days <= 0) return 'Hoy';
  if (days == 1) return 'Ayer';
  if (days < 7) return 'Hace $days días';
  if (days < 30) {
    final w = days ~/ 7;
    return w == 1 ? 'Hace 1 semana' : 'Hace $w semanas';
  }
  if (days < 365) {
    final m = days ~/ 30;
    return m == 1 ? 'Hace 1 mes' : 'Hace $m meses';
  }
  final y = days ~/ 365;
  return y == 1 ? 'Hace 1 año' : 'Hace $y años';
}

const _weekdaysLong = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _monthsLong = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];

/// "Hoy · 18 de mayo" o "Lunes 19 de mayo" para una fecha de Colombia (UTC medianoche, como `coToday`).
String longDayLabel(DateTime coDay, [DateTime? now]) {
  final base = '${coDay.day} de ${_monthsLong[coDay.month - 1]}';
  if (coDay == coToday(now)) return 'Hoy · $base';
  final wd = _weekdaysLong[coDay.weekday - 1];
  return '${wd[0].toUpperCase()}${wd.substring(1)} $base';
}

/// "3:00 PM" (o "3:30 PM") de un instante, en hora de Colombia.
String timeLabel(DateTime instant) {
  final w = coWall(instant);
  final h12 = w.hour % 12 == 0 ? 12 : w.hour % 12;
  return '$h12:${w.minute.toString().padLeft(2, '0')} ${w.hour < 12 ? 'AM' : 'PM'}';
}

/// "mié 14 oct · 3:00 PM – 5:00 PM".
String rangeLabel(DateTime start, int hours) =>
    '${dayLabel(start)} · ${timeLabel(start)} – ${timeLabel(start.add(Duration(hours: hours)))}';
