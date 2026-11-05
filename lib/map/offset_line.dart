import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Ligne [points] décalée de [px] pixels à gauche de son sens de parcours (à droite si négatif) au zoom [zoom] :
/// câbles superposés d'un même linéaire dessinés en parallèle (couche Tirage, comme FibReady). Décalage calculé
/// dans la projection de la carte, à recalculer quand le zoom change ; aux sommets, onglet borné (angle aigu).
List<LatLng> offsetLine(List<LatLng> points, double px, double zoom, {Crs crs = const Epsg3857()}) {
  if (px == 0 || points.length < 2) return points;
  final p = [for (final q in points) crs.latLngToOffset(q, zoom)];
  Offset? normal(int i, int j) {
    final d = p[j] - p[i];
    final l = d.distance;
    return l == 0 ? null : Offset(d.dy / l, -d.dx / l);
  }

  return [
    for (var i = 0; i < p.length; i++)
      crs.offsetToLatLng(
        p[i] + _miter(i > 0 ? normal(i - 1, i) : null, i < p.length - 1 ? normal(i, i + 1) : null) * px,
        zoom,
      ),
  ];
}

/// Vecteur de décalage d'un sommet entre deux segments de normales [a] et [b] (null : extrémité ou segment nul).
Offset _miter(Offset? a, Offset? b) {
  if (a == null || b == null) return a ?? b ?? Offset.zero;
  final m = a + b;
  final l = m.distance;
  if (l < 1e-9) return a;
  final u = m / l;
  // longueur de l'onglet : 1 / cos(demi-angle), bornée à 2 pour un virage très aigu
  final cos = u.dx * a.dx + u.dy * a.dy;
  return u / math.max(cos, 0.5);
}
