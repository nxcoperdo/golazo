import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/async_view.dart';
import '../../core/widgets/payment_card.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Comprobantes de pago de las reservas: por revisar e historial.
class OwnerPaymentsTab extends ConsumerStatefulWidget {
  const OwnerPaymentsTab({super.key});

  @override
  ConsumerState<OwnerPaymentsTab> createState() => _State();
}

class _State extends ConsumerState<OwnerPaymentsTab> {
  bool _history = false;

  void _refresh() {
    ref.invalidate(ownerPaymentsProvider(PaymentStatus.pending));
    ref.invalidate(ownerPaymentsProvider(null));
    ref.invalidate(ownerBookingsProvider(14));
  }

  Future<void> _approve(Payment p) async {
    if (!await confirm(context,
        title: '¿Aprobar este pago?',
        message: 'La reserva de ${p.payerName} quedará confirmada.',
        okLabel: 'Aprobar')) {
      return;
    }
    if (!mounted) return;
    final ok = await guarded(context, () => ref.read(apiProvider).approvePayment(p.id), success: 'Pago aprobado');
    if (ok) _refresh();
  }

  Future<void> _reject(Payment p) async {
    final reason = await askText(context,
        title: 'Rechazar comprobante', hint: 'Motivo (se lo mostramos al jugador)', okLabel: 'Rechazar');
    if (reason == null || !mounted) return;
    final ok = await guarded(
      context,
      () => ref.read(apiProvider).rejectPayment(p.id, reason: reason),
      success: 'Pago rechazado',
    );
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ownerPaymentsProvider(_history ? null : PaymentStatus.pending);
    final payments = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pagos')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Por revisar')),
              ButtonSegment(value: true, label: Text('Historial')),
            ],
            selected: {_history},
            onSelectionChanged: (s) => setState(() => _history = s.first),
          ),
        ),
        Expanded(
          child: AsyncView<List<Payment>>(
            value: payments,
            onRetry: () => ref.invalidate(provider),
            emptyText: _history ? 'Todavía no hay pagos.' : 'No hay comprobantes por revisar.',
            isEmpty: (l) => (_history ? l.where((p) => p.status != PaymentStatus.pending) : l).isEmpty,
            builder: (all) {
              final list = _history ? all.where((p) => p.status != PaymentStatus.pending).toList() : all;
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(provider);
                  await ref.read(provider.future);
                },
                child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final p in list)
                    PaymentCard(
                      payment: p,
                      onApprove: p.status == PaymentStatus.pending ? () => _approve(p) : null,
                      onReject: p.status == PaymentStatus.pending ? () => _reject(p) : null,
                    ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
