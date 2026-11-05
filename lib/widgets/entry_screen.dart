import 'package:flutter/material.dart';

import '../lng.dart';
import 'back_to_map.dart';
import 'messages.dart';

/// Conventions communes des écrans de saisie (fiche, rosace, paramètres) : bouton « Enregistrer » flottant en bas
/// à droite, visible seulement s'il y a quelque chose à enregistrer ; après l'enregistrement, on reste sur l'écran ;
/// le quitter avec une saisie non enregistrée (retour arrière ou retour à la carte) propose de l'enregistrer ou de
/// l'abandonner.

/// Écran de saisie : tant que [changed], le quitter demande s'il faut enregistrer ([onSave], puis l'écran se ferme)
/// ou abandonner les modifications ; le dialogue fermé autrement (toucher à côté, retour arrière), on reste sur
/// l'écran. [message] : précision éventuelle.
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key, required this.changed, required this.onSave, required this.child, this.message});

  final bool changed;
  final Future<void> Function() onSave;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !changed,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // suivi par la pile : un retour à la carte attend l'enregistrement et la fermeture de l'écran
          screenStack.leaving(() async {
            final choice = await confirmLeave(context, message: message);
            if (choice == null || !context.mounted) return;
            if (choice == LeaveChoice.save) await onSave();
            if (context.mounted) Navigator.pop(context);
          }());
        },
        child: child,
      );
}

/// Réponse à [confirmLeave].
enum LeaveChoice { save, discard }

/// Saisie non enregistrée : l'enregistrer ou l'abandonner ; null : rester sur l'écran.
Future<LeaveChoice?> confirmLeave(BuildContext context, {String? message}) => showDialog<LeaveChoice>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Enregistrer les modifications ?')),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, LeaveChoice.discard),
            child: Text(tr('Abandonner les modifications')),
          ),
          FilledButton(onPressed: () => Navigator.pop(c, LeaveChoice.save), child: Text(tr('Enregistrer'))),
        ],
      ),
    );

/// Bouton flottant « Enregistrer » (pour `Scaffold.floatingActionButton`), absent sans saisie à enregistrer.
Widget? saveButton({required bool visible, required VoidCallback onPressed}) => visible
    ? FloatingActionButton.extended(onPressed: onPressed, icon: const Icon(Icons.save), label: Text(tr('Enregistrer')))
    : null;

/// Marge à laisser sous le contenu défilant pour que le bouton flottant n'en masque pas la fin.
const fabMargin = 96.0;

/// Message d'enregistrement ; il remplace les messages affichés ou en attente (pas de file de confirmations périmées).
void showSaved(BuildContext context, [String? text]) => ScaffoldMessenger.of(context)
  .replaceSnackBar(SnackBar(content: Text(text ?? tr('Enregistré'))));
