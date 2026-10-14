import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/status_style.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../player/courts_screen.dart' show CourtImage;

/// Canchas del dueño con su estado, y acceso a crear una nueva.
class OwnerCourtsTab extends ConsumerWidget {
  const OwnerCourtsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(ownerCourtsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis canchas'),
        actions: [
          IconButton(
            tooltip: 'Estadísticas',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => context.push('/owner/stats'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/owner/courts/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cancha'),
      ),
      body: AsyncView<List<Court>>(
        value: courts,
        onRetry: () => ref.invalidate(ownerCourtsProvider),
        emptyText: 'Aún no tienes canchas.\nPublica la primera con el botón "Nueva cancha".',
        isEmpty: (l) => l.isEmpty,
        builder: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(ownerCourtsProvider);
            await ref.read(ownerCourtsProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final c = list[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => context.push('/owner/courts/${c.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CourtImage(url: c.photoUrl, height: 120),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c.name, style: Theme.of(context).textTheme.titleMedium)),
                          StatusChip(courtStatusLabel(c.status), color: courtStatusColor(c.status)),
                        ]),
                        Text('${c.city} · ${cop(c.pricePerHour)}/h'),
                        if (c.status == CourtStatus.pending)
                          Text('Paga la mensualidad para que aparezca en el buscador.',
                              style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
