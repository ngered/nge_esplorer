import 'package:flutter/material.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../theme.dart';

/// Fibre désignée par son câble (`CAB_CODE_EXT`) et son rang dans le câble (`FIB_NUM`) : positions et mesures.
typedef FibreRef = ({String cable, int num});

/// Contenu optique publié (espace `opt` des nœuds, classe `CAB` des câbles, docs/paquet.md), en lecture.
class Optical {
  /// Contenu optique de l'équipement [equipment] (`EQU_CODE_EXT`) du nœud [node] : `opt.equipements` ; null s'il
  /// n'en a pas.
  static Map<String, dynamic>? of(GeoObject node, String? equipment) {
    for (final e in _list(node.namespace('opt')?['equipements'])) {
      if (e['EQU_KEY'] == equipment) return e;
    }
    return null;
  }

  static List<Map<String, dynamic>> _list(Object? l) => [for (final x in (l as List?) ?? const []) (x as Map).cast()];

  /// Fonctions (`OTYP_CODE` : BPE, PBO, TIROIR…) des équipements optiques présents dans le nœud [node] : ceux dont
  /// l'équipement de `inf.equipements` n'est pas abandonné (marque des pictos de la carte : `OpticalMark`).
  static List<String> functions(GeoObject node, ReferenceData ref) {
    final abandoned = {
      for (final e in _list(node.namespace('inf')?['equipements']))
        if (e['DATE_ABD'] != null) e['EQU_CODE_EXT'],
    };
    return [
      for (final e in _list(node.namespace('opt')?['equipements']))
        if (!abandoned.contains(e['EQU_KEY'])) ?ref.equipmentTypeCode(e['OTYP_KEY'] as int?),
    ];
  }

  /// Équipements optiques de [node] contenus dans [equipment], à toute profondeur (`EQO_PARENT_KEY` : tiroirs d'une
  /// baie), du plus proche au plus profond.
  static List<String> descendants(GeoObject node, String equipment) {
    final all = _list(node.namespace('opt')?['equipements']);
    final res = <String>[];
    final queue = [equipment];
    while (queue.isNotEmpty) {
      final parent = queue.removeAt(0);
      for (final e in all) {
        final code = e['EQU_KEY'];
        if (e['EQO_PARENT_KEY'] == parent && code is String && code != equipment && !res.contains(code)) {
          res.add(code);
          queue.add(code);
        }
      }
    }
    return res;
  }

  static List<Map<String, dynamic>> cassettes(Map<String, dynamic>? e) => _list(e?['cassettes']);

  static List<Map<String, dynamic>> positions(Map<String, dynamic> cassette) => _list(cassette['positions']);

  static List<Map<String, dynamic>> measures(Map<String, dynamic>? e) => _list(e?['mesures']);

  static List<Map<String, dynamic>> fibres(GeoObject cable) => _list(cable.props['fibres']);

  /// Fibre [col] (`1`, `2` ou vide : `CAB1_KEY` / `FIB1_NUM`…, `CAB_KEY` / `FIB_NUM`) d'une position ou d'une mesure.
  static FibreRef? fibre(Map<String, dynamic> m, [String col = '']) {
    final cable = m['CAB${col}_KEY'], num = m['FIB${col}_NUM'];
    return cable is String && num is int ? (cable: cable, num: num) : null;
  }

  /// Câbles cités par les positions et les mesures de l'équipement [e].
  static Set<String> citedCables(Map<String, dynamic>? e) => {
    for (final c in cassettes(e))
      for (final p in positions(c)) ...[?fibre(p, '1')?.cable, ?fibre(p, '2')?.cable],
    for (final m in measures(e)) ?fibre(m)?.cable,
  };
}

/// Lien d'une fibre dans un équipement, nommé comme dans FibReady (légende `connecteurs.csv` des paramètres
/// FibReady : symbole `DLINK_SYMBOL`, gardé pour mémoire, libellé `DLINK_LIB`, seul affiché : [LinkChip]), plus le départ `o-` d'un connecteur de tiroir, que
/// FibReady écrit dans ses liens (`LIENS_CABFIB.CONNECTOR`) sans l'avoir dans sa légende. Distingue les attentes :
/// prise abonné, réserve, attente simple, fibre morte.
enum FibreLink {
  start('o-', 'Départ'), // tr
  subscriberWait('<A>', 'Attente abonné'), // tr
  subscriber('-#', 'Prise abonné'), // tr
  splice('-x-', 'Fusion'), // tr
  wait('-o', 'Attente'), // tr
  coil('-@', 'Lové'), // tr
  reserve('-R', 'Réserve'), // tr
  passageCoil('<@>', 'Passage lové'), // tr
  passageReserve('<R>', 'Passage réserve'), // tr
  passage('<P>', 'Passage'), // tr
  straightJoint('<x>', 'Joint droit'), // tr
  dead('-ø', 'Fibre morte'); // tr

  const FibreLink(this.symbol, this.lib);
  final String symbol;
  final String lib;

  /// Lien d'une position d'après sa fonction (`PFON_CODE` de DEF_POS_FONCTION) et son affectation (`POS_AFFECT`,
  /// commentaire de la position GraceTHD : ABONNE, RESERVE, MORTE, SURCAPA, PASSAGE, DEPART), calé sur les liens du
  /// FBT d'Evicom (732 `o-`, 700 `-x-`, 464 `-#` abonnés, 202 `-R` réserves, 66 `-o` attentes) : connecteur ou
  /// pigtail, départ ; épissure, fusion ; passage, passage lové (fibre non coupée, lovée dans le boîtier) ; attente
  /// d'un abonné, **attente abonné** (au PBO ; FibReady l'écrit « prise abonné », mais la prise, la PTO, est dans le
  /// logement : [ofPosition]) ; en réserve, réserve ; morte, fibre morte ; autre attente (surcapacité, sans
  /// affectation), attente. Null : fonction inconnue.
  static FibreLink? of(String? pfonCode, String? affect) => switch (pfonCode) {
    'CO' || 'PI' => start,
    'EP' => splice,
    'PA' => passageCoil,
    'AT' => switch (affect?.trim().toUpperCase()) {
      'ABONNE' => subscriberWait,
      'RESERVE' => reserve,
      'MORTE' => dead,
      _ => wait,
    },
    _ => null,
  };

  /// Lien de la position [p] (référentiel [ref]) d'un équipement de fonction [equipmentType] (`OTYP_CODE`) : **prise
  /// abonné** seulement quand la fibre s'achève à l'adresse de destination, dans la prise terminale optique (PTO,
  /// sans fibre sortante) ; sinon d'après la fonction et l'affectation ([of]).
  static FibreLink? ofPosition(Map<String, dynamic> p, ReferenceData ref, {String? equipmentType}) {
    if (equipmentType == 'PTO' && Optical.fibre(p, '1') != null && Optical.fibre(p, '2') == null) return subscriber;
    return of(ref.positionFunction(p['PFON_KEY'] as int?)?['PFON_CODE'] as String?, p['POS_AFFECT'] as String?);
  }
}

/// Mention du lien d'une position, seule à l'écran (notes equipements : ni symbole, ni légende, ni affectation
/// redite) : son libellé ([FibreLink.lib] : attente abonné, réserve, fibre morte, fusion, passage lové…) sur une
/// pastille à la couleur de sa nature (départ vert, fusion bleu pétrole, attentes ambre, passages et fibres mortes
/// gris), suivi de l'affectation de la position quand elle dit autre chose (surcapacité…) ; libellé de la fonction
/// (`PFON_LIB`) pour une fonction inconnue de la légende.
class LinkChip extends StatelessWidget {
  const LinkChip({super.key, required this.position, required this.ref, this.equipmentType});

  final Map<String, dynamic> position;
  final ReferenceData ref;

  /// Fonction de l'équipement de la position (`OTYP_CODE`) : une PTO distingue la prise abonné.
  final String? equipmentType;

  /// Affectations déjà dites par le libellé du lien (fonction comprise).
  static const _implied = {'ABONNE', 'RESERVE', 'MORTE', 'PASSAGE', 'DEPART'};

  static Color colorOf(FibreLink? l) => switch (l) {
    FibreLink.start => Nge.green,
    FibreLink.splice || FibreLink.straightJoint => Nge.petrolBlue,
    FibreLink.subscriber || FibreLink.subscriberWait || FibreLink.reserve || FibreLink.wait => Nge.amber,
    FibreLink.passage || FibreLink.passageCoil || FibreLink.passageReserve || FibreLink.coil => Nge.secondaryText,
    FibreLink.dead => Nge.secondaryText,
    null => Nge.navyBlue,
  };

  @override
  Widget build(BuildContext context) {
    final link = FibreLink.ofPosition(position, ref, equipmentType: equipmentType);
    final lib = link == null
        ? (ref.positionFunction(position['PFON_KEY'] as int?)?['PFON_LIB'] as String?)
        : tr(link.lib);
    final affect = (position['POS_AFFECT'] as String?)?.trim();
    final extra = affect == null || affect.isEmpty || _implied.contains(affect.toUpperCase()) ? null : affect;
    final color = colorOf(link);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (lib != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
            child: Text(
              lib,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        if (extra != null) Text(extra, style: const TextStyle(fontSize: 12, color: Nge.secondaryText)),
      ],
    );
  }
}

extension OpticalReferenceData on ReferenceData {
  Map<String, dynamic>? fibreColor(int? id) => row('optique', 'DEF_FO_COULEUR', 'COUL_ID', id);

  Map<String, dynamic>? positionFunction(int? id) => row('optique', 'DEF_POS_FONCTION', 'PFON_ID', id);

  String? equipmentType(int? id) => lib('optique', 'DEF_OPT_EQUIP_TYPE', 'OTYP_ID', 'OTYP_LIB', id);

  String? equipmentTypeCode(int? id) => lib('optique', 'DEF_OPT_EQUIP_TYPE', 'OTYP_ID', 'OTYP_CODE', id);

  String? cassetteType(int? id) => lib('optique', 'DEF_CASSETTE_TYPE', 'CTYP_ID', 'CTYP_LIB', id);

  String? cableFunction(int? id) => lib('optique', 'DEF_CAB_FONCTION', 'CFON_ID', 'CFON_LIB', id);

  String? progress(int? id) => lib('noyau', 'DEF_AVANCEMENT', 'AVCT_ID', 'AVCT_LIB', id);
}

/// Couleur `#RRGGBB` d'un référentiel.
Color? colorOf(Object? rgb) {
  final v = rgb is String && rgb.startsWith('#') ? int.tryParse(rgb.substring(1), radix: 16) : null;
  return v == null ? null : Color(0xFF000000 | v);
}

/// Nombre à la française (virgule), sans décimale inutile.
String decimal(num v, [int digits = 1]) {
  final s = v.toStringAsFixed(digits);
  return (s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s).replaceAll('.', ',');
}

/// Pastille de couleur d'un tube ou d'une fibre (code DEF_FO_COULEUR) ; au-delà de 12 tubes, la couleur revient
/// avec des bagues noires ([rings]), dessinées en anneau.
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, this.rings = 0, this.tooltip});

  final Color? color;
  final int rings;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? Colors.transparent,
        border: Border.all(
          color: rings > 0 ? Colors.black : Nge.border,
          width: rings > 0 ? 2.5 : (color == null ? 1 : 0.8),
        ),
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip, child: dot);
  }
}

/// Fibre d'un câble : couleurs du tube et de la fibre, étiquette du câble, tube et rang dans le tube (« T2 F3 »).
/// Câble absent du paquet ou fibre inconnue : son code et le rang de la fibre.
class FibreText extends StatelessWidget {
  const FibreText({super.key, required this.fibre, required this.cable, required this.referenceData});

  final FibreRef fibre;
  final GeoObject? cable;
  final ReferenceData referenceData;

  @override
  Widget build(BuildContext context) {
    final f = cable == null ? null : Optical.fibres(cable!).where((x) => x['FIB_NUM'] == fibre.num).firstOrNull;
    final tube = f?['FIB_TUBE'] as int?, inTube = f?['FIB_NUM_TUBE'] as int?;
    final tubeColor = referenceData.fibreColor(f?['TUBE_COUL_KEY'] as int?);
    final fibreColor = referenceData.fibreColor(f?['COUL_KEY'] as int?);
    final rings = tube == null ? 0 : (tube - 1) ~/ 12;
    final where = tube != null && inTube != null ? tr('T{0} F{1}', [tube, inTube]) : tr('F{0}', [fibre.num]);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (f != null) ...[
          ColorDot(
            color: colorOf(tubeColor?['COUL_RGB']),
            rings: rings,
            tooltip: tubeColor == null
                ? null
                : rings == 0
                ? tr('Tube {0} : {1}', [tube, tubeColor['COUL_LIB']])
                : trn(rings, 'Tube {1} : {2}, {0} bague noire', 'Tube {1} : {2}, {0} bagues noires', [
                    tube,
                    tubeColor['COUL_LIB'],
                  ]),
          ),
          ColorDot(
            color: colorOf(fibreColor?['COUL_RGB']),
            tooltip: fibreColor == null ? null : tr('Fibre {0} : {1}', [inTube ?? fibre.num, fibreColor['COUL_LIB']]),
          ),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: cable?.lib ?? fibre.cable),
                TextSpan(
                  text: '  $where',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (tube != null)
                  TextSpan(
                    text: '  (${fibre.num})',
                    style: const TextStyle(color: Nge.secondaryText),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
