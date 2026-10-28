import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'auth_ui.dart';

/// Cómo se abre una página legal (navegador). Es un provider para reemplazarlo en las pruebas.
final openUrlProvider = Provider<Future<bool> Function(Uri)>(
  (_) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Páginas públicas que sirve el backend en /legal/*.
enum LegalPage {
  terms('terminos', 'Términos y Condiciones'),
  privacy('privacidad', 'Política de privacidad'),
  support('soporte', 'Soporte');

  const LegalPage(this.slug, this.label);
  final String slug;
  final String label;

  Uri get uri => Uri.parse(AppConfig.legalUrl(slug));
}

/// Casilla obligatoria: mayoría de edad + aceptación de términos y política de datos (Ley 1581).
class LegalConsentCheck extends ConsumerStatefulWidget {
  const LegalConsentCheck({super.key, required this.value, required this.onChanged, this.showError = false});

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showError;

  @override
  ConsumerState<LegalConsentCheck> createState() => _LegalConsentCheckState();
}

class _LegalConsentCheckState extends ConsumerState<LegalConsentCheck> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()..onTap = () => _open(LegalPage.terms);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()..onTap = () => _open(LegalPage.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _open(LegalPage page) async {
    final ok = await ref.read(openUrlProvider)(page.uri).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir ${page.uri}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = authText(12, weight: 500, color: AuthColors.ink, height: 1.5);
    final link = base.copyWith(fontWeight: FontWeight.w800, color: AuthColors.primary, decoration: TextDecoration.underline);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onChanged(!widget.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: widget.value,
                onChanged: (v) => widget.onChanged(v ?? false),
                activeColor: AuthColors.primary,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(style: base, children: [
                const TextSpan(text: 'Soy mayor de 18 años y acepto los '),
                TextSpan(text: 'Términos y Condiciones', style: link, recognizer: _terms),
                const TextSpan(text: ' y la '),
                TextSpan(text: 'Política de privacidad', style: link, recognizer: _privacy),
                const TextSpan(text: ', y autorizo el tratamiento de mis datos personales.'),
              ])),
            ),
          ]),
        ),
      ),
      if (widget.showError)
        Padding(
          padding: const EdgeInsets.only(left: 34, top: 2),
          child: Text('Debes aceptar para crear tu cuenta',
              style: authText(11, weight: 700, color: const Color(0xFFB13C35))),
        ),
    ]);
  }
}
