import 'dart:ui';

import '../data/data_repository.dart';
import '../data/objet.dart';
import '../data/referentiels.dart';
import '../data/visuels.dart';
import 'poteau/rosace_edition.dart' show typePorteeAerienne, typeParcoursFacade;

/// Statut de renseignement d'un support, sur le principe de FOA Explorer (NOE_STATUT) : couleur du picto et du cadre
/// de l'étiquette sur la carte. [niveau] : valeur de `POT_NIVEAU` / `CHB_NIVEAU` (0 non relevé, 1 partiel,
/// 2 complet) ; le défaut n'est qu'un affichage.
enum Renseignement {
  aRenseigner('À renseigner', Color(0xFF00FFFF), 0),
  partiel('Partiel', Color(0xFFFF8C00), 1),
  complet('Complet', Color(0xFF00FF7F), 2),
  defaut('Défaut', Color(0xFFFF0000), null);

  const Renseignement(this.lib, this.couleur, this.niveau);
  final String lib;
  final Color couleur;
  final int? niveau;
}

/// Statut de renseignement de [o] (null : type sans règle de complétude, affiché sans couleur de statut).
/// Règles (champ `completude` des manifestes) :
/// - poteau : complet avec les visuels obligatoires, la référence du catalogue, toutes ses portées orientées et au
///   moins un contrôle ; défaut si le dernier contrôle dit le poteau inutilisable en l'état ;
/// - chambre : complète avec au moins une face relevée (positions) et les visuels obligatoires, dont la vue de
///   chaque face relevée ;
/// - sinon partiel dès qu'une photo, un contrôle, une portée orientée ou une face est saisi, à renseigner avant.
Future<Renseignement?> renseignement(Objet o, Referentiels ref, DataRepository repo) async {
  if (o.classe != Classe.noe) return null;
  final famille = ref.codeFamille(o.typeKey);
  if (famille != 'POT' && famille != 'CHB') return null;

  final faces = <String>{
    for (final f in (o.espace('chb')?['faces'] as List?) ?? const [])
      if (((f as Map)['positions'] as List?)?.isNotEmpty ?? false) '${f['FAC_CODE']}',
  };
  final visuels = Visuel.de(o, ref);
  final photos = visuels.any((v) => o.photos(v).isNotEmpty);
  final manquants = visuels.where((v) => (v.obligatoire || (v.siMasque && faces.contains(v.code))) && o.photos(v).isEmpty);

  final bool saisi;
  final bool complet;
  if (famille == 'POT') {
    final pot = o.espace('pot') ?? const {};
    final controles = [for (final c in (pot['controles'] as List?) ?? const []) (c as Map).cast<String, dynamic>()]
      ..sort((a, b) => '${a['DATE_CTL']}'.compareTo('${b['DATE_CTL']}'));
    if (controles.isNotEmpty && controles.last['SEC_UTILISABLE'] == 0) return Renseignement.defaut;
    final portees = [
      for (final l in await repo.lineairesDe(o.id))
        if (l.typeKey == typePorteeAerienne || l.typeKey == typeParcoursFacade) l,
    ];
    final orientees = portees.where((l) {
      final p = l.espace('inf')?['portee'] as Map?;
      return p?[l.noe1 == o.id ? 'PRT_ANG1' : 'PRT_ANG2'] != null;
    }).length;
    saisi = photos || controles.isNotEmpty || orientees > 0;
    complet = manquants.isEmpty && pot['MAT_KEY'] != null && orientees == portees.length && controles.isNotEmpty;
  } else {
    saisi = photos || faces.isNotEmpty;
    complet = manquants.isEmpty && faces.isNotEmpty;
  }
  return complet ? Renseignement.complet : (saisi ? Renseignement.partiel : Renseignement.aRenseigner);
}

/// Pose le niveau de renseignement du module (`POT_NIVEAU`, `CHB_NIVEAU`) avant l'enregistrement de [o], comme FOA
/// Explorer met à jour NOE_STATUT à l'enregistrement de la fiche.
Future<void> poserNiveau(Objet o, Referentiels ref, DataRepository repo) async {
  final r = await renseignement(o, ref, repo);
  if (r == null) return;
  final (cle, col) = ref.codeFamille(o.typeKey) == 'POT' ? ('pot', 'POT_NIVEAU') : ('chb', 'CHB_NIVEAU');
  // défaut : le poteau a été relevé, au moins en partie
  o.espace(cle, creer: true)![col] = r.niveau ?? Renseignement.partiel.niveau;
}
