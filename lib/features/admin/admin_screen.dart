import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';

/// Panel del administrador de Golazo.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminState();
}

class _AdminState extends ConsumerState<AdminScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    const titles = ['Canchas', 'Usuarios', 'Reseñas', 'Transacciones', 'Métricas'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[tab]), actions: [
        IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Salir',
            onPressed: () => context.go('/')),
      ]),
      body: switch (tab) {
        0 => const _CourtsTab(),
        1 => const _UsersTab(),
        2 => const _ReviewsTab(),
        3 => const _TransactionsTab(),
        _ => const _MetricsTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.stadium), label: 'Canchas'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Usuarios'),
          NavigationDestination(icon: Icon(Icons.flag), label: 'Reseñas'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Pagos'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Métricas'),
        ],
      ),
    );
  }
}

class _CourtsTab extends ConsumerWidget {
  const _CourtsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(courtsProvider);
    final subs = ref.watch(subscriptionsProvider);

    void setStatus(Court c, CourtStatus s) => ref
        .read(courtsProvider.notifier)
        .update((l) => [for (final x in l) x.id == c.id ? c.copyWith(status: s) : x]);

    void resolve(Subscription s, Court c, ReviewState r) {
      ref.read(subscriptionsProvider.notifier).update(
          (l) => [for (final x in l) x.id == s.id ? s.copyWith(state: r) : x]);
      // Al aprobar la mensualidad la cancha pasa a activa.
      if (r == ReviewState.approved) setStatus(c, CourtStatus.active);
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final c in courts)
        Builder(builder: (_) {
          final sub = subs.where((s) => s.courtId == c.id && s.state == ReviewState.pending).lastOrNull;
          final active = c.status == CourtStatus.active;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${c.city} · ${active ? 'Activa' : 'Pendiente / no visible'}'),
                if (sub != null) ...[
                  const SizedBox(height: 8),
                  Text('Mensualidad ${cop(sub.amount)} por aprobar'),
                  if (sub.proofPath != null)
                    Image.file(File(sub.proofPath!),
                        height: 140,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                        onPressed: () => resolve(sub, c, ReviewState.rejected),
                        child: const Text('Rechazar')),
                    FilledButton(
                        onPressed: () => resolve(sub, c, ReviewState.approved),
                        child: const Text('Aprobar y activar')),
                  ]),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setStatus(
                          c, active ? CourtStatus.pending : CourtStatus.active),
                      child: Text(active ? 'Desactivar' : 'Activar manualmente'),
                    ),
                  ),
              ]),
            ),
          );
        }),
    ]);
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    void update(List<AppUser> Function(List<AppUser>) f) =>
        ref.read(usersProvider.notifier).update(f);

    return ListView(children: [
      for (final u in users)
        ListTile(
          title: Text(u.name),
          subtitle: Text('${u.email}${u.suspended ? ' · Suspendido' : ''}'),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'suspend') {
                update((l) => [for (final x in l) x.id == u.id ? u.copyWith(suspended: !u.suspended) : x]);
              } else {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('¿Eliminar a ${u.name}?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
                    ],
                  ),
                );
                if (ok == true) update((l) => l.where((x) => x.id != u.id).toList());
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'suspend', child: Text(u.suspended ? 'Reactivar' : 'Suspender')),
              const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
        ),
    ]);
  }
}

class _ReviewsTab extends ConsumerWidget {
  const _ReviewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reportedReviewsProvider);
    final courts = ref.watch(courtsProvider);
    if (reviews.isEmpty) return const Center(child: Text('Sin reseñas reportadas'));

    void keep(Review r) => ref
        .read(reportedReviewsProvider.notifier)
        .update((l) => l.where((x) => x.id != r.id).toList());

    void delete(Review r) {
      keep(r);
      ref
          .read(reviewsProvider.notifier)
          .update((l) => l.where((x) => x.id != r.id).toList());
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final r in reviews)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${courts.firstWhere((c) => c.id == r.courtId).name} · ${'★' * r.stars}'),
              Text('Por ${r.author}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(r.text),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => keep(r), child: const Text('Mantener')),
                FilledButton(onPressed: () => delete(r), child: const Text('Eliminar reseña')),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

class _TransactionsTab extends ConsumerWidget {
  const _TransactionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(courtsProvider);
    String name(String id) => courts.firstWhere((c) => c.id == id).name;

    final rows = <(DateTime?, String, String, int)>[
      for (final b in ref.watch(bookingsProvider).where((b) => b.status == BookingStatus.confirmed))
        (b.start, 'Reserva', name(b.courtId), b.deposit > 0 ? b.deposit : b.total),
      for (final s in ref.watch(subscriptionsProvider).where((s) => s.state == ReviewState.approved))
        (null, 'Mensualidad', name(s.courtId), s.amount),
    ];
    if (rows.isEmpty) return const Center(child: Text('Aún no hay transacciones'));

    return ListView(children: [
      for (final r in rows)
        ListTile(
          leading: Icon(r.$2 == 'Reserva' ? Icons.sports_soccer : Icons.workspace_premium),
          title: Text('${r.$2} · ${r.$3}'),
          subtitle: Text(r.$1 == null ? 'Suscripción' : '${r.$1!.day}/${r.$1!.month} ${hourLabel(r.$1!.hour)}'),
          trailing: Text(cop(r.$4)),
        ),
    ]);
  }
}

class _MetricsTab extends ConsumerWidget {
  const _MetricsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(courtsProvider);
    final bookings = ref.watch(bookingsProvider);
    final subs = ref.watch(subscriptionsProvider);
    final confirmed = bookings.where((b) => b.status == BookingStatus.confirmed);
    final subIncome = subs.where((s) => s.state == ReviewState.approved).fold<int>(0, (a, s) => a + s.amount);

    Widget tile(String l, String v) => Card(
        child: ListTile(title: Text(l), trailing: Text(v, style: Theme.of(context).textTheme.titleLarge)));

    return ListView(padding: const EdgeInsets.all(12), children: [
      tile('Canchas activas', '${courts.where((c) => c.status == CourtStatus.active).length}'),
      tile('Canchas pendientes', '${courts.where((c) => c.status == CourtStatus.pending).length}'),
      tile('Jugadores', '${ref.watch(usersProvider).length}'),
      tile('Reservas confirmadas', '${confirmed.length}'),
      tile('Ingresos por mensualidades', cop(subIncome)),
    ]);
  }
}
