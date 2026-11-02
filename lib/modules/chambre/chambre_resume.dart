import 'package:flutter/material.dart';

import '../../data/objet.dart';
import '../../data/referentiels.dart';
import '../../widgets/champs.dart';

const niveauxChambre = ['Non relevée', 'Partielle', 'Complète'];

/// Résumé d'une chambre (espace `chb`) ; la saisie des masques en grille viendra ensuite.
class ChambreResume extends StatelessWidget {
  const ChambreResume({super.key, required this.noeud, required this.referentiels});

  final Objet noeud;
  final Referentiels referentiels;

  @override
  Widget build(BuildContext context) {
    final chb = noeud.espace('chb') ?? const {};
    final mat = referentiels.ligne('chambre', 'MAT_CHAMBRE', 'MAT_ID', chb['MAT_KEY']);
    final faces = [for (final f in (chb['faces'] as List?) ?? const []) (f as Map).cast<String, dynamic>()]
      ..sort((a, b) => '${a['FAC_CODE']}'.compareTo('${b['FAC_CODE']}'));
    final niveau = chb['CHB_NIVEAU'] as int? ?? 0;
    return Section(titre: 'Chambre', enfants: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(mat?['MAT_LIB'] as String? ?? 'Type non renseigné'),
        subtitle: Text('Niveau de renseignement : ${niveauxChambre[niveau.clamp(0, 2)]}'),
      ),
      for (final f in faces)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, child: Text('${f['FAC_CODE']}')),
          title: Text('${(f['positions'] as List?)?.length ?? 0} position(s)'),
          subtitle: f['FAC_NB_COL'] == null ? null : Text('Grille ${f['FAC_NB_COL']} × ${f['FAC_NB_LIG']}'),
        ),
      if (faces.isEmpty) const Text('Aucune face relevée.'),
      if (chb['CHB_COMMENT'] != null) Text('${chb['CHB_COMMENT']}'),
    ]);
  }
}
