import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Support candidat à un toucher : centre du symbole à l'écran et, s'il est affiché, rectangle de son étiquette.
class Target<T> {
  const Target(this.object, this.center, {this.label, this.uncertain = false});

  final T object;
  final Offset center;
  final Rect? label;

  /// Position indéterminée (à relever) : cédée aux supports bien placés.
  final bool uncertain;
}

/// Supports visés par un toucher en [tap], du plus proche au plus éloigné : vide si aucun n'est à moins de
/// [tolerance] px, un seul s'il se détache des suivants d'au moins [gap] px, sinon les [max] plus proches, à
/// départager par l'utilisateur. Le toucher d'une étiquette vaut presque celui du symbole ; une position
/// indéterminée compte [penalty] px de plus.
List<T> targetsAt<T>(
  Offset tap,
  Iterable<Target<T>> targets, {
  double tolerance = 22,
  double gap = 8,
  double penalty = 12,
  int max = 8,
}) {
  final nearby = <(T, double)>[];
  for (final c in targets) {
    var d = (c.center - tap).distance;
    final e = c.label;
    if (e != null) d = math.min(d, _distance(e, tap) + 4);
    if (d > tolerance) continue;
    nearby.add((c.object, d + (c.uncertain ? penalty : 0)));
  }
  nearby.sort((a, b) => a.$2.compareTo(b.$2));
  if (nearby.length > 1 && nearby[1].$2 - nearby[0].$2 >= gap) return [nearby.first.$1];
  return [for (final p in nearby.take(max)) p.$1];
}

double _distance(Rect r, Offset p) {
  final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
  final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
  return math.sqrt(dx * dx + dy * dy);
}
