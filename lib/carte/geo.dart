import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Calculs locaux (plan tangent) : suffisants pour des portées de quelques centaines de mètres.
abstract final class Geo {
  static const _rayonTerre = 6371008.8;

  /// Azimut de [a] vers [b] en grades, 0 = nord, sens horaire, dans [0, 400[.
  static double azimutGrades(LatLng a, LatLng b) {
    final dx = (b.longitude - a.longitude) * math.cos(a.latitudeInRad);
    final dy = b.latitude - a.latitude;
    return normaliser(math.atan2(dx, dy) * 200 / math.pi);
  }

  static double normaliser(double grades) {
    final g = grades % 400;
    return g < 0 ? g + 400 : g;
  }

  /// Distance en mètres.
  static double distance(LatLng a, LatLng b) {
    final dx = (b.longitudeInRad - a.longitudeInRad) * math.cos((a.latitudeInRad + b.latitudeInRad) / 2);
    final dy = b.latitudeInRad - a.latitudeInRad;
    return math.sqrt(dx * dx + dy * dy) * _rayonTerre;
  }

  /// Point à [metres] de [a] dans la direction [grades].
  static LatLng destination(LatLng a, double grades, double metres) {
    final r = grades * math.pi / 200;
    final dLat = metres * math.cos(r) / _rayonTerre;
    final dLon = metres * math.sin(r) / (_rayonTerre * math.cos(a.latitudeInRad));
    return LatLng(a.latitude + dLat * 180 / math.pi, a.longitude + dLon * 180 / math.pi);
  }
}
