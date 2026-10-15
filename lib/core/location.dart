import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// No hay permiso de ubicación, el GPS está apagado o no se pudo leer.
class LocationUnavailable implements Exception {
  const LocationUnavailable();
}

typedef Locate = Future<({double lat, double lng})> Function();

/// Lee la ubicación del teléfono (pide permiso si hace falta). Lanza [LocationUnavailable] si no se puede.
/// Es un provider para poder cambiarlo en las pruebas.
final locationProvider = Provider<Locate>((_) => () async {
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          throw const LocationUnavailable();
        }
        final pos = await Geolocator.getCurrentPosition();
        return (lat: pos.latitude, lng: pos.longitude);
      } on LocationUnavailable {
        rethrow;
      } catch (_) {
        throw const LocationUnavailable();
      }
    });
