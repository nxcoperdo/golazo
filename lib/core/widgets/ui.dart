import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models.dart' show CourtVariant, courtTypeLabel, courtTypePlayers, courtTypes;
import '../../data/providers.dart';
import 'auth_ui.dart' show AuthField;

/// Las listas con `padding` propio no reciben el espacio de la barra inferior flotante
/// (la barra tapa el final del contenido): este método suma ese espacio abajo.
extension NavInset on EdgeInsets {
  EdgeInsets withNav(BuildContext context) => copyWith(bottom: bottom + MediaQuery.paddingOf(context).bottom);
}

/// Tipos de cancha que ofrece el dueño, cada uno con su precio por hora.
/// Cada tipo tiene además su propio calendario de reservas. Siempre queda al menos uno.
/// Informa cada cambio con [onChanged] (un precio vacío o inválido llega como 0).
class CourtVariantsEditor extends StatefulWidget {
  const CourtVariantsEditor({super.key, required this.initial, required this.onChanged});
  final List<CourtVariant> initial;
  final ValueChanged<List<CourtVariant>> onChanged;

  @override
  State<CourtVariantsEditor> createState() => _CourtVariantsEditorState();
}

class _CourtVariantsEditorState extends State<CourtVariantsEditor> {
  late final Map<int, TextEditingController> _prices = {
    for (final v in [...widget.initial]..sort((a, b) => a.type.compareTo(b.type)))
      v.type: TextEditingController(text: v.pricePerHour > 0 ? v.pricePerHour.toString() : ''),
  };

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<CourtVariant> get _value => [
        for (final t in (_prices.keys.toList()..sort()))
          CourtVariant(type: t, pricePerHour: int.tryParse(_prices[t]!.text.replaceAll(RegExp(r'\D'), '')) ?? 0),
      ];

  void _emit() => widget.onChanged(_value);

  String? _validatePrice(String? v) {
    final n = int.tryParse((v ?? '').replaceAll(RegExp(r'\D'), ''));
    return (n == null || n < 1000 || n > 1000000) ? 'Entre \$1.000 y \$1.000.000' : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final missing = [for (final t in courtTypes) if (!_prices.containsKey(t)) t];
    final types = _prices.keys.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tipos de cancha y precios', style: theme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Agrega cada tipo que ofreces y ponle su precio por hora. Cada tipo tiene su propio horario: '
        'si alguien reserva Fútbol 5, el Fútbol 11 sigue libre.',
        style: theme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (final t in types)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${courtTypeLabel(t)} · ${courtTypePlayers(t)}', style: theme.titleSmall),
                ),
                if (types.length > 1)
                  IconButton(
                    tooltip: 'Quitar ${courtTypeLabel(t)}',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _prices.remove(t)!.dispose();
                      _emit();
                    }),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AuthField(
                  label: 'Precio por hora (COP)',
                  icon: Icons.attach_money,
                  hint: '90000',
                  controller: _prices[t]!,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _emit(),
                  validator: _validatePrice,
                ),
              ),
            ]),
          ),
        ),
      if (missing.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in missing)
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(courtTypeLabel(t)),
              onPressed: () => setState(() {
                _prices[t] = TextEditingController();
                _emit();
              }),
            ),
        ]),
    ]);
  }
}

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

/// Cómo se pide la foto de un comprobante. Es un provider para reemplazarlo en las pruebas.
final pickImageProvider = Provider<Future<PickedImage?> Function(BuildContext)>((_) => pickImage);

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
  final picker = ImagePicker();
  try {
    var f = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    // Android puede reciclar la app mientras la cámara está abierta: la foto tomada se recupera aquí.
    if (f == null) {
      final lost = await picker.retrieveLostData();
      if (!lost.isEmpty && lost.file != null) f = lost.file;
    }
    if (f == null) return null;
    final name = f.name.isEmpty ? 'foto.jpg' : f.name;
    return PickedImage(await f.readAsBytes(), name);
  } on PlatformException catch (e) {
    if (context.mounted) {
      final denied = e.code.contains('access_denied') || e.code.contains('permission');
      showSnack(
        context,
        denied
            ? 'Activa el permiso de ${source == ImageSource.camera ? 'cámara' : 'fotos'} en los Ajustes del teléfono.'
            : 'No se pudo abrir la cámara o la galería',
      );
    }
    return null;
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
