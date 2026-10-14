import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../format.dart';
import 'proof_image.dart';
import 'status_style.dart';
import 'ui.dart';

/// Tarjeta de un pago con su comprobante. Con [onApprove]/[onReject] muestra
/// los botones (solo mientras está por revisar). La usan el dueño y el admin.
class PaymentCard extends StatelessWidget {
  const PaymentCard({super.key, required this.payment, this.onApprove, this.onReject});

  final Payment payment;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(p.isSubscription ? 'Mensualidad · ${p.courtName}' : p.courtName,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            StatusChip(paymentStatusLabel(p.status), color: paymentStatusColor(p.status)),
          ]),
          const SizedBox(height: 4),
          Text('${p.payerName}${p.payerPhone != null ? ' · ${p.payerPhone}' : ''}'),
          if (p.startAt != null && p.hours != null) Text(rangeLabel(p.startAt!, p.hours!)),
          Text('Monto: ${cop(p.amount)} · enviado ${dayLabel(p.createdAt)} ${timeLabel(p.createdAt)}'),
          if (p.rejectReason != null) Text('Motivo del rechazo: ${p.rejectReason}'),
          const SizedBox(height: 8),
          ProofImage(paymentId: p.id),
          if (onApprove != null || onReject != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (onReject != null) TextButton(onPressed: onReject, child: const Text('Rechazar')),
                const SizedBox(width: 8),
                if (onApprove != null) FilledButton(onPressed: onApprove, child: const Text('Aprobar')),
              ]),
            ),
        ]),
      ),
    );
  }
}
