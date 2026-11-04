import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/geo_object.dart';
import '../lng.dart';
import '../modules/chambre/mask_overview_screen.dart';
import '../modules/infra/equipment_screen.dart';
import '../modules/poteau/rosette_screen.dart';
import '../providers/app_provider.dart';
import '../screens/visuals_screen.dart';
import 'bottom_bar.dart';
import 'back_to_map.dart';

/// Écrans d'un support et leur pile : les visuels (arrivée, route `support:<id>`), puis un onglet à la fois
/// (saisie, portées ou masques, équipements : route `onglet:<id>:<onglet>`), et ses écrans propres (grille d'une
/// face, galerie). Passer d'un onglet à l'autre remplace l'onglet au lieu de l'empiler : le retour ramène aux
/// visuels, puis à la carte.
String supportRoute(GeoObject o) => 'support:${o.id}';

String tabRoute(GeoObject o, String tab) => 'onglet:${o.id}:$tab';

/// Ouvre l'onglet [tab] de [o] sur l'objet relu dans le dépôt : les écrans au-dessus des visuels du support sont
/// fermés comme par autant de retours arrière (une saisie non enregistrée pose sa question ; si l'on y reste,
/// l'onglet ne s'ouvre pas). Se termine à la fermeture de l'onglet.
Future<void> openTab(BuildContext context, GeoObject o, String tab, Widget Function(GeoObject o) builder) async {
  final nav = Navigator.of(context);
  final fresh = await context.read<AppProvider>().repo.object(o.id) ?? o;
  // saisie enregistrée juste avant (previous) : l'écran ne demande plus confirmation
  await WidgetsBinding.instance.endOfFrame;
  final stack = screenStack.stack;
  final firstTab = stack.indexWhere((r) => r.settings.name?.startsWith('onglet:${o.id}:') ?? false);
  final base = stack.lastIndexWhere((r) => r.settings.name == supportRoute(o));
  final keep = firstTab >= 0 ? firstTab : (base >= 0 ? base + 1 : stack.length);
  if (!await popTo(nav, keep)) return;
  await nav.push(MaterialPageRoute(settings: RouteSettings(name: tabRoute(o, tab)), builder: (_) => builder(fresh)));
}

/// Barre basse commune des écrans d'un support : module (Portées du poteau, aperçu des Masques de la chambre),
/// Équipements (liens fibres des boîtes d'épissure), Carte, Ajouter (un visuel libre, ou l'ajout propre à l'écran).
/// Le module et les équipements sont des onglets ([openTab]).
class SupportBar extends StatelessWidget {
  const SupportBar({
    super.key,
    required this.object,
    this.previous,
    this.next,
    this.inModule = false,
    this.inEquipment = false,
    this.addItem,
  });

  final GeoObject object;

  /// Écran du module (rosace des portées, masques, grille d'une face) : son entrée est active.
  final bool inModule;

  /// Écran des équipements : son entrée est active.
  final bool inEquipment;

  /// Dernière entrée propre à l'écran (Direction sur la rosace) ; par défaut, Ajouter un visuel libre.
  final BarItem? addItem;

  /// Avant une action qui ouvre un écran ou écrit l'objet (enregistrer la saisie en cours) ; faux : rester.
  final Future<bool> Function()? previous;

  /// Après cette action (recharger l'objet), si l'écran est encore ouvert.
  final VoidCallback? next;

  Future<void> _action(BuildContext context, Future<void> Function() action) async {
    if (previous != null && !await previous!()) return;
    if (!context.mounted) return;
    await action();
    if (context.mounted) next?.call();
  }

  /// Entrée d'onglet : inactive sur l'onglet lui-même (une grille de face ramène à l'aperçu des masques).
  VoidCallback? _tab(BuildContext context, String tab, Widget Function(GeoObject o) builder) =>
      ModalRoute.of(context)?.settings.name == tabRoute(object, tab)
          ? null
          : () => _action(context, () => openTab(context, object, tab, builder));

  @override
  Widget build(BuildContext context) {
    final family = context.watch<AppProvider>().referenceData.familyCode(object.typeKey);
    return BottomBar(items: [
      if (family == 'POT')
        BarItem(
          icon: Icons.explore_outlined,
          label: tr('Portées'),
          active: inModule,
          onPressed: object.point == null ? null : _tab(context, 'portees', (o) => RosetteScreen(pole: o)),
        )
      else if (family == 'CHB')
        BarItem(
          icon: Icons.grid_on_outlined,
          label: tr('Masques'),
          active: inModule,
          onPressed: _tab(context, 'masques', (o) => MaskOverviewScreen(chamber: o)),
        ),
      BarItem(
        icon: Icons.inventory_2_outlined,
        label: tr('Équipements'),
        active: inEquipment,
        badge: ((object.namespace('inf')?['equipements'] as List?) ?? const [])
            .where((e) => (e as Map)['DATE_ABD'] == null)
            .length,
        onPressed: _tab(context, 'equipements', (o) => EquipmentScreen(object: o)),
      ),
      BarItem(icon: Icons.public, label: tr('Carte'), onPressed: () => backToMap(context)),
      addItem ??
          BarItem(
            icon: Icons.add,
            label: tr('Ajouter'),
            onPressed: () => _action(context, () => addFreeVisual(context, object)),
          ),
    ]);
  }
}
