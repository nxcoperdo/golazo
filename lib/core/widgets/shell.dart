import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'auth_ui.dart';
import 'liquid_nav_bar.dart';
import 'verify_banner.dart';

class TabSpec {
  const TabSpec({required this.label, required this.icon, required this.page});
  final String label;
  final IconData icon;
  final Widget page;
}

/// Barra de navegación inferior con pestañas. Revisa los avisos cada minuto
/// mientras la app está abierta y muestra el aviso de correo sin confirmar.
class ShellScaffold extends ConsumerStatefulWidget {
  const ShellScaffold({
    super.key,
    required this.tabs,
    required this.initialTab,
    this.notificationsTab,
    this.chatTab,
    this.adminChat = false,
  });

  final List<TabSpec> tabs;
  final int initialTab;

  /// Índice de la pestaña "Avisos" para mostrarle el contador de no leídos.
  final int? notificationsTab;

  /// Índice de la pestaña de mensajes (chat) para mostrarle el contador.
  final int? chatTab;

  /// Administrador: el contador cuenta los chats de soporte que esperan respuesta.
  final bool adminChat;

  @override
  ConsumerState<ShellScaffold> createState() => _ShellState();
}

class _ShellState extends ConsumerState<ShellScaffold> {
  late int _tab = widget.initialTab.clamp(0, widget.tabs.length - 1);
  Timer? _poll;
  Timer? _chatPoll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => ref.invalidate(notificationsProvider));
    if (widget.chatTab != null) {
      _chatPoll = Timer.periodic(const Duration(seconds: 30), (_) {
        ref.invalidate(widget.adminChat ? supportInboxProvider : chatThreadsProvider);
      });
    }
  }

  @override
  void didUpdateWidget(ShellScaffold old) {
    super.didUpdateWidget(old);
    // Un enlace con ?tab= cambia de pestaña aunque la pantalla ya esté abierta.
    if (old.initialTab != widget.initialTab) _tab = widget.initialTab.clamp(0, widget.tabs.length - 1);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _chatPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    final chatBadge = widget.chatTab == null
        ? 0
        : widget.adminChat
            ? (ref.watch(supportInboxProvider).value?.where((i) => i.needsReply).length ?? 0)
            : ref.watch(chatUnreadProvider);
    final content = Column(children: [
      const VerifyBanner(),
      Expanded(
        child: IndexedStack(index: _tab, children: [for (final t in widget.tabs) t.page]),
      ),
    ]);
    return Scaffold(
      backgroundColor: AuthColors.cream,
      body: SafeArea(bottom: false, child: content),
      // El contenido pasa por detrás de la barra de cristal; MediaQuery.padding.bottom
      // incluye su altura para que las listas dejen espacio al final.
      extendBody: true,
      bottomNavigationBar: LiquidGlassNavBar(
        index: _tab,
        onChanged: (i) => setState(() => _tab = i),
        items: [
          for (var i = 0; i < widget.tabs.length; i++)
            NavItem(
              label: widget.tabs[i].label,
              icon: widget.tabs[i].icon,
              badge: i == widget.notificationsTab
                  ? unread
                  : i == widget.chatTab
                      ? chatBadge
                      : 0,
            ),
        ],
      ),
    );
  }
}
