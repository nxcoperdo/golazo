import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'token_store.dart';

/// Error de la API ya traducido a algo que se puede mostrar al usuario.
class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'ERROR', this.status});

  final String message;

  /// Código estable del backend (p. ej. SLOT_TAKEN, EMAIL_TAKEN) o uno local:
  /// NETWORK, RATE_LIMITED, TIMEOUT.
  final String code;
  final int? status;

  bool get isNetwork => code == 'NETWORK' || code == 'TIMEOUT';

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// Cliente HTTP del backend: agrega el token, renueva la sesión una sola vez
/// cuando expira y convierte los errores en [ApiException].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    this.onSessionExpired,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers = {'Accept': 'application/json'}
      ..validateStatus = (s) => s != null && s >= 200 && s < 300;
  }

  final Dio _dio;
  final TokenStore tokens;

  /// Se llama cuando ya no hay forma de renovar la sesión.
  final void Function()? onSessionExpired;

  Completer<bool>? _refreshing;

  // Rutas donde un 401 significa "credenciales mal", no "token vencido".
  static const _noRefresh = [
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/google',
    '/auth/forgot-password',
    '/auth/reset-password',
  ];

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);
  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);
  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);
  Future<dynamic> delete(String path, {Object? body}) =>
      _send('DELETE', path, body: body);

  /// Sube una imagen como multipart (el backend la valida por su contenido).
  Future<dynamic> upload(
    String path, {
    required String field,
    required Uint8List bytes,
    required String filename,
  }) {
    return _send('POST', path, formBuilder: () {
      return FormData.fromMap({
        field: MultipartFile.fromBytes(bytes, filename: filename),
      });
    });
  }

  /// Descarga bytes (comprobantes, que requieren sesión).
  Future<Uint8List> getBytes(String path) async {
    final data = await _send('GET', path, bytes: true);
    return data as Uint8List;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    FormData Function()? formBuilder,
    bool bytes = false,
    bool retried = false,
  }) async {
    try {
      final token = await tokens.readAccess();
      final res = await _dio.request<dynamic>(
        path,
        data: formBuilder != null ? formBuilder() : body,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: bytes ? ResponseType.bytes : ResponseType.json,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      return res.data;
    } on DioException catch (e) {
      final canRefresh = e.response?.statusCode == 401 &&
          !retried &&
          !_noRefresh.any(path.startsWith);
      if (canRefresh && await _refresh()) {
        return _send(method, path,
            query: query,
            body: body,
            formBuilder: formBuilder,
            bytes: bytes,
            retried: true);
      }
      throw _toException(e);
    }
  }

  /// Renueva el token. Si varias peticiones fallan a la vez, solo una renueva.
  Future<bool> _refresh() {
    final running = _refreshing;
    if (running != null) return running.future;
    final c = _refreshing = Completer<bool>();
    () async {
      try {
        final refresh = await tokens.readRefresh();
        if (refresh == null) throw StateError('sin refresh token');
        final res = await _dio.post<dynamic>(
          '/auth/refresh',
          data: {'refreshToken': refresh},
        );
        final m = res.data as Map<String, dynamic>;
        await tokens.save(m['accessToken'] as String, m['refreshToken'] as String);
        c.complete(true);
      } catch (e) {
        // Sin conexión no se cierra la sesión: se podrá reintentar.
        final offline = e is DioException &&
            (e.response == null || (e.response!.statusCode ?? 0) >= 500);
        if (!offline) {
          await tokens.clear();
          onSessionExpired?.call();
        }
        c.complete(false);
      } finally {
        _refreshing = null;
      }
    }();
    return c.future;
  }

  ApiException _toException(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) {
      final timeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      return ApiException(
        timeout
            ? 'El servidor tardó demasiado en responder'
            : 'No hay conexión con el servidor',
        code: timeout ? 'TIMEOUT' : 'NETWORK',
      );
    }
    if (status == 429) {
      return const ApiException(
          'Demasiados intentos. Espera un minuto e inténtalo de nuevo.',
          code: 'RATE_LIMITED',
          status: 429);
    }
    if (status == 413) {
      return const ApiException('El archivo es demasiado grande (máximo 5 MB)',
          code: 'FILE_TOO_LARGE', status: 413);
    }
    final data = e.response?.data;
    if (data is Map) {
      final code = data['code'];
      final msg = data['message'];
      if (msg is List) {
        // Errores de validación: lista de mensajes.
        return ApiException(msg.join('\n'), code: 'VALIDATION', status: status);
      }
      return ApiException(
        msg is String ? msg : 'Ocurrió un error ($status)',
        code: code is String ? code : 'ERROR',
        status: status,
      );
    }
    return ApiException('Ocurrió un error ($status)', status: status);
  }
}
