import 'package:google_sign_in/google_sign_in.dart';

import 'api/api_client.dart';
import 'config.dart';

/// Inicio de sesión con Google. Devuelve el ID token que valida el backend,
/// o null si la persona cerró la ventana.
///
/// Requisitos fuera del código (ver backend/README.md): un cliente OAuth tipo
/// Android en Google Cloud con el nombre de paquete y el SHA-1 de la app.
class GoogleAuth {
  const GoogleAuth._();
  static bool _ready = false;

  static Future<String?> idToken() async {
    final g = GoogleSignIn.instance;
    try {
      if (!_ready) {
        await g.initialize(serverClientId: AppConfig.googleServerClientId);
        _ready = true;
      }
      final account = await g.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw const ApiException('Google no entregó la identidad. Inténtalo de nuevo.');
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw ApiException('No se pudo iniciar sesión con Google (${e.code.name}).');
    }
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Si nunca se inició con Google no hay nada que cerrar.
    }
  }
}
