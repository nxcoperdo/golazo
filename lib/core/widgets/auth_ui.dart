import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../logo.dart';

/// Paleta de las pantallas de acceso (login, registro, recuperar contraseña, confirmar correo, splash).
class AuthColors {
  const AuthColors._();

  static const cream = Color(0xFFF4F5EC);
  static const ink = Color(0xFF11251B);
  static const primary = Color(0xFF174E32);
  static const lime = Color(0xFFD9FF5B);
  static const kicker = Color(0xFF438158);
  static const link = Color(0xFF286A42);
  static const label = Color(0xFF304C3B);
  static const muted = Color(0xFF6C7B72);
  static const hint = Color(0xFF9AA49E);
  static const border = Color(0x1F143E2A); // #143E2A al 12 %
  static const error = Color(0xFFC93B3B);
  static const tile = Color(0xFFE2F0DC);
  static const splash = Color(0xFF040806); // igual al fondo del logo, para que no se note el borde
}

const authFont = 'Manrope';

/// Estilo de texto con Manrope. Es una fuente variable: el peso se pide por el eje `wght`.
TextStyle authText(double size,
    {int weight = 600, Color color = AuthColors.ink, double? spacing, double? height}) {
  return TextStyle(
    fontFamily: authFont,
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    letterSpacing: spacing == null ? null : size * spacing,
    height: height,
  );
}

OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );

/// Tema local de estas pantallas: no cambia el del resto de la app.
ThemeData authTheme(ThemeData base) {
  final scheme = base.colorScheme.copyWith(
    primary: AuthColors.primary,
    onPrimary: Colors.white,
    error: AuthColors.error,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AuthColors.cream,
    textTheme: base.textTheme.apply(fontFamily: authFont, bodyColor: AuthColors.ink, displayColor: AuthColors.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: authText(15, weight: 500, color: AuthColors.hint),
      prefixStyle: authText(15, color: AuthColors.ink),
      helperStyle: authText(12, weight: 500, color: AuthColors.muted),
      errorStyle: authText(12, weight: 600, color: AuthColors.error),
      prefixIconColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.error)
          ? AuthColors.error
          : s.contains(WidgetState.focused)
              ? AuthColors.kicker
              : AuthColors.muted),
      border: _border(AuthColors.border),
      enabledBorder: _border(AuthColors.border),
      focusedBorder: _border(AuthColors.kicker, 2),
      errorBorder: _border(AuthColors.error),
      focusedErrorBorder: _border(AuthColors.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AuthColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AuthColors.primary.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: shape,
        textStyle: authText(15, weight: 800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AuthColors.ink,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: AuthColors.border),
        shape: shape,
        textStyle: authText(14, weight: 800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AuthColors.link,
        textStyle: authText(14, weight: 800),
      ),
    ),
  );
}

/// Atrás si hay pantalla anterior; si se llegó por un enlace, al login.
void backOrLogin(BuildContext context) => context.canPop() ? context.pop() : context.go('/login');

/// Marco de las pantallas de acceso: fondo crema, columna de 420 px centrada verticalmente,
/// y arriba el logo (sin [onBack]) o el botón circular de volver (con [onBack]).
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child, this.onBack});

  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: authTheme(Theme.of(context)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 420, minHeight: box.maxHeight - 36),
                    child: IntrinsicHeight(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Align(alignment: Alignment.centerLeft, child: _header()),
                        Expanded(child: Center(child: child)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => onBack == null
      ? const GolazoLogo(width: 112)
      : Material(
          color: Colors.white,
          shape: const CircleBorder(side: BorderSide(color: AuthColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.chevron_left, color: AuthColors.primary, semanticLabel: 'Volver'),
            ),
          ),
        );
}

/// Sobretítulo verde + título grande + subtítulo.
class AuthTitle extends StatelessWidget {
  const AuthTitle({super.key, this.kicker, required this.title, this.subtitle, this.center = false});

  final String? kicker;
  final String title;
  final String? subtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (kicker != null) Text(kicker!, textAlign: align, style: authText(14, weight: 700, color: AuthColors.kicker)),
        if (kicker != null) const SizedBox(height: 8),
        Text(title, textAlign: align, style: authText(34, weight: 800, spacing: -0.05, height: 1.1)),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(subtitle!, textAlign: align, style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5)),
        ],
      ],
    );
  }
}

/// Campo con la etiqueta encima y un icono a la izquierda. Es un `TextFormField` normal
/// (validador, autocompletado y controlador). Con [password] trae el ojo para mostrar/ocultar.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.hint,
    this.validator,
    this.password = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.onChanged,
    this.prefixText,
    this.helperText,
    this.maxLines = 1,
    this.maxLength,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final bool password;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String? prefixText;
  final String? helperText;
  final int maxLines;
  final int? maxLength;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: authText(14, weight: 700, color: AuthColors.label)),
      const SizedBox(height: 8),
      TextFormField(
        controller: widget.controller,
        obscureText: widget.password && _hide,
        maxLines: widget.password ? 1 : widget.maxLines,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        autofillHints: widget.autofillHints,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        onFieldSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        validator: widget.validator,
        style: authText(15, weight: 600),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon, size: 20),
          prefixText: widget.prefixText,
          helperText: widget.helperText,
          helperMaxLines: 2,
          suffixIcon: widget.password
              ? IconButton(
                  tooltip: _hide ? 'Ver contraseña' : 'Ocultar contraseña',
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20, color: AuthColors.muted),
                  onPressed: () => setState(() => _hide = !_hide),
                )
              : null,
        ),
      ),
    ]);
  }
}

/// Botón principal verde con sombra suave; muestra un spinner mientras [busy].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [BoxShadow(color: AuthColors.primary.withValues(alpha: 0.20), blurRadius: 28, offset: const Offset(0, 12))]
            : null,
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label),
      ),
    );
  }
}

/// Línea con texto al centro: "o continúa con".
class OrDivider extends StatelessWidget {
  const OrDivider(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    const line = Expanded(child: Divider(color: AuthColors.border, height: 1));
    return Row(children: [
      line,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(text, style: authText(12, weight: 600, color: const Color(0xFF89958E))),
      ),
      line,
    ]);
  }
}

/// Cuadro redondeado con un icono (encabezado de recuperar contraseña).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: AuthColors.tile, borderRadius: BorderRadius.circular(22)),
        child: Icon(icon, size: 27, color: AuthColors.primary),
      );
}

/// Círculo grande de resultado: ✓ lima (éxito) o ! rojo claro (error).
class ResultBadge extends StatelessWidget {
  const ResultBadge({super.key, required this.ok, this.size = 96});
  final bool ok;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? AuthColors.lime : const Color(0xFFF8DFDC)),
        child: Icon(
          ok ? Icons.check_rounded : Icons.priority_high_rounded,
          size: size * 0.5,
          color: ok ? AuthColors.primary : const Color(0xFFB63B32),
          semanticLabel: ok ? 'Listo' : 'Error',
        ),
      );
}

/// Tarjeta blanca con interruptor en forma de píldora (p. ej. "Soy dueño de una cancha").
class SwitchCard extends StatelessWidget {
  const SwitchCard({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: title,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AuthColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: authText(14, weight: 800)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: authText(12, weight: 500, color: const Color(0xFF748179), height: 1.4)),
                  ],
                ]),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 28,
                padding: const EdgeInsets.all(4),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: value ? AuthColors.primary : const Color(0xFFD9DDD8),
                ),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
