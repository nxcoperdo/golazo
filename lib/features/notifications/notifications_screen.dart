import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Bandeja de notificaciones (la misma para jugador, dueño y admin).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, this.embedded = false});

  /// true cuando va dentro de una pestaña (sin botón de volver).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(notificationsProvider);
    final unread = page.value?.unread ?? 0;
    return AppPage(
      kicker: 'Mantente al día',
      title: 'Avisos',
      onBack: embedded ? null : () => context.canPop() ? context.pop() : context.go('/'),
      child: AsyncView<NotificationsPage>(
        value: page,
        onRetry: () => ref.invalidate(notificationsProvider),
        builder: (p) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(notificationsProvider);
            await ref.read(notificationsProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 16).withNav(context), children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: unread == 0
                    ? null
                    : () async {
                        await guarded(context, () => ref.read(apiProvider).markAllNotificationsRead());
                        ref.invalidate(notificationsProvider);
                      },
                child: const Text('Marcar leídas'),
              ),
            ),
            if (p.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text('No tienes notificaciones',
                    textAlign: TextAlign.center, style: authText(14, weight: 500, color: AuthColors.muted)),
              )
            else
              SoftCard(
                padding: EdgeInsets.zero,
                margin: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Column(children: [
                    for (var i = 0; i < p.items.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Color(0x14143E2A)),
                      _tile(context, ref, p.items[i]),
                    ],
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, AppNotification n) => InkWell(
        onTap: () async {
          if (n.unread) {
            await ref.read(apiProvider).markNotificationRead(n.id).catchError((_) {});
            ref.invalidate(notificationsProvider);
          }
          final target = _routeFor(n, ref.read(sessionProvider).value?.role);
          if (target != null && context.mounted) context.go(target);
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title, style: authText(14, weight: 800)),
                const SizedBox(height: 4),
                Text(n.body, style: authText(12, weight: 500, color: const Color(0xFF65736B), height: 1.5)),
                const SizedBox(height: 8),
                Text('${dayLabel(n.createdAt)} · ${timeLabel(n.createdAt)}',
                    style: authText(10, weight: 700, color: const Color(0xFF96A099))),
              ]),
            ),
            if (n.unread)
              Positioned(
                right: 0,
                top: 4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: Color(0xFFD23B34), shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
      );

  /// A qué pantalla lleva cada tipo de aviso.
  String? _routeFor(AppNotification n, Role? role) {
    final type = n.data['type'] as String?;
    return switch ((role, type)) {
      (Role.player, 'payment_rejected' || 'booking_confirmed' || 'booking_expired' || 'booking_reminder') =>
        '/home?tab=1',
      (Role.owner, 'payment_pending') => '/owner?tab=1',
      (Role.owner, 'booking_new' || 'booking_cancelled') => '/owner?tab=0',
      (Role.owner, 'subscription_approved' || 'subscription_rejected' || 'subscription_expired' || 'subscription_expiring') =>
        '/owner?tab=2',
      (Role.admin, 'subscription_pending') => '/admin?tab=0',
      _ => null,
    };
  }
}
