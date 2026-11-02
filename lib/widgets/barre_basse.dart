import 'package:flutter/material.dart';

import '../theme.dart';

/// Barre basse des écrans (maquette Figma) : bande bleue, entrées icône et libellé, entrée de l'écran courant en
/// jaune. Ce sont des actions, pas des onglets : chaque entrée ouvre un écran ou un panneau.
class BarreBasse extends StatelessWidget {
  const BarreBasse({super.key, required this.entrees});

  final List<EntreeBarre> entrees;

  @override
  Widget build(BuildContext context) => Material(
        color: Nge.ardoise,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(children: [for (final e in entrees) Expanded(child: e)]),
          ),
        ),
      );
}

class EntreeBarre extends StatelessWidget {
  const EntreeBarre({
    super.key,
    required this.icone,
    required this.libelle,
    this.onPressed,
    this.active = false,
    this.badge,
  });

  final IconData icone;
  final String libelle;

  /// Absent : entrée grisée.
  final VoidCallback? onPressed;

  /// Écran courant.
  final bool active;

  /// Compteur affiché sur l'icône (rien si nul ou zéro).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final couleur = active ? Nge.ardoiseFoncee : (onPressed == null ? Nge.inactifSurFonce : Colors.white);
    final n = badge ?? 0;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: active,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Material(
          color: active ? Nge.jaune : Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: active ? null : onPressed,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Badge(
                isLabelVisible: n > 0,
                label: Text('$n'),
                backgroundColor: Nge.jaune,
                textColor: Nge.ardoiseFoncee,
                child: Icon(icone, size: 26, color: couleur),
              ),
              const SizedBox(height: 4),
              Text(
                libelle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: couleur),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
