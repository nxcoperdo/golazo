import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/validators.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';

/// Paso 1: pedir el enlace de recuperación por correo.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotState();
}

class _ForgotState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await guarded(context, () => ref.read(apiProvider).forgotPassword(_email.text.trim()));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _sent
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.mark_email_read_outlined, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Si ese correo está registrado, te enviamos un enlace para crear una contraseña nueva. '
                    'Ábrelo desde este teléfono. Vale por 1 hora.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () => context.push('/reset'),
                    child: const Text('Ya tengo el código'),
                  ),
                  TextButton(onPressed: () => context.pop(), child: const Text('Volver')),
                ])
              : Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Escribe el correo de tu cuenta y te enviamos un enlace.'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: const Text('Enviar enlace'),
                    ),
                  ]),
                ),
        ),
      ),
    );
  }
}

/// Paso 2: crear la contraseña nueva. Llega por el enlace del correo
/// (`golazo://reset-password?token=...`), o se pega el código a mano.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token});
  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetState();
}

class _ResetState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _token = TextEditingController(text: widget.token ?? '');
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await guarded(
      context,
      () => ref.read(apiProvider).resetPassword(_token.text.trim(), _password.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      showSnack(context, 'Contraseña actualizada. Ya puedes iniciar sesión.');
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.token == null) ...[
                TextFormField(
                  controller: _token,
                  decoration: const InputDecoration(labelText: 'Código del enlace'),
                  validator: (v) => Validators.required(v, 'El código'),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña nueva (mínimo 8 caracteres)'),
                validator: Validators.password,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Guardar contraseña'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
