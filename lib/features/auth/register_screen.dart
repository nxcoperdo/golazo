import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/validators.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/legal_consent.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterState();
}

class _RegisterState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _owner = false;
  bool _accepted = false;
  bool _showConsentError = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    if (!_accepted) setState(() => _showConsentError = true);
    if (!valid || !_accepted) return;
    setState(() => _busy = true);
    final ok = await guarded(
      context,
      () => ref.read(sessionProvider.notifier).register(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            phone: _phone.text,
            asOwner: _owner,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    // Con sesión iniciada el router cambia de pantalla; hay que cerrar esta.
    if (ok && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      onBack: () => backOrLogin(context),
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 24),
            const AuthTitle(
              kicker: 'Tu equipo te espera',
              title: 'Crea tu cuenta',
              subtitle: 'Completa tus datos para empezar a reservar.',
            ),
            const SizedBox(height: 28),
            AuthField(
              label: 'Nombre completo',
              icon: Icons.person_outline,
              hint: 'Tu nombre y apellido',
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              validator: Validators.name,
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            AuthField(
              label: 'Celular de contacto',
              icon: Icons.phone_outlined,
              hint: '300 000 0000',
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              textInputAction: TextInputAction.next,
              helperText: 'Celular de 10 dígitos. Lo ve el dueño de la cancha cuando reservas.',
              validator: Validators.phone,
            ),
            const SizedBox(height: 16),
            AuthField(
              label: 'Contraseña',
              icon: Icons.lock_outline,
              hint: 'Mínimo 8 caracteres',
              controller: _password,
              password: true,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.password,
            ),
            const SizedBox(height: 16),
            SwitchCard(
              title: 'Soy dueño de una cancha',
              subtitle: 'Publica tus canchas y administra reservas y pagos de tus jugadores.',
              value: _owner,
              onChanged: (v) => setState(() => _owner = v),
            ),
            const SizedBox(height: 16),
            LegalConsentCheck(
              value: _accepted,
              showError: _showConsentError && !_accepted,
              onChanged: (v) => setState(() {
                _accepted = v;
                if (v) _showConsentError = false;
              }),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Crear cuenta', busy: _busy, onPressed: _submit),
          ]),
        ),
      ),
    );
  }
}
