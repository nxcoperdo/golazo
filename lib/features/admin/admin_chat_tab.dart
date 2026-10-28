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
import '../chat/chat_screen.dart';

enum _View { inbox, courts, reports }

/// Soporte del administrador: bandeja de mensajes de jugadores y dueños, chats entre jugador y dueño
/// (solo lectura, para moderar) y reportes de mensajes.
class AdminChatTab extends ConsumerStatefulWidget {
  const AdminChatTab({super.key});

  @override
  ConsumerState<AdminChatTab> createState() => _State();
}

class _State extends ConsumerState<AdminChatTab> {
  _View _view = _View.inbox;
  String _search = '';
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Widget _tabs() => SegmentedTabs<_View>(
        options: const [(_View.inbox, 'Soporte'), (_View.courts, 'Chats'), (_View.reports, 'Reportes')],
        value: _view,
        onChanged: (v) => setState(() => _view = v),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Text(text, textAlign: TextAlign.center, style: authText(14, weight: 500, color: AuthColors.muted)),
      );

  @override
  Widget build(BuildContext context) {
    return AppPage(
      kicker: 'Administración',
      title: 'Soporte',
      child: switch (_view) {
        _View.inbox => _inbox(),
        _View.courts => _courts(),
        _View.reports => _reports(),
      },
    );
  }

  // ---- Bandeja de soporte ----
  Widget _inbox() {
    final inbox = ref.watch(supportInboxProvider);
    return AsyncView<List<SupportInboxItem>>(
      value: inbox,
      onRetry: () => ref.invalidate(supportInboxProvider),
      builder: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(supportInboxProvider);
          await ref.read(supportInboxProvider.future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
          _tabs(),
          const SizedBox(height: 16),
          if (list.isEmpty)
            _empty('Nadie ha escrito a soporte todavía.')
          else
            for (final i in list)
              _Tile(
                title: i.participantName,
                caption: '${i.participantRole == 'owner' ? 'Dueño' : 'Jugador'}${i.participantEmail == null ? '' : ' · ${i.participantEmail}'}',
                subtitle: i.preview,
                time: i.lastMessageAt,
                pill: i.needsReply ? const StatusPill('Responder', PillTone.amber) : null,
                onTap: () async {
                  await context.push('/chat/${i.id}',
                      extra: ChatArgs(
                          title: i.participantName,
                          subtitle: 'Soporte · ${i.participantRole == 'owner' ? 'dueño' : 'jugador'}',
                          admin: true));
                  ref.invalidate(supportInboxProvider);
                },
              ),
        ]),
      ),
    );
  }

  // ---- Chats entre jugador y dueño ----
  Widget _courts() {
    final provider = adminCourtChatsProvider(_search);
    final chats = ref.watch(provider);
    return AsyncView<List<AdminChatThread>>(
      value: chats,
      onRetry: () => ref.invalidate(provider),
      builder: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(provider);
          await ref.read(provider.future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
          _tabs(),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar por cancha, jugador o dueño',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onSubmitted: (v) => setState(() => _search = v.trim()),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            _empty(_search.isEmpty ? 'Todavía no hay chats entre jugadores y dueños.' : 'Sin resultados.')
          else
            for (final c in list)
              _Tile(
                title: c.courtName,
                caption: '${c.playerName} ↔ ${c.ownerName} · ${c.messages} mensajes',
                subtitle: c.preview,
                time: c.lastMessageAt,
                onTap: () => context.push('/chat/${c.id}',
                    extra: ChatArgs(
                        title: c.courtName, subtitle: '${c.playerName} ↔ ${c.ownerName}', admin: true, readOnly: true)),
              ),
        ]),
      ),
    );
  }

  // ---- Reportes ----
  Widget _reports() {
    final reports = ref.watch(chatReportsProvider);
    return AsyncView<List<ChatReport>>(
      value: reports,
      onRetry: () => ref.invalidate(chatReportsProvider),
      builder: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(chatReportsProvider);
          await ref.read(chatReportsProvider.future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16).withNav(context), children: [
          _tabs(),
          const SizedBox(height: 16),
          if (list.isEmpty)
            _empty('No hay mensajes reportados.')
          else
            for (final r in list)
              SoftCard(
                margin: const EdgeInsets.only(bottom: 12),
                radius: 20,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.senderName} · ${r.courtName ?? 'Soporte'}', style: authText(14, weight: 800)),
                  const SizedBox(height: 2),
                  Text('Reportado por ${r.reporterName} · ${dayLabel(r.createdAt)}',
                      style: authText(11, weight: 600, color: AuthColors.muted)),
                  const SizedBox(height: 10),
                  NoticeBox(r.body ?? (r.hasImage ? '📷 Foto' : '—'), bg: const Color(0xFFFDECEA), fg: const Color(0xFF8A2D26)),
                  if (r.reason != null) ...[
                    const SizedBox(height: 8),
                    Text('Motivo: ${r.reason}', style: authText(12, weight: 600, color: const Color(0xFF6C7B72))),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlineAction(
                        label: 'Ver chat',
                        onPressed: () => context.push('/chat/${r.threadId}',
                            extra: ChatArgs(title: r.courtName ?? 'Chat', subtitle: 'Mensaje reportado', admin: true, readOnly: r.courtName != null)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlineAction(label: 'Descartar', onPressed: () => _resolve(r)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SolidAction(label: r.hidden ? 'Mensaje ya oculto' : 'Ocultar mensaje', danger: true, onPressed: r.hidden ? null : () => _hide(r)),
                ]),
              ),
        ]),
      ),
    );
  }

  Future<void> _resolve(ChatReport r) async {
    final ok = await guarded(context, () => ref.read(apiProvider).resolveChatReport(r.id), success: 'Reporte descartado');
    if (ok) ref.invalidate(chatReportsProvider);
  }

  Future<void> _hide(ChatReport r) async {
    final ok = await showAppSheet<bool>(
      context,
      builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeading('¿Ocultar el mensaje?',
            subtitle: 'Los usuarios dejarán de verlo. Tú lo seguirás viendo como evidencia.'),
        SheetActions(primaryLabel: 'Ocultar mensaje', danger: true, onPrimary: () => Navigator.pop(sheet, true)),
      ]),
    );
    if (ok != true || !mounted) return;
    final done = await guarded(context, () => ref.read(apiProvider).hideChatMessage(r.messageId), success: 'Mensaje oculto');
    if (done) ref.invalidate(chatReportsProvider);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.subtitle, required this.onTap, this.caption, this.time, this.pill});

  final String title;
  final String? caption;
  final String subtitle;
  final DateTime? time;
  final Widget? pill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SoftCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(14),
            radius: 20,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(14, weight: 800))),
                    if (time != null) Text(dayLabel(time!), style: authText(10, weight: 600, color: AuthColors.muted)),
                  ]),
                  if (caption != null)
                    Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(11, weight: 600, color: AuthColors.muted)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(12, weight: 500, color: AuthColors.muted)),
                ]),
              ),
              if (pill != null) ...[const SizedBox(width: 8), pill!],
            ]),
          ),
        ),
      );
}
