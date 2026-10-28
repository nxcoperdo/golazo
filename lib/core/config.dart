import 'package:flutter/foundation.dart';

/// Configuración de la app. Se cambia al compilar con `--dart-define`:
///   flutter run --dart-define=API_URL=https://api.tudominio.com/v1
class AppConfig {
  const AppConfig._();

  static const _apiFromEnv = String.fromEnvironment('API_URL');

  /// El emulador de Android ve el computador en 10.0.2.2, no en localhost.
  static String get apiBase {
    if (_apiFromEnv.isNotEmpty) return _apiFromEnv;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000/v1';
    }
    return 'http://127.0.0.1:3000/v1';
  }

  /// Servidor sin el prefijo `/v1` (las fotos llegan como `/v1/files/...`).
  static String get origin => Uri.parse(apiBase).replace(path: '').toString();

  /// ID de cliente "Web" de Google: es la audiencia que valida el backend.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '529889456175-4ec4f0mrquppie69ta0oma3tjfk6spc4.apps.googleusercontent.com',
  );

  /// WhatsApp de soporte (con indicativo, solo dígitos). Cambiable con --dart-define=SUPPORT_WHATSAPP=57...
  static const supportWhatsapp = String.fromEnvironment('SUPPORT_WHATSAPP', defaultValue: '573219429385');

  /// Enlace de WhatsApp al soporte, con el mensaje ya escrito (abre la app de WhatsApp o el navegador).
  static Uri whatsappUri([String? message]) => Uri.parse(
        message == null || message.isEmpty
            ? 'https://wa.me/$supportWhatsapp'
            : 'https://wa.me/$supportWhatsapp?text=${Uri.encodeComponent(message)}',
      );

  /// Páginas públicas legales del servidor (sin /v1): terminos, privacidad, eliminar-cuenta, soporte.
  static String legalUrl(String page) => '$origin/legal/$page';

  /// Convierte una ruta del servidor (`/v1/files/...`) en URL completa.
  static String fileUrl(String path) =>
      path.startsWith('http') ? path : '$origin$path';
}
