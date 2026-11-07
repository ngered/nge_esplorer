import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../widgets/fields.dart';
import '../optique/optical.dart';

/// Immeuble et BAL d'une adresse (espace `imb`, docs/paquet.md) : habitat, logements, convention ; locaux, chacun
/// desservi par son PBO. En lecture : relevé BAL préparé au BE.
class Building {
  static List<Map<String, dynamic>> premises(GeoObject address) =>
      [for (final l in (address.namespace('imb')?['locaux'] as List?) ?? const []) (l as Map).cast()];
}

/// Usage d'une adresse, codes `NOE_USAGE` de FibReady, et son picto (paramètres Evicom, `param_arbo_noe_pictures.csv` :
/// `NOE_LRI` et ses variantes). Logement individuel ou collectif, professionnel, site FTTE (entreprise raccordée en
/// propre : local technique ou opérateur).
enum AddressUsage {
  indHab('IND-HAB', 'NOE_LRI', 'Logement individuel'), // tr
  colHab('COL-HAB', 'NOE_LRI_COLHAB', 'Logements collectifs'), // tr
  indPro('IND-PRO', 'NOE_LRI_INDPRO', 'Local professionnel'), // tr
  colPro('COL-PRO', 'NOE_LRI_COLPRO', 'Locaux professionnels collectifs'), // tr
  indFtte('IND-FTTE', 'NOE_LRI_INDFTTE', 'Site FTTE'), // tr
  colFtte('COL-FTTE', 'NOE_LRI_COLFTTE', 'Site FTTE collectif'); // tr

  const AddressUsage(this.code, this.picture, this.lib);
  final String code;

  /// Picto FibReady (`assets/fibready/noe/<picture>.svg`).
  final String picture;
  final String lib;

  /// Usage de l'adresse [a], déduit de l'espace `imb` : collectif pour un immeuble (`DEF_IMB_HABITAT` I ; sans
  /// habitat renseigné, plus d'un local) ; selon les types de ses locaux (`DEF_LOC_TYPE`) : un local résidentiel en
  /// fait un logement (mixte compris, comme FibReady), sinon un local professionnel un local pro, sinon un local
  /// technique ou opérateur un site FTTE ; sans local, les nombres de logements et de locaux pro de l'adresse.
  /// Logement individuel à défaut.
  static AddressUsage of(GeoObject a, ReferenceData ref) {
    final imb = a.namespace('imb');
    final premises = Building.premises(a);
    final habitat = ref.lib('immeuble', 'DEF_IMB_HABITAT', 'HAB_ID', 'HAB_CODE', imb?['HAB_KEY']);
    final collective = habitat != null ? habitat == 'I' : premises.length > 1;
    final types = {
      for (final l in premises) ref.lib('immeuble', 'DEF_LOC_TYPE', 'LTYP_ID', 'LTYP_CODE', l['LTYP_KEY']),
    };
    final int nbLog = (imb?['IAD_NB_LOG'] as num?)?.toInt() ?? 0;
    final int nbPro = (imb?['IAD_NB_PRO'] as num?)?.toInt() ?? 0;
    final kind = types.contains('R')
        ? 0
        : types.contains('P')
            ? 1
            : (types.contains('T') || types.contains('O'))
                ? 2
                : (nbLog == 0 && nbPro > 0 ? 1 : 0);
    return [
      [indHab, indPro, indFtte],
      [colHab, colPro, colFtte],
    ][collective ? 1 : 0][kind];
  }
}

/// Numéro, complément et voie d'une adresse (« 1 RUE VOLTAIRE »), à défaut sa commune.
String addressLabel(GeoObject a) {
  final p = a.props;
  final s = [p['ADR_NUMERO'], p['ADR_REP'], p['ADR_VOIE']].where((v) => v != null && '$v'.trim().isNotEmpty).join(' ');
  return s.isNotEmpty ? s : '${p['ADR_COMMUNE'] ?? a.id}';
}

/// Adresse complète, comme la maquette de la route optique : « 15 rue du Fortin 91470 Limours ».
String fullAddressLabel(GeoObject a) {
  final p = a.props;
  final town = [p['ADR_CP'], p['ADR_COMMUNE']].where((v) => v != null && '$v'.trim().isNotEmpty).join(' ');
  final street = addressLabel(a);
  return town.isEmpty || street == '${p['ADR_COMMUNE']}' ? street : '$street $town';
}

/// Nombre de locaux et leurs types (référentiel DEF_LOC_TYPE) : « 7 locaux (Résidentiel 6, Professionnel 1) ».
String premisesSummary(List<Map<String, dynamic>> premises, ReferenceData ref) {
  final types = <String, int>{};
  for (final l in premises) {
    final t = ref.lib('immeuble', 'DEF_LOC_TYPE', 'LTYP_ID', 'LTYP_LIB', l['LTYP_KEY']) ?? tr('type inconnu');
    types[t] = (types[t] ?? 0) + 1;
  }
  final n = trn(premises.length, '{0} local', '{0} locaux');
  if (types.isEmpty) return n;
  return types.length == 1 ? '$n (${types.keys.single})' : '$n (${[for (final t in types.entries) '${t.key} ${t.value}'].join(', ')})';
}

/// Carte « Immeuble et BAL » d'une adresse, puis la liste de ses locaux et de leur PBO ; rien si l'adresse n'a pas
/// d'espace `imb`.
class BuildingSection extends StatefulWidget {
  const BuildingSection({super.key, required this.address});

  final GeoObject address;

  /// Locaux dépliés d'office jusqu'à ce nombre.
  static const unfoldedPremises = 12;

  @override
  State<BuildingSection> createState() => _BuildingSectionState();
}

class _BuildingSectionState extends State<BuildingSection> {
  /// Étiquette des PBO des locaux, par `EQU_CODE_EXT` : étiquette optique, sinon support qui le porte.
  final Map<String, String> _boxes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BuildingSection old) {
    super.didUpdateWidget(old);
    if (old.address.id != widget.address.id) _load();
  }

  Future<void> _load() async {
    final repo = context.read<AppProvider>().repo;
    final boxes = <String, String>{};
    for (final code in {for (final l in Building.premises(widget.address)) ?l['EQU_KEY'] as String?}) {
      final node = await repo.nodeOfEquipment(code);
      if (node == null) continue;
      boxes[code] = Optical.of(node, code)?['EQO_LIB'] as String? ?? node.lib ?? code;
    }
    if (mounted) setState(() => _boxes.addAll(boxes));
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<AppProvider>().referenceData;
    final imb = widget.address.namespace('imb');
    if (imb == null) return const SizedBox.shrink();
    String? lib(String table, String id, String col, Object? v) => ref.lib('immeuble', table, id, col, v);
    String yesNo(Object? v) => v == 1 ? tr('Oui') : tr('Non');
    final premises = Building.premises(widget.address);
    final sockets = [imb['IAD_NB_PRISE_LOG'], imb['IAD_NB_PRISE_PRO']].whereType<num>();
    final conv = (imb['IAD_CONV_DATE'] as String?)?.split('T').first.split('-').reversed.join('/');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Section(title: tr('Immeuble et BAL'), spacing: 4, children: [
        if (imb['HAB_KEY'] != null) InfoLine(tr('Habitat'), lib('DEF_IMB_HABITAT', 'HAB_ID', 'HAB_LIB', imb['HAB_KEY']) ?? '?'),
        if (imb['IETAT_KEY'] != null)
          InfoLine(tr('État'), lib('DEF_IMB_ETAT', 'IETAT_ID', 'IETAT_LIB', imb['IETAT_KEY']) ?? '?'),
        if (imb['IAD_NB_LOG'] != null) InfoLine(tr('Logements'), '${imb['IAD_NB_LOG']}'),
        if (imb['IAD_NB_PRO'] != null) InfoLine(tr('Locaux pro.'), '${imb['IAD_NB_PRO']}'),
        if (sockets.isNotEmpty) InfoLine(tr('Prises'), '${sockets.fold<num>(0, (a, b) => a + b)}'),
        if (imb['IAD_BATIMENT'] != null) InfoLine(tr('Bâtiment'), '${imb['IAD_BATIMENT']}'),
        if (imb['IAD_NEUF'] != null) InfoLine(tr('Neuf'), yesNo(imb['IAD_NEUF'])),
        if (imb['GEST_KEY'] != null)
          InfoLine(tr('Gestionnaire'), ref.lib('noyau', 'DEF_ORGANISME', 'ORG_ID', 'ORG_LIB', imb['GEST_KEY']) ?? '?'),
        if (conv != null) InfoLine(tr('Convention'), tr('signée le {0}', [conv])),
        if (imb['IAD_ACCORD_GEST'] != null) InfoLine(tr('Accord gestion.'), yesNo(imb['IAD_ACCORD_GEST'])),
        if (imb['IAD_COMMENT'] != null) InfoLine(tr('Commentaire'), '${imb['IAD_COMMENT']}'),
      ]),
      if (premises.isNotEmpty)
        Section(
          title: tr('Locaux'),
          expanded: premises.length <= BuildingSection.unfoldedPremises,
          action: Text(trn(premises.length, '{0} local', '{0} locaux'), style: Theme.of(context).textTheme.bodySmall),
          children: [
            Text(premisesSummary(premises, ref), style: Theme.of(context).textTheme.bodySmall),
            for (final l in premises)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.door_front_door_outlined),
                title: Text([
                  if (l['LOC_BATIMENT'] != null) tr('bât. {0}', [l['LOC_BATIMENT']]),
                  if (l['LOC_ESCALIER'] != null) tr('esc. {0}', [l['LOC_ESCALIER']]),
                  if (l['LOC_ETAGE'] != null) tr('étage {0}', [l['LOC_ETAGE']]),
                  if (l['LOC_LIB'] != null) tr('local {0}', [l['LOC_LIB']]),
                ].join(' · ').ifEmpty(tr('Local'))),
                subtitle: Text([
                  ?lib('DEF_LOC_TYPE', 'LTYP_ID', 'LTYP_LIB', l['LTYP_KEY']),
                  ?lib('DEF_LOC_RACCO', 'RACCO_ID', 'RACCO_LIB', l['RACCO_KEY']),
                  if (l['EQU_KEY'] != null) _boxes[l['EQU_KEY']] ?? tr('PBO hors paquet'),
                  ?l['LOC_COMMENT'] as String?,
                ].join(' · ')),
              ),
          ],
        ),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
