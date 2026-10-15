import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/ui.dart';
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
    return AppPage(
      kicker: 'Rendimiento',
      title: 'Estadísticas',
      onBack: () => context.canPop() ? context.pop() : context.go('/owner?tab=2'),
      child: AsyncView<OwnerStats>(
        value: stats,
        onRetry: () => ref.invalidate(ownerStatsProvider(_days)),
        builder: (s) => ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24).withNav(context), children: [
          SegmentedTabs<int>(
            options: const [(7, '7 días'), (30, '30 días'), (90, '90 días')],
            value: _days,
            onChanged: (d) => setState(() => _days = d),
          ),
          const SizedBox(height: 20),
          StatCard(label: 'Ingresos confirmados', value: cop(s.income), hero: true),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              StatCard(label: 'Reservas confirmadas', value: '${s.confirmed}'),
              StatCard(label: 'Esperando pago', value: '${s.awaitingPayment}'),
              StatCard(label: 'Canceladas', value: '${s.cancelled}'),
              StatCard(label: 'Horas reservadas', value: '${s.bookedHours} h'),
              StatCard(label: 'Ocupación', value: '${s.occupancyPercent.toStringAsFixed(1)}%'),
            ],
          ),
        ]),
      ),
    );
  }
}
