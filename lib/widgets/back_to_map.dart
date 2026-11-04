import 'dart:async';

import 'package:flutter/material.dart';

import '../data/geo_object.dart';
import '../lng.dart';

/// Écran nommé d'un support : ses visuels (route `support:<id>`, [tab] 'support'), l'un de ses onglets ou la grille
/// d'une face (`onglet:<id>:<onglet>`) ; [object] : le support à l'ouverture de l'écran (arguments de la route) ;
/// [selection] : ce qui y est choisi (alvéole, parcours, portée), noté par l'écran ([ScreenStack.note]).
typedef SupportScreen = ({String id, String tab, GeoObject? object, String? selection});

/// Pile des écrans du navigateur principal (déclarée dans `MaterialApp.navigatorObservers`). Un seul support y est
/// ouvert à la fois, au-dessus de la carte : ses visuels, un onglet, les écrans propres de l'onglet ([shown]) ; suivre
/// un parcours le remplace par le support d'en face, sans rien empiler. Les supports quittés sont retenus, avec
/// l'écran où on les a laissés ([visits], menu ⋮). Ses écoutants (la carte) sont prévenus de chaque changement, une
/// fois un remplacement terminé ([hold]).
class ScreenStack extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _stack = [];
  Completer<void>? _removal;

  /// Onglet, sélection et objet à jour notés par les écrans ([note]).
  final Map<Route<dynamic>, ({String tab, String? selection, GeoObject? object})> _notes = {};

  /// Remplacements en cours ([hold]).
  int _holds = 0;
  SupportScreen? _shown;
  final List<SupportScreen> _visits = [];

  /// Supports quittés retenus.
  static const maxVisits = 8;

  List<Route<dynamic>> get stack => List.unmodifiable(_stack);

  /// Support affiché : son écran nommé le plus haut ; null : aucun (carte, paramètres).
  SupportScreen? get shown => _shown;

  /// Supports quittés, du plus récent au plus ancien, un par support, avec l'écran où on les a laissés.
  List<SupportScreen> get visits => List.unmodifiable(_visits);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // premier écran d'un navigateur (application reconstruite, essais successifs) : nouvelle session
    if (previousRoute == null) {
      _stack.clear();
      _notes.clear();
      _visits.clear();
      _shown = null;
    }
    _stack
      // écrans d'un navigateur disparu
      ..removeWhere((r) => !r.isActive)
      ..add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) _stack[i] = newRoute;
    _notes.remove(oldRoute);
    _changed();
  }

  void _remove(Route<dynamic> route) {
    _stack.remove(route);
    _notes.remove(route);
    _removal?.complete();
    _removal = null;
    _changed();
  }

  /// Se termine au prochain écran ou dialogue fermé.
  Future<void> _nextRemoval() => (_removal ??= Completer<void>()).future;

  /// Regroupe les changements de la pile jusqu'à [release] (fermeture du support affiché puis ouverture d'un autre,
  /// onglet remplacé, retour à la carte) : les écoutants ne voient pas les états intermédiaires (la carte un instant
  /// au premier plan), et un support quitté est retenu avec l'écran où on l'a laissé, non avec le dernier fermé.
  void hold() => _holds++;

  void release() {
    _holds--;
    _changed();
  }

  /// L'écran [route] d'un support note son onglet ([SupportScreen.tab] : la face d'une grille), sa sélection et le
  /// support tel qu'il l'a enregistré ([object] : intitulé à jour), pour le rouvrir dans le même état s'il est quitté
  /// ([visits]).
  void note(Route<dynamic> route, {required String tab, String? selection, GeoObject? object}) {
    if (!_stack.contains(route)) return;
    _notes[route] = (tab: tab, selection: selection, object: object ?? _notes[route]?.object);
    if (_holds == 0) _shown = _top();
  }

  /// Oublie les supports quittés (nouveau paquet).
  void forgetVisits() {
    _visits.clear();
    notifyListeners();
  }

  /// Oublie le support [id] parmi les supports quittés (support supprimé).
  void forget(String id) {
    _visits.removeWhere((v) => v.id == id);
    notifyListeners();
  }

  void _changed() {
    if (_holds > 0) return;
    final shown = _top();
    final left = _shown;
    if (left != null && left.id != shown?.id) {
      _visits
        ..removeWhere((v) => v.id == left.id)
        ..insert(0, left);
      if (_visits.length > maxVisits) _visits.removeLast();
    }
    _shown = shown;
    notifyListeners();
  }

  /// Écran nommé d'un support le plus haut de la pile, avec ce qu'il a noté.
  SupportScreen? _top() {
    for (final r in _stack.reversed) {
      final s = supportScreenOf(r);
      if (s == null) continue;
      final n = _notes[r];
      return n == null ? s : (id: s.id, tab: n.tab, object: n.object ?? s.object, selection: n.selection);
    }
    return null;
  }
}

final screenStack = ScreenStack();

/// Support et onglet de la route [r] ('support' pour les visuels), null pour un autre écran (carte, paramètres,
/// galerie, dialogues).
SupportScreen? supportScreenOf(Route<dynamic> r) {
  final parts = r.settings.name?.split(':') ?? const <String>[];
  final object = r.settings.arguments is GeoObject ? r.settings.arguments as GeoObject : null;
  return switch (parts) {
    ['support', final id] => (id: id, tab: 'support', object: object, selection: null),
    ['onglet', final id, _, ...] => (id: id, tab: parts.skip(2).join(':'), object: object, selection: null),
    _ => null,
  };
}

/// Revient à la carte (premier écran) en fermant les écrans un par un, comme autant de retours arrière : un écran
/// dont la saisie n'est pas enregistrée pose sa question habituelle, et le retour s'arrête si l'utilisateur y reste
/// (résultat faux).
Future<bool> backToMap(BuildContext context) async {
  final nav = Navigator.of(context);
  // saisie enregistrée juste avant (menu ⋮) : l'écran, reconstruit, ne demande plus confirmation
  await WidgetsBinding.instance.endOfFrame;
  screenStack.hold();
  try {
    return await popTo(nav, 1);
  } finally {
    screenStack.release();
  }
}

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
