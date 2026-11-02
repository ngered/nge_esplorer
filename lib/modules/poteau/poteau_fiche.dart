import 'package:flutter/material.dart';

import '../../data/objet.dart';
import '../../data/paquet.dart';
import '../../data/referentiels.dart';
import '../../widgets/champs.dart';

/// Contrôles d'un poteau (FOA Explorer), par groupe.
const controlesPoteau = {
  'Résultats des tests': {
    'CTL_VISUEL': 'Contrôle visuel',
    'CTL_PERCUSSION': 'Percussion',
    'CTL_SECOUSSE': 'Secousses',
    'CTL_POINTE_CARREE': 'Pointe carrée',
    'CTL_TETE': 'Exploration tête de poteau',
  },
  'Environnement': {
    'ENV_SURPLOMB': 'Problématique surplomb',
    'ENV_ELAGAGE': 'Élagage nécessaire',
    'ENV_NACELLE': 'Accessibilité nacelle',
    'ENV_BITUME': 'Milieu bitume, macadam, pavé',
  },
  'Sécurité': {
    'SEC_VOISIN_ERDF': 'Respect voisinage ERDF',
    'SEC_FLAMBEMENT': 'Contrôle flambement',
    'SEC_VERTICALITE': 'Contrôle verticalité',
    'SEC_ETIQUETTE': 'Étiquette jaune ou orange',
    'SEC_UTILISABLE': 'Poteau utilisable en l\'état',
  },
};

/// Caractéristiques du poteau (espace `pot` du nœud).
class PoteauCaracteristiques extends StatelessWidget {
  const PoteauCaracteristiques({super.key, required this.noeud, required this.referentiels, required this.onChanged});

  final Objet noeud;
  final Referentiels referentiels;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pot = noeud.espace('pot', creer: true)!;
    final catalogue = referentiels.table('poteau', 'MAT_POTEAU');
    final mat = referentiels.matPoteau(pot['MAT_KEY'] as int?);
    String libMat(Map<String, dynamic> m) => [m['MAT_LIB'], m['MAT_DESC']].whereType<String>().join(' — ');
    return Section(titre: 'Poteau', enfants: [
      Autocomplete<Map<String, dynamic>>(
        initialValue: TextEditingValue(text: mat == null ? '' : libMat(mat)),
        displayStringForOption: libMat,
        optionsBuilder: (v) {
          final q = v.text.toLowerCase();
          if (q.isEmpty) return const [];
          return catalogue.where((m) => libMat(m).toLowerCase().contains(q)).take(50);
        },
        onSelected: (m) {
          pot['MAT_KEY'] = m['MAT_ID'];
          if (pot['POT_HAUTEUR'] == null && m['MAT_HAUT'] != null) pot['POT_HAUTEUR'] = m['MAT_HAUT'];
          onChanged();
        },
        fieldViewBuilder: (context, ctl, focus, _) => TextField(
          controller: ctl,
          focusNode: focus,
          decoration: const InputDecoration(labelText: 'Référence (catalogue)', hintText: 'BS7, BC6 ANC…'),
        ),
      ),
      ChampListe(
          m: pot, cle: 'NAT_KEY', libelle: 'Nature', lignes: referentiels.table('poteau', 'DEF_POT_NAT'),
          colId: 'NAT_ID', colLib: 'NAT_LIB', onChanged: onChanged),
      ChampListe(
          m: pot, cle: 'STRUCT_KEY', libelle: 'Structure', lignes: referentiels.table('poteau', 'DEF_POT_STRUCT'),
          colId: 'STRUCT_ID', colLib: 'STRUCT_LIB', onChanged: onChanged),
      ChampListe(
          m: pot, cle: 'CARAC_KEY', libelle: 'Caractéristique', lignes: referentiels.table('poteau', 'DEF_POT_CARAC'),
          colId: 'CARAC_ID', colLib: 'CARAC_LIB', onChanged: onChanged),
      ChampListe(
          m: pot, cle: 'IMPS_KEY', libelle: 'Implantation', lignes: referentiels.table('infra', 'DEF_SUPPORT_IMPLANT'),
          colId: 'IMPS_ID', colLib: 'IMPS_LIB', onChanged: onChanged),
      Row(children: [
        Expanded(child: ChampNombre(m: pot, cle: 'POT_HAUTEUR', libelle: 'Hauteur (m)', onChanged: onChanged)),
        const SizedBox(width: 12),
        Expanded(child: ChampNombre(m: pot, cle: 'POT_EFFORT', libelle: 'Effort (daN)', onChanged: onChanged)),
      ]),
      ChampTexte(m: pot, cle: 'POT_COMMENT', libelle: 'Commentaire poteau', lignes: 2, onChanged: onChanged),
    ]);
  }
}

/// Contrôle du jour : repris s'il existe, créé à la première réponse sinon.
class PoteauControles extends StatelessWidget {
  const PoteauControles({super.key, required this.noeud, required this.onChanged});

  final Objet noeud;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pot = noeud.espace('pot', creer: true)!;
    final jour = Paquet.horodatage().substring(0, 10);
    final liste = (pot['controles'] as List?) ?? [];
    final existant = liste.cast<Map>().where((c) => '${c['DATE_CTL']}'.startsWith(jour)).firstOrNull;
    final ctl = existant?.cast<String, dynamic>() ?? <String, dynamic>{'DATE_CTL': jour};
    void changer() {
      // un contrôle existant est modifié en place (vue sur la carte d'origine)
      if (existant == null && !liste.contains(ctl)) pot['controles'] = [...liste, ctl];
      onChanged();
    }

    final precedents = liste.length - (existant == null ? 0 : 1);
    return Section(
      titre: 'Contrôles du $jour',
      enfants: [
        if (precedents > 0)
          Text('$precedents contrôle${precedents > 1 ? 's' : ''} antérieur${precedents > 1 ? 's' : ''} conservé${precedents > 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.bodySmall),
        for (final groupe in controlesPoteau.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(groupe.key, style: Theme.of(context).textTheme.labelLarge),
          ),
          for (final c in groupe.value.entries) ChampOuiNon(m: ctl, cle: c.key, libelle: c.value, onChanged: changer),
        ],
        ChampTexte(m: ctl, cle: 'CTL_COMMENT', libelle: 'Commentaire', lignes: 2, onChanged: changer),
      ],
    );
  }
}
