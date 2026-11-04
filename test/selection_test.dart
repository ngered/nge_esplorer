import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/map/selection.dart';

void main() {
  test('toucher : le plus proche, rien hors tolérance, liste quand plusieurs se valent', () {
    const a = Target('A', Offset(100, 100));
    const b = Target('B', Offset(118, 100));
    expect(targetsAt(const Offset(102, 100), [a, b]), ['A']);
    expect(targetsAt(const Offset(160, 100), [a, b]), isEmpty);
    // à mi-chemin : à l'utilisateur de choisir, le plus proche en tête
    expect(targetsAt(const Offset(108, 100), [b, a]), ['A', 'B']);
  });

  test('toucher : étiquette visée, position indéterminée cédée au support bien placé', () {
    final label = Target('C', const Offset(100, 100), label: Rect.fromLTWH(70, 120, 60, 20));
    expect(targetsAt(const Offset(125, 135), [label]), ['C']);

    // « destination à localiser » posée à 1 m d'une chambre : la chambre l'emporte
    const chamber = Target('chambre', Offset(100, 100));
    const toLocate = Target('à localiser', Offset(103, 100), uncertain: true);
    expect(targetsAt(const Offset(103, 100), [toLocate, chamber]), ['chambre']);
  });
}
