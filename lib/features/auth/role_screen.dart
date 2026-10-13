import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import '../../core/logo.dart';
import '../../data/models.dart';

final roleProvider = StateProvider<Role?>((_) => null);

/// Pantalla de acceso mock: elige rol para recorrer cada panel.
class RoleScreen extends ConsumerWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void enter(Role r) {
      ref.read(roleProvider.notifier).state = r;
      context.go(switch (r) {
        Role.player => '/courts',
        Role.owner => '/owner',
        Role.admin => '/admin',
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: GolazoLogo(size: 96)),
              const SizedBox(height: 8),
              Text('Golazo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 32),
              FilledButton(
                  onPressed: () => enter(Role.player),
                  child: const Text('Entrar como jugador')),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: () => enter(Role.owner),
                  child: const Text('Entrar como dueño de cancha')),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: () => enter(Role.admin),
                  child: const Text('Entrar como administrador')),
            ],
          ),
        ),
      ),
    );
  }
}
