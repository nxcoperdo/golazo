import 'package:flutter/material.dart';

import '../../core/widgets/shell.dart';
import 'admin_chat_tab.dart';
import 'admin_tabs.dart';

/// Panel del administrador: Pagos · Canchas · Usuarios · Reseñas · Resumen · Soporte.
/// Avisos y Perfil están en los botones del encabezado de cada pestaña.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, this.tab = 0});
  final int tab;

  @override
  Widget build(BuildContext context) => ShellScaffold(
        initialTab: tab,
        chatTab: 5,
        adminChat: true,
        tabs: const [
          TabSpec(label: 'Pagos', icon: Icons.payments, page: AdminPaymentsTab()),
          TabSpec(label: 'Canchas', icon: Icons.stadium, page: AdminCourtsTab()),
          TabSpec(label: 'Usuarios', icon: Icons.people, page: AdminUsersTab()),
          TabSpec(label: 'Reseñas', icon: Icons.flag, page: AdminReviewsTab()),
          TabSpec(label: 'Resumen', icon: Icons.insights, page: AdminSummaryTab()),
          TabSpec(label: 'Soporte', icon: Icons.support_agent, page: AdminChatTab()),
        ],
      );
}
