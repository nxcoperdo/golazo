import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/google_auth.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/legal_consent.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';

/// Se muestra a quien aún no aceptó la versión vigente de los términos y la política de datos
/// (cuentas creadas con Google, cuentas anteriores o cambio de textos). Sin aceptar no se sigue.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _accepted = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    await guarded(context, () => ref.read(sessionProvider.notifier).acceptTerms());
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _decline() async {
    await GoogleAuth.signOut();
    await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 24),
        const AuthTitle(
          kicker: 'Un último paso',
          title: 'Antes de seguir',
          subtitle: 'Para usar Golazo necesitamos tu autorización para tratar tus datos y que aceptes los términos del servicio.',
        ),
        const SizedBox(height: 28),
        LegalConsentCheck(value: _accepted, onChanged: (v) => setState(() => _accepted = v)),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Aceptar y continuar', busy: _busy, onPressed: _accepted ? _accept : null),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : _decline, child: const Text('No acepto, cerrar sesión')),
      ]),
    );
  }
}
