import 'package:flutter/material.dart';

import '../../core/widgets/shell.dart';
import '../auth/profile_screen.dart';
import '../chat/chats_screen.dart';
import '../notifications/notifications_screen.dart';
import 'owner_bookings_tab.dart';
import 'owner_courts_tab.dart';
import 'owner_payments_tab.dart';

/// Panel del dueño: Reservas · Pagos · Canchas · Mensajes · Avisos · Perfil.
class OwnerShell extends StatelessWidget {
  const OwnerShell({super.key, this.tab = 0});
  final int tab;

  @override
  Widget build(BuildContext context) => ShellScaffold(
        initialTab: tab,
        notificationsTab: 4,
        chatTab: 3,
        tabs: const [
          TabSpec(label: 'Reservas', icon: Icons.calendar_month, page: OwnerBookingsTab()),
          TabSpec(label: 'Pagos', icon: Icons.payments, page: OwnerPaymentsTab()),
          TabSpec(label: 'Canchas', icon: Icons.stadium, page: OwnerCourtsTab()),
          TabSpec(label: 'Mensajes', icon: Icons.chat_bubble, page: ChatsScreen()),
          TabSpec(label: 'Avisos', icon: Icons.notifications, page: NotificationsScreen(embedded: true)),
          TabSpec(label: 'Perfil', icon: Icons.person, page: ProfileScreen(embedded: true)),
        ],
      );
}
