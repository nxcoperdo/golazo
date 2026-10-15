import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logo.dart';
import '../../core/widgets/auth_ui.dart';
import '../../data/providers.dart';

/// Pantalla mientras se recupera la sesión guardada (o si el servidor no responde).
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Theme(
      data: authTheme(Theme.of(context)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AuthColors.splash,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(children: [
                const Expanded(child: Center(child: GolazoLogo(width: 300))),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: session.hasError
                      ? _ConnectionError(onRetry: () => ref.read(sessionProvider.notifier).retry())
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AuthColors.lime),
                          ),
                          const SizedBox(width: 12),
                          Text('Recuperando tu sesión',
                              style: authText(12, weight: 600, color: Colors.white.withValues(alpha: 0.55))),
                        ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('No pudimos conectar',
              textAlign: TextAlign.center, style: authText(14, weight: 800, color: Colors.white)),
          const SizedBox(height: 4),
          Text('Revisa tu conexión e inténtalo de nuevo.',
              textAlign: TextAlign.center,
              style: authText(12, weight: 500, color: Colors.white.withValues(alpha: 0.55), height: 1.5)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AuthColors.lime,
              foregroundColor: AuthColors.ink,
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ]),
      );
}
