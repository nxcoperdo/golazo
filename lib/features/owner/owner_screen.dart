import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/format.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../booking/payment_info.dart';

/// Panel del dueño: Pagos, Mi cancha y Estadísticas.
class OwnerScreen extends ConsumerStatefulWidget {
  const OwnerScreen({super.key});

  @override
  ConsumerState<OwnerScreen> createState() => _OwnerState();
}

class _OwnerState extends ConsumerState<OwnerScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    const titles = ['Pagos', 'Mi cancha', 'Estadísticas'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Salir',
              onPressed: () => context.go('/')),
        ],
      ),
      body: switch (tab) {
        0 => const _PaymentsTab(),
        1 => const _CourtTab(),
        _ => const _StatsTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.payments), label: 'Pagos'),
          NavigationDestination(icon: Icon(Icons.sports_soccer), label: 'Mi cancha'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Estadísticas'),
        ],
      ),
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref
        .watch(bookingsProvider)
        .where((b) =>
            b.courtId == ownerCourtId && b.status == BookingStatus.pendingReview)
        .toList();

    void resolve(Booking b, BookingStatus s) {
      ref
          .read(bookingsProvider.notifier)
          .update((l) => [for (final x in l) x.id == b.id ? b.copyWith(status: s) : x]);
      ref.read(notificationsProvider.notifier).update((l) => [
            ...l,
            s == BookingStatus.confirmed
                ? 'Tu pago fue aprobado: reserva confirmada'
                : 'Tu pago fue rechazado: sube un nuevo comprobante',
          ]);
    }

    final sub = ref
        .watch(subscriptionsProvider)
        .where((s) => s.courtId == ownerCourtId)
        .lastOrNull;

    Future<void> payMonthly() async {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      ref.read(subscriptionsProvider.notifier).update((l) => [
            ...l,
            Subscription(
                id: 's${l.length + 1}',
                courtId: ownerCourtId,
                proofPath: file.path),
          ]);
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.workspace_premium),
          title: const Text('Mensualidad \$100.000'),
          subtitle: Text(switch (sub?.state) {
            null => 'Sin pago registrado',
            ReviewState.pending => 'Comprobante en revisión',
            ReviewState.approved => 'Pagada',
            ReviewState.rejected => 'Rechazada, sube de nuevo',
          }),
          trailing: sub?.state == ReviewState.pending
              ? null
              : TextButton(onPressed: payMonthly, child: const Text('Subir pago')),
        ),
      ),
      if (sub == null || sub.state == ReviewState.rejected)
        PaymentInfo(
            methods: platformPaymentMethods,
            amount: 100000,
            title: 'Paga tu mensualidad:'),
      if (pending.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No hay comprobantes por revisar')),
        ),
      for (final b in pending)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.start.day}/${b.start.month} · ${hourLabel(b.start.hour)}',
                  style: Theme.of(context).textTheme.titleMedium),
              Text('Anticipo: ${cop(b.deposit)} de ${cop(b.total)}'),
              if (b.proofPath != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Image.file(File(b.proofPath!),
                      height: 180,
                      errorBuilder: (_, _, _) => const Text('No se pudo mostrar el comprobante')),
                ),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () => resolve(b, BookingStatus.rejected),
                    child: const Text('Rechazar')),
                FilledButton(
                    onPressed: () => resolve(b, BookingStatus.confirmed),
                    child: const Text('Aprobar')),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

class _CourtTab extends ConsumerWidget {
  const _CourtTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final court =
        ref.watch(courtsProvider).firstWhere((c) => c.id == ownerCourtId);
    void save(Court c) => ref
        .read(courtsProvider.notifier)
        .update((l) => [for (final x in l) x.id == c.id ? c : x]);

    return ListView(padding: const EdgeInsets.all(16), children: [
      TextFormField(
        key: ValueKey('name-${court.name}'),
        initialValue: court.name,
        decoration: const InputDecoration(labelText: 'Nombre'),
        onFieldSubmitted: (v) => save(court.copyWith(name: v.trim())),
      ),
      const SizedBox(height: 12),
      TextFormField(
        initialValue: court.pricePerHour.toString(),
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Precio por hora (COP)'),
        onFieldSubmitted: (v) {
          final p = int.tryParse(v);
          if (p != null && p > 0) save(court.copyWith(pricePerHour: p));
        },
      ),
      SwitchListTile(
        title: const Text('Techada'),
        value: court.covered,
        onChanged: (v) => save(court.copyWith(covered: v)),
      ),
      SwitchListTile(
        title: const Text('Exigir anticipo'),
        subtitle: Text('${court.depositPercent}% del valor'),
        value: court.requiresDeposit,
        onChanged: (v) => save(court.copyWith(requiresDeposit: v)),
      ),
      if (court.requiresDeposit)
        Slider(
          min: 10,
          max: 100,
          divisions: 9,
          label: '${court.depositPercent}%',
          value: court.depositPercent.toDouble(),
          onChanged: (v) => save(court.copyWith(depositPercent: v.round())),
        ),
      const Divider(),
      Text('Cuentas para recibir pagos',
          style: Theme.of(context).textTheme.titleMedium),
      for (var i = 0; i < court.paymentMethods.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
              '${court.paymentMethods[i].label} · ${court.paymentMethods[i].account}'),
          subtitle: Text(court.paymentMethods[i].holder),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => save(court.copyWith(paymentMethods: [
              for (var j = 0; j < court.paymentMethods.length; j++)
                if (j != i) court.paymentMethods[j],
            ])),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Agregar cuenta'),
          onPressed: () async {
            final m = await _askMethod(context);
            if (m != null) {
              save(court.copyWith(paymentMethods: [...court.paymentMethods, m]));
            }
          },
        ),
      ),
      const Divider(),
      Text('Horario: ${hourLabel(court.openHour)} – ${hourLabel(court.closeHour)}'),
      RangeSlider(
        min: 0,
        max: 24,
        divisions: 24,
        values: RangeValues(court.openHour.toDouble(), court.closeHour.toDouble()),
        onChanged: (r) => save(court.copyWith(
            openHour: r.start.round(), closeHour: r.end.round())),
      ),
      const Text('Los cambios de nombre y precio se guardan al pulsar Enter.',
          style: TextStyle(fontSize: 12)),
    ]);
  }
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final court =
        ref.watch(courtsProvider).firstWhere((c) => c.id == ownerCourtId);
    final mine = ref
        .watch(bookingsProvider)
        .where((b) => b.courtId == ownerCourtId)
        .toList();
    final confirmed =
        mine.where((b) => b.status == BookingStatus.confirmed).toList();
    final income = confirmed.fold<int>(0, (a, b) => a + b.total);
    final slotsPerDay = court.closeHour - court.openHour;

    Widget tile(String label, String value) => Card(
          child: ListTile(title: Text(label), trailing: Text(value, style: Theme.of(context).textTheme.titleLarge)),
        );

    return ListView(padding: const EdgeInsets.all(12), children: [
      tile('Reservas totales', '${mine.length}'),
      tile('Confirmadas', '${confirmed.length}'),
      tile('Ingresos confirmados', cop(income)),
      tile('Horas disponibles por día', '$slotsPerDay'),
    ]);
  }
}

Future<PaymentMethod?> _askMethod(BuildContext context) {
  final label = TextEditingController();
  final account = TextEditingController();
  final holder = TextEditingController();
  return showDialog<PaymentMethod>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Nueva cuenta'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: label, decoration: const InputDecoration(labelText: 'Medio (Nequi, Daviplata, banco…)')),
        TextField(controller: account, decoration: const InputDecoration(labelText: 'Número de cuenta o celular')),
        TextField(controller: holder, decoration: const InputDecoration(labelText: 'Titular')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (label.text.trim().isEmpty ||
                account.text.trim().isEmpty ||
                holder.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(
                context,
                PaymentMethod(
                    label: label.text.trim(),
                    account: account.text.trim(),
                    holder: holder.text.trim()));
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
