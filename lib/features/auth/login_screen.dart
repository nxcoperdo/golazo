import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/logo.dart';

/// Login/registro simulado: valida el formulario y sigue a la elección de rol.
/// Se reemplaza por la autenticación real cuando exista el backend.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  bool _register = false;

  void _next() => context.go('/role');

  Future<void> _phone() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ingresa con tu celular'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(prefixText: '+57 ', labelText: 'Número de celular'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, RegExp(r'^3\d{9}$').hasMatch(ctrl.text.trim())),
              child: const Text('Continuar')),
        ],
      ),
    );
    if (ok == true) _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Center(child: GolazoLogo(size: 96)),
                const SizedBox(height: 8),
                Text('Golazo', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 24),
                TextFormField(
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  validator: (v) => (v != null && v.contains('@')) ? null : 'Correo no válido',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  validator: (v) => (v != null && v.length >= 6) ? null : 'Mínimo 6 caracteres',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (_form.currentState!.validate()) _next();
                  },
                  child: Text(_register ? 'Crear cuenta' : 'Ingresar'),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(_register ? 'Ya tengo cuenta' : 'Crear cuenta nueva'),
                ),
                const Divider(),
                OutlinedButton.icon(
                    onPressed: _next, icon: const Icon(Icons.g_mobiledata, size: 28), label: const Text('Continuar con Google')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _phone, icon: const Icon(Icons.phone_android), label: const Text('Usar número de celular')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
