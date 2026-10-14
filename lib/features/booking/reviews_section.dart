import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/ui.dart';
import '../../data/providers.dart';

/// Reseñas de una cancha, con opción de reportar una al administrador.
class ReviewsSection extends ConsumerWidget {
  const ReviewsSection({super.key, required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(courtReviewsProvider(courtId));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      Text('Reseñas', style: Theme.of(context).textTheme.titleMedium),
      reviews.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(errorMessage(e))),
        data: (list) => list.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aún no hay reseñas'))
            : Column(children: [
                for (final r in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${'★' * r.stars}${'☆' * (5 - r.stars)}  ${r.authorName}'),
                    subtitle: r.body == null ? null : Text(r.body!),
                    trailing: IconButton(
                      icon: const Icon(Icons.flag_outlined),
                      tooltip: 'Reportar',
                      onPressed: () async {
                        if (!await confirm(context, title: '¿Reportar esta reseña?', okLabel: 'Reportar')) return;
                        if (!context.mounted) return;
                        await guarded(context, () => ref.read(apiProvider).reportReview(r.id),
                            success: 'Gracias, la revisaremos');
                      },
                    ),
                  ),
              ]),
      ),
    ]);
  }
}

/// Diálogo para calificar una reserva ya jugada. Devuelve true si se publicó.
Future<bool> showReviewDialog(BuildContext context, WidgetRef ref, String bookingId, String courtId) async {
  var stars = 5;
  final text = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Califica la cancha'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                icon: Icon(i <= stars ? Icons.star : Icons.star_border),
                onPressed: () => setState(() => stars = i),
              ),
          ]),
          TextField(
            controller: text,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publicar')),
        ],
      ),
    ),
  );
  final body = text.text;
  text.dispose();
  if (ok != true || !context.mounted) return false;
  final done = await guarded(
    context,
    () => ref.read(apiProvider).reviewBooking(bookingId, stars, body),
    success: '¡Gracias por tu reseña!',
  );
  if (done) {
    ref.invalidate(courtReviewsProvider(courtId));
    ref.invalidate(courtDetailProvider(courtId));
    ref.invalidate(myBookingsProvider);
  }
  return done;
}
