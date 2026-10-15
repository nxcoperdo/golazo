import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/validators.dart';
import '../../core/widgets/auth_ui.dart';
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
    if (!_sent && !_form.currentState!.validate()) return;
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
    final email = _email.text.trim();
    return AuthShell(
      onBack: () => backOrLogin(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Align(alignment: Alignment.centerLeft, child: IconTile(Icons.mail_outline)),
        const SizedBox(height: 24),
        if (_sent) ...[
          const AuthTitle(title: 'Revisa tu correo'),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Si '),
              TextSpan(text: email, style: authText(14, weight: 800, color: AuthColors.label, height: 1.5)),
              const TextSpan(
                  text: ' está registrado, te enviamos un enlace para crear una contraseña nueva. '
                      'Ábrelo desde este teléfono. Vale por 1 hora.'),
            ]),
            style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: _busy ? null : _send,
            child: const Text('Enviar de nuevo'),
          ),
        ] else
          Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const AuthTitle(
                title: 'Recupera tu contraseña',
                subtitle: 'Escribe el correo de tu cuenta y te enviamos un enlace.',
              ),
              const SizedBox(height: 32),
              AuthField(
                label: 'Correo',
                icon: Icons.mail_outline,
                hint: 'tu@correo.com',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _send(),
                validator: Validators.email,
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Enviar enlace', busy: _busy, onPressed: _send),
            ]),
          ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.push('/reset'),
          child: const Text('Ya tengo el código'),
        ),
      ]),
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
  bool _saved = false;

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
    setState(() {
      _busy = false;
      _saved = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) {
      return AuthShell(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Center(child: ResultBadge(ok: true, size: 80)),
          const SizedBox(height: 24),
          const AuthTitle(
            title: 'Contraseña actualizada',
            subtitle: 'Ya puedes ingresar con tu nueva contraseña.',
            center: true,
          ),
          const SizedBox(height: 32),
          PrimaryButton(label: 'Volver a ingresar', onPressed: () => context.go('/login')),
        ]),
      );
    }
    return AuthShell(
      onBack: () => backOrLogin(context),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Align(alignment: Alignment.centerLeft, child: IconTile(Icons.lock_outline)),
          const SizedBox(height: 24),
          AuthTitle(
            title: 'Crea una contraseña nueva',
            subtitle: widget.token == null
                ? 'Pega el código que recibiste y elige una contraseña segura.'
                : 'Elige una contraseña segura.',
          ),
          const SizedBox(height: 32),
          if (widget.token == null) ...[
            AuthField(
              label: 'Código del enlace',
              icon: Icons.mail_outline,
              hint: 'Pega aquí el código',
              controller: _token,
              textInputAction: TextInputAction.next,
              validator: (v) => Validators.required(v, 'El código'),
            ),
            const SizedBox(height: 20),
          ],
          AuthField(
            label: 'Contraseña nueva',
            icon: Icons.lock_outline,
            hint: 'Mínimo 8 caracteres',
            controller: _password,
            password: true,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _save(),
            validator: Validators.password,
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Guardar contraseña', busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}
