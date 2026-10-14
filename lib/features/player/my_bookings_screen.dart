import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../booking/reviews_section.dart';

String _label(BookingStatus s) => switch (s) {
      BookingStatus.pendingPayment => 'Falta comprobante',
      BookingStatus.pendingReview => 'Pago en revisión',
      BookingStatus.confirmed => 'Confirmada',
      BookingStatus.rejected => 'Pago rechazado',
      BookingStatus.cancelled => 'Cancelada',
    };

Color _color(BookingStatus s) => switch (s) {
      BookingStatus.confirmed => Colors.green.shade700,
      BookingStatus.pendingReview => Colors.blue.shade700,
      BookingStatus.pendingPayment => Colors.orange.shade800,
      BookingStatus.rejected => Colors.red.shade700,
      BookingStatus.cancelled => Colors.grey.shade600,
    };

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myBookingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis reservas')),
      body: AsyncView<List<Booking>>(
        value: bookings,
        onRetry: () => ref.invalidate(myBookingsProvider),
        emptyText: 'Aún no tienes reservas.\nElige una cancha y reserva tu hora.',
        isEmpty: (l) => l.isEmpty,
        builder: (all) {
          // Próximas primero (la más cercana arriba); luego el historial.
          final upcoming = all
              .where((b) => !b.isPast && b.status != BookingStatus.cancelled)
              .toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
          final history = all.where((b) => !upcoming.contains(b)).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myBookingsProvider);
              await ref.read(myBookingsProvider.future);
            },
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (upcoming.isNotEmpty) _header(context, 'Próximas'),
              for (final b in upcoming) _BookingCard(booking: b),
              if (history.isNotEmpty) _header(context, 'Anteriores'),
              for (final b in history) _BookingCard(booking: b),
            ]),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final canReview = b.status == BookingStatus.confirmed && b.isPast && !b.reviewed;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(b.courtName, style: Theme.of(context).textTheme.titleMedium)),
            StatusChip(_label(b.status), color: _color(b.status)),
          ]),
          const SizedBox(height: 4),
          Text(rangeLabel(b.startAt, b.hours)),
          Text('Total ${cop(b.total)}${b.deposit > 0 ? ' · Anticipo ${cop(b.deposit)}' : ''}'),
          if (b.lastMinute && b.status != BookingStatus.cancelled)
            Text('Reserva de último momento (sin cancelación)', style: Theme.of(context).textTheme.bodySmall),
          Wrap(spacing: 8, children: [
            if (b.needsPayment)
              TextButton.icon(
                onPressed: () => context.push('/bookings/${b.id}/pay'),
                icon: const Icon(Icons.upload_file),
                label: Text(b.status == BookingStatus.rejected ? 'Subir otro comprobante' : 'Pagar anticipo'),
              ),
            if (b.cancellable)
              TextButton(
                onPressed: () => _cancel(context, ref),
                child: const Text('Cancelar'),
              ),
            if (canReview)
              TextButton.icon(
                onPressed: () => showReviewDialog(context, ref, b.id, b.courtId),
                icon: const Icon(Icons.star_outline),
                label: const Text('Calificar'),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: '¿Cancelar la reserva?',
      message: booking.status == BookingStatus.confirmed || booking.status == BookingStatus.pendingReview
          ? 'Si ya pagaste un anticipo, el dueño te lo devolverá por fuera de la app.'
          : null,
      okLabel: 'Cancelar reserva',
    );
    if (!ok || !context.mounted) return;
    final done = await guarded(context, () => ref.read(apiProvider).cancelBooking(booking.id),
        success: 'Reserva cancelada');
    if (done) ref.invalidate(myBookingsProvider);
  }
}
