import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'couleurs.dart';

/// Picto d'un support, repris de FibReady (jeu par défaut des paramètres : `Pictures/noe/svg`) : le remplissage
/// « papier » prend la couleur du statut de renseignement, l'encre est bleue pour un appui énergie. Type sans picto :
/// point.
class PictoSupport extends StatelessWidget {
  const PictoSupport({super.key, required this.famille, this.fond, this.energie = false, this.taille = 24});

  /// Famille du type (POT, CHB, FAC…).
  final String? famille;

  /// Couleur du statut (null : papier, comme dans FibReady).
  final Color? fond;
  final bool energie;
  final double taille;

  static const papier = Color(0xFFFEFFF8);

  static String? fichier(String? famille) => switch (famille) {
        'POT' => 'NOE_POT',
        'CHB' => 'NOE_CHB',
        'FAC' => 'NOE_FAC',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final f = fichier(famille);
    final encre = energie ? couleurEnergie : Colors.black;
    if (f == null) return PointSupport(fond: fond ?? papier, encre: encre, taille: taille * 0.6);
    return SvgPicture(
      SvgAssetLoader('assets/fibready/noe/$f.svg', colorMapper: _Couleurs(fond ?? papier, encre)),
      width: taille,
      height: taille,
    );
  }
}

/// Support aux petites échelles (FibReady : point au-delà du 1/10 000).
class PointSupport extends StatelessWidget {
  const PointSupport({super.key, required this.fond, required this.encre, this.taille = 10});

  final Color fond;
  final Color encre;
  final double taille;

  @override
  Widget build(BuildContext context) => Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fond, border: Border.all(color: encre, width: 1)),
      );
}

/// Papier → statut, noir → encre (clé du cache des SVG : égalité par valeur).
class _Couleurs extends ColorMapper {
  const _Couleurs(this.fond, this.encre);

  final Color fond;
  final Color encre;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) => switch (color.toARGB32()) {
        0xFFFEFFF8 => fond,
        0xFF000000 => encre,
        _ => color,
      };

  @override
  bool operator ==(Object other) => other is _Couleurs && other.fond == fond && other.encre == encre;

  @override
  int get hashCode => Object.hash(fond, encre);
}
