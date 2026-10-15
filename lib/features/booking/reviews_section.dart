import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Reseñas de una cancha, con opción de reportar una al administrador.
/// Se ve como un bloque blanco de ancho completo dentro del detalle de la cancha.
class ReviewsSection extends ConsumerStatefulWidget {
  const ReviewsSection({super.key, required this.courtId});
  final String courtId;

  @override
  ConsumerState<ReviewsSection> createState() => _ReviewsState();
}

class _ReviewsState extends ConsumerState<ReviewsSection> {
  static const _preview = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final reviews = ref.watch(courtReviewsProvider(widget.courtId));
    final list = reviews.value ?? const <Review>[];
    final shown = _all ? list : list.take(_preview).toList();
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AuthColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('COMUNIDAD', style: authText(12, weight: 700, color: AuthColors.kicker, spacing: 0.12)),
              const SizedBox(height: 4),
              Text('Reseñas', style: authText(20, weight: 800, spacing: -0.03)),
            ]),
          ),
          if (list.length > _preview)
            TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? 'Ver menos' : 'Ver todas'),
            ),
        ]),
        reviews.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          error: (e, _) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(errorMessage(e))),
          data: (_) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Aún no hay reseñas', style: authText(14, weight: 500, color: AuthColors.muted)),
                )
              : Column(children: [
                  for (var i = 0; i < shown.length; i++) _ReviewTile(review: shown[i], last: i == shown.length - 1),
                ]),
        ),
      ]),
    );
  }
}

class _ReviewTile extends ConsumerWidget {
  const _ReviewTile({required this.review, required this.last});
  final Review review;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = review;
    final initial = r.authorName.trim().isEmpty ? '?' : r.authorName.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Color(0x14143E2A))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE4EEE0)),
            child: Text(initial, style: authText(13, weight: 800, color: AuthColors.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.authorName, style: authText(14, weight: 800)),
              const SizedBox(height: 2),
              Semantics(
                label: '${r.stars} de 5 estrellas',
                child: Row(children: [
                  for (var i = 1; i <= 5; i++)
                    Icon(Icons.star_rounded, size: 14, color: i <= r.stars ? const Color(0xFFF3B61F) : const Color(0xFFE3E6E1)),
                ]),
              ),
            ]),
          ),
          Text(agoLabel(r.createdAt), style: authText(11, weight: 600, color: const Color(0xFF8A968F))),
        ]),
        if (r.body != null && r.body!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(r.body!, style: authText(14, weight: 500, color: const Color(0xFF5F7066), height: 1.5)),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8A968F),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: authText(11, weight: 700),
            ),
            onPressed: () async {
              final reason = await _askReportReason(context);
              if (reason == null || !context.mounted) return;
              await guarded(context, () => ref.read(apiProvider).reportReview(r.id, reason: reason),
                  success: 'Gracias, la revisaremos');
            },
            child: const Text('Reportar'),
          ),
        ),
      ]),
    );
  }
}

const _reportReasons = ['Lenguaje ofensivo', 'Información falsa', 'Contenido no relacionado', 'Otro motivo'];

/// Hoja inferior para elegir por qué se reporta una reseña. Devuelve el motivo o null si cancela.
Future<String?> _askReportReason(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => Theme(
        data: authTheme(Theme.of(context)),
        child: SafeArea(
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
              Text('Reportar reseña', style: authText(24, weight: 800, spacing: -0.04)),
              const SizedBox(height: 8),
              Text('Cuéntanos por qué esta reseña debería revisarse.',
                  style: authText(14, weight: 500, color: const Color(0xFF66756C), height: 1.5)),
              const SizedBox(height: 20),
              for (final reason in _reportReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AuthColors.border),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(sheet, reason),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Text(reason, style: authText(14, weight: 800)),
                      ),
                    ),
                  ),
                ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF65736B), minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Cancelar'),
              ),
            ]),
          ),
        ),
      ),
    );

/// Hoja para calificar una reserva ya jugada (5 estrellas + comentario opcional).
/// Devuelve true si se publicó.
Future<bool> showReviewDialog(BuildContext context, WidgetRef ref, String bookingId, String courtId,
    {String? courtName}) async {
  final r = await showAppSheet<(int, String)>(
    context,
    builder: (sheet) => _ReviewSheet(courtName: courtName, onPublish: (stars, text) => Navigator.pop(sheet, (stars, text))),
  );
  if (r == null || !context.mounted) return false;
  final done = await guarded(
    context,
    () => ref.read(apiProvider).reviewBooking(bookingId, r.$1, r.$2),
    success: '¡Gracias por tu reseña!',
  );
  if (done) {
    ref.invalidate(courtReviewsProvider(courtId));
    ref.invalidate(courtDetailProvider(courtId));
    ref.invalidate(myBookingsProvider);
  }
  return done;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.courtName, required this.onPublish});
  final String? courtName;
  final void Function(int stars, String text) onPublish;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _text = TextEditingController();
  int _stars = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeading('Califica la cancha',
            subtitle: widget.courtName == null ? '¿Cómo estuvo tu partido?' : '¿Cómo estuvo tu partido en ${widget.courtName}?'),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i ${i == 1 ? 'estrella' : 'estrellas'}',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.star_rounded, size: 34, color: i <= _stars ? const Color(0xFFF3B61F) : const Color(0xFFD5DBD6)),
              onPressed: () => setState(() => _stars = i),
            ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          maxLines: 3,
          maxLength: 1000,
          style: authText(14, weight: 500),
          decoration: const InputDecoration(hintText: 'Comentario opcional'),
        ),
        SheetActions(
          primaryLabel: 'Publicar reseña',
          cancelLabel: 'Volver',
          onPrimary: _stars == 0 ? null : () => widget.onPublish(_stars, _text.text.trim()),
        ),
      ]);
}
