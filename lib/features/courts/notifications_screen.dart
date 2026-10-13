import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/mock_data.dart';

/// Notificaciones dentro de la app. El push real llega con el backend.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider).reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: items.isEmpty
          ? const Center(child: Text('No tienes notificaciones'))
          : ListView(children: [
              for (final n in items)
                ListTile(leading: const Icon(Icons.notifications), title: Text(n)),
            ]),
    );
  }
}
