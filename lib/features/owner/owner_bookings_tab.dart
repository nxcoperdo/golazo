import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_style.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _daysShown = 14;

/// Reservas de las canchas del dueño (próximos 14 días, un día a la vez) y bloqueo manual de horas.
class OwnerBookingsTab extends ConsumerStatefulWidget {
  const OwnerBookingsTab({super.key});

  @override
  ConsumerState<OwnerBookingsTab> createState() => _State();
}

class _State extends ConsumerState<OwnerBookingsTab> {
  late final DateTime _today = coToday();
  late DateTime _day = _today;
  String? _courtId;

  bool _matches(OwnerBooking b) => (_courtId == null || b.courtId == _courtId) && coWall(b.startAt).day == _day.day && coWall(b.startAt).month == _day.month;

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(ownerBookingsProvider(_daysShown));
    final courts = ref.watch(ownerCourtsProvider).value ?? const <Court>[];
    final activeCourts = courts.where((c) => c.status == CourtStatus.active).toList();
    final courtName = courts.where((c) => c.id == _courtId).map((c) => c.name).firstOrNull ?? 'Todas las canchas';

    return AppPage(
      kicker: 'Próximos $_daysShown días',
      title: 'Reservas',
      fab: activeCourts.isEmpty ? null : PillFab(label: '+ Bloquear horas', onTap: () => _block(context, activeCourts)),
      child: AsyncView<List<OwnerBooking>>(
        value: bookings,
        onRetry: () => ref.invalidate(ownerBookingsProvider(_daysShown)),
        builder: (all) {
          final list = all.where(_matches).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ownerBookingsProvider(_daysShown));
              await ref.read(ownerBookingsProvider(_daysShown).future);
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 96).withNav(context), children: [
              if (courts.isNotEmpty)
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AuthColors.border)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _pickCourt(context, courts),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Expanded(child: Text(courtName, style: authText(14, weight: 800))),
                        const Icon(Icons.keyboard_arrow_down, size: 20, color: AuthColors.muted),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _daysShown,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final d = _today.add(Duration(days: i));
                    final selected = d == _day;
                    final label = i == 0 ? 'Hoy ${d.day}' : '${_cap(weekdayShort(d))} ${d.day}';
                    return Semantics(
                      button: true,
                      selected: selected,
                      child: Material(
                        color: selected ? AuthColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _day = d),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Center(
                              child: Text(label, style: authText(12, weight: 800, color: selected ? Colors.white : const Color(0xFF65736B))),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(longDayLabel(_day).toUpperCase(), style: authText(12, weight: 700, color: AuthColors.kicker, spacing: 0.12)),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('No hay reservas este día.',
                      textAlign: TextAlign.center, style: authText(14, weight: 500, color: AuthColors.muted)),
                )
              else
                for (final b in list) _row(context, b),
            ]),
          );
        },
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Future<void> _pickCourt(BuildContext context, List<Court> courts) async {
    const all = '__all__';
    final v = await showPickSheet<String>(
      context,
      title: 'Cancha',
      selected: _courtId ?? all,
      options: [(all, 'Todas las canchas'), for (final c in courts) (c.id, c.name)],
    );
    if (v != null) setState(() => _courtId = v == all ? null : v);
  }

  Widget _row(BuildContext context, OwnerBooking b) {
    final time = '${timeLabel(b.startAt)} – ${timeLabel(b.startAt.add(Duration(hours: b.hours)))}';
    final tone = b.isBlock
        ? PillTone.gray
        : switch (b.status) {
            BookingStatus.confirmed => PillTone.green,
            BookingStatus.pendingReview => PillTone.blue,
            BookingStatus.pendingPayment => PillTone.amber,
            BookingStatus.rejected || BookingStatus.cancelled => PillTone.red,
          };
    final label = b.isBlock
        ? 'Bloqueada'
        : b.status == BookingStatus.pendingReview
            ? 'En revisión'
            : bookingStatusLabel(b.status);
    return SoftCard(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      radius: 20,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$time · ${b.courtName}', style: authText(14, weight: 800)),
              const SizedBox(height: 4),
              if (b.isBlock)
                Text(b.note?.isNotEmpty == true ? b.note! : 'Horas bloqueadas por ti',
                    style: authText(12, weight: 600, color: const Color(0xFF6C7B72)))
              else
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: b.playerName ?? 'Jugador'),
                    if (b.playerPhone != null) ...[
                      const TextSpan(text: ' · '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: b.playerPhone!));
                            showSnack(context, 'Celular copiado');
                          },
                          child: Text(b.playerPhone!, style: authText(12, weight: 600, color: AuthColors.link)),
                        ),
                      ),
                    ],
                  ]),
                  style: authText(12, weight: 600, color: const Color(0xFF6C7B72)),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          StatusPill(label, tone),
        ]),
        if (b.isBlock)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFAD3E37), padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
            onPressed: () => _unblock(context, b),
            child: Text('Quitar bloqueo', style: authText(12, weight: 800, color: const Color(0xFFAD3E37))),
          ),
      ]),
    );
  }

  Future<void> _unblock(BuildContext context, OwnerBooking b) async {
    final ok = await showAppSheet<bool>(
      context,
      builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeading('¿Quitar el bloqueo?', subtitle: 'Esas horas volverán a estar disponibles para los jugadores.'),
        SheetActions(primaryLabel: 'Quitar bloqueo', danger: true, onPrimary: () => Navigator.pop(sheet, true)),
      ]),
    );
    if (ok != true || !context.mounted) return;
    final done = await guarded(context, () => ref.read(apiProvider).unblockHours(b.id));
    if (done) ref.invalidate(ownerBookingsProvider(_daysShown));
  }

  Future<void> _block(BuildContext context, List<Court> courts) async {
    final r = await showAppSheet<_BlockResult>(
      context,
      builder: (sheet) => _BlockSheet(
        courts: courts,
        today: _today,
        initialDay: _day,
        onSave: (v) => Navigator.pop(sheet, v),
      ),
    );
    if (r == null || !context.mounted) return;
    final done = await guarded(
      context,
      () => ref.read(apiProvider).blockHours(r.court.id, coInstant(r.day, r.hour), r.hours, note: r.note),
      success: 'Horas bloqueadas',
    );
    if (done) ref.invalidate(ownerBookingsProvider(_daysShown));
  }
}

class _BlockResult {
  const _BlockResult(this.court, this.day, this.hour, this.hours, this.note);
  final Court court;
  final DateTime day;
  final int hour;
  final int hours;
  final String note;
}

/// Hoja "Bloquear horas": cuatro cajas (cancha, día, desde, duración) y una nota opcional.
class _BlockSheet extends StatefulWidget {
  const _BlockSheet({required this.courts, required this.today, required this.initialDay, required this.onSave});
  final List<Court> courts;
  final DateTime today;
  final DateTime initialDay;
  final void Function(_BlockResult) onSave;

  @override
  State<_BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<_BlockSheet> {
  late Court _court = widget.courts.first;
  late DateTime _day = widget.initialDay;
  late int _hour = _court.openHour;
  int _hours = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<int> get _startHours => [for (var h = _court.openHour; h < _court.closeHour; h++) h];

  String _dayText(DateTime d) => d == widget.today ? 'Hoy, ${d.day} ${monthShort(d)}' : '${weekdayShort(d)} ${d.day} ${monthShort(d)}';

  @override
  Widget build(BuildContext context) {
    if (!_startHours.contains(_hour)) _hour = _startHours.first;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHeading('Bloquear horas', subtitle: 'Para reservas que te llegan por fuera de la app. Nadie más podrá reservar esas horas.'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.3,
        children: [
          PickTile(
            label: 'Cancha',
            value: _court.name,
            onTap: () async {
              final v = await showPickSheet<Court>(context,
                  title: 'Cancha', selected: _court, options: [for (final c in widget.courts) (c, c.name)]);
              if (v != null) setState(() => _court = v);
            },
          ),
          PickTile(
            label: 'Día',
            value: _dayText(_day),
            onTap: () async {
              final v = await showPickSheet<DateTime>(context, title: 'Día', selected: _day, options: [
                for (var i = 0; i < 14; i++) (widget.today.add(Duration(days: i)), _dayText(widget.today.add(Duration(days: i)))),
              ]);
              if (v != null) setState(() => _day = v);
            },
          ),
          PickTile(
            label: 'Desde',
            value: hourLabel(_hour),
            onTap: () async {
              final v = await showPickSheet<int>(context, title: 'Desde', selected: _hour, options: [for (final h in _startHours) (h, hourLabel(h))]);
              if (v != null) setState(() => _hour = v);
            },
          ),
          PickTile(
            label: 'Duración',
            value: _hours == 1 ? '1 hora' : '$_hours horas',
            onTap: () async {
              final v = await showPickSheet<int>(context, title: 'Duración', selected: _hours, options: [
                for (var h = 1; h <= 4; h++) (h, h == 1 ? '1 hora' : '$h horas'),
              ]);
              if (v != null) setState(() => _hours = v);
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      AuthField(label: 'Nota (opcional)', icon: Icons.edit_outlined, controller: _note, hint: 'Ej. Partido de empresa'),
      SheetActions(
        primaryLabel: 'Guardar bloqueo',
        onPrimary: () => widget.onSave(_BlockResult(_court, _day, _hour, _hours, _note.text.trim())),
      ),
    ]);
  }
}
