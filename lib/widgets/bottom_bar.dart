import 'package:flutter/material.dart';

import '../theme.dart';
import 'svg_icon.dart';

/// Barre basse des écrans (maquette Figma) : bande bleue, entrées icône et libellé, entrée de l'écran courant en
/// jaune. Ce sont des actions, pas des onglets : chaque entrée ouvre un écran ou un panneau.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.items});

  final List<BarItem> items;

  @override
  Widget build(BuildContext context) => Material(
        color: Nge.slate,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            // libellés agrandis avec la taille du texte, dans la limite de la barre (débordait à 200 %)
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: Row(children: [for (final e in items) Expanded(child: e)]),
            ),
          ),
        ),
      );
}

class BarItem extends StatelessWidget {
  const BarItem({
    super.key,
    this.icon,
    this.svg,
    required this.label,
    this.onPressed,
    this.active = false,
    this.badge,
  }) : assert((icon == null) != (svg == null), 'une icône Material ou un dessin SVG');

  final IconData? icon;

  /// Icône dessinée (assets/icons, voir [SvgIcon]) à la place d'une icône Material.
  final String? svg;
  final String label;

  /// Absent : entrée grisée.
  final VoidCallback? onPressed;

  /// Écran courant, ou écran qui en dépend (grille d'une face sous l'aperçu des masques) : mis en avant ; il reste
  /// actionnable si [onPressed] est donné.
  final bool active;

  /// Compteur affiché sur l'icône (rien si nul ou zéro).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? Nge.slateDark : (onPressed == null ? Nge.inactiveOnDark : Colors.white);
    final n = badge ?? 0;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: active,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Material(
          color: active ? Nge.yellow : Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Badge(
                isLabelVisible: n > 0,
                label: Text('$n'),
                // inversée sur l'entrée active, jaune elle aussi
                backgroundColor: active ? Nge.slateDark : Nge.yellow,
                textColor: active ? Nge.yellow : Nge.slateDark,
                child: icon != null ? Icon(icon, size: 26, color: color) : SvgIcon(svg!, size: 26, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
