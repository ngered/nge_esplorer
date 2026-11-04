import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'colors.dart';

/// Picto d'un support, repris de FibReady (jeu par défaut des paramètres : `Pictures/noe/svg`) : fond « papier », la
/// couleur du statut de renseignement dans un carré intérieur aux bords fins ; encre bleue pour un appui énergie.
/// Type sans picto : point.
class SupportSymbol extends StatelessWidget {
  const SupportSymbol({super.key, required this.family, this.fill, this.energy = false, this.size = 24});

  /// Famille du type (POT, CHB, FAC…).
  final String? family;

  /// Couleur du statut (null : papier, comme dans FibReady).
  final Color? fill;
  final bool energy;
  final double size;

  static const paper = Color(0xFFFEFFF8);

  static String? assetFile(String? family) => switch (family) {
        'POT' => 'NOE_POT',
        'CHB' => 'NOE_CHB',
        'FAC' => 'NOE_FAC',
        _ => null,
      };

  /// Carré du statut dans le corps du picto (unités du viewBox 16 × 16 des SVG FibReady).
  static Rect? square(String? family) => switch (family) {
        'POT' => const Rect.fromLTWH(4.5, 7, 7, 7),
        'CHB' => const Rect.fromLTWH(4, 4, 8, 8),
        'FAC' => const Rect.fromLTWH(3.5, 4.5, 7, 7),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final f = assetFile(family);
    final ink = energy ? energyColor : Colors.black;
    if (f == null) return SupportPoint(fill: fill ?? paper, ink: ink, size: size * 0.6);
    final svg = SvgPicture(
      SvgAssetLoader('assets/fibready/noe/$f.svg', colorMapper: _SymbolColors(paper, ink)),
      width: size,
      height: size,
    );
    final c = square(family);
    if (fill == null || c == null) return svg;
    final u = size / 16;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        svg,
        Positioned(
          left: c.left * u,
          top: c.top * u,
          child: StatusSquare(color: fill!, side: c.width * u, ink: ink),
        ),
      ]),
    );
  }
}

/// Couleur d'un statut de renseignement : carré aux bords fins (picto, étiquette).
class StatusSquare extends StatelessWidget {
  const StatusSquare({super.key, required this.color, required this.side, this.ink = Colors.black});

  final Color color;
  final double side;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
        width: side,
        height: side,
        decoration: BoxDecoration(color: color, border: Border.all(color: ink, width: 0.75)),
      );
}

/// Support aux petites échelles (FibReady : point au-delà du 1/10 000).
class SupportPoint extends StatelessWidget {
  const SupportPoint({super.key, required this.fill, required this.ink, this.size = 10});

  final Color fill;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: Border.all(color: ink, width: 1)),
      );
}

/// Papier → statut, noir → encre (clé du cache des SVG : égalité par valeur).
class _SymbolColors extends ColorMapper {
  const _SymbolColors(this.fill, this.ink);

  final Color fill;
  final Color ink;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) => switch (color.toARGB32()) {
        0xFFFEFFF8 => fill,
        0xFF000000 => ink,
        _ => color,
      };

  @override
  bool operator ==(Object other) => other is _SymbolColors && other.fill == fill && other.ink == ink;

  @override
  int get hashCode => Object.hash(fill, ink);
}
