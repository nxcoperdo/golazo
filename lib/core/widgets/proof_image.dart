import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Comprobante de pago (imagen privada que se descarga con la sesión).
/// Al tocarlo se abre en grande con zoom.
class ProofImage extends ConsumerWidget {
  const ProofImage({super.key, required this.paymentId, this.height = 160});
  final String paymentId;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = ref.watch(proofImageProvider(paymentId));
    return img.when(
      loading: () => SizedBox(height: height, child: const Center(child: CircularProgressIndicator())),
      error: (e, _) => SizedBox(
        height: height,
        child: Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(proofImageProvider(paymentId)),
            icon: const Icon(Icons.refresh),
            label: const Text('No se pudo cargar el comprobante'),
          ),
        ),
      ),
      data: (bytes) => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(child: Image.memory(bytes)),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, height: height, width: double.infinity, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// Miniatura cuadrada del comprobante; al tocarla se abre en grande con zoom.
class ProofThumb extends ConsumerWidget {
  const ProofThumb({super.key, required this.paymentId, this.size = 64});
  final String paymentId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = ref.watch(proofImageProvider(paymentId));
    const bg = Color(0xFFE6EEE2);
    Widget box(Widget child) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: child,
        );
    return img.when(
      loading: () => box(const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => InkWell(
        onTap: () => ref.invalidate(proofImageProvider(paymentId)),
        child: box(const Icon(Icons.refresh, size: 20, semanticLabel: 'Recargar comprobante')),
      ),
      data: (bytes) => Semantics(
        button: true,
        label: 'Ver comprobante',
        child: GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              child: InteractiveViewer(child: Image.memory(bytes)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
