import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/auth_ui.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/ui.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'booking_policy.dart';

/// Pago del anticipo: resumen, cuenta regresiva, cuentas del dueño y subida del comprobante.
class PayDepositScreen extends ConsumerStatefulWidget {
  const PayDepositScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  ConsumerState<PayDepositScreen> createState() => _PayState();
}

class _PayState extends ConsumerState<PayDepositScreen> {
  PickedImage? _proof;
  bool _busy = false;
  bool _refreshedAfterExpiry = false;
  late DateTime _now = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final b = ref.read(bookingProvider(widget.bookingId)).value;
      // Se acabó el tiempo: el servidor libera la hora, así que se vuelve a pedir la reserva una vez.
      if (b?.payBy != null && !_now.isBefore(b!.payBy!) && !_refreshedAfterExpiry) {
        _refreshedAfterExpiry = true;
        ref.invalidate(bookingProvider(widget.bookingId));
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _leave() => context.canPop() ? context.pop() : context.go('/home?tab=1');

  Future<void> _pick() async {
    final img = await ref.read(pickImageProvider)(context);
    if (img != null && mounted) setState(() => _proof = img);
  }

  Future<void> _send() async {
    final img = _proof;
    if (img == null) return;
    setState(() => _busy = true);
    final ok = await guarded(
      context,
      () => ref.read(apiProvider).uploadBookingProof(widget.bookingId, img.bytes, img.filename),
    );
    if (ok) {
      ref.invalidate(bookingProvider(widget.bookingId));
      ref.invalidate(myBookingsProvider);
      _proof = null;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingProvider(widget.bookingId));
    final b = booking.value;
    final needsProof = b != null && b.needsPayment;
    return Theme(
      data: authTheme(Theme.of(context)),
      child: Scaffold(
        body: Column(children: [
          _Header(onBack: _leave),
          Expanded(
            child: AsyncView<Booking>(
              value: booking,
              onRetry: () => ref.invalidate(bookingProvider(widget.bookingId)),
              builder: (b) => b.needsPayment ? _form(b) : _Result(booking: b, onDone: () => context.go('/home?tab=1')),
            ),
          ),
        ]),
        bottomNavigationBar: needsProof ? _bottomBar() : null,
      ),
    );
  }

  Widget _form(Booking b) {
    final rejected = b.status == BookingStatus.rejected;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
      _SummaryCard(booking: b),
      const SizedBox(height: 16),
      if (rejected) const _RejectedNotice() else _Countdown(payBy: b.payBy, now: _now),
      const SizedBox(height: 28),
      const _SectionTitle('1. TRANSFIERE EL ANTICIPO', 'Cuenta del dueño'),
      const SizedBox(height: 16),
      if (b.paymentMethods.isEmpty)
        Text('El dueño aún no configuró cuentas de pago. Contáctalo para coordinar.',
            style: authText(14, weight: 500, color: AuthColors.muted, height: 1.5))
      else
        for (final m in b.paymentMethods) _AccountCard(method: m),
      const SizedBox(height: 28),
      const _SectionTitle('2. SUBE LA CAPTURA', 'Comprobante de pago'),
      const SizedBox(height: 8),
      Text('Puedes elegir una imagen de tu galería o tomar una foto.',
          style: authText(12, weight: 500, color: const Color(0xFF78877E), height: 1.5)),
      const SizedBox(height: 16),
      ProofDropZone(fileName: _proof?.filename, onTap: _busy ? null : _pick),
    ]);
  }

  Widget _bottomBar() => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          border: const Border(top: BorderSide(color: AuthColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PrimaryButton(
                label: 'Enviar comprobante',
                busy: _busy,
                onPressed: _proof == null ? null : _send,
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF65736B), textStyle: authText(12, weight: 800)),
                onPressed: () => context.go('/home?tab=1'),
                child: const Text('Pagar más tarde'),
              ),
            ]),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AuthColors.cream.withValues(alpha: 0.95),
          border: const Border(bottom: BorderSide(color: AuthColors.border)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Row(children: [
              Material(
                color: Colors.white,
                shape: const CircleBorder(side: BorderSide(color: AuthColors.border)),
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
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Paso final', style: authText(12, weight: 700, color: AuthColors.kicker)),
                Text('Pagar anticipo', style: authText(18, weight: 800, spacing: -0.03)),
              ]),
            ]),
          ),
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final white60 = Colors.white.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AuthColors.primary,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: AuthColors.primary.withValues(alpha: 0.18), blurRadius: 36, offset: const Offset(0, 16))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total de la reserva', style: authText(12, weight: 600, color: white60)),
              const SizedBox(height: 4),
              Text(cop(b.total), style: authText(20, weight: 800, color: Colors.white)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Anticipo a pagar', style: authText(12, weight: 600, color: white60)),
            const SizedBox(height: 4),
            Text(cop(b.amountDue), style: authText(24, weight: 800, color: AuthColors.lime)),
          ]),
        ]),
        const SizedBox(height: 20),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
        const SizedBox(height: 16),
        Text(b.courtName, style: authText(14, weight: 700, color: Colors.white)),
        const SizedBox(height: 4),
        Text(rangeLabel(b.startAt, b.hours), style: authText(12, weight: 500, color: Colors.white.withValues(alpha: 0.65))),
      ]),
    );
  }
}

/// Aviso ámbar con el tiempo que queda para subir el comprobante.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.payBy, required this.now});
  final DateTime? payBy;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final left = payBy?.difference(now);
    final expired = left != null && left <= Duration.zero;
    final mm = left == null ? '' : left.inMinutes.toString().padLeft(2, '0');
    final ss = left == null ? '' : (left.inSeconds % 60).toString().padLeft(2, '0');
    const fg = Color(0xFF725815);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6D9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4CD82)),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: Color(0xFFF6DF91), shape: BoxShape.circle),
          child: const Icon(Icons.schedule, size: 17, color: fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              expired ? 'Tu horario fue liberado' : 'Tu horario está reservado por ${BookingPolicy.unpaidMinutes} minutos',
              style: authText(12, weight: 800, color: fg),
            ),
            if (left != null) ...[
              const SizedBox(height: 2),
              Text(
                expired ? 'Se acabó el tiempo para subir el comprobante.' : 'Tiempo restante: $mm:$ss',
                style: authText(11, weight: 600, color: fg.withValues(alpha: 0.75)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _RejectedNotice extends StatelessWidget {
  const _RejectedNotice();

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFF8A2D26);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3B8B3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, size: 22, color: fg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tu comprobante fue rechazado', style: authText(12, weight: 800, color: fg)),
            const SizedBox(height: 2),
            Text('Revisa el valor y la cuenta, y sube uno nuevo para conservar tu hora.',
                style: authText(11, weight: 600, color: fg.withValues(alpha: 0.8), height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.kicker, this.title);
  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(kicker, style: authText(12, weight: 700, color: AuthColors.kicker, spacing: 0.13)),
        const SizedBox(height: 4),
        Text(title, style: authText(20, weight: 800, spacing: -0.03)),
      ]);
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.method});
  final PaymentMethod method;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AuthColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF2E4FF), borderRadius: BorderRadius.circular(20)),
              child: Text(method.label, style: authText(12, weight: 800, color: const Color(0xFF6F2B91))),
            ),
            const Spacer(),
            Text('Cuenta de cobro', style: authText(12, weight: 600, color: const Color(0xFF78877E))),
          ]),
          const SizedBox(height: 20),
          Text('Número', style: authText(12, weight: 600, color: const Color(0xFF78877E))),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(method.account, style: authText(24, weight: 800, spacing: -0.03))),
            const SizedBox(width: 12),
            _CopyButton(text: method.account),
          ]),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0x14143E2A)),
          const SizedBox(height: 16),
          Text('Titular', style: authText(12, weight: 600, color: const Color(0xFF78877E))),
          const SizedBox(height: 4),
          Text(method.holder, style: authText(14, weight: 800)),
        ]),
      );
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text.replaceAll(RegExp(r'[^0-9-]'), '')));
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFEDF3E9),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_copied ? Icons.check : Icons.copy_rounded, size: 16, color: AuthColors.primary),
              const SizedBox(width: 8),
              Text(_copied ? 'Copiado' : 'Copiar', style: authText(12, weight: 800, color: AuthColors.primary)),
            ]),
          ),
        ),
      );
}

/// Estado final: comprobante en revisión, reserva confirmada o cancelada.
class _Result extends StatelessWidget {
  const _Result({required this.booking, required this.onDone});
  final Booking booking;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final cancelled = b.status == BookingStatus.cancelled;
    final confirmed = b.status == BookingStatus.confirmed;
    final (kicker, title, text) = cancelled
        ? ('RESERVA CANCELADA', 'Esta reserva fue cancelada', 'La hora quedó libre. Puedes reservar otra cancha cuando quieras.')
        : confirmed
            ? ('RESERVA CONFIRMADA', '¡Reserva confirmada!', 'Tu horario está asegurado. Nos vemos en la cancha.')
            : ('PAGO EN REVISIÓN', 'Comprobante enviado', 'El dueño revisará tu comprobante. Te avisaremos cuando la reserva quede confirmada.');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: ResultBadge(ok: !cancelled)),
            const SizedBox(height: 28),
            Text(kicker, textAlign: TextAlign.center, style: authText(12, weight: 700, color: AuthColors.kicker, spacing: 0.13)),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: authText(30, weight: 800, spacing: -0.045)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: authText(14, weight: 500, color: const Color(0xFF68776E), height: 1.5)),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AuthColors.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.courtName, style: authText(14, weight: 800)),
                const SizedBox(height: 4),
                Text(rangeLabel(b.startAt, b.hours), style: authText(12, weight: 600, color: const Color(0xFF78877E))),
                if (!cancelled) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0x14143E2A)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: Text(confirmed ? 'Anticipo pagado' : 'Anticipo enviado',
                          style: authText(12, weight: 600, color: const Color(0xFF78877E))),
                    ),
                    Text(cop(b.amountDue), style: authText(18, weight: 800)),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Ver mis reservas', onPressed: onDone),
          ]),
        ),
      ),
    );
  }
}
