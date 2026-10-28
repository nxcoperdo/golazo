import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
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

enum _View { review, refunds, history }

class _State extends ConsumerState<OwnerPaymentsTab> {
  _View _view = _View.review;
  bool get _history => _view == _View.history;

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

  Future<void> _markRefund(Refund r) async {
    final v = await showFormSheet(
      context,
      title: '¿Ya devolviste el dinero?',
      subtitle: 'Devuélvele ${cop(r.amount)} a ${r.playerName} por transferencia o efectivo y luego márcalo aquí. Le avisaremos.',
      primaryLabel: 'Marcar como devuelto',
      initial: [''],
      fields: [
        (c) => AuthField(label: 'Nota (opcional)', icon: Icons.notes_outlined, controller: c, hint: 'Ej.: Nequi, 25 oct'),
      ],
    );
    if (v == null || !mounted) return;
    final ok = await guarded(context, () => ref.read(apiProvider).markRefundDone(r.id, note: v[0]),
        success: 'Devolución registrada');
    if (ok) ref.invalidate(ownerRefundsProvider);
  }

  Widget _tabs() => SegmentedTabs<_View>(
        options: const [(_View.review, 'Por revisar'), (_View.refunds, 'Devoluciones'), (_View.history, 'Historial')],
        value: _view,
        onChanged: (v) => setState(() => _view = v),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Text(text, textAlign: TextAlign.center, style: authText(14, weight: 500, color: AuthColors.muted)),
      );

  Widget _refundsView() {
    final refunds = ref.watch(ownerRefundsProvider);
    return AsyncView<List<Refund>>(
      value: refunds,
      onRetry: () => ref.invalidate(ownerRefundsProvider),
      builder: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ownerRefundsProvider);
          await ref.read(ownerRefundsProvider.future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
          _tabs(),
          const SizedBox(height: 12),
          Text(
            'Cuando un jugador cancela una reserva con anticipo aprobado, debes devolvérselo por fuera de la app. Aquí queda el registro.',
            style: authText(12, weight: 500, color: AuthColors.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            _empty('No hay devoluciones.')
          else
            for (final r in list) _RefundCard(refund: r, onDone: r.done ? null : () => _markRefund(r)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_view == _View.refunds) {
      return AppPage(kicker: 'Anticipos', title: 'Pagos', child: _refundsView());
    }
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
              _tabs(),
              const SizedBox(height: 20),
              if (list.isEmpty)
                _empty(_history ? 'Todavía no hay pagos.' : 'No hay comprobantes por revisar.')
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

/// Devolución de un anticipo: quién, cuánto, y el botón para marcarla como hecha.
class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.refund, required this.onDone});

  final Refund refund;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final r = refund;
    final detail = r.startAt != null && r.hours != null ? '${r.courtName} · ${rangeLabel(r.startAt!, r.hours!)}' : r.courtName;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusPill(r.done ? 'Devuelto' : 'Por devolver', r.done ? PillTone.green : PillTone.amber),
          const Spacer(),
          Text(cop(r.amount), style: authText(18, weight: 800)),
        ]),
        const SizedBox(height: 12),
        Text(r.playerName, style: authText(14, weight: 800)),
        const SizedBox(height: 4),
        Text(detail, style: authText(12, weight: 500, color: const Color(0xFF6C7B72), height: 1.4)),
        if (r.playerPhone != null)
          Text(r.playerPhone!, style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
        if (r.done && r.note != null) ...[
          const SizedBox(height: 8),
          Text('Nota: ${r.note}', style: authText(11, weight: 600, color: const Color(0xFF96A099))),
        ],
        if (onDone != null) ...[
          const SizedBox(height: 16),
          SolidAction(label: 'Marcar como devuelto', onPressed: onDone),
        ],
      ]),
    );
  }
}
