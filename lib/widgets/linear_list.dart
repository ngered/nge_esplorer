import 'package:flutter/material.dart';

import '../data/data_repository.dart';
import '../data/geo_object.dart';
import '../data/reference_data.dart';
import '../lng.dart';
import '../theme.dart';
import 'fields.dart';
import 'support_bar.dart';
import 'support_link.dart';

/// Linéaires rattachés à un nœud et nœud à leur autre extrémité (par identifiant).
typedef Linears = ({List<GeoObject> linears, Map<String, GeoObject?> ends});

Future<Linears> loadLinears(DataRepository repo, GeoObject node) async {
  final linears = await repo.linearsOf(node.id);
  final ends = <String, GeoObject?>{};
  for (final l in linears) {
    final other = l.noe1 == node.id ? l.noe2 : l.noe1;
    if (other != null) ends[other] = await repo.object(other);
  }
  return (linears: linears, ends: ends);
}

/// Intitulé d'un linéaire vu de l'un de ses nœuds : type et support d'en face ([other] ; « ? » s'il manque au paquet).
String linearTitle(ReferenceData referenceData, GeoObject linear, GeoObject? other) => tr('{0} vers {1}',
    [referenceData.typeLabel(linear.typeKey), other == null ? '?' : other.lib ?? tr('Sans étiquette')]);

/// Détails d'un linéaire : longueur, conduites, câbles portés.
String linearDetails(GeoObject l) => [
      if (l.props['LIN_LNG'] != null) '${l.props['LIN_LNG']} m',
      if ((l.namespace('inf')?['conduites'] as List?)?.isNotEmpty ?? false)
        trn((l.namespace('inf')!['conduites'] as List).length, '{0} conduite', '{0} conduites'),
      if (l.namespace('inf')?['portee'] != null)
        trn(((l.namespace('inf')!['portee'] as Map)['cables'] as List?)?.length ?? 0, '{0} câble porté', '{0} câbles portés'),
    ].join(' · ');

/// Carton du parcours sélectionné, au-dessus de la barre basse (aperçu des masques, portées du poteau) : intitulé,
/// détails, et « Naviguer vers » le support d'en face ([onNavigate] ; absent du paquet ou supprimé : pas de
/// navigation).
class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.linear,
    required this.other,
    required this.referenceData,
    required this.onNavigate,
    required this.onClose,
  });

  final GeoObject linear;
  final GeoObject? other;
  final ReferenceData referenceData;
  final void Function(GeoObject linear, GeoObject other) onNavigate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final details = linearDetails(linear);
    final to = other;
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Nge.rule))),
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(linearTitle(referenceData, linear, to), style: t.titleSmall),
                if (details.isNotEmpty) Text(details, style: t.bodySmall),
              ]),
            ),
            IconButton(tooltip: tr('Fermer'), icon: const Icon(Icons.close), onPressed: onClose),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: to == null || to.abandoned
                ? Text(to == null ? tr('Support d\'en face absent du paquet') : tr('Support d\'en face supprimé'),
                    style: t.bodySmall)
                : FilledButton.icon(
                    onPressed: () => onNavigate(linear, to),
                    icon: const Icon(Icons.near_me_outlined),
                    // pictogramme du support d'en face, comme sur la carte
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      supportSymbolOf(to, referenceData),
                      const SizedBox(width: 8),
                      Flexible(child: Text(tr('Naviguer vers {0}', [to.lib ?? tr('Sans étiquette')]))),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Carte des linéaires d'un nœud (conduites de la chambre, autres parcours du poteau, portées et parcours des autres
/// supports) : pictogramme et extrémité, longueur, conduites, câbles portés ; toucher une ligne ou sa pastille jaune
/// de direction suit le linéaire jusqu'au support à l'autre extrémité ([onOpen], par défaut [follow] ; aperçu des
/// masques), ou le sélectionne ([onSelect]) : l'écran montre alors son carton « Naviguer vers » (rosace, autres
/// supports). [extra] : lignes ajoutées à la fin (conduites sans destination connue).
class LinearList extends StatelessWidget {
  const LinearList({
    super.key,
    required this.node,
    required this.data,
    required this.referenceData,
    required this.title,
    this.extra = const [],
    this.onOpen,
    this.onSelect,
    this.selected,
    this.note,
  });

  final GeoObject node;
  final Linears data;
  final ReferenceData referenceData;
  final String title;
  final List<Widget> extra;

  /// Suivi du linéaire jusqu'au support d'en face (rosace : portées enregistrées d'abord, relues ensuite).
  final void Function(GeoObject linear, GeoObject other)? onOpen;

  /// Sélection du linéaire touché, à la place du suivi (aperçu des masques : carton « Naviguer vers »).
  final void Function(GeoObject linear)? onSelect;

  /// Identifiant du linéaire sélectionné, mis en avant.
  final String? selected;

  /// Précision ajoutée entre parenthèses à l'intitulé d'un linéaire (aperçu des masques : masques où ses conduites
  /// sont placées, notes rep13) ; null : rien.
  final String? Function(GeoObject linear)? note;

  @override
  Widget build(BuildContext context) {
    if (data.linears.isEmpty && extra.isEmpty) return const SizedBox.shrink();
    return Section(title: title, children: [
      for (final l in data.linears)
        Builder(builder: (context) {
          final other = data.ends[l.noe1 == node.id ? l.noe2 : l.noe1];
          void open() => onOpen == null ? follow(context, l, other!) : onOpen!(l, other!);
          final select = onSelect;
          // support d'en face atteignable : présent dans le paquet et non supprimé
          final reachable = other != null && !other.abandoned;
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            selected: l.id == selected,
            selectedTileColor: Nge.slate.withValues(alpha: 0.08),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
            // pictogramme du support d'en face, comme sur la carte
            leading: other == null ? null : supportSymbolOf(other, referenceData),
            title: Text([linearTitle(referenceData, l, other), if (note?.call(l) case final n?) '($n)'].join(' ')),
            // suivi impossible (aperçu des masques) : la ligne dit pourquoi
            subtitle: Text([
              linearDetails(l),
              if (select == null && !reachable) other == null ? tr('support absent du paquet') : tr('support supprimé'),
            ].where((t) => t.isNotEmpty).join(' · ')),
            // pastille jaune de direction (notes rep11) : d'une touche au support d'en face, sans carton ; en
            // sélection, c'est le carton de l'écran qui y mène
            trailing: !reachable || select != null
                ? null
                : IconButton.filled(
                    tooltip: tr('Naviguer vers {0}', [other.lib ?? tr('Sans étiquette')]),
                    style: IconButton.styleFrom(backgroundColor: Nge.yellow, foregroundColor: Nge.slateDark),
                    icon: const Icon(Icons.near_me_outlined),
                    onPressed: open,
                  ),
            onTap: select != null ? () => select(l) : (reachable ? open : null),
          );
        }),
      ...extra,
    ]);
  }
}
