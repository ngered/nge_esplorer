import 'package:flutter/material.dart';

import '../theme.dart';

/// Titre de barre sur deux lignes (maquette Figma) : l'objet, puis l'écran ou son état.
class TitreEcran extends StatelessWidget {
  const TitreEcran(this.titre, this.sousTitre, {super.key});

  final String titre;
  final String sousTitre;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          sousTitre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Nge.texteSurFonce),
        ),
      ]);
}
