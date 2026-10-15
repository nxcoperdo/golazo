import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/auth_ui.dart';
import '../../data/providers.dart';

/// Confirma el correo con el token del enlace (`golazo://verify-email?token=...`).
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.token});
  final String? token;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyState();
}

class _VerifyState extends ConsumerState<VerifyEmailScreen> {
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'El enlace no trae el código de confirmación.');
      return;
    }
    try {
      await ref.read(apiProvider).verifyEmail(token);
      // Si hay sesión, se actualiza el usuario para quitar el aviso de "confirma tu correo".
      if (ref.read(sessionProvider).value != null) {
        await ref.read(sessionProvider.notifier).reload();
      }
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _error == null && !_done;
    return AuthShell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (loading)
          const Center(child: CircularProgressIndicator(color: AuthColors.primary))
        else ...[
          Center(child: ResultBadge(ok: _done)),
          const SizedBox(height: 28),
          AuthTitle(
            kicker: _done ? 'Todo listo' : 'No pudimos verificarlo',
            title: _done ? '¡Correo confirmado!' : 'No pudimos confirmar tu correo',
            subtitle: _done
                ? 'Tu correo fue verificado correctamente. Ya puedes usar todas las funciones de Golazo.'
                : _error,
            center: true,
          ),
          const SizedBox(height: 36),
          PrimaryButton(label: 'Continuar', onPressed: () => context.go('/')),
        ],
      ]),
    );
  }
}
