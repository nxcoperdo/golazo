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
