import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_style.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../player/courts_screen.dart' show CourtImage;

/// Canchas del dueño con su estado, y acceso a crear una nueva y a las estadísticas.
class OwnerCourtsTab extends ConsumerWidget {
  const OwnerCourtsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courts = ref.watch(ownerCourtsProvider);
    return AppPage(
      kicker: 'Tu negocio',
      title: 'Mis canchas',
      fab: PillFab(label: '+ Nueva cancha', onTap: () => context.push('/owner/courts/new')),
      child: AsyncView<List<Court>>(
        value: courts,
        onRetry: () => ref.invalidate(ownerCourtsProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(ownerCourtsProvider);
            await ref.read(ownerCourtsProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 96).withNav(context), children: [
            Material(
              color: AuthColors.primary,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/owner/stats'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Rendimiento', style: authText(12, weight: 500, color: Colors.white.withValues(alpha: 0.6))),
                        const SizedBox(height: 4),
                        Text('Ver estadísticas', style: authText(14, weight: 800, color: Colors.white)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text('Aún no tienes canchas.\nPublica la primera con el botón "+ Nueva cancha".',
                    textAlign: TextAlign.center, style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5)),
              )
            else
              for (final c in list) _CourtCard(court: c),
          ]),
        ),
      ),
    );
  }
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court});
  final Court court;

  @override
  Widget build(BuildContext context) {
    final c = court;
    final (dot, text) = switch (c.status) {
      CourtStatus.active => (const Color(0xFF48A35F), const Color(0xFF2C7743)),
      CourtStatus.pending => (const Color(0xFFE1A72D), const Color(0xFF9A6900)),
      CourtStatus.suspended => (const Color(0xFF9AA49E), const Color(0xFF65736B)),
    };
    return SoftCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(children: [
          InkWell(
            onTap: () => context.push('/owner/courts/${c.id}'),
            child: Row(children: [
              SizedBox(width: 112, height: 112, child: CourtImage(url: c.photoUrl, height: 112)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(14, weight: 800))),
                      const SizedBox(width: 8),
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 4),
                    Text('${c.city} · ${courtTypesLabel(c.types)} · ${cop(c.pricePerHour)}/h',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(12, weight: 500, color: const Color(0xFF6C7B72))),
                    const SizedBox(height: 12),
                    Text(courtStateLabel(c.status), style: authText(10, weight: 800, color: text)),
                  ]),
                ),
              ),
            ]),
          ),
          const Divider(height: 1, color: Color(0x14143E2A)),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: const RoundedRectangleBorder()),
            onPressed: () => context.push('/owner/courts/${c.id}'),
            child: Text('Administrar cancha', style: authText(12, weight: 800, color: AuthColors.primary)),
          ),
        ]),
      ),
    );
  }
}
