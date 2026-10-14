import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/api/api_client.dart';
import 'package:golazo/core/api/token_store.dart';

/// Servidor simulado: responde según la ruta y el token que reciba.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.handler);

  final ResponseBody Function(RequestOptions o) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}

  int count(String path) => requests.where((r) => r.path == path).length;
}

ResponseBody jsonBody(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );

ApiClient clientFor(FakeServer s, MemoryTokenStore tokens, {void Function()? onExpired}) {
  final dio = Dio()..httpClientAdapter = s;
  return ApiClient(baseUrl: 'http://test/v1', tokens: tokens, dio: dio, onSessionExpired: onExpired);
}

void main() {
  test('envía el token de acceso en cada petición', () async {
    final tokens = MemoryTokenStore();
    await tokens.save('acc', 'ref');
    final s = FakeServer((_) => jsonBody(200, {'ok': true}));
    await clientFor(s, tokens).get('/courts');
    expect(s.requests.single.headers['Authorization'], 'Bearer acc');
  });

  test('sin sesión no envía Authorization', () async {
    final s = FakeServer((_) => jsonBody(200, []));
    await clientFor(s, MemoryTokenStore()).get('/cities');
    expect(s.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  group('renovación de sesión', () {
    ResponseBody server(RequestOptions o) {
      if (o.path == '/auth/refresh') {
        return jsonBody(200, {'accessToken': 'new', 'refreshToken': 'ref2', 'user': {}});
      }
      return o.headers['Authorization'] == 'Bearer new'
          ? jsonBody(200, {'ok': true})
          : jsonBody(401, {'code': 'BAD_TOKEN', 'message': 'Sesión inválida o expirada'});
    }

    test('un 401 renueva el token y repite la petición', () async {
      final tokens = MemoryTokenStore();
      await tokens.save('old', 'ref');
      final s = FakeServer(server);
      final r = await clientFor(s, tokens).get('/bookings/mine');
      expect(r, {'ok': true});
      expect(await tokens.readAccess(), 'new');
      expect(await tokens.readRefresh(), 'ref2'); // el refresh token rota
      expect(s.count('/bookings/mine'), 2);
      expect(s.count('/auth/refresh'), 1);
    });

    test('peticiones simultáneas con token vencido renuevan una sola vez', () async {
      final tokens = MemoryTokenStore();
      await tokens.save('old', 'ref');
      final s = FakeServer(server);
      final c = clientFor(s, tokens);
      final results = await Future.wait([c.get('/a'), c.get('/b'), c.get('/c')]);
      expect(results, everyElement({'ok': true}));
      expect(s.count('/auth/refresh'), 1, reason: 'el refresh token rota: dos renovaciones cerrarían la sesión');
    });

    test('si no se puede renovar se cierra la sesión', () async {
      final tokens = MemoryTokenStore();
      await tokens.save('old', 'ref');
      var expired = 0;
      final s = FakeServer((o) => jsonBody(401, {'code': 'BAD_REFRESH', 'message': 'Sesión expirada'}));
      await expectLater(
        clientFor(s, tokens, onExpired: () => expired++).get('/bookings/mine'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(expired, 1);
      expect(await tokens.readAccess(), isNull);
      expect(await tokens.readRefresh(), isNull);
    });

    test('sin conexión durante la renovación NO cierra la sesión', () async {
      final tokens = MemoryTokenStore();
      await tokens.save('old', 'ref');
      var expired = 0;
      final s = FakeServer((o) {
        if (o.path == '/auth/refresh') {
          throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
        }
        return jsonBody(401, {'code': 'BAD_TOKEN', 'message': 'x'});
      });
      await expectLater(
        clientFor(s, tokens, onExpired: () => expired++).get('/bookings/mine'),
        throwsA(isA<ApiException>()),
      );
      expect(expired, 0);
      expect(await tokens.readRefresh(), 'ref', reason: 'se podrá reintentar al volver la conexión');
    });

    test('un 401 de login (contraseña mala) no intenta renovar', () async {
      final tokens = MemoryTokenStore();
      await tokens.save('acc', 'ref');
      final s = FakeServer((_) => jsonBody(401, {'code': 'BAD_CREDENTIALS', 'message': 'Correo o contraseña incorrectos'}));
      await expectLater(
        clientFor(s, tokens).post('/auth/login', body: {'email': 'a@b.co', 'password': 'x'}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'BAD_CREDENTIALS')),
      );
      expect(s.count('/auth/refresh'), 0);
    });
  });

  group('errores', () {
    Future<ApiException> fail(ResponseBody Function(RequestOptions) h) async {
      final s = FakeServer(h);
      try {
        await clientFor(s, MemoryTokenStore()).post('/bookings', body: {});
      } on ApiException catch (e) {
        return e;
      }
      fail_('no lanzó');
      throw StateError('unreachable');
    }

    test('conserva el código y el mensaje del backend', () async {
      final e = await fail((_) => jsonBody(409, {'code': 'SLOT_TAKEN', 'message': 'Esa hora ya fue reservada'}));
      expect((e.code, e.message, e.status), ('SLOT_TAKEN', 'Esa hora ya fue reservada', 409));
    });

    test('errores de validación se unen en un solo texto', () async {
      final e = await fail((_) => jsonBody(400, {
            'message': ['El celular debe tener 10 dígitos', 'password muy corta'],
            'error': 'Bad Request',
            'statusCode': 400,
          }));
      expect(e.code, 'VALIDATION');
      expect(e.message, contains('celular'));
      expect(e.message, contains('password'));
    });

    test('límite de intentos (429) con mensaje amable', () async {
      final e = await fail((_) => jsonBody(429, {'statusCode': 429, 'message': 'ThrottlerException: Too Many Requests'}));
      expect(e.code, 'RATE_LIMITED');
      expect(e.message, isNot(contains('Throttler')));
    });

    test('archivo demasiado grande (413)', () async {
      final e = await fail((_) => jsonBody(413, {'message': 'File too large'}));
      expect(e.code, 'FILE_TOO_LARGE');
    });

    test('sin conexión', () async {
      final e = await fail((o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
      expect(e.isNetwork, isTrue);
      expect(e.message, contains('conexión'));
    });

    test('tiempo agotado', () async {
      final e = await fail((o) => throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout));
      expect(e.code, 'TIMEOUT');
      expect(e.isNetwork, isTrue);
    });
  });
}

Never fail_(String m) => throw TestFailure(m);
