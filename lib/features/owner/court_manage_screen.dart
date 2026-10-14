import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/validators.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/status_style.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../booking/payment_info.dart';

/// Gestión de una cancha: estado y mensualidad, fotos, datos, anticipo y cuentas de cobro.
class CourtManageScreen extends ConsumerStatefulWidget {
  const CourtManageScreen({super.key, required this.courtId});
  final String courtId;

  @override
  ConsumerState<CourtManageScreen> createState() => _State();
}

class _State extends ConsumerState<CourtManageScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _price = TextEditingController();
  int _open = 8;
  int _close = 23;
  bool _covered = false;
  bool _deposit = false;
  int _percent = 30;
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Llena el formulario la primera vez que llegan los datos (no pisa lo que el dueño está editando).
  void _fill(Court c) {
    if (_loaded) return;
    _loaded = true;
    _name.text = c.name;
    _description.text = c.description ?? '';
    _address.text = c.address;
    _price.text = c.pricePerHour.toString();
    _open = c.openHour;
    _close = c.closeHour;
    _covered = c.covered;
    _deposit = c.requiresDeposit;
    _percent = c.depositPercent;
  }

  void _refresh() {
    ref.invalidate(ownerCourtProvider(widget.courtId));
    ref.invalidate(ownerCourtsProvider);
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    final ok = await guarded(context, action, success: success);
    if (ok) _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_close <= _open) {
      showSnack(context, 'El cierre debe ser después de la apertura');
      return;
    }
    await _run(() async {
      await ref.read(apiProvider).updateCourt(widget.courtId, {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'address': _address.text.trim(),
        'pricePerHour': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
        'openHour': _open,
        'closeHour': _close,
        'covered': _covered,
        'requiresDeposit': _deposit,
        if (_deposit) 'depositPercent': _percent,
      });
    }, success: 'Cambios guardados');
  }

  Future<void> _addPhoto() async {
    final img = await pickImage(context);
    if (img == null || !mounted) return;
    await _run(() => ref.read(apiProvider).addCourtPhoto(widget.courtId, img.bytes, img.filename),
        success: 'Foto agregada');
  }

  Future<void> _removePhoto(CourtPhoto p) async {
    if (p.id == null || !await confirm(context, title: '¿Borrar esta foto?', okLabel: 'Borrar')) return;
    if (!mounted) return;
    await _run(() => ref.read(apiProvider).removeCourtPhoto(widget.courtId, p.id!));
  }

  Future<void> _setMethods(List<PaymentMethod> methods) =>
      _run(() => ref.read(apiProvider).setPaymentMethods(widget.courtId, methods), success: 'Cuentas guardadas');

  Future<void> _addMethod(Court c) async {
    final label = TextEditingController();
    final account = TextEditingController();
    final holder = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva cuenta de cobro'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Medio (Nequi, Daviplata, banco…)'),
              validator: (v) => Validators.required(v, 'El medio'),
            ),
            TextFormField(
              controller: account,
              decoration: const InputDecoration(labelText: 'Número de cuenta o celular'),
              validator: (v) => Validators.required(v, 'El número'),
            ),
            TextFormField(
              controller: holder,
              decoration: const InputDecoration(labelText: 'Titular'),
              validator: (v) => Validators.required(v, 'El titular'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final m = PaymentMethod(label: label.text.trim(), account: account.text.trim(), holder: holder.text.trim());
    label.dispose();
    account.dispose();
    holder.dispose();
    if (ok == true && mounted) await _setMethods([...c.paymentMethods, m]);
  }

  Future<void> _paySubscription(Court c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubscriptionSheet(courtId: c.id, onSent: _refresh),
    );
  }

  Future<void> _togglePause(Court c) async {
    final pausing = c.status == CourtStatus.active;
    if (pausing &&
        !await confirm(context,
            title: '¿Ocultar la cancha?',
            message: 'Dejará de aparecer en el buscador. Las reservas que ya tienes se mantienen.',
            okLabel: 'Ocultar')) {
      return;
    }
    if (!mounted) return;
    await _run(() => pausing ? ref.read(apiProvider).pauseCourt(c.id) : ref.read(apiProvider).resumeCourt(c.id),
        success: pausing ? 'Cancha oculta' : 'Cancha visible otra vez');
  }

  @override
  Widget build(BuildContext context) {
    final court = ref.watch(ownerCourtProvider(widget.courtId));
    return Scaffold(
      appBar: AppBar(title: Text(court.value?.name ?? 'Mi cancha')),
      body: AsyncView<Court>(
        value: court,
        onRetry: _refresh,
        builder: (c) {
          _fill(c);
          return ListView(padding: const EdgeInsets.all(16), children: [
            _statusCard(c),
            const SizedBox(height: 16),
            Text('Fotos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _photos(c),
            const SizedBox(height: 16),
            Text('Datos de la cancha', style: Theme.of(context).textTheme.titleMedium),
            _formFields(),
            const SizedBox(height: 16),
            Text('Cuentas para recibir pagos', style: Theme.of(context).textTheme.titleMedium),
            const Text('Los jugadores ven estas cuentas cuando deben pagar un anticipo.'),
            for (final m in c.paymentMethods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m.label} · ${m.account}'),
                subtitle: Text(m.holder),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _setMethods(c.paymentMethods.where((x) => x != m).toList()),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy || c.paymentMethods.length >= 5 ? null : () => _addMethod(c),
                icon: const Icon(Icons.add),
                label: const Text('Agregar cuenta'),
              ),
            ),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }

  Widget _statusCard(Court c) {
    final sub = c.subscription;
    final String detail;
    if (sub?.pendingReview == true) {
      detail = 'Tu comprobante de mensualidad está en revisión.';
    } else if (c.status == CourtStatus.pending) {
      detail = 'Está oculta. Paga la mensualidad para que aparezca en el buscador.';
    } else if (c.status == CourtStatus.suspended) {
      detail = 'Está oculta del buscador.';
    } else {
      detail = sub?.activeUntil != null ? 'Visible. Mensualidad pagada hasta el ${sub!.activeUntil}.' : 'Visible en el buscador.';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Estado', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            StatusChip(courtStatusLabel(c.status), color: courtStatusColor(c.status)),
          ]),
          const SizedBox(height: 4),
          Text(detail),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy || sub?.pendingReview == true ? null : () => _paySubscription(c),
              icon: const Icon(Icons.workspace_premium),
              label: Text(c.status == CourtStatus.active ? 'Renovar mensualidad' : 'Pagar mensualidad'),
            ),
            if (c.status == CourtStatus.active || (c.status == CourtStatus.suspended && sub?.activeUntil != null))
              OutlinedButton(
                onPressed: _busy ? null : () => _togglePause(c),
                child: Text(c.status == CourtStatus.active ? 'Ocultar' : 'Volver a mostrar'),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _photos(Court c) => SizedBox(
        height: 110,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final p in c.photos)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: AppConfig.fileUrl(p.url),
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox(width: 110, child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    onTap: _busy ? null : () => _removePhoto(p),
                    child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 16)),
                  ),
                ),
              ]),
            ),
          if (c.photos.length < 8)
            InkWell(
              onTap: _busy ? null : _addPhoto,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo_outlined),
                  SizedBox(height: 4),
                  Text('Agregar'),
                ]),
              ),
            ),
        ]),
      );

  Widget _formFields() => Form(
        key: _form,
        child: Column(children: [
          const SizedBox(height: 8),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) => (v == null || v.trim().length < 3) ? 'Mínimo 3 letras' : null,
          ),
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
            decoration: const InputDecoration(labelText: 'Descripción'),
          ),
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
            subtitle: Text(_deposit ? '$_percent% del valor de la reserva' : 'La reserva se confirma al instante'),
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Guardar cambios'),
            ),
          ),
        ]),
      );
}

/// Cuentas de Golazo + subida del comprobante de la mensualidad.
class _SubscriptionSheet extends ConsumerStatefulWidget {
  const _SubscriptionSheet({required this.courtId, required this.onSent});
  final String courtId;
  final VoidCallback onSent;

  @override
  ConsumerState<_SubscriptionSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_SubscriptionSheet> {
  bool _busy = false;

  Future<void> _upload() async {
    final img = await pickImage(context);
    if (img == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await guarded(
      context,
      () => ref.read(apiProvider).uploadSubscriptionProof(widget.courtId, img.bytes, img.filename),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onSent();
      Navigator.pop(context);
      showSnack(context, 'Comprobante enviado. Te avisaremos cuando lo revisen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(subscriptionConfigProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: AsyncView<SubscriptionConfig>(
          value: cfg,
          onRetry: () => ref.invalidate(subscriptionConfigProvider),
          builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mensualidad', style: Theme.of(context).textTheme.titleLarge),
            Text('${cop(c.price)} por ${c.periodDays} días'),
            const SizedBox(height: 8),
            const Text('1. Transfiere el valor a una de estas cuentas.\n2. Sube la captura del comprobante.'),
            if (c.accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Aún no hay cuentas configuradas. Escríbenos para coordinar el pago.'),
              )
            else
              PaymentInfo(methods: c.accounts, amount: c.price, title: 'Transfiere'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Subir comprobante'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
