import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../format.dart';
import 'auth_ui.dart';
import 'design.dart';
import 'proof_image.dart';
import 'status_style.dart';

/// Tarjeta de un pago con la miniatura de su comprobante. Con [onApprove]/[onReject] muestra
/// los botones (solo mientras está por revisar). La usan el dueño (anticipos) y el admin (mensualidades).
class PaymentCard extends StatelessWidget {
  const PaymentCard({super.key, required this.payment, this.onApprove, this.onReject});

  final Payment payment;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final detail = p.startAt != null && p.hours != null
        ? '${p.courtName} · ${rangeLabel(p.startAt!, p.hours!)}'
        : p.courtName;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p.isSubscription || p.status != PaymentStatus.pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              if (p.isSubscription) const StatusPill('Mensualidad', PillTone.amber),
              const Spacer(),
              if (p.status != PaymentStatus.pending) StatusPill(paymentStatusLabel(p.status), paymentTone(p.status)),
            ]),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProofThumb(paymentId: p.id),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.payerName, style: authText(14, weight: 800)),
              const SizedBox(height: 4),
              Text(detail, style: authText(12, weight: 500, color: const Color(0xFF6C7B72), height: 1.4)),
              if (p.payerPhone != null)
                Text(p.payerPhone!, style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
              const SizedBox(height: 8),
              Text(cop(p.amount), style: authText(18, weight: 800)),
              Text('Enviado ${dayLabel(p.createdAt)} · ${timeLabel(p.createdAt)}',
                  style: authText(10, weight: 600, color: const Color(0xFF96A099))),
            ]),
          ),
        ]),
        if (p.rejectReason != null) ...[
          const SizedBox(height: 12),
          NoticeBox('Motivo del rechazo: ${p.rejectReason}', bg: const Color(0xFFFDECEA), fg: const Color(0xFF8A2D26)),
        ],
        if (onApprove != null || onReject != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            if (onReject != null) Expanded(child: OutlineAction(label: 'Rechazar', onPressed: onReject)),
            if (onReject != null && onApprove != null) const SizedBox(width: 8),
            if (onApprove != null) Expanded(child: SolidAction(label: 'Aprobar', onPressed: onApprove)),
          ]),
        ],
      ]),
    );
  }
}
