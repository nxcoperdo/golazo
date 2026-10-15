import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/payment_actions.dart';
import '../../core/widgets/payment_card.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Botones del encabezado del admin: avisos (con contador) y perfil.
List<Widget> _adminActions(BuildContext context, WidgetRef ref) => [
      HeaderIconButton(
        icon: Icons.notifications_none,
        tooltip: 'Avisos',
        badge: ref.watch(notificationsProvider).value?.unread ?? 0,
        onTap: () => context.push('/notifications'),
      ),
      HeaderIconButton(icon: Icons.person_outline, tooltip: 'Mi perfil', dark: true, onTap: () => context.push('/profile')),
    ];

Widget _empty(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Text(text, textAlign: TextAlign.center, style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5)),
    );

/// Hoja de confirmación de una acción del admin. Devuelve true si acepta.
Future<bool> _confirmSheet(BuildContext context, {required String title, String? message, required String okLabel, bool danger = true}) async {
  final ok = await showAppSheet<bool>(
    context,
    builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeading(title, subtitle: message),
      SheetActions(primaryLabel: okLabel, danger: danger, onPrimary: () => Navigator.pop(sheet, true)),
    ]),
  );
  return ok == true;
}

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
    return AppPage(
      kicker: 'Administración',
      title: 'Pagos',
      actions: _adminActions(context, ref),
      child: AsyncView<List<Payment>>(
        value: payments,
        onRetry: () => ref.invalidate(provider),
        builder: (all) {
          final list = _history ? all.where((p) => p.status != PaymentStatus.pending).toList() : all;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(provider);
              await ref.read(provider.future);
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
              SegmentedTabs<bool>(
                options: const [(false, 'Por revisar'), (true, 'Historial')],
                value: _history,
                onChanged: (v) => setState(() => _history = v),
              ),
              const SizedBox(height: 20),
              if (list.isEmpty)
                _empty(_history ? 'Todavía no hay pagos.' : 'No hay mensualidades por revisar.')
              else
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
    );
  }

  Future<void> _approve(Payment p) async {
    if (!await askApprove(context,
        title: '¿Aprobar la mensualidad?', message: '${p.courtName} quedará activa y visible por 30 días.')) {
      return;
    }
    if (!mounted) return;
    final ok = await guarded(context, () => ref.read(apiProvider).approveSubscription(p.id),
        success: 'Mensualidad aprobada');
    if (ok) _refresh();
  }

  Future<void> _reject(Payment p) async {
    final reason = await askRejectReason(context);
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

    return AppPage(
      kicker: 'Administración',
      title: 'Canchas',
      actions: _adminActions(context, ref),
      child: AsyncView<List<AdminCourt>>(
        value: courts,
        onRetry: () => ref.invalidate(adminCourtsProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminCourtsProvider);
            await ref.read(adminCourtsProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
            if (list.isEmpty) _empty('No hay canchas registradas.'),
            for (final c in list)
              SoftCard(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                radius: 20,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name, style: authText(14, weight: 800)),
                        const SizedBox(height: 4),
                        Text('Dueño: ${c.ownerName}${c.ownerPhone != null ? ' · ${c.ownerPhone}' : ''}',
                            style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
                        Text(c.city, style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
                        Text(c.activeUntil != null ? 'Mensualidad hasta ${c.activeUntil}' : 'Sin mensualidad pagada',
                            style: authText(11, weight: 500, color: const Color(0xFF96A099))),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (c.status) {
                          CourtStatus.active => const Color(0xFF48A35F),
                          CourtStatus.pending => const Color(0xFFE1A72D),
                          CourtStatus.suspended => const Color(0xFFD1473F),
                        },
                      ),
                    ),
                  ]),
                  if (c.pendingSubscription) ...[
                    const SizedBox(height: 12),
                    const NoticeBox('Tiene una mensualidad por revisar', bg: Color(0xFFFFF4D2), fg: Color(0xFF765B12)),
                  ],
                  if (c.suspendedByAdmin) ...[
                    const SizedBox(height: 12),
                    const NoticeBox('Suspendida por el administrador', bg: Color(0xFFFDECEA), fg: Color(0xFF8A2D26)),
                  ],
                  if (c.status == CourtStatus.active)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFB13C35), padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                      onPressed: () async {
                        if (await _confirmSheet(context,
                            title: '¿Suspender la cancha?',
                            message: 'Dejará de verse en el buscador y el dueño no podrá reactivarla.',
                            okLabel: 'Suspender')) {
                          if (context.mounted) await act(() => ref.read(apiProvider).suspendCourt(c.id), 'Cancha suspendida');
                        }
                      },
                      child: Text('Suspender', style: authText(12, weight: 800, color: const Color(0xFFB13C35))),
                    )
                  else if (c.status == CourtStatus.suspended)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                      onPressed: () => act(() => ref.read(apiProvider).reactivateCourt(c.id), 'Cancha reactivada'),
                      child: const Text('Reactivar'),
                    ),
                ]),
              ),
          ]),
        ),
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

  static String _roleLabel(Role r) => switch (r) {
        Role.admin => 'Admin',
        Role.owner => 'Dueño',
        Role.player => 'Jugador',
      };

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider(_query));
    final me = ref.watch(userIdProvider);
    return AppPage(
      kicker: 'Administración',
      title: 'Usuarios',
      actions: _adminActions(context, ref),
      child: AsyncView<List<AdminUser>>(
        value: users,
        onRetry: () => ref.invalidate(adminUsersProvider(_query)),
        builder: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminUsersProvider(_query));
            await ref.read(adminUsersProvider(_query).future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              style: authText(14, weight: 600),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o correo',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onSubmitted: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty) _empty('No se encontraron usuarios.'),
            for (final u in list)
              SoftCard(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                radius: 18,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.name, style: authText(14, weight: 800)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      u.email ?? 'Sin correo',
                      _roleLabel(u.role),
                      if (u.phone != null) u.phone!,
                      if (u.suspended) 'Suspendido',
                      if (u.deleted) 'Eliminado',
                    ].join(' · '),
                    style: authText(12, weight: 500, color: const Color(0xFF6C7B72), height: 1.4),
                  ),
                  if (!(u.role == Role.admin || u.deleted || u.id == me))
                    Row(children: [
                      TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                        onPressed: () => _act(
                          () => u.suspended ? ref.read(apiProvider).restoreUser(u.id) : ref.read(apiProvider).suspendUser(u.id),
                          u.suspended ? 'Usuario restaurado' : 'Usuario suspendido',
                        ),
                        child: Text(u.suspended ? 'Restaurar' : 'Suspender'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFB13C35), padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                        onPressed: () async {
                          if (!await _confirmSheet(context,
                              title: '¿Eliminar a ${u.name}?',
                              message: 'Se borran sus datos personales y se cancelan sus reservas futuras.',
                              okLabel: 'Eliminar')) {
                            return;
                          }
                          await _act(() => ref.read(apiProvider).deleteUser(u.id), 'Cuenta eliminada');
                        },
                        child: Text('Eliminar', style: authText(12, weight: 800, color: const Color(0xFFB13C35))),
                      ),
                    ]),
                ]),
              ),
          ]),
        ),
      ),
    );
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

    return AppPage(
      kicker: 'Administración',
      title: 'Reseñas',
      actions: _adminActions(context, ref),
      child: AsyncView<List<ReportedReview>>(
        value: reviews,
        onRetry: () => ref.invalidate(reportedReviewsProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(reportedReviewsProvider);
            await ref.read(reportedReviewsProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
            if (list.isEmpty) _empty('No hay reseñas reportadas.'),
            for (final r in list)
              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(r.courtName, style: authText(14, weight: 800))),
                    Text('${r.stars} ${r.stars == 1 ? 'estrella' : 'estrellas'}',
                        style: authText(12, weight: 700, color: const Color(0xFFE2A51C))),
                  ]),
                  const SizedBox(height: 4),
                  Text('Por ${r.authorName} · ${r.reports} reporte${r.reports == 1 ? '' : 's'}',
                      style: authText(11, weight: 500, color: const Color(0xFF8A968F))),
                  if (r.body != null) ...[
                    const SizedBox(height: 16),
                    Text(r.body!, style: authText(14, weight: 500, color: const Color(0xFF52665A), height: 1.5)),
                  ],
                  if (r.reasons.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Motivos: ${r.reasons.join(', ')}', style: authText(10, weight: 700, color: const Color(0xFFB13C35))),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlineAction(
                        label: 'Conservar',
                        danger: false,
                        onPressed: () => act(() => ref.read(apiProvider).dismissReview(r.id), 'Reportes descartados'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SolidAction(
                        label: 'Ocultar',
                        danger: true,
                        onPressed: () async {
                          if (!await _confirmSheet(context,
                              title: '¿Ocultar la reseña?',
                              message: 'Dejará de verse y de contar en la calificación.',
                              okLabel: 'Ocultar')) {
                            return;
                          }
                          if (context.mounted) await act(() => ref.read(apiProvider).hideReview(r.id), 'Reseña oculta');
                        },
                      ),
                    ),
                  ]),
                ]),
              ),
          ]),
        ),
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

    return AppPage(
      kicker: 'Administración',
      title: 'Resumen',
      actions: _adminActions(context, ref),
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(metricsProvider);
          ref.invalidate(transactionsProvider);
          await ref.read(metricsProvider.future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
          metrics.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorRetry(message: errorMessage(e), onRetry: () => ref.invalidate(metricsProvider)),
            data: (m) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                StatCard(label: 'Usuarios', value: fmtInt(m.players + m.owners)),
                StatCard(label: 'Canchas activas', value: fmtInt(m.activeCourts)),
                StatCard(label: 'Reservas confirmadas', value: fmtInt(m.confirmedBookings)),
                StatCard(label: 'Ingresos aprobados', value: tx.value == null ? '—' : cop(tx.value!.totalAmount), hero: true),
                StatCard(label: 'Mensualidades por revisar', value: '${m.pendingSubscriptionPayments}'),
                StatCard(label: 'Reseñas reportadas', value: '${m.reportedReviews}'),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Transacciones aprobadas', style: authText(18, weight: 800)),
          const SizedBox(height: 12),
          tx.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorRetry(message: errorMessage(e), onRetry: () => ref.invalidate(transactionsProvider)),
            data: (t) => SoftCard(
              margin: EdgeInsets.zero,
              child: t.items.isEmpty
                  ? Text('Aún no hay transacciones.', style: authText(14, weight: 500, color: AuthColors.muted))
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('${t.count} transacciones', style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
                          Text(cop(t.totalAmount), style: authText(14, weight: 800)),
                        ]),
                      ),
                      for (final i in t.items) ...[
                        const Divider(height: 1, color: Color(0x14143E2A)),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: i.payerName, style: authText(12, weight: 800)),
                                  TextSpan(
                                      text: '  ${i.kind == 'subscription' ? 'Mensualidad' : 'Reserva'} · ${dayLabel(i.date)}',
                                      style: authText(12, weight: 500, color: const Color(0xFF8A968F))),
                                ]),
                              ),
                            ),
                            Text(cop(i.amount), style: authText(12, weight: 800)),
                          ]),
                        ),
                      ],
                    ]),
            ),
          ),
        ]),
      ),
    );
  }
}
