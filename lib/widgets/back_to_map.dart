import 'dart:async';

import 'package:flutter/material.dart';

import '../lng.dart';

/// Pile des écrans du navigateur principal (déclarée dans `MaterialApp.navigatorObservers`).
class ScreenStack extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];
  Completer<void>? _removal;

  List<Route<dynamic>> get stack => List.unmodifiable(_stack);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack
    // écrans d'un navigateur disparu (application reconstruite, essais successifs)
    ..removeWhere((r) => !r.isActive)
    ..add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) _stack[i] = newRoute;
  }

  void _remove(Route<dynamic> route) {
    _stack.remove(route);
    _removal?.complete();
    _removal = null;
  }

  /// Se termine au prochain écran ou dialogue fermé.
  Future<void> _nextRemoval() => (_removal ??= Completer<void>()).future;
}

final screenStack = ScreenStack();

/// Revient à la carte (premier écran) en fermant les écrans un par un, comme autant de retours arrière : un écran
/// dont la saisie n'est pas enregistrée pose sa question habituelle, et le retour s'arrête si l'utilisateur y reste.
Future<void> backToMap(BuildContext context) => popTo(Navigator.of(context), 1);

/// Ferme les écrans un par un, comme autant de retours arrière, jusqu'à n'en garder que [keep] ; faux si un écran
/// est resté ouvert (saisie non enregistrée, l'utilisateur a choisi de rester).
Future<bool> popTo(NavigatorState nav, int keep) async {
  while (screenStack._stack.length > keep) {
    final top = screenStack._stack.last;
    await nav.maybePop();
    // demande de confirmation ouverte par l'écran : attendre sa fermeture, puis que l'écran se ferme ou non
    while (screenStack._stack.contains(top) && screenStack._stack.last is PopupRoute) {
      await screenStack._nextRemoval();
      await Future<void>.delayed(Duration.zero);
    }
    if (screenStack._stack.contains(top)) return false;
  }
  return true;
}

/// Bouton « Revenir à la carte » des barres de titre, masqué sur la carte et quand elle est l'écran précédent (la
/// flèche de retour suffit alors).
class MapButton extends StatelessWidget {
  const MapButton({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final rank = route == null ? -1 : screenStack.stack.indexOf(route);
    if (rank == 0 || rank == 1) return const SizedBox.shrink();
    return IconButton(
      tooltip: tr('Revenir à la carte'),
      icon: const Icon(Icons.map_outlined),
      onPressed: () => backToMap(context),
    );
  }
}
