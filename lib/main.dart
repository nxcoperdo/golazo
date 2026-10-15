import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPush();
  runApp(const ProviderScope(child: GolazoApp()));
}

class GolazoApp extends ConsumerStatefulWidget {
  const GolazoApp({super.key});

  @override
  ConsumerState<GolazoApp> createState() => _GolazoAppState();
}

class _GolazoAppState extends ConsumerState<GolazoApp> {
  StreamSubscription<Uri>? _links;
  ProviderSubscription<String?>? _pushSession;

  @override
  void initState() {
    super.initState();
    _listenLinks();
    // Con sesión iniciada se registra el dispositivo para recibir push.
    _pushSession = ref.listenManual<String?>(userIdProvider, (_, id) {
      if (id != null) ref.read(pushProvider).start();
    }, fireImmediately: true);
  }

  /// Enlaces de los correos: golazo://reset-password?token=… y golazo://verify-email?token=…
  Future<void> _listenLinks() async {
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) _open(initial);
    } catch (_) {
      // En plataformas sin soporte de enlaces profundos simplemente no hay enlace inicial.
    }
    _links = links.uriLinkStream.listen(_open, onError: (_) {});
  }

  void _open(Uri uri) {
    if (uri.scheme != 'golazo') return;
    final token = uri.queryParameters['token'];
    final target = switch (uri.host) {
      'reset-password' => '/reset',
      'verify-email' => '/verify',
      _ => null,
    };
    if (target == null) return;
    final path = token == null ? target : '$target?token=${Uri.encodeQueryComponent(token)}';
    ref.read(routerProvider).go(path);
  }

  @override
  void dispose() {
    _links?.cancel();
    _pushSession?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Golazo',
        scaffoldMessengerKey: rootMessengerKey,
        theme: buildTheme(),
        routerConfig: ref.watch(routerProvider),
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      );
}
