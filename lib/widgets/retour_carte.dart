import 'dart:async';

import 'package:flutter/material.dart';

/// Pile des écrans du navigateur principal (déclarée dans `MaterialApp.navigatorObservers`).
class PileEcrans extends NavigatorObserver {
  final List<Route<dynamic>> _pile = [];
  Completer<void>? _retrait;

  List<Route<dynamic>> get pile => List.unmodifiable(_pile);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _pile.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _retirer(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _retirer(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pile.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) _pile[i] = newRoute;
  }

  void _retirer(Route<dynamic> route) {
    _pile.remove(route);
    _retrait?.complete();
    _retrait = null;
  }

  /// Se termine au prochain écran ou dialogue fermé.
  Future<void> _prochainRetrait() => (_retrait ??= Completer<void>()).future;
}

final pileEcrans = PileEcrans();

/// Revient à la carte (premier écran) en fermant les écrans un par un, comme autant de retours arrière : un écran
/// dont la saisie n'est pas enregistrée pose sa question habituelle, et le retour s'arrête si l'utilisateur y reste.
Future<void> revenirALaCarte(BuildContext context) async {
  final nav = Navigator.of(context);
  while (pileEcrans._pile.length > 1) {
    final haut = pileEcrans._pile.last;
    await nav.maybePop();
    // demande de confirmation ouverte par l'écran : attendre sa fermeture, puis que l'écran se ferme ou non
    while (pileEcrans._pile.contains(haut) && pileEcrans._pile.last is PopupRoute) {
      await pileEcrans._prochainRetrait();
      await Future<void>.delayed(Duration.zero);
    }
    if (pileEcrans._pile.contains(haut)) return;
  }
}

/// Bouton « Revenir à la carte » des barres de titre, masqué sur la carte et quand elle est l'écran précédent (la
/// flèche de retour suffit alors).
class BoutonCarte extends StatelessWidget {
  const BoutonCarte({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final rang = route == null ? -1 : pileEcrans.pile.indexOf(route);
    if (rang == 0 || rang == 1) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Revenir à la carte',
      icon: const Icon(Icons.map_outlined),
      onPressed: () => revenirALaCarte(context),
    );
  }
}
