import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/format.dart';
import '../../data/models.dart';

/// Cuentas a las que se transfiere, con botón para copiar el número.
class PaymentInfo extends StatelessWidget {
  const PaymentInfo({
    super.key,
    required this.methods,
    required this.amount,
    this.title = 'Transfiere',
  });

  final List<PaymentMethod> methods;
  final int amount;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (methods.isEmpty) {
      return const Text(
          'El dueño aún no configuró cuentas de pago. Contáctalo para coordinar.');
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title ${cop(amount)} a:',
            style: Theme.of(context).textTheme.titleSmall),
        for (final m in methods)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${m.label} · ${m.account}'),
            subtitle: Text(m.holder),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar número',
              onPressed: () {
                Clipboard.setData(ClipboardData(
                    text: m.account.replaceAll(RegExp(r'[^0-9-]'), '')));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Número copiado')));
              },
            ),
          ),
      ]),
    );
  }
}
