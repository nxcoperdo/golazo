import 'package:flutter/material.dart';

import '../../core/widgets/shell.dart';
import '../auth/profile_screen.dart';
import '../notifications/notifications_screen.dart';
import 'courts_screen.dart';
import 'my_bookings_screen.dart';

/// Navegación inferior del jugador: Canchas · Reservas · Avisos · Perfil.
class PlayerShell extends StatelessWidget {
  const PlayerShell({super.key, this.tab = 0});
  final int tab;

  @override
  Widget build(BuildContext context) => ShellScaffold(
        initialTab: tab,
        notificationsTab: 2,
        tabs: const [
          TabSpec(label: 'Canchas', icon: Icons.sports_soccer, page: CourtsScreen()),
          TabSpec(label: 'Reservas', icon: Icons.receipt_long, page: MyBookingsScreen()),
          TabSpec(label: 'Avisos', icon: Icons.notifications, page: NotificationsScreen(embedded: true)),
          TabSpec(label: 'Perfil', icon: Icons.person, page: ProfileScreen(embedded: true)),
        ],
      );
}
