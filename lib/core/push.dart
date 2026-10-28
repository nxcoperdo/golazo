import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../features/chat/chat_screen.dart';
import 'router.dart';

/// Permite mostrar un SnackBar desde fuera del árbol de pantallas (aviso con la app abierta).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// iOS solo usa push si se compila con `--dart-define=GOLAZO_PUSH_IOS=true` y trae
/// GoogleService-Info.plist; sin él, Firebase puede fallar al arrancar.
const _pushOnIos = bool.fromEnvironment('GOLAZO_PUSH_IOS');

bool get _platformSupportsPush =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        (defaultTargetPlatform == TargetPlatform.iOS && _pushOnIos));

bool _firebaseReady = false;

/// Inicializa Firebase (solo se usa FCM). Si falta google-services.json la app sigue sin push.
Future<void> initPush() async {
  if (!_platformSupportsPush) return;
  try {
    await Firebase.initializeApp();
    _firebaseReady = true;
  } catch (e) {
    debugPrint('Push desactivado (Firebase no configurado): $e');
  }
}

final pushProvider = Provider<PushService>((ref) => PushService(ref));

class PushService {
  PushService(this._ref);

  final Ref _ref;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  bool _listening = false;

  String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Se llama cuando hay sesión: pide permiso, registra el token en la API y escucha los avisos.
  Future<void> start() async {
    if (!_firebaseReady) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _register(token);
      _refreshSub ??= messaging.onTokenRefresh.listen(_register, onError: (_) {});

      if (!_listening) {
        _listening = true;
        _foregroundSub = FirebaseMessaging.onMessage.listen(_onForeground);
        _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_openFrom);
        final initial = await messaging.getInitialMessage();
        if (initial != null) _openFrom(initial);
      }
    } catch (e) {
      debugPrint('No se pudo activar el push: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _ref.read(apiProvider).registerDevice(_platform, token);
      _token = token;
    } catch (e) {
      debugPrint('No se pudo registrar el dispositivo: $e');
    }
  }

  /// Se llama ANTES de cerrar sesión (aún hay credenciales) para dejar de recibir avisos del usuario.
  Future<void> stop() async {
    final token = _token;
    _token = null;
    if (!_firebaseReady) return;
    try {
      if (token != null) await _ref.read(apiProvider).removeDevice(_platform, token);
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('No se pudo dar de baja el dispositivo: $e');
    }
  }

  void _onForeground(RemoteMessage m) {
    final chatId = _chatThread(m);
    if (chatId != null) {
      _ref.invalidate(chatThreadsProvider);
      // Si ya estás en ese chat, los mensajes llegan solos: no hace falta avisar.
      if (activeChatThreadId == chatId) return;
    } else {
      _ref.invalidate(notificationsProvider);
    }
    final title = m.notification?.title;
    if (title == null) return;
    rootMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(title),
        action: SnackBarAction(label: 'Ver', onPressed: () => _openFrom(m)),
      ));
  }

  /// Id del chat si el aviso es un mensaje nuevo (data.type == chat_message).
  String? _chatThread(RemoteMessage m) => m.data['type'] == 'chat_message' ? m.data['threadId'] as String? : null;

  /// Toque en un aviso: los mensajes de chat abren la conversación; el resto, la bandeja.
  void _openFrom(RemoteMessage m) {
    final chatId = _chatThread(m);
    if (chatId == null) return _openInbox();
    _ref.invalidate(chatThreadsProvider);
    _ref.read(routerProvider).push('/chat/$chatId');
  }

  void _openInbox() {
    _ref.invalidate(notificationsProvider);
    _ref.read(routerProvider).go('/notifications');
  }

  void dispose() {
    _refreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedSub?.cancel();
  }
}
