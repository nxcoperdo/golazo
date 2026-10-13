import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';

const currentUserName = 'Tú';

/// Reseñas de una cancha, con opción de reportar una al administrador.
class ReviewsSection extends ConsumerWidget {
  const ReviewsSection({super.key, required this.courtId});
  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews =
        ref.watch(reviewsProvider).where((r) => r.courtId == courtId).toList();
    final reported = ref.watch(reportedReviewsProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      Text('Reseñas', style: Theme.of(context).textTheme.titleMedium),
      if (reviews.isEmpty) const Text('Aún no hay reseñas'),
      for (final r in reviews)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${'★' * r.stars}  ${r.author}'),
          subtitle: Text(r.text),
          trailing: r.author == currentUserName || reported.any((x) => x.id == r.id)
              ? null
              : IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: 'Reportar',
                  onPressed: () {
                    ref.read(reportedReviewsProvider.notifier).update((l) => [...l, r]);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Reseña reportada')));
                  },
                ),
        ),
    ]);
  }
}

/// Diálogo para calificar una cancha tras jugar.
Future<void> showReviewDialog(BuildContext context, WidgetRef ref, String courtId) async {
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
          TextField(controller: text, maxLines: 3, decoration: const InputDecoration(labelText: 'Comentario')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publicar')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  ref.read(reviewsProvider.notifier).update((l) => [
        ...l,
        Review(
            id: 'r${l.length + 1}',
            courtId: courtId,
            author: currentUserName,
            stars: stars,
            text: text.text.trim()),
      ]);
}
