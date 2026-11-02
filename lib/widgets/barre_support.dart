import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/objet.dart';
import '../modules/poteau/rosace_screen.dart';
import '../providers/app_provider.dart';
import '../screens/visuels_screen.dart';
import 'barre_basse.dart';
import 'retour_carte.dart';

/// Barre basse commune des écrans d'un support : module (Portées du poteau, Masques de la chambre à venir),
/// Connecteurs (liens optiques, à venir), Carte, Ajouter (un visuel libre, ou l'ajout propre à l'écran).
class BarreSupport extends StatelessWidget {
  const BarreSupport({super.key, required this.objet, this.avant, this.apres, this.dansModule = false, this.ajout});

  final Objet objet;

  /// Écran du module (rosace des portées) : son entrée est active.
  final bool dansModule;

  /// Dernière entrée propre à l'écran (Direction sur la rosace) ; par défaut, Ajouter un visuel libre.
  final EntreeBarre? ajout;

  /// Avant une action qui ouvre un écran ou écrit l'objet (enregistrer la saisie en cours) ; faux : rester.
  final Future<bool> Function()? avant;

  /// Après cette action (recharger l'objet).
  final VoidCallback? apres;

  Future<void> _action(BuildContext context, Future<void> Function() action) async {
    if (avant != null && !await avant!()) return;
    if (!context.mounted) return;
    await action();
    apres?.call();
  }

  @override
  Widget build(BuildContext context) {
    final famille = context.watch<AppProvider>().referentiels.codeFamille(objet.typeKey);
    return BarreBasse(entrees: [
      if (famille == 'POT')
        EntreeBarre(
          icone: Icons.explore_outlined,
          libelle: 'Portées',
          active: dansModule,
          onPressed: objet.point == null
              ? null
              : () => _action(
                  context, () => Navigator.push(context, MaterialPageRoute(builder: (_) => RosaceScreen(poteau: objet)))),
        )
      else if (famille == 'CHB')
        const EntreeBarre(icone: Icons.grid_on_outlined, libelle: 'Masques'),
      const EntreeBarre(icone: Icons.cable_outlined, libelle: 'Connecteurs'),
      EntreeBarre(icone: Icons.public, libelle: 'Carte', onPressed: () => revenirALaCarte(context)),
      ajout ??
          EntreeBarre(
            icone: Icons.add,
            libelle: 'Ajouter',
            onPressed: () => _action(context, () => ajouterVisuelLibre(context, objet)),
          ),
    ]);
  }
}
