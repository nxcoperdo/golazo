import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
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
    this.showAppBar = false,
  });

  final List<TabSpec> tabs;
  final int initialTab;

  /// Índice de la pestaña "Avisos" para mostrarle el contador de no leídos.
  final int? notificationsTab;

  /// true = la barra superior la pone el shell (las páginas no traen Scaffold propio),
  /// con atajos a Avisos y Perfil.
  final bool showAppBar;

  @override
  ConsumerState<ShellScaffold> createState() => _ShellState();
}

class _ShellState extends ConsumerState<ShellScaffold> {
  late int _tab = widget.initialTab.clamp(0, widget.tabs.length - 1);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => ref.invalidate(notificationsProvider));
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    final content = Column(children: [
      const VerifyBanner(),
      Expanded(
        child: IndexedStack(index: _tab, children: [for (final t in widget.tabs) t.page]),
      ),
    ]);
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(widget.tabs[_tab].label),
              actions: [
                IconButton(
                  tooltip: 'Avisos',
                  onPressed: () => context.push('/notifications'),
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                ),
                IconButton(
                  tooltip: 'Mi perfil',
                  onPressed: () => context.push('/profile'),
                  icon: const Icon(Icons.person_outline),
                ),
              ],
            )
          : null,
      body: widget.showAppBar ? content : SafeArea(bottom: false, child: content),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (var i = 0; i < widget.tabs.length; i++)
            NavigationDestination(
              icon: i == widget.notificationsTab
                  ? Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: Icon(widget.tabs[i].icon))
                  : Icon(widget.tabs[i].icon),
              label: widget.tabs[i].label,
            ),
        ],
      ),
    );
  }
}
