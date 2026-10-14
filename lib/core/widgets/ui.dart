import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/providers.dart';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, Object e) => showSnack(context, errorMessage(e));

/// Ejecuta [action] mostrando el error en un snackbar. Devuelve true si salió bien.
Future<bool> guarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

class PickedImage {
  const PickedImage(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

/// Pide al usuario una foto (cámara o galería). Reduce el tamaño para que
/// quepa en el límite de 5 MB del servidor.
Future<PickedImage?> pickImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: const Text('Tomar foto'),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: const Text('Elegir de la galería'),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (f == null) return null;
    final name = f.name.isEmpty ? 'foto.jpg' : f.name;
    return PickedImage(await f.readAsBytes(), name);
  } catch (_) {
    if (context.mounted) showSnack(context, 'No se pudo abrir la cámara o la galería');
    return null;
  }
}

/// Diálogo de confirmación. Devuelve true si el usuario acepta.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String okLabel = 'Aceptar',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(okLabel)),
      ],
    ),
  );
  return r ?? false;
}

/// Pide un texto (p. ej. el motivo de un rechazo). Devuelve null si cancela.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String? hint,
  bool obscure = false,
  String okLabel = 'Aceptar',
}) async {
  final ctrl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        obscureText: obscure,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(okLabel)),
      ],
    ),
  );
  ctrl.dispose();
  return r;
}

/// Chip de estado con color según el tipo.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
