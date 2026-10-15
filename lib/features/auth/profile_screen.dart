import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/google_auth.dart';
import '../../core/validators.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Perfil de cualquier rol: datos, correo, contraseña, cerrar sesión y borrar cuenta.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// true cuando va dentro de una pestaña (sin botón de volver).
  final bool embedded;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts[1][0] : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value;
    if (user == null) return const SizedBox.shrink();
    final roleLabel = switch (user.role) {
      Role.player => 'Jugador',
      Role.owner => 'Dueño de cancha',
      Role.admin => 'Administrador',
    };

    return AppPage(
      kicker: 'Tu cuenta',
      title: 'Perfil',
      onBack: embedded ? null : () => context.canPop() ? context.pop() : context.go('/'),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24).withNav(context), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AuthColors.primary, borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AuthColors.lime, shape: BoxShape.circle),
              child: Text(_initials(user.name), style: authText(20, weight: 800, color: AuthColors.primary)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(18, weight: 800, color: Colors.white)),
                const SizedBox(height: 2),
                Text(roleLabel, style: authText(12, weight: 500, color: Colors.white.withValues(alpha: 0.65))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _Row(label: 'Nombre', value: user.name, onTap: () => _editName(context, ref, user)),
            const Divider(height: 1, color: Color(0x14143E2A)),
            _Row(
              label: 'Correo',
              value: user.email ?? 'Sin correo',
              trailing: user.email == null
                  ? null
                  : user.emailVerified
                      ? const StatusPill('Confirmado', PillTone.green)
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const StatusPill('Sin confirmar', PillTone.amber),
                          TextButton(
                            onPressed: () => guarded(context, () => ref.read(apiProvider).resendVerification(),
                                success: 'Te enviamos el correo de confirmación'),
                            child: const Text('Reenviar'),
                          ),
                        ]),
            ),
            const Divider(height: 1, color: Color(0x14143E2A)),
            _Row(
              label: 'Celular',
              value: user.hasPhone ? '+57 ${user.phone}' : 'Agrega tu celular',
              onTap: () => _editPhone(context, ref, user),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        SoftCard(
          padding: EdgeInsets.zero,
          margin: EdgeInsets.zero,
          child: _Row(
            label: null,
            value: 'Cambiar contraseña',
            icon: Icons.lock_outline,
            onTap: () => _changePassword(context, ref),
          ),
        ),
        const SizedBox(height: 28),
        OutlineAction(
          label: 'Cerrar sesión',
          danger: false,
          onPressed: () async {
            await GoogleAuth.signOut();
            await ref.read(sessionProvider.notifier).logout();
          },
        ),
        if (user.role != Role.admin)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB13C35), minimumSize: const Size.fromHeight(48)),
            onPressed: () => _delete(context, ref),
            child: Text('Borrar mi cuenta', style: authText(12, weight: 800, color: const Color(0xFFB13C35))),
          ),
      ]),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, AppUser user) async {
    final v = await showFormSheet(
      context,
      title: 'Cambiar nombre',
      primaryLabel: 'Guardar cambios',
      initial: [user.name],
      fields: [
        (c) => AuthField(
              label: 'Nombre completo',
              icon: Icons.person_outline,
              controller: c,
              hint: user.name,
              textCapitalization: TextCapitalization.words,
              validator: Validators.name,
            ),
      ],
    );
    if (v == null || !context.mounted) return;
    await guarded(context, () async {
      final u = await ref.read(apiProvider).updateProfile(name: v[0]);
      ref.read(sessionProvider.notifier).setUser(u);
    }, success: 'Datos actualizados');
  }

  Future<void> _editPhone(BuildContext context, WidgetRef ref, AppUser user) async {
    final v = await showFormSheet(
      context,
      title: 'Celular de contacto',
      subtitle: 'Lo ve el dueño de la cancha cuando reservas.',
      primaryLabel: 'Guardar cambios',
      initial: [user.phone ?? ''],
      fields: [
        (c) => AuthField(
              label: 'Celular',
              icon: Icons.phone_outlined,
              controller: c,
              hint: '300 000 0000',
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
            ),
      ],
    );
    if (v == null || !context.mounted) return;
    await guarded(context, () async {
      final u = await ref.read(apiProvider).updateProfile(phone: v[0]);
      ref.read(sessionProvider.notifier).setUser(u);
    }, success: 'Datos actualizados');
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final v = await showFormSheet(
      context,
      title: 'Cambiar contraseña',
      primaryLabel: 'Guardar cambios',
      initial: ['', ''],
      fields: [
        (c) => AuthField(
              label: 'Contraseña actual',
              icon: Icons.lock_outline,
              controller: c,
              hint: 'Contraseña actual',
              password: true,
              validator: (x) => Validators.required(x, 'La contraseña actual'),
            ),
        (c) => AuthField(
              label: 'Contraseña nueva',
              icon: Icons.lock_outline,
              controller: c,
              hint: 'Mínimo 8 caracteres',
              password: true,
              validator: Validators.password,
            ),
      ],
    );
    if (v == null || !context.mounted) return;
    await guarded(context, () => ref.read(apiProvider).changePassword(v[0], v[1]), success: 'Contraseña cambiada');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final v = await showFormSheet(
      context,
      title: 'Borrar mi cuenta',
      subtitle:
          'Esta acción es permanente: se eliminan tus datos y se cancelan tus reservas futuras. Escribe tu contraseña para confirmar (déjala vacía si entras con Google).',
      primaryLabel: 'Eliminar definitivamente',
      danger: true,
      initial: [''],
      fields: [
        (c) => AuthField(label: 'Contraseña', icon: Icons.lock_outline, controller: c, hint: 'Tu contraseña', password: true),
      ],
    );
    if (v == null || !context.mounted) return;
    await guarded(
      context,
      () => ref.read(sessionProvider.notifier).deleteAccount(password: v[0].isEmpty ? null : v[0]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing, this.icon, this.onTap});
  final String? label;
  final String value;
  final Widget? trailing;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: AuthColors.ink), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (label != null) Text(label!, style: authText(11, weight: 600, color: const Color(0xFF849088))),
                if (label != null) const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(14, weight: 800)),
              ]),
            ),
            trailing ?? (onTap == null ? const SizedBox.shrink() : const Icon(Icons.chevron_right, size: 18, color: AuthColors.muted)),
          ]),
        ),
      );
}
