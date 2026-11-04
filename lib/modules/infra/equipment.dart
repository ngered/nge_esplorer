import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/geo_object.dart';
import '../../data/bundle.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../theme.dart';
import '../../widgets/fields.dart';

/// Équipements d'un support (espace `inf.equipements` du nœud : INF_EQUIPEMENT, catalogue MAT_EQUIP) : boîtes,
/// manchons… Retirer un équipement venu du dépôt l'abandonne (`DATE_ABD`) ; un équipement ajouté pendant la saisie
/// ([newIds]) disparaît. Dans l'écran des équipements ([fibreLinks]), une boîte d'épissure (capacité d'épissures au
/// catalogue) propose ses liens fibres.
class SupportEquipment extends StatelessWidget {
  const SupportEquipment({
    super.key,
    required this.node,
    required this.referenceData,
    required this.author,
    required this.newIds,
    required this.onChanged,
    this.expanded,
    this.fibreLinks = false,
  });

  final GeoObject node;
  final ReferenceData referenceData;
  final String author;

  /// `EQU_CODE_EXT` des équipements ajoutés pendant la saisie (tenu par l'écran).
  final Set<String> newIds;
  final VoidCallback onChanged;

  /// Carte dépliable (voir [Section.expanded]).
  final bool? expanded;
  final bool fibreLinks;

  static bool isSpliceBox(Map<String, dynamic>? mat) => ((mat?['MAT_CAPAEPIS'] as num?) ?? 0) > 0;

  List<Map<String, dynamic>> get _list {
    final l = node.namespace('inf', create: true)!.putIfAbsent('equipements', () => <dynamic>[]) as List;
    for (var i = 0; i < l.length; i++) {
      if (l[i] is! Map<String, dynamic>) l[i] = (l[i] as Map).cast<String, dynamic>();
    }
    return l.cast<Map<String, dynamic>>();
  }

  static String label(Map<String, dynamic> m) =>
      [m['MAT_LIB'], m['MAT_REF']].whereType<String>().where((s) => s.trim().isNotEmpty).join(' — ');

  Future<void> _add(BuildContext context) async {
    final catalog = referenceData.table('infra', 'MAT_EQUIP');
    final choice = await showDialog<(Map<String, dynamic>, int)>(
      context: context,
      builder: (c) => _NewEquipment(catalog: catalog),
    );
    if (choice == null) return;
    final code = const Uuid().v4();
    newIds.add(code);
    _list.add(<String, dynamic>{
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
      _list.remove(e);
    } else {
      e['DATE_ABD'] = Bundle.timestamp();
      e['SRC_ABD'] = author;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final presents = _list.where((e) => e['DATE_ABD'] == null).toList();
    return Section(title: tr('Équipements'), expanded: expanded, children: [
      if (presents.isEmpty) Text(tr('Aucun équipement'), style: Theme.of(context).textTheme.bodySmall),
      for (final e in presents)
        Builder(builder: (context) {
          final m = referenceData.row('infra', 'MAT_EQUIP', 'MAT_ID', e['MAT_KEY']);
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(m == null ? tr('Matériel {0}', [e['MAT_KEY'] ?? tr('inconnu')]) : label(m)),
            subtitle: (e['EQU_QTE'] as int? ?? 1) > 1 ? Text(tr('Quantité : {0}', [e['EQU_QTE']])) : null,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (fibreLinks && isSpliceBox(m))
                IconButton(
                  tooltip: tr('Liens fibres'),
                  icon: const Icon(Icons.cable_outlined),
                  onPressed: () => ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(tr('Liens fibres de la boîte : à venir')))),
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
    ]);
  }
}

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
