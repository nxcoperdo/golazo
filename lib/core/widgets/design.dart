import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_ui.dart';

/// Bloques de diseño compartidos por las pantallas con sesión (jugador, dueño y admin).
/// Usan los colores y la tipografía de `auth_ui.dart`.

/// Página con el encabezado del diseño: sobretítulo verde, título grande, botón volver y acciones.
/// Dentro del shell con pestañas el espacio de la barra de cristal lo da `MediaQuery`
/// (las listas deben usar `.withNav(context)` si fijan su propio padding).
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.kicker,
    this.onBack,
    this.actions = const [],
    this.fab,
    required this.child,
  });

  final String title;
  final String? kicker;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? fab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: authTheme(Theme.of(context)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          floatingActionButton: fab,
          body: Column(children: [
            Container(
              decoration: BoxDecoration(
                color: AuthColors.cream.withValues(alpha: 0.95),
                border: const Border(bottom: BorderSide(color: Color(0x14143E2A))),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Row(children: [
                    if (onBack != null) ...[
                      Material(
                        color: Colors.white,
                        elevation: 1,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onBack,
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.chevron_left, color: AuthColors.primary, semanticLabel: 'Volver'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (kicker != null)
                          Text(kicker!.toUpperCase(),
                              style: authText(11, weight: 700, color: AuthColors.kicker, spacing: 0.12)),
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: authText(24, weight: 800, spacing: -0.04)),
                      ]),
                    ),
                    for (final a in actions) ...[const SizedBox(width: 8), a],
                  ]),
                ),
              ),
            ),
            Expanded(child: child),
          ]),
        ),
      ),
    );
  }
}

/// Botón redondo del encabezado (campana, perfil…). Con [badge] > 0 muestra el contador rojo.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.badge = 0, this.dark = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  final bool dark;

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Material(
          color: dark ? AuthColors.primary : Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 19, color: dark ? Colors.white : AuthColors.primary, semanticLabel: tooltip),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFD23B34), borderRadius: BorderRadius.circular(8)),
              child: Text(badge > 99 ? '99+' : '$badge', style: authText(9, weight: 800, color: Colors.white)),
            ),
          ),
      ]);
}

/// Selector de 2 o 3 opciones en una píldora gris (Próximas / Anteriores, Por revisar / Historial…).
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFE7EBE5), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (final (v, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == value,
                child: Material(
                  color: v == value ? Colors.white : Colors.transparent,
                  elevation: v == value ? 1 : 0,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(v),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: authText(14, weight: 800, color: v == value ? AuthColors.primary : const Color(0xFF718078))),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

enum PillTone { green, amber, red, gray, blue }

/// Etiqueta de estado con los colores del diseño.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.tone, {super.key});
  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.green => (const Color(0xFFDFF2DD), const Color(0xFF23653A)),
      PillTone.amber => (const Color(0xFFFFF0C7), const Color(0xFF7A5B0B)),
      PillTone.red => (const Color(0xFFF8DFDC), const Color(0xFFA43730)),
      PillTone.gray => (const Color(0xFFE8ECE9), const Color(0xFF5F7066)),
      PillTone.blue => (const Color(0xFFE1ECFA), const Color(0xFF24558F)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: authText(10, weight: 800, color: fg)),
    );
  }
}

/// Tarjeta blanca redondeada del diseño.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.margin = const EdgeInsets.only(bottom: 16), this.radius = 22, this.color = Colors.white, this.borderColor});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor ?? AuthColors.border),
          boxShadow: [BoxShadow(color: const Color(0xFF133524).withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}

/// Aviso con fondo de color (p. ej. "Reserva de último momento · Sin cancelación").
class NoticeBox extends StatelessWidget {
  const NoticeBox(this.text, {super.key, this.bg = const Color(0xFFFFF1CD), this.fg = const Color(0xFF755912)});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: authText(10, weight: 700, color: fg, height: 1.4)),
      );
}

/// Tarjeta de cifra. [hero] = tarjeta verde con la cifra en lima.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.hero = false});
  final String label;
  final String value;
  final bool hero;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hero ? AuthColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: authText(11, weight: 600, color: hero ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF78877E))),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: authText(hero ? 30 : 24, weight: 800, spacing: -0.04, color: hero ? AuthColors.lime : AuthColors.ink)),
          ),
        ]),
      );
}

/// Caja con etiqueta y valor que abre un selector (Cancha, Día, Desde, Duración…).
class PickTile extends StatelessWidget {
  const PickTile({super.key, required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AuthColors.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: authText(12, weight: 700, color: const Color(0xFF78877E))),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: authText(14, weight: 800)),
            ]),
          ),
        ),
      );
}

/// Botón flotante lima ("+ Bloquear horas", "+ Nueva cancha").
class PillFab extends StatelessWidget {
  const PillFab({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AuthColors.lime,
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Text(label, style: authText(14, weight: 800, color: AuthColors.ink)),
          ),
        ),
      );
}

/// Botón de contorno ("Cancelar", "Rechazar"); [danger] = rojo.
class OutlineAction extends StatelessWidget {
  const OutlineAction({super.key, required this.label, required this.onPressed, this.danger = true});
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? const Color(0xFFB13C35) : AuthColors.ink;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        foregroundColor: c,
        backgroundColor: Colors.white,
        side: BorderSide(color: danger ? c.withValues(alpha: 0.2) : AuthColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: authText(12, weight: 800),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Botón sólido pequeño ("Aprobar", "Pagar anticipo"); [danger] = rojo.
class SolidAction extends StatelessWidget {
  const SolidAction({super.key, required this.label, required this.onPressed, this.danger = false, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          backgroundColor: danger ? const Color(0xFFB13C35) : AuthColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: authText(12, weight: 800),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label),
      );
}

/// Hoja inferior estándar: agarradera + contenido. Devuelve lo que se pase a `Navigator.pop`.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => Theme(
        data: authTheme(Theme.of(context)),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
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
                Builder(builder: builder),
              ]),
            ),
          ),
        ),
      ),
    );

/// Título (y subtítulo opcional) de una hoja inferior.
class SheetHeading extends StatelessWidget {
  const SheetHeading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: authText(24, weight: 800, spacing: -0.04, height: 1.15)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: authText(14, weight: 500, color: const Color(0xFF66756C), height: 1.5)),
        ],
        const SizedBox(height: 20),
      ]);
}

/// Botones de pie de una hoja: acción principal (verde o roja) y "Cancelar".
class SheetActions extends StatelessWidget {
  const SheetActions({super.key, required this.primaryLabel, required this.onPrimary, this.danger = false, this.busy = false, this.cancelLabel = 'Cancelar'});
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool danger;
  final bool busy;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: danger ? const Color(0xFFB13C35) : AuthColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: authText(14, weight: 800),
          ),
          onPressed: busy ? null : onPrimary,
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(primaryLabel),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF65736B), minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.pop(context),
          child: Text(cancelLabel),
        ),
      ]);
}

/// Fila de interruptor del diseño (tarjeta blanca con píldora): "Cancha techada", "Exigir anticipo".
class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchCard(
        title: title,
        subtitle: subtitle,
        value: value,
        onChanged: onChanged,
      );
}

/// Hoja con un formulario. La hoja crea y destruye sus propios controladores (con los textos
/// iniciales de [initial]); [fields] recibe el controlador de cada campo. Valida al pulsar el
/// botón principal y devuelve los textos escritos (en el mismo orden), o null si se cancela.
Future<List<String>?> showFormSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<String> initial,
  required List<Widget Function(TextEditingController controller)> fields,
  required String primaryLabel,
  bool danger = false,
}) =>
    showAppSheet<List<String>>(
      context,
      builder: (sheet) => _FormSheetBody(
        title: title,
        subtitle: subtitle,
        initial: initial,
        fields: fields,
        primaryLabel: primaryLabel,
        danger: danger,
        onSubmit: (values) => Navigator.pop(sheet, values),
      ),
    );

class _FormSheetBody extends StatefulWidget {
  const _FormSheetBody({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.fields,
    required this.primaryLabel,
    required this.danger,
    required this.onSubmit,
  });

  final String title;
  final String? subtitle;
  final List<String> initial;
  final List<Widget Function(TextEditingController)> fields;
  final String primaryLabel;
  final bool danger;
  final void Function(List<String> values) onSubmit;

  @override
  State<_FormSheetBody> createState() => _FormSheetBodyState();
}

class _FormSheetBodyState extends State<_FormSheetBody> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _controllers = [for (final t in widget.initial) TextEditingController(text: t)];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeading(widget.title, subtitle: widget.subtitle),
          for (var i = 0; i < widget.fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            widget.fields[i](_controllers[i]),
          ],
          SheetActions(
            primaryLabel: widget.primaryLabel,
            danger: widget.danger,
            onPrimary: () {
              if (_form.currentState!.validate()) widget.onSubmit([for (final c in _controllers) c.text.trim()]);
            },
          ),
        ]),
      );
}

/// Hoja para elegir una opción de una lista (cancha, día, hora…). Devuelve la elegida o null.
Future<T?> showPickSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  T? selected,
}) =>
    showAppSheet<T>(
      context,
      builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeading(title),
        for (final (value, label) in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: value == selected ? const Color(0xFFEDF5E9) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: value == selected ? AuthColors.primary : AuthColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.pop(sheet, value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Text(label,
                          style: authText(14, weight: 700, color: value == selected ? AuthColors.primary : const Color(0xFF405348))),
                    ),
                    if (value == selected) const Icon(Icons.check_circle, size: 20, color: AuthColors.primary),
                  ]),
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
    );

/// Interruptor en forma de píldora (el mismo del diseño), sin tarjeta alrededor.
class PillSwitch extends StatelessWidget {
  const PillSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        label: semanticLabel,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: Opacity(
            opacity: onChanged == null ? 0.4 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(4),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: value ? AuthColors.primary : const Color(0xFFD9DDD8),
              ),
              child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            ),
          ),
        ),
      );
}

/// Zona punteada para elegir la captura del comprobante.
class ProofDropZone extends StatelessWidget {
  const ProofDropZone({super.key, required this.fileName, required this.onTap});
  final String? fileName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chosen = fileName != null;
    return Semantics(
      button: true,
      label: chosen ? 'Cambiar comprobante: $fileName' : 'Subir comprobante',
      child: CustomPaint(
        foregroundPainter: _DashedBorder(chosen ? AuthColors.kicker : AuthColors.primary.withValues(alpha: 0.2)),
        child: Material(
          color: chosen ? const Color(0xFFEEF5EA) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 144),
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFE2EFDD), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.upload_outlined, size: 21, color: AuthColors.primary),
                ),
                const SizedBox(height: 12),
                Text(fileName ?? 'Subir comprobante',
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: authText(14, weight: 800)),
                const SizedBox(height: 4),
                Text(chosen ? 'Toca para cambiar la imagen' : 'JPG, PNG o foto de cámara',
                    style: authText(11, weight: 600, color: const Color(0xFF88938D))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, (d + 6).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

