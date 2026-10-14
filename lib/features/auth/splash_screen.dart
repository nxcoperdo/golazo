import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logo.dart';
import '../../core/widgets/async_view.dart';
import '../../data/providers.dart';

/// Pantalla mientras se recupera la sesión guardada (o si el servidor no responde).
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: SafeArea(
        child: session.hasError
            ? ErrorRetry(
                message: errorMessage(session.error!),
                onRetry: () => ref.read(sessionProvider.notifier).retry(),
              )
            : const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  GolazoLogo(size: 96),
                  SizedBox(height: 24),
                  CircularProgressIndicator(),
                ]),
              ),
      ),
    );
  }
}
