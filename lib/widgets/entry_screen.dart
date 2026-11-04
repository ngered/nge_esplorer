import 'package:flutter/material.dart';

import '../lng.dart';

/// Conventions communes des écrans de saisie (fiche, rosace, paramètres) : bouton « Enregistrer » flottant en bas
/// à droite, visible seulement s'il y a quelque chose à enregistrer ; après l'enregistrement, on reste sur l'écran ;
/// le quitter avec une saisie non enregistrée (retour arrière ou retour à la carte) demande confirmation.

/// Écran de saisie : tant que [changed], le quitter demande confirmation ([message] : précision éventuelle).
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key, required this.changed, required this.child, this.message});

  final bool changed;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !changed,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await confirmLeave(context, message: message) && context.mounted) Navigator.pop(context);
        },
        child: child,
      );
}

Future<bool> confirmLeave(BuildContext context, {String? message}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Quitter sans enregistrer ?')),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Rester'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Quitter'))),
        ],
      ),
    ) ??
    false;

/// Bouton flottant « Enregistrer » (pour `Scaffold.floatingActionButton`), absent sans saisie à enregistrer.
Widget? saveButton({required bool visible, required VoidCallback onPressed}) => visible
    ? FloatingActionButton.extended(onPressed: onPressed, icon: const Icon(Icons.save), label: Text(tr('Enregistrer')))
    : null;

/// Marge à laisser sous le contenu défilant pour que le bouton flottant n'en masque pas la fin.
const fabMargin = 96.0;

void showSaved(BuildContext context, [String? text]) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text ?? tr('Enregistré'))));
