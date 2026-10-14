import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/google_auth.dart';
import '../../core/validators.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Perfil de cualquier rol: datos, correo, contraseña, cerrar sesión y borrar cuenta.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// true cuando va dentro de una pestaña (sin su propia barra superior).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value;
    if (user == null) return const SizedBox.shrink();

    final body = ListView(children: [
      const SizedBox(height: 16),
      ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(user.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(switch (user.role) {
          Role.player => 'Jugador',
          Role.owner => 'Dueño de cancha',
          Role.admin => 'Administrador',
        }),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.email_outlined),
        title: Text(user.email ?? 'Sin correo'),
        subtitle: user.emailVerified ? const Text('Correo confirmado') : const Text('Correo sin confirmar'),
        trailing: user.emailVerified
            ? const Icon(Icons.verified, color: Colors.green)
            : TextButton(
                onPressed: () => guarded(
                  context,
                  () => ref.read(apiProvider).resendVerification(),
                  success: 'Te enviamos el correo de confirmación',
                ),
                child: const Text('Reenviar'),
              ),
      ),
      ListTile(
        leading: const Icon(Icons.phone_outlined),
        title: Text(user.hasPhone ? '+57 ${user.phone}' : 'Agrega tu celular'),
        subtitle: const Text('Contacto para las reservas'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editProfile(context, ref, user),
      ),
      ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: const Text('Cambiar nombre'),
        onTap: () => _editProfile(context, ref, user, editName: true),
      ),
      ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Cambiar contraseña'),
        onTap: () => _changePassword(context, ref),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Cerrar sesión'),
        onTap: () async {
          await GoogleAuth.signOut();
          await ref.read(sessionProvider.notifier).logout();
        },
      ),
      if (user.role != Role.admin)
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
          title: Text('Borrar mi cuenta', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => _delete(context, ref),
        ),
    ]);

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Mi perfil')), body: body);
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, AppUser user, {bool editName = false}) async {
    final ctrl = TextEditingController(text: editName ? user.name : (user.phone ?? ''));
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(editName ? 'Nombre' : 'Celular de contacto'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            keyboardType: editName ? TextInputType.name : TextInputType.phone,
            decoration: InputDecoration(prefixText: editName ? null : '+57 '),
            validator: editName ? Validators.name : Validators.phone,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final value = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !context.mounted) return;
    await guarded(context, () async {
      final u = await ref.read(apiProvider).updateProfile(
            name: editName ? value : null,
            phone: editName ? null : value,
          );
      ref.read(sessionProvider.notifier).setUser(u);
    }, success: 'Datos actualizados');
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (v) => Validators.required(v, 'La contraseña actual'),
            ),
            TextFormField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña nueva'),
              validator: Validators.password,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
    final c = current.text, n = next.text;
    current.dispose();
    next.dispose();
    if (ok != true || !context.mounted) return;
    await guarded(context, () => ref.read(apiProvider).changePassword(c, n),
        success: 'Contraseña cambiada');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final okay = await confirm(
      context,
      title: '¿Borrar tu cuenta?',
      message:
          'Se eliminan tus datos personales y se cancelan tus reservas futuras. Esta acción no se puede deshacer.',
      okLabel: 'Borrar',
    );
    if (!okay || !context.mounted) return;
    // Las cuentas con contraseña deben confirmarla; las de Google no tienen.
    final password = await askText(context,
        title: 'Confirma tu contraseña', hint: 'Déjalo vacío si entras con Google', obscure: true);
    if (password == null || !context.mounted) return;
    await guarded(
      context,
      () => ref.read(sessionProvider.notifier).deleteAccount(password: password.isEmpty ? null : password),
    );
  }
}
