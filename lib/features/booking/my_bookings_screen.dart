import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/format.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import 'payment_info.dart';
import 'reviews_section.dart';

String _label(BookingStatus s) => switch (s) {
      BookingStatus.pendingPayment => 'Falta comprobante',
      BookingStatus.pendingReview => 'Pago en revisión',
      BookingStatus.confirmed => 'Confirmada',
      BookingStatus.rejected => 'Pago rechazado',
      BookingStatus.cancelled => 'Cancelada',
    };

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingsProvider);

    void update(Booking b) => ref
        .read(bookingsProvider.notifier)
        .update((l) => [for (final x in l) x.id == b.id ? b : x]);

    Future<void> attachProof(Booking b) async {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      update(b.copyWith(
          proofPath: file.path, status: BookingStatus.pendingReview));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mis reservas')),
      body: bookings.isEmpty
          ? const Center(child: Text('Aún no tienes reservas'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final b in bookings)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              ref
                                  .watch(courtsProvider)
                                  .firstWhere((c) => c.id == b.courtId)
                                  .name,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              '${b.start.day}/${b.start.month} · ${hourLabel(b.start.hour)}${b.hours > 1 ? ' – ${hourLabel(b.start.hour + b.hours)}' : ''} · ${cop(b.total)}'),
                          if (b.deposit > 0)
                            Text('Anticipo: ${cop(b.deposit)}'),
                          const SizedBox(height: 4),
                          Chip(label: Text(_label(b.status))),
                          if (b.status == BookingStatus.pendingPayment ||
                              b.status == BookingStatus.rejected)
                            PaymentInfo(
                              methods: ref
                                  .watch(courtsProvider)
                                  .firstWhere((c) => c.id == b.courtId)
                                  .paymentMethods,
                              amount: b.deposit > 0 ? b.deposit : b.total,
                            ),
                          Row(children: [
                            if (b.status == BookingStatus.pendingPayment ||
                                b.status == BookingStatus.rejected)
                              TextButton.icon(
                                onPressed: () => attachProof(b),
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Subir comprobante'),
                              ),
                            if (b.status == BookingStatus.confirmed &&
                                b.start.isBefore(DateTime.now()) &&
                                !ref.watch(reviewsProvider).any((r) =>
                                    r.courtId == b.courtId &&
                                    r.author == currentUserName))
                              TextButton.icon(
                                onPressed: () =>
                                    showReviewDialog(context, ref, b.courtId),
                                icon: const Icon(Icons.star_outline),
                                label: const Text('Calificar'),
                              ),
                            if (b.status != BookingStatus.cancelled &&
                                b.refundable)
                              TextButton(
                                onPressed: () => update(
                                    b.copyWith(status: BookingStatus.cancelled)),
                                child: const Text('Cancelar gratis'),
                              ),
                          ]),
                          if (!b.refundable &&
                              b.status != BookingStatus.cancelled)
                            const Text('Sin cancelación gratuita',
                                style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
