import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/mock_data.dart';

class CourtsScreen extends ConsumerWidget {
  const CourtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(visibleCourtsProvider);
    final f = ref.watch(filtersProvider);
    void set(CourtFilters n) => ref.read(filtersProvider.notifier).state = n;

    return Scaffold(
      appBar: AppBar(title: const Text('Canchas'), actions: [
        IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Usar mi ubicación',
            onPressed: () => _useLocation(context, ref)),
        IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notificaciones',
            onPressed: () => context.push('/notifications')),
        IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Mis reservas',
            onPressed: () => context.push('/bookings')),
      ]),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final city in const ['Bogotá', 'Medellín', 'Cali'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(city),
                    selected: f.city == city,
                    onSelected: (s) => set(CourtFilters(
                        city: s ? city : null,
                        maxPrice: f.maxPrice,
                        covered: f.covered)),
                  ),
                ),
              FilterChip(
                label: const Text('Techada'),
                selected: f.covered == true,
                onSelected: (s) => set(CourtFilters(
                    city: f.city,
                    maxPrice: f.maxPrice,
                    covered: s ? true : null)),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text(r'Hasta $80.000'),
                selected: f.maxPrice == 80000,
                onSelected: (s) => set(CourtFilters(
                    city: f.city,
                    maxPrice: s ? 80000 : null,
                    covered: f.covered)),
              ),
            ],
          ),
        ),
        Expanded(
          child: courts.isEmpty
              ? const Center(child: Text('No hay canchas con esos filtros'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: courts.length,
                  itemBuilder: (_, i) {
                    final c = courts[i];
                    return Card(
                      child: InkWell(
                        onTap: () => context.push('/courts/${c.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CachedNetworkImage(
                              imageUrl: c.photoUrl,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => const SizedBox(
                                  height: 160,
                                  child: Icon(Icons.sports_soccer, size: 48)),
                            ),
                            ListTile(
                              title: Text(c.name),
                              subtitle: Text(
                                  '${c.city} · ${c.covered ? 'Techada' : 'Aire libre'} · ★ ${c.rating}'),
                              trailing: Text('${cop(c.pricePerHour)}/h'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Asigna la ciudad más cercana usando el GPS (o avisa si no hay permiso).
Future<void> _useLocation(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Sin permiso de ubicación. Elige tu ciudad manualmente.')));
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    String? best;
    var bestD = double.infinity;
    cityCoords.forEach((city, c) {
      final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, c.$1, c.$2);
      if (d < bestD) {
        bestD = d;
        best = city;
      }
    });
    final f = ref.read(filtersProvider);
    ref.read(filtersProvider.notifier).state =
        CourtFilters(city: best, maxPrice: f.maxPrice, covered: f.covered);
    messenger.showSnackBar(SnackBar(content: Text('Ciudad: $best')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo obtener la ubicación. Elige tu ciudad manualmente.')));
  }
}
