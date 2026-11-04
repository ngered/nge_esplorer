import 'package:flutter/material.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../widgets/fields.dart';

/// Fiche de la chambre (espace `chb` du nœud), comme « Chambre - édition des informations » de FOA Explorer, répartie
/// dans les cartes de la saisie du support : référence et implantation (Général), dimensions, commentaire.
/// L'aperçu des masques s'ouvre par la barre basse (mask_overview_screen.dart).

/// Référence du catalogue et implantation (carte Général).
class ChamberReference extends StatelessWidget {
  const ChamberReference({super.key, required this.node, required this.referenceData, required this.onChanged});

  final GeoObject node;
  final ReferenceData referenceData;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final chb = node.namespace('chb', create: true)!;
    final catalog = referenceData.table('chambre', 'MAT_CHAMBRE')
      ..sort((a, b) => '${a['MAT_LIB']}'.compareTo('${b['MAT_LIB']}'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      ChoiceField(
          m: chb, column: 'MAT_KEY', label: tr('Référence (catalogue)'), rows: catalog,
          colId: 'MAT_ID', colLabel: 'MAT_LIB', onChanged: onChanged),
      ChoiceField(
          m: chb, column: 'IMPS_KEY', label: tr('Implantation'), rows: referenceData.table('infra', 'DEF_SUPPORT_IMPLANT'),
          colId: 'IMPS_ID', colLabel: 'IMPS_LIB', onChanged: onChanged),
    ]);
  }
}

/// Dimensions : une ligne par dimension, la dimension relevée (saisie seulement si elle diffère) avec la référence
/// du catalogue (intérieur) en gris sous le champ.
class ChamberDimensions extends StatelessWidget {
  const ChamberDimensions({super.key, required this.node, required this.referenceData, required this.onChanged});

  final GeoObject node;
  final ReferenceData referenceData;
  final VoidCallback onChanged;

  /// Colonne relevée, colonne de référence au catalogue, libellé.
  static const dimensions = [
    ('CHB_LARG', 'CHB_LARG_INT', 'Largeur'), // tr
    ('CHB_LNG', 'CHB_LNG_INT', 'Longueur'), // tr
    ('CHB_HAUT', 'CHB_HAUT_INT', 'Hauteur'), // tr
  ];

  static String _m(Object? v) => (v as num).toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final chb = node.namespace('chb', create: true)!;
    final mat = referenceData.row('chambre', 'MAT_CHAMBRE', 'MAT_ID', chb['MAT_KEY']);
    return Section(title: tr('Dimensions'), expanded: true, spacing: 12, children: [
      Text(
        mat == null
            ? tr('Choisir la référence (Général) pour afficher les dimensions du catalogue.')
            : tr('Dimensions intérieures de la référence {0} ; ne saisir que celles qui diffèrent.', [mat['MAT_LIB']]),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (final (column, refColumn, label) in dimensions)
        NumberField(
          m: chb,
          column: column,
          label: tr(label),
          unit: 'm',
          helper: tr('référence : {0}',
              [((mat?[refColumn] as num?) ?? 0) > 0 ? '${_m(mat![refColumn])} m' : tr('non renseignée')]),
          onChanged: onChanged,
        ),
    ]);
  }
}

/// Commentaire propre à la chambre (`CHB_COMMENT`, repris de FOA Explorer) : proposé seulement si la chambre l'avait
/// à l'ouverture de la saisie ([opened]), le commentaire du support suffisant sinon.
Widget? chamberComment({required GeoObject opened, required GeoObject node, required VoidCallback onChanged}) =>
    opened.namespace('chb')?['CHB_COMMENT'] == null
        ? null
        : StringField(
            m: node.namespace('chb', create: true)!, column: 'CHB_COMMENT', label: tr('Commentaire chambre (FOA)'),
            rows: 2, onChanged: onChanged);
