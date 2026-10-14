import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Muestra el resultado de un provider asíncrono: cargando, error con
/// "Reintentar", y los datos. Permite jalar para refrescar.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
    this.emptyText,
    this.isEmpty,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  /// Si [isEmpty] devuelve true, se muestra [emptyText] en lugar de los datos.
  final String? emptyText;
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      // Con datos previos (al refrescar) no se tapa la pantalla con un spinner.
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(message: errorMessage(e), onRetry: onRetry),
      data: (d) {
        if (emptyText != null && (isEmpty?.call(d) ?? false)) {
          return RefreshIndicator(
            onRefresh: () async => onRetry(),
            child: ListView(children: [
              const SizedBox(height: 120),
              Center(child: Text(emptyText!, textAlign: TextAlign.center)),
            ]),
          );
        }
        return builder(d);
      },
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ]),
        ),
      );
}
