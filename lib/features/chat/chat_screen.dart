import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Id del chat que está en pantalla (null si ninguno): el push no avisa de lo que ya se está viendo.
String? activeChatThreadId;

/// Cómo se presenta un chat a quien lo abre (título, a quién se bloquea, si es el administrador).
class ChatArgs {
  const ChatArgs({required this.title, this.subtitle, this.peerId, this.admin = false, this.readOnly = false});

  final String title;
  final String? subtitle;

  /// La otra persona (para bloquearla). Null en soporte.
  final String? peerId;

  /// Lo abre un administrador: usa las rutas de administración.
  final bool admin;

  /// Chats entre jugador y dueño vistos por el administrador: solo lectura.
  final bool readOnly;

  factory ChatArgs.forThread(ChatThread t, String myId) {
    if (t.isSupport) {
      return myId == t.participantId
          ? const ChatArgs(title: 'Soporte Golazo', subtitle: 'Te respondemos por aquí')
          : ChatArgs(title: t.participantName, subtitle: 'Soporte', admin: true);
    }
    if (myId == t.participantId) {
      return ChatArgs(title: t.courtName ?? 'Cancha', subtitle: 'Dueño: ${t.ownerName ?? ''}', peerId: t.ownerId);
    }
    return ChatArgs(title: t.participantName, subtitle: t.courtName, peerId: t.participantId);
  }
}

/// Conversación. Pide los mensajes nuevos cada pocos segundos mientras está abierta y la app en primer plano;
/// con la app cerrada llega un aviso push.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.threadId, this.args, this.pollEvery = const Duration(seconds: 4)});

  final String threadId;
  final ChatArgs? args;
  final Duration pollEvery;

  @override
  ConsumerState<ChatScreen> createState() => _ChatState();
}

class _ChatState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  ChatArgs? _args;
  Object? _error;
  bool _loading = true;
  bool _open = true;
  bool _blocked = false;
  bool _sending = false;
  bool _foreground = true;
  bool _fetching = false;
  PickedImage? _photo;
  Timer? _timer;

  int get _lastSeq => _messages.isEmpty ? 0 : _messages.last.seq;
  bool get _admin => _args?.admin ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _args = widget.args;
    activeChatThreadId = widget.threadId;
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (activeChatThreadId == widget.threadId) activeChatThreadId = null;
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _fetchNew();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      // Abierto desde una notificación: solo se conoce el id, así que se busca el título en mis chats.
      if (_args == null) {
        final myId = ref.read(userIdProvider) ?? '';
        final t = (await api.chatThreads()).where((x) => x.id == widget.threadId).firstOrNull;
        _args = t == null ? const ChatArgs(title: 'Chat') : ChatArgs.forThread(t, myId);
      }
      final page = await api.chatMessages(widget.threadId, admin: _admin);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _open = page.open;
        _blocked = page.blocked;
        _loading = false;
      });
      ref.invalidate(chatThreadsProvider); // al leer, el contador baja
      _toBottom(jump: true);
      _timer?.cancel();
      _timer = Timer.periodic(widget.pollEvery, (_) => _fetchNew());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchNew() async {
    if (!mounted || !_foreground || _fetching || _sending || _loading || _error != null) return;
    _fetching = true;
    try {
      final page = await ref.read(apiProvider).chatMessages(widget.threadId, after: _lastSeq, admin: _admin);
      if (!mounted) return;
      final fresh = page.messages.where((m) => m.seq > _lastSeq).toList();
      if (fresh.isNotEmpty || page.open != _open || page.blocked != _blocked) {
        final atEnd = _nearBottom();
        setState(() {
          _messages.addAll(fresh);
          _open = page.open;
          _blocked = page.blocked;
        });
        if (fresh.isNotEmpty) {
          ref.invalidate(chatThreadsProvider);
          if (atEnd) _toBottom();
        }
      }
    } catch (_) {
      // Sin conexión un momento: el siguiente intento lo recupera.
    } finally {
      _fetching = false;
    }
  }

  bool _nearBottom() => !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.offset < 120;

  void _toBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickPhoto() async {
    final img = await ref.read(pickImageProvider)(context);
    if (img != null && mounted) setState(() => _photo = img);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _photo == null) || _sending) return;
    setState(() => _sending = true);
    try {
      final m = await ref.read(apiProvider).sendChatMessage(
            widget.threadId,
            body: text.isEmpty ? null : text,
            image: _photo?.bytes,
            filename: _photo?.filename,
            admin: _admin,
          );
      if (!mounted) return;
      setState(() {
        if (!_messages.any((x) => x.id == m.id)) _messages.add(m);
        _input.clear();
        _photo = null;
      });
      ref.invalidate(chatThreadsProvider);
      _toBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'CHAT_CLOSED') setState(() => _open = false);
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report(ChatMessage m) async {
    final v = await showFormSheet(
      context,
      title: 'Reportar mensaje',
      subtitle: 'Un administrador de Golazo lo revisará. Cuéntanos qué pasó (opcional).',
      primaryLabel: 'Enviar reporte',
      initial: [''],
      fields: [
        (c) => AuthField(label: 'Motivo', icon: Icons.flag_outlined, controller: c, hint: 'Ej.: insultos, spam'),
      ],
    );
    if (v == null || !mounted) return;
    await guarded(context, () => ref.read(apiProvider).reportChatMessage(m.id, reason: v[0]),
        success: 'Gracias, lo revisaremos');
  }

  Future<void> _toggleBlock() async {
    final peer = _args?.peerId;
    if (peer == null) return;
    final unblock = _blocked;
    final ok = await showAppSheet<bool>(
      context,
      builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeading(unblock ? '¿Desbloquear?' : '¿Bloquear a esta persona?',
            subtitle: unblock
                ? 'Podrán volver a escribirse mientras haya una reserva vigente.'
                : 'Ninguno de los dos podrá escribir en este chat hasta que la desbloquees.'),
        SheetActions(
          primaryLabel: unblock ? 'Desbloquear' : 'Bloquear',
          danger: !unblock,
          onPrimary: () => Navigator.pop(sheet, true),
        ),
      ]),
    );
    if (ok != true || !mounted) return;
    final api = ref.read(apiProvider);
    final done = await guarded(context, () => unblock ? api.unblockChatUser(peer) : api.blockChatUser(peer),
        success: unblock ? 'Desbloqueado' : 'Bloqueado');
    if (done) {
      final page = await api.chatMessages(widget.threadId, after: _lastSeq);
      if (mounted) {
        setState(() {
          _open = page.open;
          _blocked = page.blocked;
        });
      }
    }
  }

  void _showActions(ChatMessage m, bool mine) {
    if (mine || _admin || m.hidden) return;
    showAppSheet<void>(
      context,
      builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeading('Mensaje'),
        SolidAction(
          label: 'Reportar mensaje',
          icon: Icons.flag_outlined,
          danger: true,
          onPressed: () {
            Navigator.pop(sheet);
            _report(m);
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(userIdProvider);
    final args = _args ?? const ChatArgs(title: 'Chat');
    return AppPage(
      kicker: args.subtitle,
      title: args.title,
      onBack: () => context.canPop() ? context.pop() : context.go('/'),
      actions: [
        if (args.peerId != null && !args.admin)
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert, color: AuthColors.ink),
            onSelected: (_) => _toggleBlock(),
            itemBuilder: (_) => [PopupMenuItem(value: 'block', child: Text(_blocked ? 'Desbloquear' : 'Bloquear'))],
          ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('No se pudo cargar el chat', style: authText(14, weight: 600)),
                    TextButton(onPressed: _start, child: const Text('Reintentar')),
                  ]),
                )
              : Column(children: [
                  Expanded(child: _list(myId)),
                  if (!_open || args.readOnly) _closedBar(args) else _composer(),
                ]),
    );
  }

  Widget _list(String? myId) {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _open ? 'Todavía no hay mensajes.\nEscribe el primero.' : 'No hubo mensajes en este chat.',
            textAlign: TextAlign.center,
            style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final newDay = i == 0 || dayLabel(_messages[i - 1].createdAt) != dayLabel(m.createdAt);
        final mine = m.senderId == myId || (_admin && m.fromSupport);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (newDay)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(child: Text(dayLabel(m.createdAt), style: authText(11, weight: 700, color: AuthColors.muted))),
            ),
          _Bubble(message: m, mine: mine, showSender: _admin || _args?.readOnly == true, onLongPress: () => _showActions(m, mine)),
        ]);
      },
    );
  }

  Widget _closedBar(ChatArgs args) {
    final text = args.readOnly
        ? 'Solo lectura (moderación).'
        : _blocked
            ? 'Bloqueaste a esta persona. Desbloquéala (menú ⋮) para volver a escribir.'
            : 'Chat cerrado: se abre de nuevo cuando haya una reserva vigente.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      color: const Color(0xFFEDEFE6),
      child: SafeArea(
        top: false,
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 16, color: AuthColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: authText(12, weight: 600, color: AuthColors.muted, height: 1.4))),
        ]),
      ),
    );
  }

  Widget _composer() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_photo != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: InputChip(
                  avatar: const Icon(Icons.image_outlined, size: 16),
                  label: Text(_photo!.filename, overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => _photo = null),
                ),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              tooltip: 'Adjuntar foto',
              onPressed: _sending ? null : _pickPhoto,
              icon: const Icon(Icons.photo_camera_outlined, color: AuthColors.primary),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF2F4EC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              tooltip: 'Enviar',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: AuthColors.primary),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.showSender, required this.onLongPress});

  final ChatMessage message;
  final bool mine;
  final bool showSender;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final bg = mine ? AuthColors.primary : Colors.white;
    final fg = mine ? Colors.white : AuthColors.ink;
    final meta = mine ? Colors.white.withValues(alpha: 0.7) : AuthColors.muted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: mine ? null : Border.all(color: const Color(0x14143E2A)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (m.fromSupport && !mine)
              Text('Soporte Golazo', style: authText(11, weight: 800, color: AuthColors.link))
            else if (showSender)
              Text(m.senderName, style: authText(11, weight: 800, color: meta)),
            if (m.hidden)
              Text(m.body == null ? 'Mensaje oculto por moderación' : 'Oculto: ${m.body}',
                  style: authText(13, weight: 500, color: meta).copyWith(fontStyle: FontStyle.italic))
            else ...[
              if (m.hasImage) ChatImage(messageId: m.id),
              if (m.body != null && m.body!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: m.hasImage ? 6 : 0),
                  child: Text(m.body!, style: authText(14, weight: 500, color: fg, height: 1.35)),
                ),
            ],
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(timeLabel(m.createdAt), style: authText(10, weight: 600, color: meta)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Foto de un mensaje (descarga privada con la sesión). Al tocarla se abre en grande.
class ChatImage extends ConsumerWidget {
  const ChatImage({super.key, required this.messageId});
  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = ref.watch(chatImageProvider(messageId));
    return img.when(
      loading: () => const SizedBox(width: 180, height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => TextButton.icon(
        onPressed: () => ref.invalidate(chatImageProvider(messageId)),
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Reintentar foto'),
      ),
      data: (bytes) => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(insetPadding: const EdgeInsets.all(12), child: InteractiveViewer(child: Image.memory(bytes))),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(bytes, width: 220, height: 160, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
