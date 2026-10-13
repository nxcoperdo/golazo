import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: GolazoApp()));

class GolazoApp extends StatelessWidget {
  const GolazoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Golazo',
        theme: buildTheme(),
        routerConfig: appRouter,
      );
}
