import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';

/// Alta de una cancha nueva. Nace "pendiente": se hace visible al pagar la mensualidad.
class CourtFormScreen extends ConsumerStatefulWidget {
  const CourtFormScreen({super.key});

  @override
  ConsumerState<CourtFormScreen> createState() => _State();
}

class _State extends ConsumerState<CourtFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  int _open = 8;
  int _close = 23;
  bool _covered = false;
  bool _deposit = false;
  int _percent = 30;
  bool _busy = false;
  bool _locating = false;

  @override
  void dispose() {
    for (final c in [_name, _city, _address, _description, _price, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, 'Sin permiso de ubicación. Escribe las coordenadas a mano.');
        return;
      }
      final p = await Geolocator.getCurrentPosition();
      _lat.text = p.latitude.toStringAsFixed(6);
      _lng.text = p.longitude.toStringAsFixed(6);
    } catch (_) {
      if (mounted) showSnack(context, 'No se pudo obtener la ubicación. Escribe las coordenadas a mano.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String? _coord(String? v, double min, double max) {
    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (n == null || n < min || n > max) return 'Obligatorio';
    return null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_close <= _open) {
      showSnack(context, 'El cierre debe ser después de la apertura');
      return;
    }
    setState(() => _busy = true);
    try {
      final court = await ref.read(apiProvider).createCourt({
        'name': _name.text.trim(),
        'city': _city.text.trim(),
        'address': _address.text.trim(),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        'lat': double.parse(_lat.text.replaceAll(',', '.')),
        'lng': double.parse(_lng.text.replaceAll(',', '.')),
        'covered': _covered,
        'pricePerHour': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
        'openHour': _open,
        'closeHour': _close,
        'requiresDeposit': _deposit,
        if (_deposit) 'depositPercent': _percent,
      });
      ref.invalidate(ownerCourtsProvider);
      if (!mounted) return;
      showSnack(context, 'Cancha creada. Sube fotos y paga la mensualidad para publicarla.');
      context.pushReplacement('/owner/courts/${court.id}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider).value ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva cancha')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre de la cancha'),
            validator: (v) => (v == null || v.trim().length < 3) ? 'Mínimo 3 letras' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ciudad'),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Obligatoria' : null,
          ),
          if (cities.isNotEmpty)
            Wrap(spacing: 8, children: [
              for (final c in cities) ActionChip(label: Text(c), onPressed: () => setState(() => _city.text = c)),
            ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección'),
            validator: (v) => (v == null || v.trim().length < 3) ? 'Obligatoria' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
          ),
          const SizedBox(height: 8),
          Text('Ubicación', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text('Para que te encuentren por cercanía. Si estás en la cancha, usa el botón.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _locating ? null : _useLocation,
            icon: _locating
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: const Text('Usar mi ubicación actual'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitud'),
                validator: (v) => _coord(v, -90, 90),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitud'),
                validator: (v) => _coord(v, -180, 180),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Precio por hora (COP)', prefixText: r'$ '),
            validator: (v) {
              final n = int.tryParse((v ?? '').replaceAll(RegExp(r'\D'), ''));
              return (n == null || n < 1000 || n > 1000000) ? 'Entre \$1.000 y \$1.000.000' : null;
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _open,
                decoration: const InputDecoration(labelText: 'Abre'),
                items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(hourLabel(h)))],
                onChanged: (v) => setState(() => _open = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _close,
                decoration: const InputDecoration(labelText: 'Cierra'),
                items: [for (var h = 1; h <= 24; h++) DropdownMenuItem(value: h, child: Text(hourLabel(h)))],
                onChanged: (v) => setState(() => _close = v!),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cancha techada'),
            value: _covered,
            onChanged: (v) => setState(() => _covered = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exigir anticipo'),
            subtitle: const Text('El jugador paga un porcentaje por transferencia para confirmar.'),
            value: _deposit,
            onChanged: (v) => setState(() => _deposit = v),
          ),
          if (_deposit)
            Slider(
              min: 10,
              max: 100,
              divisions: 9,
              label: '$_percent%',
              value: _percent.toDouble(),
              onChanged: (v) => setState(() => _percent = v.round()),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Crear cancha'),
          ),
          const SizedBox(height: 12),
          Text(
            'Quedará oculta hasta que pagues la mensualidad. Después podrás subir fotos y tus cuentas de cobro.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}
