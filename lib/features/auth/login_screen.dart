import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/google_auth.dart';
import '../../core/validators.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await guarded(context, action);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    await _run(() => ref.read(sessionProvider.notifier).login(_email.text, _password.text));
  }

  Future<void> _google() => _run(() async {
        final token = await GoogleAuth.idToken();
        if (token == null) return; // cerró la ventana
        await ref.read(sessionProvider.notifier).loginWithGoogle(token);
      });

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            const AuthTitle(
              kicker: 'Bienvenido de nuevo',
              title: 'Reserva tu cancha\nen segundos.',
              subtitle: 'Ingresa para volver a la cancha y organizar tu próximo partido.',
            ),
            const SizedBox(height: 32),
            AuthField(
              label: 'Correo',
              icon: Icons.mail_outline,
              hint: 'tu@correo.com',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: Validators.email,
            ),
            const SizedBox(height: 20),
            AuthField(
              label: 'Contraseña',
              icon: Icons.lock_outline,
              hint: 'Ingresa tu contraseña',
              controller: _password,
              password: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _login(),
              validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => context.push('/forgot'),
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
            const SizedBox(height: 4),
            PrimaryButton(label: 'Ingresar', busy: _busy, onPressed: _login),
            const SizedBox(height: 24),
            const OrDivider('o continúa con'),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : _google,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('G', style: authText(18, weight: 800, color: const Color(0xFF4285F4))),
                const SizedBox(width: 12),
                const Text('Continuar con Google'),
              ]),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : () => context.push('/register'),
              child: const Text('Crear cuenta nueva'),
            ),
          ]),
        ),
      ),
    );
  }
}
