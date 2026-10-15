import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/validators.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Gestión de una cancha: fotos, datos, estado, cuentas de cobro y mensualidad.
class CourtManageScreen extends ConsumerStatefulWidget {
  const CourtManageScreen({super.key, required this.courtId});
  final String courtId;

  @override
  ConsumerState<CourtManageScreen> createState() => _State();
}

class _State extends ConsumerState<CourtManageScreen> {
  bool _busy = false;

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

  Future<void> _addPhoto() async {
    final img = await ref.read(pickImageProvider)(context);
    if (img == null || !mounted) return;
    await _run(() => ref.read(apiProvider).addCourtPhoto(widget.courtId, img.bytes, img.filename),
        success: 'Foto agregada');
  }

  Future<void> _removePhoto(CourtPhoto p) async {
    if (p.id == null) return;
    final ok = await showAppSheet<bool>(
      context,
      builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeading('¿Borrar esta foto?'),
        SheetActions(primaryLabel: 'Borrar', danger: true, onPrimary: () => Navigator.pop(sheet, true)),
      ]),
    );
    if (ok != true || !mounted) return;
    await _run(() => ref.read(apiProvider).removeCourtPhoto(widget.courtId, p.id!));
  }

  Future<void> _setMethods(List<PaymentMethod> methods) =>
      _run(() => ref.read(apiProvider).setPaymentMethods(widget.courtId, methods), success: 'Cuentas guardadas');

  Future<void> _addMethod(Court c) async {
    final v = await showFormSheet(
      context,
      title: 'Nueva cuenta de cobro',
      subtitle: 'Los jugadores ven esta cuenta cuando deben pagar un anticipo.',
      primaryLabel: 'Agregar cuenta',
      initial: ['', '', ''],
      fields: [
        (x) => AuthField(
              label: 'Medio',
              icon: Icons.account_balance_wallet_outlined,
              controller: x,
              hint: 'Nequi, Daviplata o banco',
              validator: (t) => Validators.required(t, 'El medio'),
            ),
        (x) => AuthField(
              label: 'Número de cuenta o celular',
              icon: Icons.phone_outlined,
              controller: x,
              hint: '300 000 0000',
              validator: (t) => Validators.required(t, 'El número'),
            ),
        (x) => AuthField(
              label: 'Titular',
              icon: Icons.person_outline,
              controller: x,
              hint: 'Nombre del titular',
              validator: (t) => Validators.required(t, 'El titular'),
            ),
      ],
    );
    if (v == null || !mounted) return;
    await _setMethods([...c.paymentMethods, PaymentMethod(label: v[0], account: v[1], holder: v[2])]);
  }

  Future<void> _paySubscription(Court c) async {
    final sent = await showAppSheet<bool>(
      context,
      builder: (sheet) => _SubscriptionBody(courtId: c.id, onSent: () => Navigator.pop(sheet, true)),
    );
    if (sent == true && mounted) {
      _refresh();
      showSnack(context, 'Comprobante enviado. Te avisaremos cuando lo revisen.');
    }
  }

  Future<void> _togglePause(Court c) async {
    final pausing = c.status == CourtStatus.active;
    if (pausing) {
      final ok = await showAppSheet<bool>(
        context,
        builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHeading('¿Ocultar la cancha?',
              subtitle: 'Dejará de aparecer en el buscador. Las reservas que ya tienes se mantienen.'),
          SheetActions(primaryLabel: 'Ocultar', danger: true, onPrimary: () => Navigator.pop(sheet, true)),
        ]),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    await _run(() => pausing ? ref.read(apiProvider).pauseCourt(c.id) : ref.read(apiProvider).resumeCourt(c.id),
        success: pausing ? 'Cancha oculta' : 'Cancha visible otra vez');
  }

  Future<void> _editData(Court c) async {
    final data = await showAppSheet<Map<String, dynamic>>(
      context,
      builder: (sheet) => _EditCourtBody(court: c, onSave: (d) => Navigator.pop(sheet, d)),
    );
    if (data == null || !mounted) return;
    await _run(() => ref.read(apiProvider).updateCourt(widget.courtId, data), success: 'Cambios guardados');
  }

  @override
  Widget build(BuildContext context) {
    final court = ref.watch(ownerCourtProvider(widget.courtId));
    return AppPage(
      kicker: 'Administrar',
      title: court.value?.name ?? 'Mi cancha',
      onBack: () => context.canPop() ? context.pop() : context.go('/owner?tab=2'),
      child: AsyncView<Court>(
        value: court,
        onRetry: _refresh,
        builder: (c) => ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24).withNav(context), children: [
          Text('Fotos', style: authText(14, weight: 800)),
          const SizedBox(height: 12),
          _photos(c),
          const SizedBox(height: 24),
          SoftCard(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Datos de la cancha', style: authText(16, weight: 800)),
              const SizedBox(height: 8),
              Text(
                '${courtTypesLabel(c.types)} · ${c.covered ? 'Techada' : 'Al aire libre'} · ${cop(c.pricePerHour)}/h · '
                '${hourLabel(c.openHour)} – ${hourLabel(c.closeHour)}'
                '${c.requiresDeposit ? ' · Anticipo ${c.depositPercent} %' : ''}',
                style: authText(12, weight: 500, color: const Color(0xFF6C7B72), height: 1.5),
              ),
              const SizedBox(height: 4),
              Text('${c.address}, ${c.city}', style: authText(12, weight: 500, color: const Color(0xFF6C7B72), height: 1.5)),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40), alignment: Alignment.centerLeft),
                onPressed: _busy ? null : () => _editData(c),
                child: const Text('Editar datos'),
              ),
            ]),
          ),
          _statusCard(c),
          _accountsCard(c),
          _subscriptionCard(c),
        ]),
      ),
    );
  }

  Widget _photos(Court c) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final p in c.photos)
            Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: AppConfig.fileUrl(p.url),
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: _busy ? null : () => _removePhoto(p),
                  child: const CircleAvatar(radius: 12, backgroundColor: Colors.white, child: Icon(Icons.close, size: 15, semanticLabel: 'Borrar foto')),
                ),
              ),
            ]),
          if (c.photos.length < 8)
            Semantics(
              button: true,
              label: 'Agregar foto',
              child: CustomPaint(
                foregroundPainter: _DashPainter(AuthColors.primary.withValues(alpha: 0.2)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _busy ? null : _addPhoto,
                  child: const Center(child: Icon(Icons.add, size: 28, color: AuthColors.primary)),
                ),
              ),
            ),
        ],
      );

  Widget _statusCard(Court c) {
    final sub = c.subscription;
    final canToggle = c.status == CourtStatus.active || (c.status == CourtStatus.suspended && sub?.activeUntil != null);
    final String detail;
    if (sub?.pendingReview == true) {
      detail = 'Tu comprobante de mensualidad está en revisión.';
    } else if (c.status == CourtStatus.pending) {
      detail = 'Oculta hasta que pagues la mensualidad.';
    } else if (c.status == CourtStatus.suspended) {
      detail = 'Oculta en el buscador';
    } else {
      detail = 'Activa y visible';
    }
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Estado', style: authText(16, weight: 800)),
            const SizedBox(height: 4),
            Text(detail, style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
          ]),
        ),
        PillSwitch(
          value: c.status == CourtStatus.active,
          semanticLabel: 'Cancha visible',
          onChanged: canToggle && !_busy ? (_) => _togglePause(c) : null,
        ),
      ]),
    );
  }

  Widget _accountsCard(Court c) => SoftCard(
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Cuentas para pagos', style: authText(16, weight: 800))),
            TextButton(
              onPressed: _busy || c.paymentMethods.length >= 5 ? null : () => _addMethod(c),
              child: const Text('Agregar'),
            ),
          ]),
          if (c.paymentMethods.isEmpty)
            Text('Los jugadores ven tus cuentas cuando deben pagar un anticipo.',
                style: authText(12, weight: 500, color: const Color(0xFF6C7B72), height: 1.5))
          else
            for (final m in c.paymentMethods)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m.label} · ${m.account}', style: authText(12, weight: 700)),
                      Text(m.holder, style: authText(11, weight: 500, color: const Color(0xFF6C7B72))),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Quitar cuenta',
                    icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFB13C35)),
                    onPressed: _busy ? null : () => _setMethods(c.paymentMethods.where((x) => x != m).toList()),
                  ),
                ]),
              ),
        ]),
      );

  Widget _subscriptionCard(Court c) {
    final sub = c.subscription;
    final price = ref.watch(subscriptionConfigProvider).value?.price;
    final (pill, tone) = sub?.pendingReview == true
        ? ('En revisión', PillTone.blue)
        : c.status == CourtStatus.pending
            ? ('Pendiente', PillTone.amber)
            : _until(sub?.activeUntil);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7DC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDFC974)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StatusPill(pill, tone),
        const SizedBox(height: 12),
        Text(price == null ? 'Mensualidad' : 'Mensualidad · ${cop(price)}', style: authText(16, weight: 800)),
        const SizedBox(height: 4),
        Text('Mantén tu cancha visible durante 30 días.',
            style: authText(12, weight: 500, color: const Color(0xFF76683C), height: 1.5)),
        const SizedBox(height: 16),
        SolidAction(
          label: c.status == CourtStatus.active ? 'Renovar mensualidad' : 'Pagar mensualidad',
          onPressed: _busy || sub?.pendingReview == true ? null : () => _paySubscription(c),
        ),
      ]),
    );
  }

  /// "Vence en N días" / "Vence hoy" / "Vencida" a partir de la fecha YYYY-MM-DD (hora de Colombia).
  static (String, PillTone) _until(String? date) {
    if (date == null) return ('Sin pagar', PillTone.amber);
    final end = DateTime.tryParse(date);
    if (end == null) return ('Pagada', PillTone.green);
    final left = DateTime.utc(end.year, end.month, end.day).difference(coToday()).inDays;
    if (left < 0) return ('Vencida', PillTone.red);
    if (left == 0) return ('Vence hoy', PillTone.amber);
    return (left == 1 ? 'Vence mañana' : 'Vence en $left días', left <= 3 ? PillTone.amber : PillTone.green);
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, (d + 5).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Hoja "Editar datos": el formulario completo de la cancha. Devuelve el cuerpo para `updateCourt`.
class _EditCourtBody extends StatefulWidget {
  const _EditCourtBody({required this.court, required this.onSave});
  final Court court;
  final void Function(Map<String, dynamic> data) onSave;

  @override
  State<_EditCourtBody> createState() => _EditCourtBodyState();
}

class _EditCourtBodyState extends State<_EditCourtBody> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.court.name);
  late final _description = TextEditingController(text: widget.court.description ?? '');
  late final _address = TextEditingController(text: widget.court.address);
  late final _price = TextEditingController(text: widget.court.pricePerHour.toString());
  late int _open = widget.court.openHour;
  late int _close = widget.court.closeHour;
  late bool _covered = widget.court.covered;
  late List<int> _courtTypes = List.of(widget.court.types);
  late bool _deposit = widget.court.requiresDeposit;
  late int _percent = widget.court.depositPercent;

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_close <= _open) {
      showSnack(context, 'El cierre debe ser después de la apertura');
      return;
    }
    widget.onSave({
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'address': _address.text.trim(),
      'pricePerHour': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
      'openHour': _open,
      'closeHour': _close,
      'covered': _covered,
      'courtTypes': _courtTypes,
      'requiresDeposit': _deposit,
      if (_deposit) 'depositPercent': _percent,
    });
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
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHeading('Editar datos'),
          AuthField(
            label: 'Nombre',
            icon: Icons.sports_soccer,
            controller: _name,
            validator: (v) => (v == null || v.trim().length < 3) ? 'Mínimo 3 letras' : null,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'Dirección',
            icon: Icons.map_outlined,
            controller: _address,
            validator: (v) => (v == null || v.trim().length < 3) ? 'Obligatoria' : null,
          ),
          const SizedBox(height: 16),
          AuthField(label: 'Descripción', icon: Icons.notes, controller: _description, maxLines: 3, maxLength: 1000),
          const SizedBox(height: 8),
          AuthField(
            label: 'Precio por hora (COP)',
            icon: Icons.attach_money,
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
          CourtTypePicker(value: _courtTypes, onChanged: (t) => setState(() => _courtTypes = t)),
          const SizedBox(height: 16),
          ToggleRow(title: 'Cancha techada', value: _covered, onChanged: (v) => setState(() => _covered = v)),
          const SizedBox(height: 12),
          ToggleRow(
            title: 'Exigir anticipo',
            subtitle: _deposit ? '$_percent % del valor de la reserva' : 'La reserva se confirma al instante',
            value: _deposit,
            onChanged: (v) => setState(() => _deposit = v),
          ),
          if (_deposit) ...[
            const SizedBox(height: 12),
            PickTile(
              label: 'Porcentaje de anticipo',
              value: '$_percent %',
              onTap: () async {
                final v = await showPickSheet<int>(context,
                    title: 'Porcentaje de anticipo',
                    selected: _percent,
                    options: [for (var p = 10; p <= 100; p += 10) (p, '$p %')]);
                if (v != null) setState(() => _percent = v);
              },
            ),
          ],
          SheetActions(primaryLabel: 'Guardar cambios', onPrimary: _save),
        ]),
      );
}

/// Cuenta de la plataforma + subida del comprobante de la mensualidad.
class _SubscriptionBody extends ConsumerStatefulWidget {
  const _SubscriptionBody({required this.courtId, required this.onSent});
  final String courtId;
  final VoidCallback onSent;

  @override
  ConsumerState<_SubscriptionBody> createState() => _SubscriptionBodyState();
}

class _SubscriptionBodyState extends ConsumerState<_SubscriptionBody> {
  PickedImage? _proof;
  bool _busy = false;

  Future<void> _pick() async {
    final img = await ref.read(pickImageProvider)(context);
    if (img != null && mounted) setState(() => _proof = img);
  }

  Future<void> _send() async {
    final img = _proof;
    if (img == null) return;
    setState(() => _busy = true);
    final ok = await guarded(
      context,
      () => ref.read(apiProvider).uploadSubscriptionProof(widget.courtId, img.bytes, img.filename),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(subscriptionConfigProvider);
    return AsyncView<SubscriptionConfig>(
      value: cfg,
      onRetry: () => ref.invalidate(subscriptionConfigProvider),
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeading('Pagar mensualidad', subtitle: '${cop(c.price)} por ${c.periodDays} días.'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF2F5EE), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Transfiere a la cuenta de la plataforma', style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
            if (c.accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Aún no hay cuentas configuradas. Escríbenos para coordinar el pago.',
                    style: authText(14, weight: 600, height: 1.4)),
              )
            else
              for (final a in c.accounts) ...[
                const SizedBox(height: 8),
                Text('${a.label} · ${a.account}', style: authText(18, weight: 800)),
                Text(a.holder, style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
              ],
            const SizedBox(height: 8),
            Text(cop(c.price), style: authText(14, weight: 800)),
          ]),
        ),
        const SizedBox(height: 16),
        ProofDropZone(fileName: _proof?.filename, onTap: _busy ? null : _pick),
        SheetActions(primaryLabel: 'Enviar comprobante', busy: _busy, onPrimary: _proof == null ? null : _send),
      ]),
    );
  }
}
