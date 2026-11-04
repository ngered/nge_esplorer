import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icône dessinée (assets/icons : trait sur une grille de 24) affichée comme une icône Material : taille et couleur
/// du thème d'icône ambiant (barre basse, ListTile…), sauf précision.
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.asset, {super.key, this.size, this.color, this.semanticLabel});

  final String asset;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  /// Équipements d'un support : boîtier sur câble (boîte d'épissure, PBO, manchon ; boîte de jonction, coffret).
  static const equipment = 'assets/icons/equipment.svg';

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SvgPicture.asset(
      asset,
      width: s,
      height: s,
      semanticsLabel: semanticLabel,
      colorFilter: ColorFilter.mode(color ?? theme.color ?? Colors.black, BlendMode.srcIn),
    );
  }
}
