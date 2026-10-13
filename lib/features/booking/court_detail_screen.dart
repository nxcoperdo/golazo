import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import 'booking_policy.dart';
import 'reviews_section.dart';

/// Detalle + horarios + confirmación en una sola pantalla (flujo de 3 toques:
/// cancha → hora → confirmar).
class CourtDetailScreen extends ConsumerStatefulWidget {
  const CourtDetailScreen({super.key, required this.courtId});
  final String courtId;

  @override
  ConsumerState<CourtDetailScreen> createState() => _State();
}

class _State extends ConsumerState<CourtDetailScreen> {
  late DateTime day = DateUtils.dateOnly(DateTime.now());
  Set<int> hours = {};

  @override
  Widget build(BuildContext context) {
    final court = ref.watch(courtsProvider).firstWhere((c) => c.id == widget.courtId);
    final now = DateTime.now();
    final busy = occupiedHours(court, day, ref.watch(bookingsProvider));
    final today = DateUtils.isSameDay(day, now);

    bool free(int h) => !busy.contains(h) && !(today && h <= now.hour);

    final first = hours.isEmpty ? null : hours.reduce((a, b) => a < b ? a : b);
    final start =
        first == null ? null : DateTime(day.year, day.month, day.day, first);
    final total = court.pricePerHour * hours.length;
    final deposit = start == null
        ? 0
        : BookingPolicy.depositFor(
            total: total,
            courtRequiresDeposit: court.requiresDeposit,
            courtDepositPercent: court.depositPercent,
            start: start,
            now: now);
    final dayIndex = day.difference(DateUtils.dateOnly(now)).inDays;

    return Scaffold(
      appBar: AppBar(title: Text(court.name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
            '${court.city} · ${court.covered ? 'Techada' : 'Aire libre'} · ${cop(court.pricePerHour)}/h'),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Hoy')),
            ButtonSegment(value: 1, label: Text('Mañana')),
            ButtonSegment(value: 2, label: Text('+2 días')),
          ],
          selected: {dayIndex},
          onSelectionChanged: (v) => setState(() {
            day = DateUtils.dateOnly(now).add(Duration(days: v.first));
            hours = {};
          }),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var h = court.openHour; h < court.closeHour; h++)
            ChoiceChip(
              label: Text(hourLabel(h)),
              selected: hours.contains(h),
              onSelected: free(h)
                  ? (_) => setState(() => hours = BookingPolicy.toggleHour(hours, h))
                  : null,
            ),
        ]),
        const SizedBox(height: 8),
        Text('Toca horas seguidas para reservar hasta ${BookingPolicy.maxHours} horas.',
            style: Theme.of(context).textTheme.bodySmall),
        if (start != null) ...[
          const SizedBox(height: 16),
          Text('${hours.length} h · Total ${cop(total)}',
              style: Theme.of(context).textTheme.titleMedium),
          Text(BookingPolicy.isLastMinute(start, now)
              ? 'Reserva de último momento: anticipo del 30% obligatorio y sin cancelación.'
              : 'Cancelación gratis hasta 24 h antes.'),
          if (deposit > 0) Text('Anticipo a pagar: ${cop(deposit)}'),
        ],
        ReviewsSection(courtId: court.id),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: start == null
                ? null
                : () async {
                    final confirmed = deposit == 0;
                    // Con anticipo: avisar y llevar al pago. Si el jugador
                    // cierra el aviso no se crea la reserva ni se bloquea la hora.
                    if (!confirmed) {
                      final pay = await _askDeposit(
                        context,
                        deposit: deposit,
                        lastMinute: BookingPolicy.isLastMinute(start, now),
                      );
                      if (pay != true) return;
                    }
                    final id = 'b${ref.read(bookingsProvider).length + 1}';
                    ref.read(bookingsProvider.notifier).update((l) => [
                          ...l,
                          Booking(
                            id: id,
                            courtId: court.id,
                            start: start,
                            total: total,
                            hours: hours.length,
                            deposit: deposit,
                            status: confirmed
                                ? BookingStatus.confirmed
                                : BookingStatus.pendingPayment,
                            refundable: BookingPolicy.canCancelFree(start, now),
                          ),
                        ]);
                    ref.read(notificationsProvider.notifier).update((l) => [
                          ...l,
                          confirmed
                              ? 'Reserva confirmada en ${court.name}'
                              : 'Reserva en ${court.name}: paga el anticipo y sube tu comprobante',
                        ]);
                    if (!context.mounted) return;
                    if (confirmed) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Reserva confirmada')));
                      context.pop();
                    } else {
                      context.pushReplacement('/bookings/$id/pay');
                    }
                  },
            child: const Text('Confirmar reserva'),
          ),
        ),
      ),
    );
  }
}

/// Aviso previo a crear una reserva que exige anticipo.
/// Devuelve true si el jugador elige "Pagar anticipo".
Future<bool?> _askDeposit(
  BuildContext context, {
  required int deposit,
  required bool lastMinute,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.payments_outlined),
      title: const Text('Esta reserva requiere anticipo'),
      content: Text(
        lastMinute
            ? 'Por ser una reserva de último momento debes pagar un anticipo de ${cop(deposit)} (30%). Esta reserva no tiene cancelación.'
            : 'Para confirmar tu reserva debes pagar un anticipo de ${cop(deposit)} y subir el comprobante.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pagar anticipo')),
      ],
    ),
  );
}
