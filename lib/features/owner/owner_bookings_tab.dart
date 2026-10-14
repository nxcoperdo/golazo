import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/status_style.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _daysShown = 14;

/// Reservas de las canchas del dueño (próximos 14 días) y bloqueo manual de horas.
class OwnerBookingsTab extends ConsumerStatefulWidget {
  const OwnerBookingsTab({super.key});

  @override
  ConsumerState<OwnerBookingsTab> createState() => _State();
}

class _State extends ConsumerState<OwnerBookingsTab> {
  String? _courtId;

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(ownerBookingsProvider(_daysShown));
    final courts = ref.watch(ownerCourtsProvider).value ?? const <Court>[];
    final activeCourts = courts.where((c) => c.status == CourtStatus.active).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservas'),
        actions: [
          if (courts.length > 1)
            PopupMenuButton<String?>(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtrar por cancha',
              onSelected: (v) => setState(() => _courtId = v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: null, child: Text('Todas las canchas')),
                for (final c in courts) PopupMenuItem(value: c.id, child: Text(c.name)),
              ],
            ),
        ],
      ),
      floatingActionButton: activeCourts.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _block(context, activeCourts),
              icon: const Icon(Icons.block),
              label: const Text('Bloquear horas'),
            ),
      body: AsyncView<List<OwnerBooking>>(
        value: bookings,
        onRetry: () => ref.invalidate(ownerBookingsProvider(_daysShown)),
        emptyText: 'No tienes reservas en los próximos $_daysShown días.',
        isEmpty: (l) => l.where(_matches).isEmpty,
        builder: (all) {
          final list = all.where(_matches).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
          // Agrupa por día de Colombia.
          final byDay = <String, List<OwnerBooking>>{};
          for (final b in list) {
            byDay.putIfAbsent(dateParam(coWall(b.startAt)), () => []).add(b);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ownerBookingsProvider(_daysShown));
              await ref.read(ownerBookingsProvider(_daysShown).future);
            },
            child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              for (final e in byDay.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(dayLabel(e.value.first.startAt), style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final b in e.value) _row(context, b),
              ],
            ]),
          );
        },
      ),
    );
  }

  bool _matches(OwnerBooking b) => _courtId == null || b.courtId == _courtId;

  Widget _row(BuildContext context, OwnerBooking b) {
    final time = '${timeLabel(b.startAt)} – ${timeLabel(b.startAt.add(Duration(hours: b.hours)))}';
    if (b.isBlock) {
      return ListTile(
        leading: const Icon(Icons.block),
        title: Text(b.note?.isNotEmpty == true ? 'Bloqueado: ${b.note}' : 'Horas bloqueadas'),
        subtitle: Text('$time · ${b.courtName}'),
        trailing: IconButton(
          tooltip: 'Quitar bloqueo',
          icon: const Icon(Icons.lock_open),
          onPressed: () async {
            if (!await confirm(context, title: '¿Quitar el bloqueo?', okLabel: 'Quitar')) return;
            if (!context.mounted) return;
            final ok = await guarded(context, () => ref.read(apiProvider).unblockHours(b.id));
            if (ok) ref.invalidate(ownerBookingsProvider(_daysShown));
          },
        ),
      );
    }
    return ListTile(
      leading: const Icon(Icons.sports_soccer),
      title: Text(b.playerName ?? 'Jugador'),
      subtitle: Text('$time · ${b.courtName}\n${b.playerPhone != null ? 'Cel. ${b.playerPhone}' : ''}'.trim()),
      isThreeLine: b.playerPhone != null,
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        StatusChip(bookingStatusLabel(b.status), color: bookingStatusColor(b.status)),
      ]),
      onTap: b.playerPhone == null
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: b.playerPhone!));
              showSnack(context, 'Celular copiado');
            },
    );
  }

  Future<void> _block(BuildContext context, List<Court> courts) async {
    final today = coToday();
    var court = courts.first;
    var day = today;
    var hour = court.openHour;
    var hours = 1;
    final note = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          final startHours = [for (var h = court.openHour; h < court.closeHour; h++) h];
          if (!startHours.contains(hour)) hour = startHours.first;
          return AlertDialog(
            title: const Text('Bloquear horas'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Para reservas que te llegan por fuera de la app. Nadie más podrá reservar esas horas.'),
                const SizedBox(height: 12),
                if (courts.length > 1)
                  DropdownButtonFormField<Court>(
                    initialValue: court,
                    decoration: const InputDecoration(labelText: 'Cancha'),
                    items: [for (final c in courts) DropdownMenuItem(value: c, child: Text(c.name))],
                    onChanged: (c) => setState(() => court = c!),
                  ),
                DropdownButtonFormField<DateTime>(
                  initialValue: day,
                  decoration: const InputDecoration(labelText: 'Día'),
                  items: [
                    for (var i = 0; i < 14; i++)
                      DropdownMenuItem(
                        value: today.add(Duration(days: i)),
                        child: Text(i == 0 ? 'Hoy' : dayLabel(coInstant(today.add(Duration(days: i)), 12))),
                      ),
                  ],
                  onChanged: (d) => setState(() => day = d!),
                ),
                DropdownButtonFormField<int>(
                  initialValue: hour,
                  decoration: const InputDecoration(labelText: 'Desde'),
                  items: [for (final h in startHours) DropdownMenuItem(value: h, child: Text(hourLabel(h)))],
                  onChanged: (h) => setState(() => hour = h!),
                ),
                DropdownButtonFormField<int>(
                  initialValue: hours,
                  decoration: const InputDecoration(labelText: 'Cuántas horas'),
                  items: [for (var h = 1; h <= 4; h++) DropdownMenuItem(value: h, child: Text('$h'))],
                  onChanged: (h) => setState(() => hours = h!),
                ),
                TextField(
                  controller: note,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bloquear')),
            ],
          );
        },
      ),
    );
    final text = note.text;
    note.dispose();
    if (ok != true || !context.mounted) return;
    final done = await guarded(
      context,
      () => ref.read(apiProvider).blockHours(court.id, coInstant(day, hour), hours, note: text),
      success: 'Horas bloqueadas',
    );
    if (done) ref.invalidate(ownerBookingsProvider(_daysShown));
  }
}
