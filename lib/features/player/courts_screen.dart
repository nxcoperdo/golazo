import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Listado de canchas con filtros (ciudad, techada, precio) y búsqueda por cercanía.
class CourtsScreen extends ConsumerWidget {
  const CourtsScreen({super.key});

  static const _priceOptions = [60000, 80000, 100000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(courtFiltersProvider);
    final courts = ref.watch(courtsProvider);
    final cities = ref.watch(citiesProvider).value ?? const <String>[];

    void set(CourtFilters f) => ref.read(courtFiltersProvider.notifier).set(f);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Canchas'),
        actions: [
          IconButton(
            icon: Icon(filters.hasLocation ? Icons.my_location : Icons.location_searching),
            tooltip: 'Cerca de mí',
            onPressed: () => filters.hasLocation
                ? set(filters.copyWith(clearLocation: true))
                : _useLocation(context, ref),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if (filters.hasLocation)
                _chip(
                  FilterChip(
                    avatar: const Icon(Icons.near_me, size: 16),
                    label: const Text('Cerca de mí'),
                    selected: true,
                    onSelected: (_) => set(filters.copyWith(clearLocation: true)),
                  ),
                ),
              for (final c in cities)
                _chip(FilterChip(
                  label: Text(c),
                  selected: filters.city == c,
                  onSelected: (s) => set(s ? filters.copyWith(city: c) : filters.copyWith(clearCity: true)),
                )),
              _chip(FilterChip(
                label: const Text('Techada'),
                selected: filters.covered == true,
                onSelected: (s) =>
                    set(s ? filters.copyWith(covered: true) : filters.copyWith(clearCovered: true)),
              )),
              _chip(FilterChip(
                label: Text(filters.maxPrice == null ? 'Precio' : 'Hasta ${cop(filters.maxPrice!)}'),
                selected: filters.maxPrice != null,
                onSelected: (_) => _pickPrice(context, filters, set),
              )),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<Court>>(
            value: courts,
            onRetry: () => ref.invalidate(courtsProvider),
            emptyText: 'No hay canchas con esos filtros',
            isEmpty: (l) => l.isEmpty,
            builder: (list) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(citiesProvider);
                ref.invalidate(courtsProvider);
                await ref.read(courtsProvider.future);
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) => _CourtCard(court: list[i]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(Widget c) => Padding(padding: const EdgeInsets.only(right: 8), child: c);

  Future<void> _pickPrice(BuildContext context, CourtFilters f, void Function(CourtFilters) set) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          for (final p in _priceOptions)
            ListTile(title: Text('Hasta ${cop(p)} por hora'), onTap: () => Navigator.pop(context, p)),
          ListTile(title: const Text('Sin límite'), onTap: () => Navigator.pop(context, -1)),
        ]),
      ),
    );
    if (picked == null) return;
    set(picked == -1 ? f.copyWith(clearPrice: true) : f.copyWith(maxPrice: picked));
  }

  /// Ordena por cercanía usando el GPS. Si no hay permiso, se puede elegir la ciudad a mano.
  Future<void> _useLocation(BuildContext context, WidgetRef ref) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (context.mounted) showSnack(context, 'Sin permiso de ubicación. Elige tu ciudad en los filtros.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final f = ref.read(courtFiltersProvider);
      ref.read(courtFiltersProvider.notifier).set(f.copyWith(lat: pos.latitude, lng: pos.longitude, clearCity: true));
    } catch (_) {
      if (context.mounted) showSnack(context, 'No se pudo obtener la ubicación. Elige tu ciudad en los filtros.');
    }
  }
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court});
  final Court court;

  @override
  Widget build(BuildContext context) {
    final dist = court.distanceM;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/courts/${court.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CourtImage(url: court.photoUrl, height: 160),
          ListTile(
            title: Text(court.name),
            subtitle: Text([
              court.city,
              court.covered ? 'Techada' : 'Aire libre',
              if (court.reviewCount > 0) '★ ${court.rating.toStringAsFixed(1)} (${court.reviewCount})',
              if (dist != null) dist < 1000 ? '${dist.round()} m' : '${(dist / 1000).toStringAsFixed(1)} km',
            ].join(' · ')),
            trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${cop(court.pricePerHour)}/h', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (court.requiresDeposit)
                Text('Anticipo ${court.depositPercent}%', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Foto de cancha con respaldo cuando no hay imagen o no carga.
class CourtImage extends StatelessWidget {
  const CourtImage({super.key, required this.url, this.height = 160});
  final String? url;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Icon(Icons.sports_soccer, size: 48),
    );
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: AppConfig.fileUrl(url!),
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}
