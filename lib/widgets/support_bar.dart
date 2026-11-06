import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/geo_object.dart';
import '../lng.dart';
import '../modules/chambre/mask_editor.dart';
import '../modules/chambre/mask_overview_screen.dart';
import '../modules/chambre/mask_screen.dart';
import '../modules/infra/equipment.dart';
import '../modules/optique/equipment_screen.dart';
import '../modules/optique/splice_screen.dart';
import '../modules/poteau/rosette_editor.dart';
import '../modules/poteau/rosette_screen.dart';
import '../providers/app_provider.dart';
import '../screens/object_screen.dart';
import '../screens/visuals_screen.dart';
import 'bottom_bar.dart';
import 'messages.dart';
import 'back_to_map.dart';

/// Écrans d'un support et leur pile : les visuels (arrivée par « Ouvrir » de la carte, route `support:<id>`), puis
/// un onglet à la fois (saisie, portées ou masques, un équipement : route `onglet:<id>:<onglet>`), et ses écrans
/// propres (grille d'une face, galerie). Passer d'un onglet à l'autre remplace l'onglet au lieu de l'empiler : le
/// retour ramène aux visuels s'ils sont dessous, puis à la carte. Un seul support est ouvert à la fois : suivre un
/// parcours ([follow]) ou rouvrir un support quitté (menu ⋮, [SupportMenu]) remplace le support affiché ([openAt])
/// par son écran d'arrivée, directement au-dessus de la carte (comme les pastilles d'équipement de l'aperçu de la
/// carte).
String supportRoute(GeoObject o) => 'support:${o.id}';

String tabRoute(GeoObject o, String tab) => 'onglet:${o.id}:$tab';

/// Route des visuels de [o] ; l'objet en argument (intitulé des supports quittés, menu ⋮).
RouteSettings supportSettings(GeoObject o) => RouteSettings(name: supportRoute(o), arguments: o);

/// Route de l'onglet [tab] de [o] (`masques:<face>` : la grille d'une face).
RouteSettings tabSettings(GeoObject o, String tab) => RouteSettings(name: tabRoute(o, tab), arguments: o);

/// Écrans de [o] en haut de la pile (ses visuels, ses onglets et leurs écrans propres, sans nom) : rang de ses
/// visuels et de son premier onglet, -1 si absents.
(int, int) _top(GeoObject o) {
  final stack = screenStack.stack;
  var firstTab = -1;
  for (var i = stack.length - 1; i >= 0; i--) {
    final name = stack[i].settings.name;
    if (name == supportRoute(o)) return (i, firstTab);
    if (name == null) continue;
    if (!name.startsWith('onglet:${o.id}:')) break;
    firstTab = i;
  }
  return (-1, firstTab);
}

/// Ouvre l'onglet [tab] de [o] sur l'objet relu dans le dépôt : les écrans au-dessus des visuels du support sont
/// fermés comme par autant de retours arrière (une saisie non enregistrée pose sa question ; si l'on y reste,
/// l'onglet ne s'ouvre pas). Se termine à la fermeture de l'onglet.
Future<void> openTab(BuildContext context, GeoObject o, String tab, Widget Function(GeoObject o) builder) async {
  final nav = Navigator.of(context);
  final fresh = await context.read<AppProvider>().repo.object(o.id) ?? o;
  // saisie enregistrée juste avant (previous) : l'écran ne demande plus confirmation
  await WidgetsBinding.instance.endOfFrame;
  final (visuals, firstTab) = _top(o);
  final keep = firstTab >= 0 ? firstTab : (visuals >= 0 ? visuals + 1 : screenStack.stack.length);
  Future<void>? opened;
  screenStack.hold();
  try {
    if (await popTo(nav, keep)) {
      opened = nav.push(MaterialPageRoute(settings: tabSettings(fresh, tab), builder: (_) => builder(fresh)));
    }
  } finally {
    screenStack.release();
  }
  if (opened != null) await opened;
}

/// Revient aux visuels de [o] (« Visuels du support » du menu ⋮) : s'ils sont sous ses onglets, en fermant ceux-ci comme
/// autant de retours arrière ; sinon (support ouvert sur un onglet), à la place de ses onglets.
Future<void> openVisuals(BuildContext context, GeoObject o) async {
  final nav = Navigator.of(context);
  final fresh = await context.read<AppProvider>().repo.object(o.id) ?? o;
  // saisie enregistrée juste avant (previous) : l'écran ne demande plus confirmation
  await WidgetsBinding.instance.endOfFrame;
  final (visuals, firstTab) = _top(o);
  screenStack.hold();
  try {
    if (visuals >= 0) {
      await popTo(nav, visuals + 1);
    } else if (firstTab < 0 || await popTo(nav, firstTab)) {
      unawaited(nav.push(MaterialPageRoute(settings: supportSettings(fresh), builder: (_) => VisualsScreen(object: fresh))));
    }
  } finally {
    screenStack.release();
  }
}

/// Écran d'arrivée sur un support : l'onglet (son nom de route) et son écran ; écran null : les visuels.
typedef Arrival = (String tab, Widget? screen);

/// Ouvre [o], relu dans le dépôt, à la place du support affiché : celui-ci est fermé comme par autant de retours
/// arrière jusqu'à la carte (une saisie non enregistrée pose sa question ; si l'on y reste, rien ne change, et le
/// résultat est faux), puis l'écran d'[arrival] s'ouvre au-dessus de la carte. Un seul support est ainsi ouvert à la
/// fois, sans pile de supports dont les copies vieilliraient : le retour ramène à la carte (aux visuels d'abord s'ils
/// sont l'arrivée), le menu ⋮ rouvre les supports quittés.
Future<bool> openAt(BuildContext context, GeoObject o, Arrival Function(GeoObject fresh) arrival) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final fresh = await context.read<AppProvider>().repo.object(o.id) ?? o;
  // un support supprimé ne s'ouvre plus : une écriture l'aurait déclaré modifié au retour
  if (fresh.abandoned) {
    messenger.replaceSnackBar(SnackBar(content: Text(tr('{0} a été supprimé', [fresh.lib ?? tr('Le support')]))));
    return false;
  }
  // saisie enregistrée juste avant : l'écran ne demande plus confirmation
  await WidgetsBinding.instance.endOfFrame;
  screenStack.hold();
  try {
    if (!await popTo(nav, 1)) return false;
    final (tab, screen) = arrival(fresh);
    unawaited(nav.push(MaterialPageRoute(
      settings: screen == null ? supportSettings(fresh) : tabSettings(fresh, tab),
      builder: (_) => screen ?? VisualsScreen(object: fresh),
    )));
    return true;
  } finally {
    screenStack.release();
  }
}

/// Écran de l'onglet [tab] de [o] ('support' : null, ses visuels ; `equipement:<code>` : l'écran dédié d'un
/// équipement ; `liens:<code>` : ses liens fibres), [selection] choisie (alvéole d'une grille, parcours de l'aperçu des masques, portée ou autre parcours
/// de la rosace) : réouverture d'un support quitté.
Widget? tabScreen(GeoObject o, String tab, [String? selection]) {
  if (tab.startsWith('masques:')) {
    final face = tab.substring('masques:'.length);
    return MaskScreen(chamber: o, face: chamberFaces.contains(face) ? face : null, selection: selection);
  }
  if (tab.startsWith(EquipmentScreen.tabPrefix)) {
    return EquipmentScreen(node: o, equipment: tab.substring(EquipmentScreen.tabPrefix.length));
  }
  if (tab.startsWith(SpliceScreen.tabPrefix)) {
    return SpliceScreen(node: o, equipment: tab.substring(SpliceScreen.tabPrefix.length));
  }
  return switch (tab) {
    'saisie' => ObjectScreen(object: o, linear: selection),
    'portees' when o.point != null => RosetteScreen(pole: o, span: selection, linear: selection),
    'masques' => MaskOverviewScreen(chamber: o, linear: selection),
    _ => null,
  };
}

/// Suit le linéaire [linear] jusqu'au support [other], qui remplace le support affiché ([openAt]) : pour un poteau,
/// ses portées, la portée commune ouverte, ou depuis un écran des parcours ([route]) l'autre parcours sélectionné,
/// avec son carton « Naviguer vers » du retour ; pour une chambre, depuis une alvéole ([cd]), directement la grille
/// de la face où le parcours arrive, sur l'alvéole de la même conduite si elle y est placée (sinon sur son alvéole à
/// placer en miroir, mise en évidence), sinon son aperçu des masques, le parcours mis en évidence ; pour un autre support, depuis un écran des parcours, sa
/// saisie (liste des portées et parcours), le linéaire sélectionné avec son carton, sinon ses visuels. L'écran de
/// départ doit avoir enregistré sa saisie.
Future<void> follow(BuildContext context, GeoObject linear, GeoObject other, {String? cd, bool route = false}) async {
  final ref = context.read<AppProvider>().referenceData;
  await openAt(context, other, (o) {
    switch (ref.familyCode(o.typeKey)) {
      case 'POT' when o.point != null:
        return (
          'portees',
          RosetteScreen(
            pole: o,
            span: isSpan(linear) ? linear.id : null,
            linear: route && !isSpan(linear) ? linear.id : null,
          ),
        );
      case 'CHB' when cd != null:
        // conduite que la chambre d'en face n'a pas encore placée : la grille met en évidence son alvéole à placer en
        // miroir (MaskScreen.selection)
        final a = MaskEditor.arrival(o, linear, cd: cd);
        final face = a?.face ?? MaskEditor.firstFace(o);
        return ('masques:$face', MaskScreen(chamber: o, face: face, selection: cd));
      case 'CHB':
        return ('masques', MaskOverviewScreen(chamber: o, linear: linear.id));
      default:
        return route ? ('saisie', ObjectScreen(object: o, linear: linear.id)) : ('support', null);
    }
  });
}

/// Intitulé de l'écran [tab] d'un support (menu ⋮).
String tabLabel(String tab) {
  if (tab.startsWith('masques:')) {
    final face = tab.substring('masques:'.length);
    return chamberFaces.contains(face) ? tr('masque {0}', [face]) : tr('masques');
  }
  if (tab.startsWith(EquipmentScreen.tabPrefix)) return tr('équipement');
  if (tab.startsWith(SpliceScreen.tabPrefix)) return tr('optique');
  return switch (tab) {
    'saisie' => tr('saisie du support'),
    'portees' => tr('portées'),
    'masques' => tr('masques'),
    _ => tr('visuels'),
  };
}

/// Action propre à un écran dans son menu ⋮ ([SupportMenu]).
typedef MenuAction = ({IconData icon, String label, VoidCallback onSelected});

/// Supports quittés proposés par le menu ⋮.
const maxMenuVisits = 5;

/// Menu ⋮ des écrans d'un support, seul bouton de leur barre de titre (notes rep8 : il remplace les pictos) : actions
/// propres à l'écran ([actions]), les visuels du support ([visuals], sauf sur ces visuels eux-mêmes ; la saisie est
/// dans la barre basse, notes rep16), puis les supports quittés récemment, du plus récent au plus ancien (le premier :
/// « Revenir à … »), chacun rouvert à la place du support affiché sur l'écran où on l'a laissé (face, alvéole,
/// parcours ou portée choisis), et « Repérer sur la carte » (retour à la carte, qui vole jusqu'au support).
/// [previous] : avant de quitter l'écran (enregistrer la saisie en cours), faux pour y rester ; sinon, une saisie
/// non enregistrée pose sa question habituelle.
class SupportMenu extends StatelessWidget {
  const SupportMenu({
    super.key,
    required this.object,
    this.actions = const [],
    this.previous,
    this.visuals = true,
  });

  final GeoObject object;
  final List<MenuAction> actions;
  final Future<bool> Function()? previous;
  final bool visuals;

  Future<bool> _leave(BuildContext context) async =>
      (previous == null || await previous!()) && context.mounted;

  Future<void> _visuals(BuildContext context) async {
    if (await _leave(context) && context.mounted) await openVisuals(context, object);
  }

  Future<void> _reopen(BuildContext context, SupportScreen v) async {
    if (!await _leave(context) || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final o = await context.read<AppProvider>().repo.object(v.id);
    if (!context.mounted) return;
    if (o == null) {
      messenger.replaceSnackBar(SnackBar(content: Text(tr('Support absent du paquet'))));
      return;
    }
    await openAt(context, o, (o) => (v.tab, tabScreen(o, v.tab, v.selection)));
  }

  /// Retour à la carte, qui repère le support ; demande retirée si l'on reste sur un écran (saisie non enregistrée).
  Future<void> _locate(BuildContext context) async {
    if (!await _leave(context) || !context.mounted) return;
    final app = context.read<AppProvider>()..locate(object.id);
    if (!await backToMap(context)) app.cancelLocate();
  }

  static Widget _item(IconData icon, String title, [String? subtitle]) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
      );

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
        tooltip: tr('Plus d\'actions'),
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => action(),
        itemBuilder: (menuContext) {
          final visits = [
            for (final v in screenStack.visits)
              if (v.id != object.id && !(v.object?.abandoned ?? false)) v,
          ].take(maxMenuVisits).toList();
          return [
            for (final a in actions) PopupMenuItem(value: a.onSelected, child: _item(a.icon, a.label)),
            if (visuals)
              PopupMenuItem<VoidCallback>(
                value: () => _visuals(context),
                child: _item(Icons.photo_library_outlined, tr('Visuels du support')),
              ),
            if (actions.isNotEmpty || visuals) const PopupMenuDivider(),
            for (final (i, v) in visits.indexed)
              PopupMenuItem<VoidCallback>(
                value: () => _reopen(context, v),
                child: _item(
                  i == 0 ? Icons.undo : Icons.history,
                  i == 0 ? tr('Revenir à {0}', [v.object?.lib ?? tr('Sans étiquette')]) : v.object?.lib ?? tr('Sans étiquette'),
                  tabLabel(v.tab),
                ),
              ),
            if (visits.isNotEmpty) const PopupMenuDivider(),
            PopupMenuItem<VoidCallback>(
              value: () => _locate(context),
              enabled: object.point != null,
              child: _item(Icons.my_location, tr('Repérer sur la carte')),
            ),
          ];
        },
      );
}

/// Barre basse commune des écrans d'un support : module (Portées du poteau, aperçu des Masques de la chambre),
/// Saisie du support (notes rep16, à la place des Équipements, ouverts de l'aperçu de la carte et de la carte
/// Équipements de la saisie, [openEquipment]), Carte, Ajouter (un visuel libre, ou l'ajout propre à l'écran). Le
/// module et la saisie sont des onglets ([openTab]).
class SupportBar extends StatelessWidget {
  const SupportBar({
    super.key,
    required this.object,
    this.previous,
    this.next,
    this.inModule = false,
    this.addItem,
  });

  final GeoObject object;

  /// Écran du module (rosace des portées, masques, grille d'une face) : son entrée est active.
  final bool inModule;

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
    // sur la saisie elle-même : son entrée active et inactive
    final entry = context.findAncestorWidgetOfExactType<ObjectScreen>() != null ||
        ModalRoute.of(context)?.settings.name == tabRoute(object, 'saisie');
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
      // saisie du support à portée de pouce (notes rep16) ; les équipements s'ouvrent déjà de l'aperçu de la carte et
      // de la carte Équipements de la saisie
      BarItem(
        icon: Icons.edit_outlined,
        label: tr('Saisie'),
        active: entry,
        onPressed: entry ? null : _tab(context, 'saisie', (o) => ObjectScreen(object: o)),
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

/// Ouvre l'écran dédié d'un équipement de [o] (onglet `equipement:<code>`) : [equipment], sinon le seul équipement
/// présent, sinon celui choisi parmi eux ([chooseEquipment], l'équipement affiché [current] marqué) ; rien si le choix
/// est celui de l'écran affiché. Depuis la carte ([fromMap], aperçu du support), l'écran s'ouvre au-dessus d'elle,
/// comme les portées ; sinon il remplace l'onglet affiché.
Future<void> openEquipment(BuildContext context, GeoObject o,
    {String? equipment, String? current, bool fromMap = false}) async {
  var code = equipment;
  if (code == null) {
    final codes = [
      for (final e in SupportEquipment.presentOf(o))
        if (e['EQU_CODE_EXT'] case final String c) c,
    ];
    if (codes.isEmpty) return;
    code = codes.length == 1
        ? codes.single
        : await chooseEquipment(context, o, context.read<AppProvider>().referenceData, current: current);
    if (code == null || !context.mounted) return;
    if (code == current && ModalRoute.of(context)?.settings.name == tabRoute(o, EquipmentScreen.tab(code))) return;
  }
  final c = code;
  if (fromMap) {
    await Navigator.push(context,
        MaterialPageRoute(settings: tabSettings(o, EquipmentScreen.tab(c)), builder: (_) => EquipmentScreen(node: o, equipment: c)));
  } else {
    await openTab(context, o, EquipmentScreen.tab(c), (o) => EquipmentScreen(node: o, equipment: c));
  }
}
