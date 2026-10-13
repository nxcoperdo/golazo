import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/format.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import 'payment_info.dart';

/// Pantalla de pago del anticipo: cuentas del dueño y subida del comprobante.
class PayDepositScreen extends ConsumerWidget {
  const PayDepositScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking =
        ref.watch(bookingsProvider).where((b) => b.id == bookingId).firstOrNull;
    if (booking == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('Reserva no encontrada')));
    }
    final court =
        ref.watch(courtsProvider).firstWhere((c) => c.id == booking.courtId);
    final sent = booking.status == BookingStatus.pendingReview;

    Future<void> upload() async {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      ref.read(bookingsProvider.notifier).update((l) => [
            for (final x in l)
              x.id == booking.id
                  ? x.copyWith(
                      proofPath: file.path, status: BookingStatus.pendingReview)
                  : x
          ]);
      ref.read(notificationsProvider.notifier).update((l) => [
            ...l,
            'Comprobante enviado a ${court.name}. Te avisaremos cuando lo revisen.',
          ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pagar anticipo')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(court.name, style: Theme.of(context).textTheme.titleLarge),
        Text(
            '${booking.start.day}/${booking.start.month} · ${hourLabel(booking.start.hour)} – ${hourLabel(booking.start.hour + booking.hours)}'),
        const SizedBox(height: 8),
        Text('Total ${cop(booking.total)} · Anticipo ${cop(booking.deposit)}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!sent) ...[
          const Text(
              '1. Transfiere el anticipo a una de estas cuentas.\n2. Sube la captura del comprobante.'),
          PaymentInfo(methods: court.paymentMethods, amount: booking.deposit),
        ] else
          const Card(
            child: ListTile(
              leading: Icon(Icons.hourglass_top),
              title: Text('Comprobante enviado'),
              subtitle: Text('El dueño lo revisará y tu reserva quedará confirmada.'),
            ),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: sent
              ? FilledButton(
                  onPressed: () => context.pushReplacement('/bookings'),
                  child: const Text('Ver mis reservas'))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton.icon(
                    onPressed: upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Subir comprobante'),
                  ),
                  TextButton(
                      onPressed: () => context.pushReplacement('/bookings'),
                      child: const Text('Pagar más tarde')),
                ]),
        ),
      ),
    );
  }
}
