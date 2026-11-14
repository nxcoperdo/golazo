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
import 'chat_screen.dart';

/// Abre una conversación ya conocida.
void openChat(BuildContext context, WidgetRef ref, ChatThread t) {
  final myId = ref.read(userIdProvider) ?? '';
  context.push('/chat/${t.id}', extra: ChatArgs.forThread(t, myId));
}

/// Abre (o crea) el chat de una reserva y entra a él. Lo usan el jugador y el dueño desde la reserva.
Future<void> openBookingChat(BuildContext context, WidgetRef ref, String bookingId) async {
  ChatThread? t;
  final ok = await guarded(context, () async => t = await ref.read(apiProvider).openBookingChat(bookingId));
  if (ok && t != null && context.mounted) openChat(context, ref, t!);
}

/// Abre (o crea) el chat con soporte.
Future<void> openSupportChat(BuildContext context, WidgetRef ref) async {
  ChatThread? t;
  final ok = await guarded(context, () async => t = await ref.read(apiProvider).openSupportChat());
  if (ok && t != null && context.mounted) openChat(context, ref, t!);
}

/// Dueño: abre el chat de soporte con el pedido de activar/renovar su cancha ya enviado y la respuesta con las cuentas.
Future<void> openSubscriptionChat(BuildContext context, WidgetRef ref, String courtId) async {
  ChatThread? t;
  final ok = await guarded(context, () async => t = await ref.read(apiProvider).requestSubscriptionChat(courtId));
  if (ok && t != null && context.mounted) {
    ref.invalidate(chatThreadsProvider);
    openChat(context, ref, t!);
  }
}

/// Pestaña «Mensajes»: soporte fijo arriba y los chats con canchas (jugador) o con jugadores (dueño).
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(chatThreadsProvider);
    final role = ref.watch(sessionProvider).value?.role;
    return AppPage(
      kicker: 'Conversaciones',
      title: 'Mensajes',
      child: AsyncView<List<ChatThread>>(
        value: threads,
        onRetry: () => ref.invalidate(chatThreadsProvider),
        builder: (all) {
          final support = all.where((t) => t.isSupport).firstOrNull;
          final courts = all.where((t) => !t.isSupport).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(chatThreadsProvider);
              await ref.read(chatThreadsProvider.future);
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
              _ThreadTile(
                icon: Icons.support_agent,
                title: 'Soporte Golazo',
                subtitle: support?.lastBody == null ? 'Escríbenos tus dudas' : support!.preview,
                unread: support?.unread ?? 0,
                time: support?.lastMessageAt,
                highlight: true,
                onTap: () => support != null ? openChat(context, ref, support) : openSupportChat(context, ref),
              ),
              const SizedBox(height: 12),
              if (courts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    role == Role.owner
                        ? 'Cuando un jugador reserve una de tus canchas, podrás hablar con él aquí.'
                        : 'Cuando reserves una cancha, podrás hablar con el dueño aquí.',
                    textAlign: TextAlign.center,
                    style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5),
                  ),
                )
              else
                for (final t in courts)
                  _ThreadTile(
                    icon: Icons.sports_soccer,
                    title: ref.read(userIdProvider) == t.participantId ? (t.courtName ?? 'Cancha') : t.participantName,
                    caption: ref.read(userIdProvider) == t.participantId ? null : t.courtName,
                    subtitle: t.preview,
                    unread: t.unread,
                    time: t.lastMessageAt,
                    closed: !t.open,
                    onTap: () => openChat(context, ref, t),
                  ),
            ]),
          );
        },
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.caption,
    this.unread = 0,
    this.time,
    this.closed = false,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String? caption;
  final String subtitle;
  final int unread;
  final DateTime? time;
  final bool closed;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SoftCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          radius: 20,
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: highlight ? AuthColors.primary : const Color(0xFFE6EEE2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: highlight ? AuthColors.lime : AuthColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(14, weight: 800))),
                  if (time != null) Text(dayLabel(time!), style: authText(10, weight: 600, color: AuthColors.muted)),
                ]),
                if (caption != null)
                  Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(11, weight: 600, color: AuthColors.muted)),
                const SizedBox(height: 2),
                Row(children: [
                  if (closed) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock_outline, size: 12, color: AuthColors.muted)),
                  Expanded(
                    child: Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: authText(12, weight: unread > 0 ? 800 : 500, color: unread > 0 ? AuthColors.ink : AuthColors.muted)),
                  ),
                  if (unread > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFD23B34), borderRadius: BorderRadius.circular(10)),
                      child: Text('$unread', style: authText(10, weight: 800, color: Colors.white)),
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
