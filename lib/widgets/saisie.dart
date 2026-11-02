import 'package:flutter/material.dart';

/// Conventions communes des écrans de saisie (fiche, rosace, paramètres) : bouton « Enregistrer » flottant en bas
/// à droite, visible seulement s'il y a quelque chose à enregistrer ; après l'enregistrement, on reste sur l'écran ;
/// le quitter avec une saisie non enregistrée (retour arrière ou retour à la carte) demande confirmation.

/// Écran de saisie : tant que [modifie], le quitter demande confirmation ([message] : précision éventuelle).
class EcranSaisie extends StatelessWidget {
  const EcranSaisie({super.key, required this.modifie, required this.child, this.message});

  final bool modifie;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !modifie,
        onPopInvokedWithResult: (fait, _) async {
          if (fait) return;
          if (await confirmerQuitter(context, message: message) && context.mounted) Navigator.pop(context);
        },
        child: child,
      );
}

Future<bool> confirmerQuitter(BuildContext context, {String? message}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Quitter sans enregistrer ?'),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Rester')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitter')),
        ],
      ),
    ) ??
    false;

/// Bouton flottant « Enregistrer » (pour `Scaffold.floatingActionButton`), absent sans saisie à enregistrer.
Widget? boutonEnregistrer({required bool visible, required VoidCallback onPressed}) => visible
    ? FloatingActionButton.extended(onPressed: onPressed, icon: const Icon(Icons.save), label: const Text('Enregistrer'))
    : null;

/// Marge à laisser sous le contenu défilant pour que le bouton flottant n'en masque pas la fin.
const margeBoutonFlottant = 96.0;

void signalerEnregistre(BuildContext context, [String texte = 'Enregistré']) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
