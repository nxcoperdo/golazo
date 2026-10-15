import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Quita tildes y pasa a minúsculas para buscar "bogota" y encontrar "Bogotá".
String _norm(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Listado de canchas: búsqueda por texto y filtros (cerca de mí, ciudad, techada, tipo, precio).
class CourtsScreen extends ConsumerStatefulWidget {
  const CourtsScreen({super.key});

  @override
  ConsumerState<CourtsScreen> createState() => _CourtsState();
}

class _CourtsState extends ConsumerState<CourtsScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _locating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set(CourtFilters f) => ref.read(courtFiltersProvider.notifier).set(f);

  void _clearAll() {
    _search.clear();
    setState(() => _query = '');
    _set(const CourtFilters());
  }

  List<Court> _visible(List<Court> all) {
    final q = _norm(_query.trim());
    if (q.isEmpty) return all;
    return all.where((c) => _norm('${c.name} ${c.city} ${c.address}').contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(courtFiltersProvider);
    final courts = ref.watch(courtsProvider);
    final cities = ref.watch(citiesProvider).value ?? const <String>[];
    final anyFilter = _query.isNotEmpty ||
        filters.city != null ||
        filters.covered != null ||
        filters.courtType != null ||
        filters.maxPrice != null ||
        filters.hasLocation;

    return Theme(
      data: authTheme(Theme.of(context)),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Juega donde quieras', style: authText(14, weight: 700, color: AuthColors.kicker)),
                const SizedBox(height: 4),
                Text('Encuentra tu cancha', style: authText(28, weight: 800, spacing: -0.04)),
                const SizedBox(height: 18),
                _searchField(),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _Pill(
                    label: _locating ? 'Ubicando…' : 'Cerca de mí',
                    icon: Icons.near_me_outlined,
                    busy: _locating,
                    selected: filters.hasLocation,
                    onTap: () {
                      if (_locating) return;
                      filters.hasLocation ? _set(filters.copyWith(clearLocation: true)) : _useLocation();
                    },
                  ),
                  _Pill(
                    label: 'Todas',
                    soft: true,
                    selected: filters.city == null,
                    onTap: () => _set(filters.copyWith(clearCity: true)),
                  ),
                  for (final c in cities)
                    _Pill(
                      label: c,
                      soft: true,
                      selected: filters.city == c,
                      onTap: () => _set(filters.city == c ? filters.copyWith(clearCity: true) : filters.copyWith(city: c)),
                    ),
                  _Pill(
                    label: filters.covered == true ? 'Techada ✓' : 'Techada',
                    selected: filters.covered == true,
                    onTap: () => _set(filters.covered == true
                        ? filters.copyWith(clearCovered: true)
                        : filters.copyWith(covered: true)),
                  ),
                  _Pill(
                    label: filters.courtType == null ? 'Tipo' : courtTypeLabel(filters.courtType!),
                    selected: filters.courtType != null,
                    trailing: Icons.keyboard_arrow_down,
                    onTap: () => _pickType(filters),
                  ),
                  _Pill(
                    label: filters.maxPrice == null ? 'Sin límite de precio' : 'Hasta \$${filters.maxPrice! ~/ 1000} mil',
                    selected: filters.maxPrice != null,
                    trailing: Icons.keyboard_arrow_down,
                    onTap: () => _pickPrice(filters),
                  ),
                  if (anyFilter) _Pill(label: 'Limpiar', onTap: _clearAll),
                ],
              ),
            ),
            Expanded(
              child: AsyncView<List<Court>>(
                value: courts,
                onRetry: () => ref.invalidate(courtsProvider),
                builder: (all) {
                  final list = _visible(all);
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(citiesProvider);
                      ref.invalidate(courtsProvider);
                      await ref.read(courtsProvider.future);
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12).withNav(context),
                      children: [
                        Text(
                          '${list.length} ${list.length == 1 ? 'cancha disponible' : 'canchas disponibles'}',
                          style: authText(14, weight: 800),
                        ),
                        const SizedBox(height: 16),
                        if (list.isEmpty)
                          _EmptyState(onClear: anyFilter ? _clearAll : null)
                        else
                          for (final c in list) _CourtCard(court: c),
                      ],
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _searchField() => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF133524).withValues(alpha: 0.07), blurRadius: 28, offset: const Offset(0, 8))],
        ),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          style: authText(14, weight: 600),
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Busca por cancha, barrio o ciudad',
            prefixIcon: const Icon(Icons.search, size: 20, color: AuthColors.primary),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar búsqueda',
                    icon: const Icon(Icons.close, size: 18, color: AuthColors.muted),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      );

  Future<void> _pickPrice(CourtFilters f) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => Theme(data: authTheme(Theme.of(context)), child: _PriceSheet(selected: f.maxPrice)),
    );
    if (picked == null) return;
    _set(picked == _PriceSheet.none ? f.copyWith(clearPrice: true) : f.copyWith(maxPrice: picked));
  }

  Future<void> _pickType(CourtFilters f) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          for (final t in courtTypes) ListTile(title: Text(courtTypeLabel(t)), onTap: () => Navigator.pop(context, t)),
          ListTile(title: const Text('Todos los tipos'), onTap: () => Navigator.pop(context, -1)),
        ]),
      ),
    );
    if (picked == null) return;
    _set(picked == -1 ? f.copyWith(clearCourtType: true) : f.copyWith(courtType: picked));
  }

  /// Ordena por cercanía usando el GPS. Si no se puede, avisa y se puede elegir la ciudad a mano.
  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await ref.read(locationProvider)();
      final f = ref.read(courtFiltersProvider);
      _set(f.copyWith(lat: pos.lat, lng: pos.lng, clearCity: true));
    } on LocationUnavailable {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AuthColors.ink,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            content: Text('Activa la ubicación para mostrar canchas cercanas.',
                style: authText(12, weight: 600, color: Colors.white, height: 1.5)),
            action: SnackBarAction(label: 'Entendido', textColor: AuthColors.lime, onPressed: () {}),
          ));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }
}

/// Hoja inferior para elegir el precio máximo por hora.
class _PriceSheet extends StatelessWidget {
  const _PriceSheet({required this.selected});
  final int? selected;

  /// Valor que devuelve la hoja para "Sin límite" (null significa que la cerraron sin elegir).
  static const none = -1;
  static const _options = [60000, 80000, 100000, 120000];

  @override
  Widget build(BuildContext context) {
    Widget option(String label, int value) {
      final isSel = value == none ? selected == null : selected == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: isSel ? const Color(0xFFEDF5E9) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isSel ? AuthColors.primary : AuthColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(context, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Expanded(
                  child: Text(label, style: authText(14, weight: 700, color: isSel ? AuthColors.primary : const Color(0xFF405348))),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSel ? AuthColors.primary : null,
                    border: Border.all(color: isSel ? AuthColors.primary : const Color(0xFF9AA49E)),
                  ),
                  child: isSel ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
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
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('FILTRAR', style: authText(12, weight: 700, color: AuthColors.kicker, spacing: 0.12)),
                const SizedBox(height: 4),
                Text('Precio por hora', style: authText(20, weight: 800, spacing: -0.03)),
              ]),
            ),
            IconButton.filled(
              tooltip: 'Cerrar',
              style: IconButton.styleFrom(backgroundColor: const Color(0xFFEEF1EC), foregroundColor: const Color(0xFF52665A)),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
          const SizedBox(height: 20),
          option('Sin límite', none),
          for (final p in _options) option('Hasta ${cop(p)} por hora', p),
        ]),
      ),
    );
  }
}

/// Chip de filtro. [soft] = el seleccionado se ve verde claro (ciudades); si no, verde oscuro.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.soft = false,
    this.icon,
    this.trailing,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool soft;
  final IconData? icon;
  final IconData? trailing;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dark = selected && !soft;
    final bg = dark ? AuthColors.primary : (selected ? AuthColors.tile : Colors.white);
    final fg = dark ? Colors.white : (selected ? AuthColors.primary : const Color(0xFF405348));
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: bg,
          shape: StadiumBorder(side: BorderSide(color: selected ? AuthColors.primary : AuthColors.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (busy) ...[
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                  const SizedBox(width: 8),
                ] else if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label, style: authText(14, weight: 800, color: fg)),
                if (trailing != null) ...[const SizedBox(width: 2), Icon(trailing, size: 18, color: fg)],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onClear});
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AuthColors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          Text('No encontramos canchas con esos filtros',
              textAlign: TextAlign.center, style: authText(17, weight: 800)),
          const SizedBox(height: 4),
          Text('Prueba otra ciudad o amplía el rango de precio.',
              textAlign: TextAlign.center, style: authText(13, weight: 500, color: const Color(0xFF78877E))),
          if (onClear != null) ...[
            const SizedBox(height: 16),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AuthColors.tile,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: const StadiumBorder(),
              ),
              onPressed: onClear,
              child: const Text('Limpiar búsqueda'),
            ),
          ],
        ]),
      );
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court});
  final Court court;

  @override
  Widget build(BuildContext context) {
    final dist = court.distanceM;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AuthColors.border),
          boxShadow: [BoxShadow(color: const Color(0xFF133524).withValues(alpha: 0.08), blurRadius: 36, offset: const Offset(0, 12))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/courts/${court.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 208,
                child: Stack(fit: StackFit.expand, children: [
                  CourtImage(url: court.photoUrl, height: 208),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [Color(0x73071B10), Color(0x00071B10)],
                      ),
                    ),
                  ),
                  Positioned(left: 16, top: 16, child: _Badge(courtTypesLabel(court.types), lime: true)),
                  if (dist != null)
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: _Badge(
                        dist < 1000 ? '${dist.round()} m' : '${(dist / 1000).toStringAsFixed(1)} km',
                        dark: true,
                        icon: Icons.place_outlined,
                      ),
                    ),
                  if (court.covered) const Positioned(right: 16, bottom: 16, child: _Badge('Techada')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(court.name, style: authText(18, weight: 800, spacing: -0.025)),
                        const SizedBox(height: 4),
                        Text('${court.address} · ${court.city}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: authText(14, weight: 500, color: AuthColors.muted)),
                        if (court.requiresDeposit) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFFEDF3E9), borderRadius: BorderRadius.circular(20)),
                            child: Text('Anticipo ${court.depositPercent} %',
                                style: authText(10, weight: 800, color: const Color(0xFF285E3C))),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 12),
                    _Rating(court.rating, court.reviewCount),
                  ]),
                  const SizedBox(height: 18),
                  const Divider(height: 1, color: AuthColors.border),
                  const SizedBox(height: 16),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Desde', style: authText(12, weight: 600, color: const Color(0xFF78877E))),
                        const SizedBox(height: 2),
                        Text.rich(TextSpan(children: [
                          TextSpan(text: cop(court.pricePerHour), style: authText(20, weight: 800, spacing: -0.03)),
                          TextSpan(text: '  / hora', style: authText(12, weight: 600, color: const Color(0xFF78877E))),
                        ])),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: AuthColors.primary, borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Reservar', style: authText(14, weight: 800, color: Colors.white)),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right, size: 18, color: Colors.white),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  const _Rating(this.rating, this.count);
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text('Sin reseñas', style: authText(12, weight: 600, color: const Color(0xFF8B978F)));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF3B61F)),
      const SizedBox(width: 2),
      Text(rating.toStringAsFixed(1), style: authText(14, weight: 800)),
      const SizedBox(width: 3),
      Text('($count)', style: authText(14, weight: 500, color: const Color(0xFF8B978F))),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.lime = false, this.dark = false, this.icon});
  final String text;
  final bool lime;
  final bool dark;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = lime ? AuthColors.lime : (dark ? const Color(0xBF071B10) : const Color(0xE6FFFFFF));
    final fg = dark ? Colors.white : (lime ? AuthColors.ink : AuthColors.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
        Text(text, style: authText(12, weight: 800, color: fg)),
      ]),
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
      color: AuthColors.tile,
      child: const Icon(Icons.sports_soccer, size: 48, color: AuthColors.primary),
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
