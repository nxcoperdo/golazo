import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/payment_card.dart';
import '../../core/widgets/status_style.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

// ---------------- Pagos de mensualidad ----------------

class AdminPaymentsTab extends ConsumerStatefulWidget {
  const AdminPaymentsTab({super.key});

  @override
  ConsumerState<AdminPaymentsTab> createState() => _PaymentsState();
}

class _PaymentsState extends ConsumerState<AdminPaymentsTab> {
  bool _history = false;

  void _refresh() {
    ref.invalidate(adminPaymentsProvider(PaymentStatus.pending));
    ref.invalidate(adminPaymentsProvider(null));
    ref.invalidate(adminCourtsProvider);
    ref.invalidate(metricsProvider);
    ref.invalidate(transactionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final provider = adminPaymentsProvider(_history ? null : PaymentStatus.pending);
    final payments = ref.watch(provider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Por revisar')),
            ButtonSegment(value: true, label: Text('Historial')),
          ],
          selected: {_history},
          onSelectionChanged: (s) => setState(() => _history = s.first),
        ),
      ),
      Expanded(
        child: AsyncView<List<Payment>>(
          value: payments,
          onRetry: () => ref.invalidate(provider),
          emptyText: _history ? 'Todavía no hay pagos.' : 'No hay mensualidades por revisar.',
          isEmpty: (l) => (_history ? l.where((p) => p.status != PaymentStatus.pending) : l).isEmpty,
          builder: (all) {
            final list = _history ? all.where((p) => p.status != PaymentStatus.pending).toList() : all;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(provider);
                await ref.read(provider.future);
              },
              child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
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
      ),
    ]);
  }

  Future<void> _approve(Payment p) async {
    if (!await confirm(context,
        title: '¿Aprobar la mensualidad?',
        message: '${p.courtName} quedará activa y visible por 30 días.',
        okLabel: 'Aprobar')) {
      return;
    }
    if (!mounted) return;
    final ok = await guarded(context, () => ref.read(apiProvider).approveSubscription(p.id),
        success: 'Mensualidad aprobada');
    if (ok) _refresh();
  }

  Future<void> _reject(Payment p) async {
    final reason = await askText(context,
        title: 'Rechazar comprobante', hint: 'Motivo (se lo mostramos al dueño)', okLabel: 'Rechazar');
    if (reason == null || !mounted) return;
    final ok = await guarded(context, () => ref.read(apiProvider).rejectSubscription(p.id, reason: reason),
        success: 'Pago rechazado');
    if (ok) _refresh();
  }
}

// ---------------- Canchas ----------------

class AdminCourtsTab extends ConsumerWidget {
  const AdminCourtsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(adminCourtsProvider);

    Future<void> act(Future<void> Function() f, String ok) async {
      if (await guarded(context, f, success: ok)) {
        ref.invalidate(adminCourtsProvider);
        ref.invalidate(metricsProvider);
      }
    }

    return AsyncView<List<AdminCourt>>(
      value: courts,
      onRetry: () => ref.invalidate(adminCourtsProvider),
      emptyText: 'No hay canchas registradas.',
      isEmpty: (l) => l.isEmpty,
      builder: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminCourtsProvider);
          await ref.read(adminCourtsProvider.future);
        },
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final c in list)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(c.name, style: Theme.of(context).textTheme.titleMedium)),
                    StatusChip(courtStatusLabel(c.status), color: courtStatusColor(c.status)),
                  ]),
                  Text(c.city),
                  Text('Dueño: ${c.ownerName}${c.ownerPhone != null ? ' · ${c.ownerPhone}' : ''}'),
                  if (c.ownerEmail != null) Text(c.ownerEmail!),
                  Text(c.activeUntil != null ? 'Mensualidad hasta ${c.activeUntil}' : 'Sin mensualidad pagada'),
                  if (c.pendingSubscription)
                    Text('Tiene un pago de mensualidad por revisar',
                        style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
                  if (c.suspendedByAdmin) const Text('Suspendida por el administrador'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: c.status == CourtStatus.active
                        ? TextButton(
                            onPressed: () async {
                              if (await confirm(context,
                                  title: '¿Suspender la cancha?',
                                  message: 'Dejará de verse en el buscador y el dueño no podrá reactivarla.',
                                  okLabel: 'Suspender')) {
                                if (context.mounted) {
                                  await act(() => ref.read(apiProvider).suspendCourt(c.id), 'Cancha suspendida');
                                }
                              }
                            },
                            child: const Text('Suspender'),
                          )
                        : c.status == CourtStatus.suspended
                            ? TextButton(
                                onPressed: () =>
                                    act(() => ref.read(apiProvider).reactivateCourt(c.id), 'Cancha reactivada'),
                                child: const Text('Reactivar'),
                              )
                            : const SizedBox.shrink(),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------- Usuarios ----------------

class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _UsersState();
}

class _UsersState extends ConsumerState<AdminUsersTab> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() f, String ok) async {
    if (await guarded(context, f, success: ok)) {
      ref.invalidate(adminUsersProvider(_query));
      ref.invalidate(metricsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider(_query));
    final me = ref.watch(userIdProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar por nombre o correo',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
          onSubmitted: (v) => setState(() => _query = v.trim()),
        ),
      ),
      Expanded(
        child: AsyncView<List<AdminUser>>(
          value: users,
          onRetry: () => ref.invalidate(adminUsersProvider(_query)),
          emptyText: 'No se encontraron usuarios.',
          isEmpty: (l) => l.isEmpty,
          builder: (list) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(adminUsersProvider(_query));
              await ref.read(adminUsersProvider(_query).future);
            },
            child: ListView(children: [
              for (final u in list)
                ListTile(
                  leading: Icon(switch (u.role) {
                    Role.admin => Icons.admin_panel_settings,
                    Role.owner => Icons.storefront,
                    Role.player => Icons.person,
                  }),
                  title: Text(u.name),
                  subtitle: Text([
                    u.email ?? 'Sin correo',
                    if (u.phone != null) u.phone!,
                    if (u.suspended) 'Suspendido',
                    if (u.deleted) 'Eliminado',
                  ].join(' · ')),
                  trailing: u.role == Role.admin || u.deleted || u.id == me
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'delete') {
                              if (!await confirm(context,
                                  title: '¿Eliminar a ${u.name}?',
                                  message: 'Se borran sus datos personales y se cancelan sus reservas futuras.',
                                  okLabel: 'Eliminar')) {
                                return;
                              }
                              await _act(() => ref.read(apiProvider).deleteUser(u.id), 'Cuenta eliminada');
                            } else if (v == 'suspend') {
                              await _act(() => ref.read(apiProvider).suspendUser(u.id), 'Usuario suspendido');
                            } else {
                              await _act(() => ref.read(apiProvider).restoreUser(u.id), 'Usuario restaurado');
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: u.suspended ? 'restore' : 'suspend', child: Text(u.suspended ? 'Restaurar' : 'Suspender')),
                            const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                          ],
                        ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ---------------- Reseñas reportadas ----------------

class AdminReviewsTab extends ConsumerWidget {
  const AdminReviewsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reportedReviewsProvider);

    Future<void> act(Future<void> Function() f, String ok) async {
      if (await guarded(context, f, success: ok)) {
        ref.invalidate(reportedReviewsProvider);
        ref.invalidate(metricsProvider);
      }
    }

    return AsyncView<List<ReportedReview>>(
      value: reviews,
      onRetry: () => ref.invalidate(reportedReviewsProvider),
      emptyText: 'No hay reseñas reportadas.',
      isEmpty: (l) => l.isEmpty,
      builder: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reportedReviewsProvider);
          await ref.read(reportedReviewsProvider.future);
        },
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final r in list)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.courtName} · ${'★' * r.stars}', style: Theme.of(context).textTheme.titleMedium),
                  Text('Por ${r.authorName} · ${r.reports} reporte${r.reports == 1 ? '' : 's'}'),
                  if (r.body != null) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r.body!)),
                  if (r.reasons.isNotEmpty) Text('Motivos: ${r.reasons.join(', ')}'),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => act(() => ref.read(apiProvider).dismissReview(r.id), 'Reportes descartados'),
                      child: const Text('Conservar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        if (!await confirm(context,
                            title: '¿Ocultar la reseña?',
                            message: 'Dejará de verse y de contar en la calificación.',
                            okLabel: 'Ocultar')) {
                          return;
                        }
                        if (context.mounted) await act(() => ref.read(apiProvider).hideReview(r.id), 'Reseña oculta');
                      },
                      child: const Text('Ocultar'),
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------- Resumen ----------------

class AdminSummaryTab extends ConsumerWidget {
  const AdminSummaryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(metricsProvider);
    final tx = ref.watch(transactionsProvider);

    Widget tile(String label, String value) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(title: Text(label), trailing: Text(value, style: Theme.of(context).textTheme.titleLarge)),
        );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(metricsProvider);
        ref.invalidate(transactionsProvider);
        await ref.read(metricsProvider.future);
      },
      child: ListView(padding: const EdgeInsets.all(12), children: [
        metrics.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorRetry(message: errorMessage(e), onRetry: () => ref.invalidate(metricsProvider)),
          data: (m) => Column(children: [
            tile('Canchas activas', '${m.activeCourts}'),
            tile('Canchas pendientes', '${m.pendingCourts}'),
            tile('Jugadores', '${m.players}'),
            tile('Dueños', '${m.owners}'),
            tile('Reservas confirmadas (30 días)', '${m.bookings30d}'),
            tile('Valor de reservas (30 días)', cop(m.bookingsValue30d)),
            tile('Mensualidades este mes', cop(m.subscriptionsThisMonth)),
            tile('Mensualidades totales', cop(m.subscriptionsTotal)),
            tile('Mensualidades por revisar', '${m.pendingSubscriptionPayments}'),
            tile('Reseñas reportadas', '${m.reportedReviews}'),
          ]),
        ),
        const SizedBox(height: 8),
        Text('Transacciones aprobadas', style: Theme.of(context).textTheme.titleMedium),
        tx.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorRetry(message: errorMessage(e), onRetry: () => ref.invalidate(transactionsProvider)),
          data: (t) => t.items.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Aún no hay transacciones.'))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${t.count} transacciones · ${cop(t.totalAmount)}'),
                  ),
                  for (final i in t.items)
                    ListTile(
                      leading: Icon(i.kind == 'subscription' ? Icons.workspace_premium : Icons.sports_soccer),
                      title: Text('${i.kind == 'subscription' ? 'Mensualidad' : 'Reserva'} · ${i.courtName}'),
                      subtitle: Text('${i.payerName} · ${dayLabel(i.date)}'),
                      trailing: Text(cop(i.amount)),
                    ),
                ]),
        ),
      ]),
    );
  }
}
