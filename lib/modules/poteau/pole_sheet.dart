import 'package:flutter/material.dart';

import '../../data/geo_object.dart';
import '../../data/bundle.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../widgets/fields.dart';

/// Fiche du poteau (espace `pot` du nœud), répartie dans les cartes de la saisie du support comme celle de la
/// chambre : caractéristiques (Général), contrôles. Les commentaires sont le journal commun des supports
/// (widgets/comments.dart), sans champ libre au contrôle ; les portées et les autres parcours sont dans l'onglet
/// Portées de la barre basse (rosette_screen.dart).

/// Contrôles d'un poteau (FOA Explorer), par groupe.
const poleChecks = {
  'Résultats des tests': { // tr
    'CTL_VISUEL': 'Contrôle visuel', // tr
    'CTL_PERCUSSION': 'Percussion', // tr
    'CTL_SECOUSSE': 'Secousses', // tr
    'CTL_POINTE_CARREE': 'Pointe carrée', // tr
    'CTL_TETE': 'Exploration tête de poteau', // tr
  },
  'Environnement': { // tr
    'ENV_SURPLOMB': 'Problématique surplomb', // tr
    'ENV_ELAGAGE': 'Élagage nécessaire', // tr
    'ENV_NACELLE': 'Accessibilité nacelle', // tr
    'ENV_BITUME': 'Milieu bitume, macadam, pavé', // tr
  },
  'Sécurité': { // tr
    'SEC_VOISIN_ERDF': 'Respect voisinage ERDF', // tr
    'SEC_FLAMBEMENT': 'Contrôle flambement', // tr
    'SEC_VERTICALITE': 'Contrôle verticalité', // tr
    'SEC_ETIQUETTE': 'Étiquette jaune ou orange', // tr
    'SEC_UTILISABLE': 'Poteau utilisable en l\'état', // tr
  },
};

/// Caractéristiques du poteau (carte Général) : référence du catalogue, nature, structure, caractéristique,
/// implantation, hauteur et effort.
class PoleSpecs extends StatelessWidget {
  const PoleSpecs({super.key, required this.node, required this.referenceData, required this.onChanged});

  final GeoObject node;
  final ReferenceData referenceData;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pot = node.namespace('pot', create: true)!;
    final catalog = referenceData.table('poteau', 'MAT_POTEAU');
    final mat = referenceData.poleMat(pot['MAT_KEY'] as int?);
    String matLabel(Map<String, dynamic> m) => [m['MAT_LIB'], m['MAT_DESC']].whereType<String>().join(' — ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Autocomplete<Map<String, dynamic>>(
        initialValue: TextEditingValue(text: mat == null ? '' : matLabel(mat)),
        displayStringForOption: matLabel,
        optionsBuilder: (v) {
          final q = v.text.toLowerCase();
          if (q.isEmpty) return const [];
          return catalog.where((m) => matLabel(m).toLowerCase().contains(q)).take(50);
        },
        onSelected: (m) {
          pot['MAT_KEY'] = m['MAT_ID'];
          if (pot['POT_HAUTEUR'] == null && m['MAT_HAUT'] != null) pot['POT_HAUTEUR'] = m['MAT_HAUT'];
          onChanged();
        },
        fieldViewBuilder: (context, ctl, focus, _) => TextField(
          controller: ctl,
          focusNode: focus,
          decoration: InputDecoration(labelText: tr('Référence (catalogue)'), hintText: 'BS7, BC6 ANC…'),
        ),
      ),
      ChoiceField(
          m: pot, column: 'NAT_KEY', label: tr('Nature'), rows: referenceData.table('poteau', 'DEF_POT_NAT'),
          colId: 'NAT_ID', colLabel: 'NAT_LIB', onChanged: onChanged),
      ChoiceField(
          m: pot, column: 'STRUCT_KEY', label: tr('Structure'), rows: referenceData.table('poteau', 'DEF_POT_STRUCT'),
          colId: 'STRUCT_ID', colLabel: 'STRUCT_LIB', onChanged: onChanged),
      ChoiceField(
          m: pot, column: 'CARAC_KEY', label: tr('Caractéristique'), rows: referenceData.table('poteau', 'DEF_POT_CARAC'),
          colId: 'CARAC_ID', colLabel: 'CARAC_LIB', onChanged: onChanged),
      ChoiceField(
          m: pot, column: 'IMPS_KEY', label: tr('Implantation'), rows: referenceData.table('infra', 'DEF_SUPPORT_IMPLANT'),
          colId: 'IMPS_ID', colLabel: 'IMPS_LIB', onChanged: onChanged),
      Row(children: [
        Expanded(child: NumberField(m: pot, column: 'POT_HAUTEUR', label: tr('Hauteur (m)'), onChanged: onChanged)),
        const SizedBox(width: 12),
        Expanded(child: NumberField(m: pot, column: 'POT_EFFORT', label: tr('Effort (daN)'), onChanged: onChanged)),
      ]),
    ]);
  }
}

/// Carte Contrôles : contrôle du jour, repris s'il existe, créé à la première réponse sinon.
class PoleChecks extends StatelessWidget {
  const PoleChecks({super.key, required this.node, required this.onChanged});

  final GeoObject node;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pot = node.namespace('pot', create: true)!;
    final day = Bundle.timestamp().substring(0, 10);
    final list = (pot['controles'] as List?) ?? [];
    final existing = list.cast<Map>().where((c) => '${c['DATE_CTL']}'.startsWith(day)).firstOrNull;
    final ctl = existing?.cast<String, dynamic>() ?? <String, dynamic>{'DATE_CTL': day};
    void change() {
      // un contrôle existant est modifié en place (vue sur la carte d'origine)
      if (existing == null && !list.contains(ctl)) pot['controles'] = [...list, ctl];
      onChanged();
    }

    final previousCount = list.length - (existing == null ? 0 : 1);
    final [y, m, d] = day.split('-');
    return Section(
      title: tr('Contrôles'),
      expanded: true,
      children: [
        Text(
          [
            tr('Contrôle du {0}', ['$d/$m/$y']),
            if (previousCount > 0)
              trn(previousCount, '{0} contrôle antérieur conservé', '{0} contrôles antérieurs conservés'),
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final group in poleChecks.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr(group.key), style: Theme.of(context).textTheme.labelLarge),
          ),
          for (final c in group.value.entries) YesNoField(m: ctl, column: c.key, label: tr(c.value), onChanged: change),
        ],
      ],
    );
  }
}
