import '../../data/models.dart';
import 'design.dart';

String bookingStatusLabel(BookingStatus s) => switch (s) {
      BookingStatus.pendingPayment => 'Falta comprobante',
      BookingStatus.pendingReview => 'Pago en revisión',
      BookingStatus.confirmed => 'Confirmada',
      BookingStatus.rejected => 'Pago rechazado',
      BookingStatus.cancelled => 'Cancelada',
    };

String paymentStatusLabel(PaymentStatus s) => switch (s) {
      PaymentStatus.pending => 'Por revisar',
      PaymentStatus.approved => 'Aprobado',
      PaymentStatus.rejected => 'Rechazado',
    };

// ---- Etiquetas y tonos de las píldoras de estado (diseño) ----

/// "Completada" cuando una reserva confirmada ya se jugó.
String bookingLabelFor(Booking b) =>
    b.status == BookingStatus.confirmed && b.isPast ? 'Completada' : bookingStatusLabel(b.status);

PillTone bookingToneFor(Booking b) => switch (b.status) {
      BookingStatus.confirmed => b.isPast ? PillTone.gray : PillTone.green,
      BookingStatus.pendingReview => PillTone.blue,
      BookingStatus.pendingPayment => PillTone.amber,
      BookingStatus.rejected => PillTone.red,
      BookingStatus.cancelled => PillTone.red,
    };

String courtStateLabel(CourtStatus s) => switch (s) {
      CourtStatus.active => 'Activa',
      CourtStatus.pending => 'Mensualidad pendiente',
      CourtStatus.suspended => 'Oculta',
    };

PillTone courtTone(CourtStatus s) => switch (s) {
      CourtStatus.active => PillTone.green,
      CourtStatus.pending => PillTone.amber,
      CourtStatus.suspended => PillTone.gray,
    };

PillTone paymentTone(PaymentStatus s) => switch (s) {
      PaymentStatus.approved => PillTone.green,
      PaymentStatus.pending => PillTone.amber,
      PaymentStatus.rejected => PillTone.red,
    };
