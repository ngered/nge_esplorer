import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Calculs locaux (plan tangent) : suffisants pour des portées de quelques centaines de mètres.
abstract final class Geo {
  static const _earthRadius = 6371008.8;

  /// Azimut de [a] vers [b] en grades, 0 = nord, sens horaire, dans [0, 400[.
  static double azimuthGrads(LatLng a, LatLng b) {
    final dx = (b.longitude - a.longitude) * math.cos(a.latitudeInRad);
    final dy = b.latitude - a.latitude;
    return normalize(math.atan2(dx, dy) * 200 / math.pi);
  }

  static double normalize(double grads) {
    final g = grads % 400;
    return g < 0 ? g + 400 : g;
  }

  /// Distance en mètres.
  static double distance(LatLng a, LatLng b) {
    final dx = (b.longitudeInRad - a.longitudeInRad) * math.cos((a.latitudeInRad + b.latitudeInRad) / 2);
    final dy = b.latitudeInRad - a.latitudeInRad;
    return math.sqrt(dx * dx + dy * dy) * _earthRadius;
  }

  /// Point à [meters] de [a] dans la direction [grads].
  static LatLng destination(LatLng a, double grads, double meters) {
    final r = grads * math.pi / 200;
    final dLat = meters * math.cos(r) / _earthRadius;
    final dLon = meters * math.sin(r) / (_earthRadius * math.cos(a.latitudeInRad));
    return LatLng(a.latitude + dLat * 180 / math.pi, a.longitude + dLon * 180 / math.pi);
  }
}
