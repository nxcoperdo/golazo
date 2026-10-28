import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/validators.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../player/courts_screen.dart' show CourtImage;
import 'booking_policy.dart';
import 'reviews_section.dart';

/// Detalle de la cancha + elegir día y horas + confirmar (flujo de 3 toques:
/// cancha → hora → confirmar).
class CourtDetailScreen extends ConsumerStatefulWidget {
  const CourtDetailScreen({super.key, required this.courtId});
  final String courtId;

  @override
  ConsumerState<CourtDetailScreen> createState() => _State();
}

class _State extends ConsumerState<CourtDetailScreen> {
  static const _daysAhead = 14;

  late final DateTime _today = coToday();
  late DateTime _day = _today;
  Set<int> _hours = {};

  /// Tipo elegido; mientras no elija, el más barato.
  int? _courtType;
  bool _busy = false;
  final _phone = TextEditingController();
  final _reviewsKey = GlobalKey();

  CourtVariant _variant(Court c) => c.options.firstWhere((v) => v.type == _courtType, orElse: () => c.options.first);

  AvailabilityKey _key(Court c) => (courtId: widget.courtId, day: _day, courtType: _variant(c).type);

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  /// El dueño necesita un celular para contactar al jugador: se pide aquí solo si falta.
  bool get _needsPhone {
    final user = ref.read(sessionProvider).value;
    return user != null && !user.hasPhone;
  }

  bool get _phoneOk => !_needsPhone || Validators.phone(_phone.text) == null;

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider); // el campo de celular depende de si el usuario ya lo tiene
    final court = ref.watch(courtDetailProvider(widget.courtId));
    return Theme(
      data: authTheme(Theme.of(context)),
      child: Scaffold(
        body: Stack(children: [
          AsyncView<Court>(
            value: court,
            onRetry: () => ref.invalidate(courtDetailProvider(widget.courtId)),
            builder: _content,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _RoundButton(
                icon: Icons.chevron_left,
                tooltip: 'Volver a canchas',
                onTap: () => context.canPop() ? context.pop() : context.go('/home'),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: court.hasValue ? _bottomBar(court.value!) : null,
      ),
    );
  }

  Widget _content(Court c) {
    final slots = ref.watch(availabilityProvider(_key(c)));
    return RefreshIndicator(
      edgeOffset: 80,
      onRefresh: () async {
        ref.invalidate(courtDetailProvider(widget.courtId));
        ref.invalidate(availabilityProvider(_key(c)));
        ref.invalidate(courtReviewsProvider(widget.courtId));
      },
      child: ListView(padding: EdgeInsets.zero, children: [
        _Gallery(photos: c.photos),
        _header(c),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(height: 1, color: AuthColors.border)),
        _about(c),
        _booking(c, slots),
        if (_needsPhone) _phoneSection(),
        KeyedSubtree(key: _reviewsKey, child: ReviewsSection(courtId: c.id)),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _header(Court c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Tag(courtTypesLabel(c.types), lime: true),
            if (c.covered) const _Tag('Techada'),
            if (c.requiresDeposit) _Tag('Anticipo ${c.depositPercent} %'),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(c.name, style: authText(30, weight: 800, spacing: -0.05, height: 1.1))),
            if (c.reviewCount > 0) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF3B61F)),
                  const SizedBox(width: 2),
                  Text(c.rating.toStringAsFixed(1), style: authText(14, weight: 800)),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          InkWell(
            onTap: c.reviewCount == 0
                ? null
                : () => Scrollable.ensureVisible(_reviewsKey.currentContext!, duration: const Duration(milliseconds: 400)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: c.reviewCount > 0
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${c.reviewCount} ${c.reviewCount == 1 ? 'reseña' : 'reseñas'}',
                          style: authText(14, weight: 800, color: AuthColors.primary)),
                      const Icon(Icons.chevron_right, size: 16, color: AuthColors.primary),
                    ])
                  : Text('Sin reseñas todavía', style: authText(14, weight: 500, color: AuthColors.muted)),
            ),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.place_outlined, size: 18, color: AuthColors.kicker),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${c.address} · ${c.city}',
                  style: authText(14, weight: 500, color: const Color(0xFF5C6D63), height: 1.5)),
            ),
          ]),
        ]),
      );

  Widget _about(Court c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c.description != null && c.description!.isNotEmpty) ...[
            Text('Sobre la cancha', style: authText(18, weight: 800, spacing: -0.025)),
            const SizedBox(height: 12),
            Text(c.description!, style: authText(14, weight: 500, color: const Color(0xFF65736B), height: 1.6)),
            const SizedBox(height: 16),
          ],
          Row(children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.schedule,
                label: 'Horario',
                value: '${hourLabel(c.openHour)} – ${hourLabel(c.closeHour)}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoTile(
                icon: Icons.sports_soccer,
                label: 'Tipo',
                value: '${courtTypesLabel(c.types)} · ${c.covered ? 'Techada' : 'Aire libre'}',
              ),
            ),
          ]),
        ]),
      );

  Widget _booking(Court c, AsyncValue<List<HourSlot>> slots) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border.symmetric(horizontal: BorderSide(color: AuthColors.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c.options.length > 1) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _StepTitle('PASO 1', 'Elige el tipo de cancha', trailing: 'Cada tipo tiene su precio'),
            ),
            const SizedBox(height: 16),
            _typePicker(c),
            const SizedBox(height: 32),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _StepTitle(c.options.length > 1 ? 'PASO 2' : 'PASO 1', 'Elige el día'),
          ),
          const SizedBox(height: 16),
          _dayPicker(),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StepTitle(c.options.length > 1 ? 'PASO 3' : 'PASO 2', 'Elige la hora', trailing: 'Máx. ${BookingPolicy.maxHours} horas'),
              const SizedBox(height: 16),
              AsyncView<List<HourSlot>>(
                value: slots,
                onRetry: () => ref.invalidate(availabilityProvider(_key(c))),
                builder: (list) => _hourGrid(list),
              ),
              const SizedBox(height: 12),
              const _Legend(),
              _summary(c),
            ]),
          ),
        ]),
      );

  Widget _typePicker(Court c) {
    final selected = _variant(c).type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in c.options)
            SizedBox(
              width: w,
              child: _TypeTile(
                variant: v,
                selected: v.type == selected,
                onTap: () => setState(() {
                  _courtType = v.type;
                  _hours = {};
                }),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _dayPicker() => SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _daysAhead,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final d = _today.add(Duration(days: i));
            final selected = d == _day;
            final fg = selected ? Colors.white : const Color(0xFF5F7066);
            return Semantics(
              button: true,
              selected: selected,
              child: Material(
                color: selected ? AuthColors.primary : const Color(0xFFF7F8F2),
                elevation: selected ? 4 : 0,
                shadowColor: AuthColors.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: selected ? AuthColors.primary : AuthColors.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    _day = d;
                    _hours = {};
                  }),
                  child: SizedBox(
                    width: 64,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(i == 0 ? 'Hoy' : weekdayShort(d), style: authText(11, weight: 700, color: fg)),
                      const SizedBox(height: 4),
                      Text('${d.day}', style: authText(20, weight: 800, color: fg)),
                      Text(monthShort(d).toUpperCase(), style: authText(10, weight: 600, color: fg)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _hourGrid(List<HourSlot> list) => LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in list)
            SizedBox(
              width: w,
              height: 44,
              child: _HourTile(
                label: hourLabel(s.hour),
                free: s.free,
                selected: _hours.contains(s.hour),
                onTap: () => setState(() => _hours = BookingPolicy.toggleHour(_hours, s.hour)),
              ),
            ),
        ]);
      });

  Widget _phoneSection() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tu celular de contacto', style: authText(18, weight: 800, spacing: -0.025)),
          const SizedBox(height: 4),
          Text('El dueño lo usará únicamente si necesita contactarte por esta reserva.',
              style: authText(12, weight: 500, color: const Color(0xFF78877E), height: 1.5)),
          const SizedBox(height: 16),
          Form(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: AuthField(
              label: 'Celular',
              icon: Icons.phone_outlined,
              hint: '300 000 0000',
              controller: _phone,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
              validator: Validators.phone,
            ),
          ),
        ]),
      );

  /// Instante de inicio y desglose del cobro de la selección actual.
  ({DateTime start, int total, int deposit, bool lastMinute})? _quote(Court c) {
    if (_hours.isEmpty) return null;
    final first = _hours.reduce((a, b) => a < b ? a : b);
    final start = coInstant(_day, first);
    final total = _variant(c).pricePerHour * _hours.length;
    final now = DateTime.now();
    return (
      start: start,
      total: total,
      deposit: BookingPolicy.depositFor(
        total: total,
        courtRequiresDeposit: c.requiresDeposit,
        courtDepositPercent: c.depositPercent,
        start: start,
        now: now,
      ),
      lastMinute: BookingPolicy.isLastMinute(start, now),
    );
  }

  Widget _summary(Court c) {
    final q = _quote(c);
    if (q == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFEDF3E9), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rangeLabel(q.start, _hours.length), style: authText(13, weight: 800, color: const Color(0xFF285E3C))),
        const SizedBox(height: 4),
        Text(
          q.lastMinute
              ? 'Reserva de último momento: anticipo del 30% obligatorio y sin cancelación.'
              : 'Cancelación gratis hasta 24 h antes.',
          style: authText(12, weight: 500, color: const Color(0xFF285E3C), height: 1.5),
        ),
      ]),
    );
  }

  Widget _bottomBar(Court c) {
    final q = _quote(c);
    final canBook = q != null && _phoneOk && !_busy;
    final sub = q == null
        ? 'Selecciona una hora'
        : '${_hours.length} h${q.deposit > 0 ? ' · Anticipo ${cop(q.deposit)}' : ''}';
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            border: const Border(top: BorderSide(color: AuthColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sub, style: authText(12, weight: 600, color: const Color(0xFF78877E))),
                      const SizedBox(height: 2),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: cop(q?.total ?? 0), style: authText(24, weight: 800, spacing: -0.04)),
                        TextSpan(text: '  total', style: authText(12, weight: 600, color: const Color(0xFF78877E))),
                      ])),
                    ]),
                  ),
                  Text('${cop(_variant(c).pricePerHour)}/h', style: authText(12, weight: 700, color: AuthColors.kicker)),
                ]),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Reservar',
                  busy: _busy,
                  onPressed: canBook ? () => _book(c, q.start, q.deposit, q.lastMinute) : null,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _book(Court c, DateTime start, int deposit, bool lastMinute) async {
    if (!await _ensurePhone()) return;
    if (deposit > 0) {
      if (!mounted) return;
      final pay = await _askDeposit(
        context,
        deposit: deposit,
        total: _variant(c).pricePerHour * _hours.length,
        hours: _hours.length,
        courtType: c.options.length > 1 ? _variant(c) : null,
        lastMinute: lastMinute,
      );
      if (pay != true) return; // si cierra el aviso no se crea la reserva
    }
    setState(() => _busy = true);
    try {
      final b = await ref.read(apiProvider).createBooking(c.id, start, _hours.length, courtType: _variant(c).type);
      ref.invalidate(myBookingsProvider);
      ref.invalidate(availabilityProvider(_key(c)));
      if (!mounted) return;
      if (b.status == BookingStatus.pendingPayment) {
        context.pushReplacement('/bookings/${b.id}/pay');
      } else {
        showSnack(context, 'Reserva confirmada');
        context.go('/home?tab=1');
      }
    } on ApiException catch (e) {
      if (e.code == 'SLOT_TAKEN') {
        // Alguien más tomó la hora mientras tanto: se recarga la disponibilidad.
        ref.invalidate(availabilityProvider(_key(c)));
        setState(() => _hours = {});
      }
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Si el usuario no tenía celular, se guarda el que escribió en el campo de la pantalla.
  Future<bool> _ensurePhone() async {
    if (!_needsPhone) return true;
    final phone = _phone.text.trim();
    final invalid = Validators.phone(phone);
    if (invalid != null) {
      showSnack(context, invalid);
      return false;
    }
    return guarded(context, () async {
      final u = await ref.read(apiProvider).updateProfile(phone: phone);
      ref.read(sessionProvider.notifier).setUser(u);
    });
  }
}

/// Aviso previo a crear una reserva que exige anticipo (hoja inferior).
/// Devuelve true si el jugador elige "Pagar anticipo"; cerrarla o cancelar = no se crea la reserva.
Future<bool?> _askDeposit(
  BuildContext context, {
  required int deposit,
  required int total,
  required int hours,
  required bool lastMinute,
  CourtVariant? courtType,
}) {
  final percent = total == 0 ? 0 : (deposit * 100 / total).round();
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => Theme(
      data: authTheme(Theme.of(context)),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD5DBD6), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFFFF2CD), borderRadius: BorderRadius.circular(16)),
                child: Text('!', style: authText(26, weight: 800, color: const Color(0xFF8A6A00))),
              ),
            ),
            const SizedBox(height: 20),
            Text('Esta reserva requiere anticipo', style: authText(24, weight: 800, spacing: -0.04, height: 1.15)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Para asegurar el horario debes transferir '),
                TextSpan(text: cop(deposit), style: authText(14, weight: 800, color: AuthColors.ink, height: 1.5)),
                TextSpan(
                  text: lastMinute
                      ? ' (30 % del total, por ser una reserva de último momento). Esta reserva no tiene cancelación.'
                      : ', equivalente al $percent % del total.',
                ),
              ]),
              style: authText(14, weight: 500, color: const Color(0xFF66756C), height: 1.5),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF2F5EE), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                if (courtType != null) ...[
                  _SummaryRow('Tipo', '${courtType.label} · ${courtType.players}'),
                  const SizedBox(height: 8),
                ],
                _SummaryRow('Reserva', '$hours h'),
                const SizedBox(height: 8),
                _SummaryRow('Total', cop(total)),
              ]),
            ),
            const SizedBox(height: 16),
            Text(
              'Tendrás ${BookingPolicy.unpaidMinutes} minutos para subir el comprobante o las horas se liberarán automáticamente.',
              style: authText(12, weight: 500, color: const Color(0xFF7D8982), height: 1.5),
            ),
            const SizedBox(height: 24),
            Builder(builder: (ctx) => PrimaryButton(label: 'Pagar anticipo', onPressed: () => Navigator.pop(ctx, true))),
            Builder(
              builder: (ctx) => TextButton(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF65736B), minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: authText(14, weight: 500, color: AuthColors.muted))),
        Text(value, style: authText(14, weight: 800)),
      ]);
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.95),
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Colors.black38,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: AuthColors.primary, semanticLabel: tooltip),
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.lime = false});
  final String text;
  final bool lime;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: lime ? AuthColors.lime : const Color(0xFFE1EEE1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: authText(11, weight: 800, color: lime ? AuthColors.primary : const Color(0xFF285E3C))),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AuthColors.kicker),
          const SizedBox(height: 12),
          Text(label, style: authText(12, weight: 600, color: const Color(0xFF78877E))),
          const SizedBox(height: 4),
          Text(value, style: authText(14, weight: 800, height: 1.3)),
        ]),
      );
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.kicker, this.title, {this.trailing});
  final String kicker;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kicker, style: authText(12, weight: 700, color: AuthColors.kicker, spacing: 0.12)),
            const SizedBox(height: 4),
            Text(title, style: authText(20, weight: 800, spacing: -0.03)),
          ]),
        ),
        if (trailing != null) Text(trailing!, style: authText(12, weight: 600, color: const Color(0xFF78877E))),
      ]);
}

/// Tarjeta de un tipo de cancha: nombre, jugadores por equipo y precio por hora.
class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.variant, required this.selected, required this.onTap});
  final CourtVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${variant.label}, ${variant.players}, ${cop(variant.pricePerHour)} por hora',
        child: ExcludeSemantics(
          child: Material(
            color: selected ? AuthColors.lime : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: selected ? AuthColors.primary : const Color(0x1F143E2A), width: selected ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(variant.label, style: authText(15, weight: 800, color: AuthColors.ink)),
                  const SizedBox(height: 2),
                  Text(variant.players, style: authText(12, weight: 600, color: const Color(0xFF5F7066))),
                  const SizedBox(height: 8),
                  Text('${cop(variant.pricePerHour)}/h', style: authText(14, weight: 800, color: AuthColors.primary)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _HourTile extends StatelessWidget {
  const _HourTile({required this.label, required this.free, required this.selected, required this.onTap});
  final String label;
  final bool free;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final BorderSide side;
    if (!free) {
      bg = const Color(0xFFEEF0EB);
      fg = const Color(0xFFA6AEA9);
      side = BorderSide.none;
    } else if (selected) {
      bg = AuthColors.lime;
      fg = AuthColors.ink;
      side = const BorderSide(color: AuthColors.primary);
    } else {
      bg = Colors.white;
      fg = AuthColors.label;
      side = const BorderSide(color: Color(0x1F143E2A));
    }
    return Semantics(
      button: true,
      enabled: free,
      selected: selected,
      label: free ? label : '$label, ocupada',
      child: ExcludeSemantics(
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: side),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: free ? onTap : null,
            child: Center(
              child: Text(
                label,
                style: authText(12, weight: 800, color: fg).copyWith(
                  decoration: free ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  Widget _item(String text, Color color, {Color? ring}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: ring == null ? null : Border.all(color: ring)),
        ),
        const SizedBox(width: 6),
        Text(text, style: authText(11, weight: 600, color: const Color(0xFF77837C))),
      ]);

  @override
  Widget build(BuildContext context) => Wrap(spacing: 16, runSpacing: 6, children: [
        _item('Libre', Colors.white, ring: const Color(0x33174E32)),
        _item('Elegida', AuthColors.lime, ring: AuthColors.primary),
        _item('Ocupada', const Color(0xFFDFE3DD)),
      ]);
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.photos});
  final List<CourtPhoto> photos;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  static const _height = 320.0;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const CourtImage(url: null, height: _height);
    return SizedBox(
      height: _height,
      child: Stack(fit: StackFit.expand, children: [
        PageView.builder(
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => CachedNetworkImage(
            imageUrl: AppConfig.fileUrl(widget.photos[i].url),
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
            errorWidget: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Color(0x8C071B10), Color(0x00071B10)],
              ),
            ),
          ),
        ),
        if (widget.photos.length > 1)
          Positioned(
            right: 20,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xB3071B10), borderRadius: BorderRadius.circular(20)),
              child: Text('${_page + 1} / ${widget.photos.length}', style: authText(12, weight: 700, color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}
