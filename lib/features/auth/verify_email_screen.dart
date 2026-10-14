import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final Widget body;
    if (_error != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 64),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center),
      ]);
    } else if (_done) {
      body = const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_outlined, size: 64),
        SizedBox(height: 16),
        Text('¡Correo confirmado!', style: TextStyle(fontSize: 20)),
      ]);
    } else {
      body = const CircularProgressIndicator();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar correo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            body,
            const SizedBox(height: 24),
            if (_done || _error != null)
              FilledButton(onPressed: () => context.go('/'), child: const Text('Continuar')),
          ]),
        ),
      ),
    );
  }
}
