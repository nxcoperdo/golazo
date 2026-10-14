import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/validators.dart';
import '../../core/widgets/async_view.dart';
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
  bool _busy = false;

  AvailabilityKey get _key => (courtId: widget.courtId, day: _day);

  @override
  Widget build(BuildContext context) {
    final court = ref.watch(courtDetailProvider(widget.courtId));
    return Scaffold(
      appBar: AppBar(title: Text(court.value?.name ?? 'Cancha')),
      body: AsyncView<Court>(
        value: court,
        onRetry: () => ref.invalidate(courtDetailProvider(widget.courtId)),
        builder: _content,
      ),
      bottomNavigationBar: court.hasValue ? _bottomBar(court.value!) : null,
    );
  }

  Widget _content(Court c) {
    final slots = ref.watch(availabilityProvider(_key));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(courtDetailProvider(widget.courtId));
        ref.invalidate(availabilityProvider(_key));
        ref.invalidate(courtReviewsProvider(widget.courtId));
      },
      child: ListView(children: [
        _Gallery(photos: c.photos),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            if (c.reviewCount > 0)
              Text('★ ${c.rating.toStringAsFixed(1)} · ${c.reviewCount} reseñas')
            else
              const Text('Sin reseñas todavía'),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('${c.address}, ${c.city}')),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusChip(c.covered ? 'Techada' : 'Aire libre'),
              StatusChip('${hourLabel(c.openHour)} – ${hourLabel(c.closeHour)}'),
              StatusChip('${cop(c.pricePerHour)} por hora'),
              if (c.requiresDeposit) StatusChip('Anticipo ${c.depositPercent}%', color: Colors.orange.shade800),
            ]),
            if (c.description != null && c.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(c.description!),
            ],
            const SizedBox(height: 20),
            Text('Elige el día', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _dayPicker(),
            const SizedBox(height: 16),
            Text('Elige la hora', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Toca horas seguidas para reservar hasta ${BookingPolicy.maxHours} horas.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            AsyncView<List<HourSlot>>(
              value: slots,
              onRetry: () => ref.invalidate(availabilityProvider(_key)),
              builder: (list) => Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in list)
                  ChoiceChip(
                    label: Text(hourLabel(s.hour)),
                    selected: _hours.contains(s.hour),
                    onSelected: s.free ? (_) => setState(() => _hours = BookingPolicy.toggleHour(_hours, s.hour)) : null,
                  ),
              ]),
            ),
            _summary(c),
            ReviewsSection(courtId: c.id),
            const SizedBox(height: 24),
          ]),
        ),
      ]),
    );
  }

  Widget _dayPicker() => SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _daysAhead,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final d = _today.add(Duration(days: i));
            final label = i == 0
                ? 'Hoy'
                : i == 1
                    ? 'Mañana'
                    : dayLabel(coInstant(d, 12));
            return ChoiceChip(
              label: Text(label),
              selected: d == _day,
              onSelected: (_) => setState(() {
                _day = d;
                _hours = {};
              }),
            );
          },
        ),
      );

  /// Instante de inicio y desglose del cobro de la selección actual.
  ({DateTime start, int total, int deposit, bool lastMinute})? _quote(Court c) {
    if (_hours.isEmpty) return null;
    final first = _hours.reduce((a, b) => a < b ? a : b);
    final start = coInstant(_day, first);
    final total = c.pricePerHour * _hours.length;
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
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rangeLabel(q.start, _hours.length), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('${_hours.length} h · Total ${cop(q.total)}'),
            if (q.deposit > 0) Text('Anticipo a pagar: ${cop(q.deposit)}'),
            const SizedBox(height: 4),
            Text(
              q.lastMinute
                  ? 'Reserva de último momento: anticipo del 30% obligatorio y sin cancelación.'
                  : 'Cancelación gratis hasta 24 h antes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bottomBar(Court c) {
    final q = _quote(c);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: q == null || _busy ? null : () => _book(c, q.start, q.deposit, q.lastMinute),
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(q == null ? 'Elige una hora' : 'Confirmar reserva'),
        ),
      ),
    );
  }

  Future<void> _book(Court c, DateTime start, int deposit, bool lastMinute) async {
    if (!await _ensurePhone()) return;
    if (deposit > 0) {
      if (!mounted) return;
      final pay = await _askDeposit(context, deposit: deposit, lastMinute: lastMinute);
      if (pay != true) return; // si cierra el aviso no se crea la reserva
    }
    setState(() => _busy = true);
    try {
      final b = await ref.read(apiProvider).createBooking(c.id, start, _hours.length);
      ref.invalidate(myBookingsProvider);
      ref.invalidate(availabilityProvider(_key));
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
        ref.invalidate(availabilityProvider(_key));
        setState(() => _hours = {});
      }
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// El dueño necesita un celular para contactar al jugador: se pide la primera vez.
  Future<bool> _ensurePhone() async {
    final user = ref.read(sessionProvider).value;
    if (user == null || user.hasPhone) return true;
    final phone = await askText(context,
        title: 'Tu celular de contacto', hint: '3001234567', okLabel: 'Guardar');
    if (phone == null || !mounted) return false;
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

/// Aviso previo a crear una reserva que exige anticipo.
/// Devuelve true si el jugador elige "Pagar anticipo".
Future<bool?> _askDeposit(
  BuildContext context, {
  required int deposit,
  required bool lastMinute,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.payments_outlined),
      title: const Text('Esta reserva requiere anticipo'),
      content: Text(
        lastMinute
            ? 'Por ser una reserva de último momento debes pagar un anticipo de ${cop(deposit)} (30%). Esta reserva no tiene cancelación.'
            : 'Para confirmar tu reserva debes pagar un anticipo de ${cop(deposit)} y subir el comprobante.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pagar anticipo')),
      ],
    ),
  );
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.photos});
  final List<CourtPhoto> photos;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const CourtImage(url: null, height: 200);
    return SizedBox(
      height: 220,
      child: Stack(children: [
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
        if (widget.photos.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < widget.photos.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page ? Colors.white : Colors.white54,
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
