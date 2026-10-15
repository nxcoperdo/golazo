import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
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
  int _courtType = 5;
  bool _deposit = false;
  int _percent = 30;
  bool _busy = false;
  bool _locating = false;
  bool _manualCoords = false;

  @override
  void dispose() {
    for (final c in [_name, _city, _address, _description, _price, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasCoords => _lat.text.trim().isNotEmpty && _lng.text.trim().isNotEmpty;

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      final p = await ref.read(locationProvider)();
      _lat.text = p.lat.toStringAsFixed(6);
      _lng.text = p.lng.toStringAsFixed(6);
    } on LocationUnavailable {
      if (mounted) {
        setState(() => _manualCoords = true);
        showSnack(context, 'No se pudo obtener la ubicación. Escribe las coordenadas a mano.');
      }
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
    if (!_hasCoords) {
      setState(() => _manualCoords = true);
      showSnack(context, 'Usa tu ubicación actual o escribe las coordenadas.');
      return;
    }
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
        'courtType': _courtType,
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

  Future<void> _pickHour(bool opening) async {
    final v = await showPickSheet<int>(
      context,
      title: opening ? 'Abre' : 'Cierra',
      selected: opening ? _open : _close,
      options: [for (var h = opening ? 0 : 1; h <= (opening ? 23 : 24); h++) (h, hourLabel(h))],
    );
    if (v != null) {
      setState(() {
        if (opening) {
          _open = v;
        } else {
          _close = v;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider).value ?? const <String>[];
    return AppPage(
      kicker: 'Nueva',
      title: 'Crear cancha',
      onBack: () => context.canPop() ? context.pop() : context.go('/owner?tab=2'),
      child: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24).withNav(context), children: [
          AuthField(
            label: 'Nombre',
            icon: Icons.sports_soccer,
            hint: 'Nombre de la cancha',
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().length < 3) ? 'Mínimo 3 letras' : null,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'Ciudad',
            icon: Icons.place_outlined,
            hint: 'Selecciona o escribe una ciudad',
            controller: _city,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().length < 2) ? 'Obligatoria' : null,
          ),
          if (cities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in cities) ActionChip(label: Text(c), onPressed: () => setState(() => _city.text = c)),
            ]),
          ],
          const SizedBox(height: 16),
          AuthField(
            label: 'Dirección',
            icon: Icons.map_outlined,
            hint: 'Calle, número y barrio',
            controller: _address,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().length < 3) ? 'Obligatoria' : null,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'Descripción (opcional)',
            icon: Icons.notes,
            hint: 'Iluminación, camerinos, parqueadero…',
            controller: _description,
            maxLines: 3,
            maxLength: 1000,
          ),
          const SizedBox(height: 8),
          Material(
            color: const Color(0xFFE8F2E4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AuthColors.primary.withValues(alpha: 0.15)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _locating ? null : _useLocation,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_locating)
                    const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    const Icon(Icons.my_location, size: 17, color: AuthColors.primary),
                  const SizedBox(width: 8),
                  Text(_hasCoords ? 'Ubicación lista · usar otra vez' : 'Usar mi ubicación actual',
                      style: authText(14, weight: 800, color: AuthColors.primary)),
                ]),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _manualCoords = !_manualCoords),
              child: Text(_manualCoords ? 'Ocultar coordenadas' : 'Ingresar coordenadas a mano'),
            ),
          ),
          if (_manualCoords) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AuthField(
                  label: 'Latitud',
                  icon: Icons.explore_outlined,
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  validator: (v) => _coord(v, -90, 90),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AuthField(
                  label: 'Longitud',
                  icon: Icons.explore_outlined,
                  controller: _lng,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  validator: (v) => _coord(v, -180, 180),
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          AuthField(
            label: 'Precio por hora (COP)',
            icon: Icons.attach_money,
            hint: '90000',
            controller: _price,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse((v ?? '').replaceAll(RegExp(r'\D'), ''));
              return (n == null || n < 1000 || n > 1000000) ? 'Entre \$1.000 y \$1.000.000' : null;
            },
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: PickTile(label: 'Abre', value: hourLabel(_open), onTap: () => _pickHour(true))),
            const SizedBox(width: 12),
            Expanded(child: PickTile(label: 'Cierra', value: hourLabel(_close), onTap: () => _pickHour(false))),
          ]),
          const SizedBox(height: 16),
          CourtTypePicker(value: _courtType, onChanged: (t) => setState(() => _courtType = t)),
          const SizedBox(height: 16),
          ToggleRow(title: 'Cancha techada', value: _covered, onChanged: (v) => setState(() => _covered = v)),
          const SizedBox(height: 12),
          ToggleRow(
            title: 'Exigir anticipo',
            subtitle: 'El jugador paga un porcentaje por transferencia para confirmar.',
            value: _deposit,
            onChanged: (v) => setState(() => _deposit = v),
          ),
          if (_deposit) ...[
            const SizedBox(height: 12),
            PickTile(
              label: 'Porcentaje de anticipo',
              value: '$_percent %',
              onTap: () async {
                final v = await showPickSheet<int>(
                  context,
                  title: 'Porcentaje de anticipo',
                  selected: _percent,
                  options: [for (var p = 10; p <= 100; p += 10) (p, '$p %')],
                );
                if (v != null) setState(() => _percent = v);
              },
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(label: 'Crear cancha', busy: _busy, onPressed: _submit),
          const SizedBox(height: 12),
          Text(
            'Quedará oculta hasta que pagues la mensualidad. Después podrás subir fotos y tus cuentas de cobro.',
            textAlign: TextAlign.center,
            style: authText(11, weight: 500, color: const Color(0xFF7D8982), height: 1.5),
          ),
        ]),
      ),
    );
  }
}
