import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Bandeja de notificaciones (la misma para jugador, dueño y admin).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(notificationsProvider);
    final body = AsyncView<NotificationsPage>(
      value: page,
      onRetry: () => ref.invalidate(notificationsProvider),
      emptyText: 'No tienes notificaciones',
      isEmpty: (p) => p.items.isEmpty,
      builder: (p) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
        },
        child: ListView.separated(
          itemCount: p.items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) => _tile(context, ref, p.items[i]),
        ),
      ),
    );
    final actions = [
      if ((page.value?.unread ?? 0) > 0)
        TextButton(
          onPressed: () async {
            await guarded(context, () => ref.read(apiProvider).markAllNotificationsRead());
            ref.invalidate(notificationsProvider);
          },
          child: const Text('Marcar leídas'),
        ),
    ];
    if (embedded) {
      return Scaffold(appBar: AppBar(title: const Text('Avisos'), actions: actions), body: body);
    }
    return Scaffold(appBar: AppBar(title: const Text('Notificaciones'), actions: actions), body: body);
  }

  Widget _tile(BuildContext context, WidgetRef ref, AppNotification n) => ListTile(
        leading: Icon(n.unread ? Icons.notifications_active : Icons.notifications_none,
            color: n.unread ? Theme.of(context).colorScheme.primary : null),
        title: Text(n.title, style: TextStyle(fontWeight: n.unread ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text('${n.body}\n${dayLabel(n.createdAt)} · ${timeLabel(n.createdAt)}'),
        isThreeLine: true,
        onTap: () async {
          if (n.unread) {
            await ref.read(apiProvider).markNotificationRead(n.id).catchError((_) {});
            ref.invalidate(notificationsProvider);
          }
          final target = _routeFor(n, ref.read(sessionProvider).value?.role);
          if (target != null && context.mounted) context.go(target);
        },
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
