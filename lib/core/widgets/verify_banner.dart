import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'ui.dart';

/// Aviso "Confirma tu correo" mientras el usuario no lo haya confirmado.
class VerifyBanner extends ConsumerWidget {
  const VerifyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value;
    if (user == null || user.emailVerified || user.email == null) return const SizedBox.shrink();
    return MaterialBanner(
      leading: const Icon(Icons.mark_email_unread_outlined),
      content: const Text('Confirma tu correo con el enlace que te enviamos.'),
      actions: [
        TextButton(
          onPressed: () => guarded(context, () => ref.read(apiProvider).resendVerification(),
              success: 'Te enviamos el correo otra vez'),
          child: const Text('Reenviar'),
        ),
        TextButton(
          onPressed: () => ref.read(sessionProvider.notifier).reload(),
          child: const Text('Ya lo confirmé'),
        ),
      ],
    );
  }
}
