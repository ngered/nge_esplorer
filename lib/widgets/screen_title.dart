import 'package:flutter/material.dart';

import '../theme.dart';

/// Titre de barre sur deux lignes (maquette Figma) : l'objet, puis l'écran ou son état.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, this.subtitle, {super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Nge.textOnDark),
        ),
      ]);
}
