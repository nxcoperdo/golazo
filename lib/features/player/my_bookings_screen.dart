import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_style.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../booking/reviews_section.dart';

enum _Group { upcoming, past }

/// Mis reservas: próximas y anteriores, con pago, cancelación y reseña.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsState();
}

class _MyBookingsState extends ConsumerState<MyBookingsScreen> {
  _Group _group = _Group.upcoming;

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(myBookingsProvider);
    return AppPage(
      kicker: 'Tu agenda',
      title: 'Mis reservas',
      child: AsyncView<List<Booking>>(
        value: bookings,
        onRetry: () => ref.invalidate(myBookingsProvider),
        builder: (all) {
          // Próximas primero (la más cercana arriba); luego el historial.
          final upcoming = all.where((b) => !b.isPast && b.status != BookingStatus.cancelled).toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
          final history = all.where((b) => !upcoming.contains(b)).toList();
          final list = _group == _Group.upcoming ? upcoming : history;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myBookingsProvider);
              await ref.read(myBookingsProvider.future);
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
              SegmentedTabs<_Group>(
                options: const [(_Group.upcoming, 'Próximas'), (_Group.past, 'Anteriores')],
                value: _group,
                onChanged: (g) => setState(() => _group = g),
              ),
              const SizedBox(height: 20),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text(
                    _group == _Group.upcoming
                        ? 'Aún no tienes reservas próximas.\nElige una cancha y reserva tu hora.'
                        : 'Todavía no tienes reservas anteriores.',
                    textAlign: TextAlign.center,
                    style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5),
                  ),
                )
              else
                for (final b in list) _BookingCard(booking: b, upcoming: _group == _Group.upcoming),
            ]),
          );
        },
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking, required this.upcoming});
  final Booking booking;
  final bool upcoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final canReview = b.status == BookingStatus.confirmed && b.isPast && !b.reviewed;
    final showCancel = upcoming && b.cancellable;
    final primary = b.needsPayment
        ? (b.status == BookingStatus.rejected ? 'Subir otro comprobante' : 'Pagar anticipo')
        : canReview
            ? 'Calificar'
            : null;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.courtName, style: authText(16, weight: 800)),
              const SizedBox(height: 4),
              Text(rangeLabel(b.startAt, b.hours), style: authText(12, weight: 600, color: const Color(0xFF748179))),
            ]),
          ),
          const SizedBox(width: 12),
          StatusPill(bookingLabelFor(b), bookingToneFor(b)),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF5F6F1), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Total '),
              TextSpan(text: cop(b.total), style: authText(12, weight: 800)),
            ]), style: authText(12, weight: 500, color: const Color(0xFF748179))),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Anticipo '),
              TextSpan(text: cop(b.deposit), style: authText(12, weight: 800)),
            ]), style: authText(12, weight: 500, color: const Color(0xFF748179))),
          ]),
        ),
        if (b.lastMinute && b.status != BookingStatus.cancelled) ...[
          const SizedBox(height: 12),
          const NoticeBox('Reserva de último momento · Sin cancelación'),
        ],
        if (showCancel || primary != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            if (showCancel) Expanded(child: OutlineAction(label: 'Cancelar', onPressed: () => _cancel(context, ref))),
            if (showCancel && primary != null) const SizedBox(width: 8),
            if (primary != null)
              Expanded(
                child: SolidAction(
                  label: primary,
                  onPressed: () => canReview && !b.needsPayment
                      ? showReviewDialog(context, ref, b.id, b.courtId, courtName: b.courtName)
                      : context.push('/bookings/${b.id}/pay'),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final paid = booking.status == BookingStatus.confirmed || booking.status == BookingStatus.pendingReview;
    final ok = await showAppSheet<bool>(
      context,
      builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeading(
          '¿Cancelar la reserva?',
          subtitle: paid
              ? 'Puedes cancelar sin costo. Si ya pagaste un anticipo, el dueño te lo devolverá por fuera de la app.'
              : 'Todavía no pagaste, así que puedes cancelarla sin costo.',
        ),
        SheetActions(
          primaryLabel: 'Sí, cancelar reserva',
          cancelLabel: 'Volver',
          danger: true,
          onPrimary: () => Navigator.pop(sheet, true),
        ),
      ]),
    );
    if (ok != true || !context.mounted) return;
    final done = await guarded(context, () => ref.read(apiProvider).cancelBooking(booking.id),
        success: 'Reserva cancelada');
    if (done) ref.invalidate(myBookingsProvider);
  }
}
