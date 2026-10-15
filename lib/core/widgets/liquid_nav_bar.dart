import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

class NavItem {
  const NavItem({required this.label, required this.icon, this.badge = 0});
  final String label;
  final IconData icon;

  /// Contador sobre el ícono (0 = sin insignia).
  final int badge;
}

/// Barra inferior flotante con efecto "liquid glass": cristal esmerilado y una burbuja
/// que marca la pestaña activa. Al mantener presionado, la burbuja crece y sigue el dedo;
/// al soltar se acomoda (con resorte) en la pestaña más cercana.
///
/// Úsala como `bottomNavigationBar` de un Scaffold con `extendBody: true` para que el
/// contenido pase por detrás del cristal.
class LiquidGlassNavBar extends StatefulWidget {
  const LiquidGlassNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  static const height = 68.0;

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar> with SingleTickerProviderStateMixin {
  static const _pad = 6.0;
  static const _spring = SpringDescription(mass: 1, stiffness: 320, damping: 22);

  /// El valor del controlador es la posición de la burbuja en unidades de pestaña (0 … n-1).
  late final AnimationController _pos = AnimationController.unbounded(vsync: this, value: widget.index.toDouble());
  bool _pressed = false;

  /// Última posición del dedo (en unidades de pestaña): al soltar manda ella, no la burbuja,
  /// que en un toque rápido todavía no alcanzó al dedo.
  double _finger = 0;
  int _lastNearest = -1;

  int get _count => widget.items.length;

  @override
  void didUpdateWidget(LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (!_pressed && old.index != widget.index) _settle(widget.index);
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _settle(int to) =>
      _pos.animateWith(SpringSimulation(_spring, _pos.value, to.toDouble(), _pos.velocity));

  double _fingerPos(double dx, double itemW) => ((dx - _pad) / itemW - 0.5).clamp(0.0, _count - 1.0);

  void _haptic() {
    final n = _pos.value.round().clamp(0, _count - 1);
    if (n != _lastNearest) {
      _lastNearest = n;
      HapticFeedback.selectionClick();
    }
  }

  void _down(PointerDownEvent e, double itemW) {
    setState(() => _pressed = true);
    _lastNearest = _pos.value.round();
    _finger = _fingerPos(e.localPosition.dx, itemW);
    _pos.animateWith(SpringSimulation(_spring, _pos.value, _finger, _pos.velocity));
    HapticFeedback.lightImpact();
  }

  void _move(PointerMoveEvent e, double itemW) {
    _finger = _fingerPos(e.localPosition.dx, itemW);
    _pos.value = _finger; // seguir el dedo sin retraso
    _haptic();
  }

  void _up() {
    final to = _finger.round().clamp(0, _count - 1);
    setState(() => _pressed = false);
    _settle(to);
    if (to != widget.index) widget.onChanged(to);
  }

  void _cancel() {
    setState(() => _pressed = false);
    _settle(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final base = dark ? Colors.white : Colors.black;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SizedBox(
          height: LiquidGlassNavBar.height,
          child: LayoutBuilder(builder: (context, box) {
            final itemW = (box.maxWidth - _pad * 2) / _count;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _down(e, itemW),
              onPointerMove: (e) => _move(e, itemW),
              onPointerUp: (_) => _up(),
              onPointerCancel: (_) => _cancel(),
              child: Stack(clipBehavior: Clip.none, children: [
                // Cristal esmerilado.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [BoxShadow(color: base.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                (dark ? Colors.white : Colors.white).withValues(alpha: dark ? 0.16 : 0.62),
                                (dark ? Colors.white : Colors.white).withValues(alpha: dark ? 0.06 : 0.30),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(34),
                            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.22 : 0.75), width: 1.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Burbuja.
                AnimatedBuilder(
                  animation: _pos,
                  builder: (context, _) {
                    const h = LiquidGlassNavBar.height - _pad * 2;
                    final w = itemW - 4;
                    final left = _pad + _pos.value * itemW + 2;
                    return Positioned(
                      left: left,
                      top: _pad,
                      width: w,
                      height: h,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: _pressed ? 1.0 : 0.0),
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        builder: (context, t, child) =>
                            Transform.scale(scaleX: 1 + 0.16 * t, scaleY: 1 + 0.30 * t, child: child),
                        child: IgnorePointer(child: _Bubble(accent: accent, dark: dark, pressed: _pressed)),
                      ),
                    );
                  },
                ),
                // Íconos y textos.
                AnimatedBuilder(
                  animation: _pos,
                  builder: (context, _) {
                    final nearest = _pos.value.round().clamp(0, _count - 1);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _pad),
                      child: Row(children: [
                        for (var i = 0; i < _count; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: i == widget.index,
                              label: widget.items[i].label,
                              onTap: () => widget.onChanged(i),
                              child: ExcludeSemantics(
                                child: _Item(item: widget.items[i], active: i == nearest, accent: accent, base: base),
                              ),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
              ]),
            );
          }),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.accent, required this.dark, required this.pressed});
  final Color accent;
  final bool dark;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: pressed ? 0.30 : 0.16), blurRadius: pressed ? 22 : 12, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: dark ? 0.30 : (pressed ? 0.85 : 0.70)),
                  accent.withValues(alpha: pressed ? 0.20 : 0.14),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.active, required this.accent, required this.base});
  final NavItem item;
  final bool active;
  final Color accent;
  final Color base;

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : base.withValues(alpha: 0.62);
    final icon = Icon(item.icon, size: 24, color: color);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      AnimatedScale(
        scale: active ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: item.badge > 0
            ? Badge(label: Text(item.badge > 99 ? '99+' : '${item.badge}'), child: icon)
            : icon,
      ),
      const SizedBox(height: 2),
      Text(
        item.label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color),
      ),
    ]);
  }
}
