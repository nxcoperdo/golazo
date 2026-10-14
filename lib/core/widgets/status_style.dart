import 'package:flutter/material.dart';

import '../../data/models.dart';

String bookingStatusLabel(BookingStatus s) => switch (s) {
      BookingStatus.pendingPayment => 'Falta comprobante',
      BookingStatus.pendingReview => 'Pago en revisión',
      BookingStatus.confirmed => 'Confirmada',
      BookingStatus.rejected => 'Pago rechazado',
      BookingStatus.cancelled => 'Cancelada',
    };

Color bookingStatusColor(BookingStatus s) => switch (s) {
      BookingStatus.confirmed => Colors.green.shade700,
      BookingStatus.pendingReview => Colors.blue.shade700,
      BookingStatus.pendingPayment => Colors.orange.shade800,
      BookingStatus.rejected => Colors.red.shade700,
      BookingStatus.cancelled => Colors.grey.shade600,
    };

String courtStatusLabel(CourtStatus s) => switch (s) {
      CourtStatus.pending => 'Pendiente',
      CourtStatus.active => 'Activa',
      CourtStatus.suspended => 'Oculta',
    };

Color courtStatusColor(CourtStatus s) => switch (s) {
      CourtStatus.active => Colors.green.shade700,
      CourtStatus.pending => Colors.orange.shade800,
      CourtStatus.suspended => Colors.grey.shade600,
    };

String paymentStatusLabel(PaymentStatus s) => switch (s) {
      PaymentStatus.pending => 'Por revisar',
      PaymentStatus.approved => 'Aprobado',
      PaymentStatus.rejected => 'Rechazado',
    };

Color paymentStatusColor(PaymentStatus s) => switch (s) {
      PaymentStatus.approved => Colors.green.shade700,
      PaymentStatus.pending => Colors.orange.shade800,
      PaymentStatus.rejected => Colors.red.shade700,
    };
