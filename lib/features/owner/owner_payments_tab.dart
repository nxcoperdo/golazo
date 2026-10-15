import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/payment_actions.dart';
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
    if (!await askApprove(context,
        title: '¿Aprobar este pago?', message: 'La reserva de ${p.payerName} quedará confirmada.')) {
      return;
    }
    if (!mounted) return;
    final ok = await guarded(context, () => ref.read(apiProvider).approvePayment(p.id), success: 'Pago aprobado');
    if (ok) _refresh();
  }

  Future<void> _reject(Payment p) async {
    final reason = await askRejectReason(context);
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
    return AppPage(
      kicker: 'Anticipos',
      title: 'Pagos',
      child: AsyncView<List<Payment>>(
        value: payments,
        onRetry: () => ref.invalidate(provider),
        builder: (all) {
          final list = _history ? all.where((p) => p.status != PaymentStatus.pending).toList() : all;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(provider);
              await ref.read(provider.future);
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
              SegmentedTabs<bool>(
                options: const [(false, 'Por revisar'), (true, 'Historial')],
                value: _history,
                onChanged: (v) => setState(() => _history = v),
              ),
              const SizedBox(height: 20),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text(_history ? 'Todavía no hay pagos.' : 'No hay comprobantes por revisar.',
                      textAlign: TextAlign.center, style: authText(14, weight: 500, color: AuthColors.muted)),
                )
              else
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
    );
  }
}
