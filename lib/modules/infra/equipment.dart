import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/geo_object.dart';
import '../../data/bundle.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../theme.dart';
import '../../widgets/fields.dart';
import '../../widgets/svg_icon.dart';
import '../optique/optical.dart';

/// Équipements d'un support (espace `inf.equipements` du nœud : INF_EQUIPEMENT, catalogue MAT_EQUIP) : boîtes,
/// manchons… Carte de la saisie du support, seul endroit où on les ajoute et les retire (ajout rapide : matériel du
/// catalogue et quantité). Retirer un équipement venu du dépôt l'abandonne (`DATE_ABD`) ; un équipement ajouté pendant
/// la saisie ([newIds]) disparaît. Un équipement optique (espace `opt` du nœud) montre son étiquette et sa fonction.
/// Le picto de chaque équipement ([onOpen]) ouvre son écran dédié (module optique : ses visuels, ses liens fibres),
/// où le renseigner en détail, ce qui n'est pas exigé d'un équipement préexistant.
class SupportEquipment extends StatelessWidget {
  const SupportEquipment({
    super.key,
    required this.node,
    required this.referenceData,
    required this.author,
    required this.newIds,
    required this.onChanged,
    required this.onOpen,
    this.expanded,
  });

  final GeoObject node;
  final ReferenceData referenceData;
  final String author;

  /// `EQU_CODE_EXT` des équipements ajoutés pendant la saisie (tenu par l'écran).
  final Set<String> newIds;
  final VoidCallback onChanged;

  /// Ouvre l'écran dédié de l'équipement (`EQU_CODE_EXT`).
  final ValueChanged<String> onOpen;

  /// Carte dépliable (saisie en cartes de la chambre et du poteau) : ouverte au départ si vrai.
  final bool? expanded;

  static bool isSpliceBox(Map<String, dynamic>? mat) => ((mat?['MAT_CAPAEPIS'] as num?) ?? 0) > 0;

  /// Équipements de [node] (`inf.equipements`), cartes normalisées ; [create] : liste créée si absente.
  static List<Map<String, dynamic>> listOf(GeoObject node, {bool create = false}) {
    final inf = node.namespace('inf', create: create);
    final l = (create ? inf!.putIfAbsent('equipements', () => <dynamic>[]) : inf?['equipements']) as List?;
    if (l == null) return [];
    for (var i = 0; i < l.length; i++) {
      if (l[i] is! Map<String, dynamic>) l[i] = (l[i] as Map).cast<String, dynamic>();
    }
    return l.cast<Map<String, dynamic>>();
  }

  /// Équipements présents (non abandonnés) de [node].
  static List<Map<String, dynamic>> presentOf(GeoObject node) => [
        for (final e in listOf(node))
          if (e['DATE_ABD'] == null) e,
      ];

  /// Équipement [code] (`EQU_CODE_EXT`) de [node], abandonné ou non ; null s'il n'y est pas.
  static Map<String, dynamic>? find(GeoObject node, String code) =>
      listOf(node).where((e) => e['EQU_CODE_EXT'] == code).firstOrNull;

  static String label(Map<String, dynamic> m) =>
      [m['MAT_LIB'], m['MAT_REF']].whereType<String>().where((s) => s.trim().isNotEmpty).join(' — ');

  /// Intitulé de l'équipement [e] de [node] : étiquette terrain du contenu optique, sinon matériel du catalogue.
  static String title(GeoObject node, Map<String, dynamic> e, ReferenceData ref) {
    final lib = Optical.of(node, e['EQU_CODE_EXT'] as String?)?['EQO_LIB'];
    if (lib is String && lib.trim().isNotEmpty) return lib;
    final m = ref.row('infra', 'MAT_EQUIP', 'MAT_ID', e['MAT_KEY']);
    return m == null ? tr('Matériel {0}', [e['MAT_KEY'] ?? tr('inconnu')]) : label(m);
  }

  /// Détail de l'équipement [e] : fonction optique et matériel quand l'intitulé est l'étiquette, quantité ; null
  /// s'il n'y a rien à ajouter.
  static String? subtitle(GeoObject node, Map<String, dynamic> e, ReferenceData ref) {
    final opt = Optical.of(node, e['EQU_CODE_EXT'] as String?);
    final m = ref.row('infra', 'MAT_EQUIP', 'MAT_ID', e['MAT_KEY']);
    final quantity = e['EQU_QTE'] as int? ?? 1;
    final parts = [
      if (opt != null) ...[
        ?ref.equipmentType(opt['OTYP_KEY'] as int?),
        if (opt['EQO_LIB'] is String) m == null ? tr('Matériel {0}', [e['MAT_KEY'] ?? tr('inconnu')]) : label(m),
      ],
      if (quantity > 1) tr('Quantité : {0}', [quantity]),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _add(BuildContext context) async {
    final catalog = referenceData.table('infra', 'MAT_EQUIP');
    final choice = await showDialog<(Map<String, dynamic>, int)>(
      context: context,
      builder: (c) => _NewEquipment(catalog: catalog),
    );
    if (choice == null) return;
    final code = const Uuid().v4();
    newIds.add(code);
    listOf(node, create: true).add(<String, dynamic>{
      'EQU_CODE_EXT': code,
      'MAT_KEY': choice.$1['MAT_ID'],
      'EQU_QTE': choice.$2,
      'DATE_CREA': Bundle.timestamp(),
      'SRC_MODIF': author,
    });
    onChanged();
  }

  void _remove(Map<String, dynamic> e) {
    if (newIds.remove(e['EQU_CODE_EXT'])) {
      listOf(node).remove(e);
    } else {
      e['DATE_ABD'] = Bundle.timestamp();
      e['SRC_ABD'] = author;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final presents = presentOf(node);
    return Section(
      title: tr('Équipements'),
      expanded: expanded,
      action: presents.isEmpty
          ? null
          : Text(trn(presents.length, '{0} équipement', '{0} équipements'),
              textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, color: Nge.secondaryText)),
      children: [
        if (presents.isEmpty) Text(tr('Aucun équipement'), style: Theme.of(context).textTheme.bodySmall),
        for (final e in presents)
          Builder(builder: (context) {
            final code = e['EQU_CODE_EXT'] as String?;
            final sub = subtitle(node, e, referenceData);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const SvgIcon(SvgIcon.equipment),
              title: Text(title(node, e, referenceData)),
              subtitle: sub == null ? null : Text(sub),
              onTap: code == null ? null : () => onOpen(code),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                // picto des équipements (à la place des connecteurs) : l'écran dédié de l'équipement
                if (code != null)
                  IconButton(
                    tooltip: tr('Ouvrir l\'équipement'),
                    icon: const SvgIcon(SvgIcon.equipment),
                    onPressed: () => onOpen(code),
                  ),
                IconButton(
                  tooltip: tr('Retirer l\'équipement'),
                  color: Nge.red,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(e),
                ),
              ]),
            );
          }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: Text(tr('Ajouter un équipement')),
          ),
        ),
      ],
    );
  }
}

/// Équipement à afficher parmi les équipements présents de [node] ([SupportEquipment.presentOf]) : feuille de choix,
/// l'équipement [current] marqué ; null si elle est fermée sans choix.
Future<String?> chooseEquipment(BuildContext context, GeoObject node, ReferenceData ref, {String? current}) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 8), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(tr('Équipements de {0}', [node.lib ?? tr('Sans étiquette')]),
                style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final e in SupportEquipment.presentOf(node))
            if (e['EQU_CODE_EXT'] case final String code)
              ListTile(
                leading: const SvgIcon(SvgIcon.equipment),
                title: Text(SupportEquipment.title(node, e, ref)),
                subtitle: switch (SupportEquipment.subtitle(node, e, ref)) {
                  final String s => Text(s),
                  null => null,
                },
                selected: code == current,
                trailing: code == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, code),
              ),
        ]),
      ),
    );

/// Choix d'un matériel du catalogue (recherche sur le libellé et la référence) et de la quantité.
class _NewEquipment extends StatefulWidget {
  const _NewEquipment({required this.catalog});

  final List<Map<String, dynamic>> catalog;

  @override
  State<_NewEquipment> createState() => _NewEquipmentState();
}

class _NewEquipmentState extends State<_NewEquipment> {
  Map<String, dynamic>? _mat;
  int _quantity = 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Nouvel équipement')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Autocomplete<Map<String, dynamic>>(
            displayStringForOption: SupportEquipment.label,
            optionsBuilder: (v) {
              final q = v.text.toLowerCase().trim();
              return widget.catalog
                  .where((m) => q.isEmpty || SupportEquipment.label(m).toLowerCase().contains(q))
                  .take(50);
            },
            onSelected: (m) => setState(() => _mat = m),
            fieldViewBuilder: (context, ctl, focus, _) => TextField(
              controller: ctl,
              focusNode: focus,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Matériel (catalogue)'), hintText: tr('Boîte, manchon, PBO…')),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(tr('Quantité'))),
            IconButton(
              tooltip: tr('Moins'),
              icon: const Icon(Icons.remove),
              onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
            ),
            SizedBox(width: 32, child: Text('$_quantity', textAlign: TextAlign.center)),
            IconButton(tooltip: tr('Plus'), icon: const Icon(Icons.add), onPressed: () => setState(() => _quantity++)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
          FilledButton(
            onPressed: _mat == null ? null : () => Navigator.pop(context, (_mat!, _quantity)),
            child: Text(tr('Ajouter')),
          ),
        ],
      );
}
