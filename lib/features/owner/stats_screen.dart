import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Estadísticas del dueño: reservas, ingresos y ocupación en los últimos 7/30/90 días.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _State();
}

class _State extends ConsumerState<StatsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(ownerStatsProvider(_days));
    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 días')),
              ButtonSegment(value: 30, label: Text('30 días')),
              ButtonSegment(value: 90, label: Text('90 días')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
        ),
        Expanded(
          child: AsyncView<OwnerStats>(
            value: stats,
            onRetry: () => ref.invalidate(ownerStatsProvider(_days)),
            builder: (s) => ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              _tile(context, 'Ingresos confirmados', cop(s.income)),
              _tile(context, 'Reservas confirmadas', '${s.confirmed}'),
              _tile(context, 'Esperando pago', '${s.awaitingPayment}'),
              _tile(context, 'Canceladas', '${s.cancelled}'),
              _tile(context, 'Horas reservadas', '${s.bookedHours}'),
              _tile(context, 'Ocupación', '${s.occupancyPercent.toStringAsFixed(1)}%'),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context, String label, String value) => Card(
        child: ListTile(
          title: Text(label),
          trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
        ),
      );
}
