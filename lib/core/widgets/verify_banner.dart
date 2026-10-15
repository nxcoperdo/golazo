import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'auth_ui.dart';
import 'ui.dart';

/// Aviso "Confirma tu correo" mientras el usuario no lo haya confirmado.
class VerifyBanner extends ConsumerWidget {
  const VerifyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value;
    if (user == null || user.emailVerified || user.email == null) return const SizedBox.shrink();
    const fg = Color(0xFF725815);
    return Container(
      color: const Color(0xFFFFF6D9),
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(children: [
        const Icon(Icons.mark_email_unread_outlined, size: 20, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Confirma tu correo con el enlace que te enviamos.',
              style: authText(12, weight: 700, color: fg, height: 1.3)),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AuthColors.link, padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: () => guarded(context, () => ref.read(apiProvider).resendVerification(),
              success: 'Te enviamos el correo otra vez'),
          child: Text('Reenviar', style: authText(12, weight: 800, color: AuthColors.link)),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AuthColors.link, padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: () => ref.read(sessionProvider.notifier).reload(),
          child: Text('Ya lo confirmé', style: authText(12, weight: 800, color: AuthColors.link)),
        ),
      ]),
    );
  }
}
