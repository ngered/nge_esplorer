import 'dart:ui';

import '../data/data_repository.dart';
import '../data/geo_object.dart';
import '../data/reference_data.dart';
import '../data/visuals.dart';
import 'poteau/rosette_editor.dart' show aerialSpanType, facadeRunType;

/// Statut de renseignement d'un support, sur le principe de FOA Explorer (NOE_STATUT) : couleur du picto et du cadre
/// de l'étiquette sur la carte. [level] : valeur de `POT_NIVEAU` / `CHB_NIVEAU` (0 non relevé, 1 partiel,
/// 2 complet) ; le défaut n'est qu'un affichage.
enum Completion {
  toFill('À renseigner', Color(0xFF00FFFF), 0), // tr
  partial('Partiel', Color(0xFFFF8C00), 1), // tr
  complete('Complet', Color(0xFF00FF7F), 2), // tr
  defect('Défaut', Color(0xFFFF0000), null); // tr

  const Completion(this.lib, this.color, this.level);
  final String lib;
  final Color color;
  final int? level;
}

/// Statut de renseignement de [o] (null : type sans règle de complétude, affiché sans couleur de statut).
/// Règles (champ `completude` des manifestes) :
/// - poteau : complet avec les visuels obligatoires, la référence du catalogue, toutes ses portées orientées et au
///   moins un contrôle ; défaut si le dernier contrôle dit le poteau inutilisable en l'état ;
/// - chambre : complète avec au moins une face relevée (positions) et les visuels obligatoires, dont la vue de
///   chaque face relevée ;
/// - sinon partiel dès qu'une photo, un contrôle, une portée orientée ou une face est saisi, à renseigner avant.
Future<Completion?> completionOf(GeoObject o, ReferenceData ref, DataRepository repo) async {
  if (o.objectClass != ObjectClass.noe) return null;
  final family = ref.familyCode(o.typeKey);
  if (family != 'POT' && family != 'CHB') return null;

  final faces = <String>{
    for (final f in (o.namespace('chb')?['faces'] as List?) ?? const [])
      if (((f as Map)['positions'] as List?)?.any((p) => (p as Map)['DATE_ABD'] == null) ?? false) '${f['FAC_CODE']}',
  };
  final visuals = Visual.of(o, ref);
  final photos = visuals.any((v) => o.photos(v).isNotEmpty);
  final missing = visuals.where((v) => (v.mandatory || (v.ifMasked && faces.contains(v.code))) && o.photos(v).isEmpty);

  final bool entered;
  final bool complete;
  if (family == 'POT') {
    final pot = o.namespace('pot') ?? const {};
    final checks = [for (final c in (pot['controles'] as List?) ?? const []) (c as Map).cast<String, dynamic>()]
      ..sort((a, b) => '${a['DATE_CTL']}'.compareTo('${b['DATE_CTL']}'));
    if (checks.isNotEmpty && checks.last['SEC_UTILISABLE'] == 0) return Completion.defect;
    final spans = [
      for (final l in await repo.linearsOf(o.id))
        if (l.typeKey == aerialSpanType || l.typeKey == facadeRunType) l,
    ];
    final oriented = spans.where((l) {
      final p = l.namespace('inf')?['portee'] as Map?;
      return p?[l.noe1 == o.id ? 'PRT_ANG1' : 'PRT_ANG2'] != null;
    }).length;
    entered = photos || checks.isNotEmpty || oriented > 0;
    complete = missing.isEmpty && pot['MAT_KEY'] != null && oriented == spans.length && checks.isNotEmpty;
  } else {
    entered = photos || faces.isNotEmpty;
    complete = missing.isEmpty && faces.isNotEmpty;
  }
  return complete ? Completion.complete : (entered ? Completion.partial : Completion.toFill);
}

/// Pose le niveau de renseignement du module (`POT_NIVEAU`, `CHB_NIVEAU`) avant l'enregistrement de [o], comme FOA
/// Explorer met à jour NOE_STATUT à l'enregistrement de la fiche.
Future<void> saveLevel(GeoObject o, ReferenceData ref, DataRepository repo) async {
  final r = await completionOf(o, ref, repo);
  if (r == null) return;
  final (space, col) = ref.familyCode(o.typeKey) == 'POT' ? ('pot', 'POT_NIVEAU') : ('chb', 'CHB_NIVEAU');
  // défaut : le poteau a été relevé, au moins en partie
  o.namespace(space, create: true)![col] = r.level ?? Completion.partial.level;
}
