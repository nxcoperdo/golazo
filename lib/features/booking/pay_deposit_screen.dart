import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'payment_info.dart';

/// Pago del anticipo: cuentas del dueño y subida del comprobante.
class PayDepositScreen extends ConsumerStatefulWidget {
  const PayDepositScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  ConsumerState<PayDepositScreen> createState() => _PayState();
}

class _PayState extends ConsumerState<PayDepositScreen> {
  bool _busy = false;

  Future<void> _upload() async {
    final img = await pickImage(context);
    if (img == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await guarded(
      context,
      () => ref.read(apiProvider).uploadBookingProof(widget.bookingId, img.bytes, img.filename),
      success: 'Comprobante enviado',
    );
    if (ok) {
      ref.invalidate(bookingProvider(widget.bookingId));
      ref.invalidate(myBookingsProvider);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingProvider(widget.bookingId));
    return Scaffold(
      appBar: AppBar(title: const Text('Pagar anticipo')),
      body: AsyncView<Booking>(
        value: booking,
        onRetry: () => ref.invalidate(bookingProvider(widget.bookingId)),
        builder: (b) {
          final sent = b.status == BookingStatus.pendingReview;
          final done = b.status == BookingStatus.confirmed;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(b.courtName, style: Theme.of(context).textTheme.titleLarge),
            Text(rangeLabel(b.startAt, b.hours)),
            const SizedBox(height: 8),
            Text('Total ${cop(b.total)} · Anticipo ${cop(b.deposit)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (b.status == BookingStatus.rejected)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.error_outline),
                  title: Text('Tu comprobante fue rechazado'),
                  subtitle: Text('Revisa el valor y la cuenta, y sube uno nuevo para conservar tu hora.'),
                ),
              ),
            if (b.status == BookingStatus.cancelled)
              const Card(child: ListTile(title: Text('Esta reserva fue cancelada')))
            else if (sent)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.hourglass_top),
                  title: Text('Comprobante enviado'),
                  subtitle: Text('El dueño lo revisará y tu reserva quedará confirmada.'),
                ),
              )
            else if (done)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('¡Reserva confirmada!'),
                ),
              )
            else ...[
              const Text('1. Transfiere el anticipo a una de estas cuentas.\n2. Sube la captura del comprobante.'),
              PaymentInfo(methods: b.paymentMethods, amount: b.deposit),
              Text(
                'Si no subes el comprobante a tiempo, la hora se libera automáticamente.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ]);
        },
      ),
      bottomNavigationBar: booking.hasValue ? _bottom(booking.value!) : null,
    );
  }

  Widget _bottom(Booking b) {
    final canUpload = b.status == BookingStatus.pendingPayment || b.status == BookingStatus.rejected;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: canUpload
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file),
                  label: const Text('Subir comprobante'),
                ),
                TextButton(
                    onPressed: () => context.go('/home?tab=1'), child: const Text('Pagar más tarde')),
              ])
            : FilledButton(
                onPressed: () => context.go('/home?tab=1'),
                child: const Text('Ver mis reservas'),
              ),
      ),
    );
  }
}
