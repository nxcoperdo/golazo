import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dónde se guardan los tokens de sesión.
abstract class TokenStore {
  Future<String?> readAccess();
  Future<String?> readRefresh();
  Future<void> save(String access, String refresh);
  Future<void> clear();
}

/// Almacenamiento cifrado del sistema (Keystore en Android, Keychain en iOS).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _kAccess = 'golazo.access';
  static const _kRefresh = 'golazo.refresh';

  @override
  Future<String?> readAccess() => _s.read(key: _kAccess);
  @override
  Future<String?> readRefresh() => _s.read(key: _kRefresh);
  @override
  Future<void> save(String access, String refresh) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
  }
}

/// Solo en memoria: para pruebas.
class MemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<String?> readAccess() async => _access;
  @override
  Future<String?> readRefresh() async => _refresh;
  @override
  Future<void> save(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
