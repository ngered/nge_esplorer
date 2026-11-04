import 'package:flutter/material.dart';

import '../data/data_repository.dart';
import '../data/geo_object.dart';
import '../data/reference_data.dart';
import '../lng.dart';
import '../screens/visuals_screen.dart';
import '../theme.dart';
import 'fields.dart';

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

/// Carte des linéaires d'un nœud (linéaires du poteau, conduites de la chambre) : type et extrémité, longueur,
/// conduites, câbles portés ; toucher une ligne ouvre le support à l'autre extrémité. [extra] : lignes ajoutées
/// à la fin (conduites sans destination connue).
class LinearList extends StatelessWidget {
  const LinearList({
    super.key,
    required this.node,
    required this.data,
    required this.referenceData,
    required this.title,
    this.extra = const [],
  });

  final GeoObject node;
  final Linears data;
  final ReferenceData referenceData;
  final String title;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    if (data.linears.isEmpty && extra.isEmpty) return const SizedBox.shrink();
    return Section(title: title, children: [
      for (final l in data.linears)
        Builder(builder: (context) {
          final other = data.ends[l.noe1 == node.id ? l.noe2 : l.noe1];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(tr('{0} vers {1}', [referenceData.typeLabel(l.typeKey), other?.lib ?? other?.id ?? '?'])),
            subtitle: Text([
              if (l.props['LIN_LNG'] != null) '${l.props['LIN_LNG']} m',
              if ((l.namespace('inf')?['conduites'] as List?)?.isNotEmpty ?? false)
                trn((l.namespace('inf')!['conduites'] as List).length, '{0} conduite', '{0} conduites'),
              if (l.namespace('inf')?['portee'] != null) trn(((l.namespace('inf')!['portee'] as Map)['cables'] as List?)?.length ?? 0, '{0} câble porté', '{0} câbles portés'),
            ].join(' · ')),
            // pas de chevron, confondu avec le dépliage des cartes : l'icône « ouvrir » mène au support d'en face
            trailing: other == null
                ? null
                : IconButton(
                    tooltip: tr('Ouvrir {0}', [other.lib ?? other.id]),
                    icon: const Icon(Icons.open_in_new, color: Nge.slate),
                    onPressed: () => openSupport(context, other),
                  ),
            onTap: other == null ? null : () => openSupport(context, other),
          );
        }),
      ...extra,
    ]);
  }
}
