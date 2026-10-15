import 'package:flutter/material.dart';

import '../widgets/auth_ui.dart';
import '../widgets/design.dart';

/// Hoja para confirmar una aprobación (pago de reserva o mensualidad). Devuelve true si acepta.
Future<bool> askApprove(BuildContext context, {required String title, required String message, String okLabel = 'Aprobar'}) async {
  final ok = await showAppSheet<bool>(
    context,
    builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeading(title, subtitle: message),
      SheetActions(primaryLabel: okLabel, onPrimary: () => Navigator.pop(sheet, true)),
    ]),
  );
  return ok == true;
}

/// Hoja para rechazar un comprobante con motivo opcional. Devuelve el motivo (puede ser vacío) o null si cancela.
Future<String?> askRejectReason(BuildContext context, {String title = 'Rechazar comprobante'}) async {
  final v = await showFormSheet(
    context,
    title: title,
    subtitle: 'El motivo se le muestra a quien envió el comprobante.',
    primaryLabel: 'Rechazar',
    danger: true,
    initial: [''],
    fields: [
      (c) => AuthField(label: 'Motivo', icon: Icons.edit_outlined, controller: c, hint: 'Ej. El valor no coincide'),
    ],
  );
  return v?[0];
}
