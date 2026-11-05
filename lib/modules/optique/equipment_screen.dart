import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../data/visuals.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../screens/gallery_screen.dart';
import '../../screens/visuals_screen.dart';
import '../../theme.dart';
import '../../widgets/back_to_map.dart';
import '../../widgets/bottom_bar.dart';
import '../../widgets/fields.dart';
import '../../widgets/photo.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/support_bar.dart';
import '../infra/equipment.dart';
import 'optical.dart';
import 'splice_screen.dart';

/// Écran dédié d'un équipement d'un support (module optique ; onglet `equipement:<EQU_CODE_EXT>` du support), ouvert
/// depuis l'aperçu du support sur la carte ou la carte Équipements de la saisie (« Autre équipement » du menu ⋮ s'il y
/// en a plusieurs) : l'équipement (fonction, matériel, capacité…), ses visuels, chacun avec sa galerie (vues des équipements :
/// boîtier fermé, ouvert, cassettes, mesures photométriques ; visuels libres de l'équipement, « Ajouter » de la barre
/// basse), et son écran Optique (liens fibres, notes equipements rep1). Un support peut porter plusieurs équipements :
/// chacun a ses visuels, distincts de ceux du support. Les photos sont portées par le support, relu après chaque
/// écriture comme pour ses visuels.
class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key, required this.node, required this.equipment});

  final GeoObject node;

  /// `EQU_CODE_EXT` de l'équipement (`inf.equipements` du nœud).
  final String equipment;

  /// Onglet du support : `equipement:<EQU_CODE_EXT>`.
  static String tab(String equipment) => '$tabPrefix$equipment';

  static const tabPrefix = 'equipement:';

  /// Écran Optique consultable (liens fibres) : contenu optique publié, ou boîte d'épissure du catalogue (ajoutée sur le terrain).
  static bool hasSplices(GeoObject node, String equipment, Map<String, dynamic>? mat) =>
      Optical.of(node, equipment) != null || SupportEquipment.isSpliceBox(mat);

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  late GeoObject _o = widget.node;

  /// Écritures déjà relues ([AppProvider.revision]), comme les visuels du support.
  int _revision = -1;
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  /// Relit le support, noté tel qu'il est enregistré (intitulé à jour dans les supports quittés, menu ⋮).
  Future<void> _reload() async {
    final fresh = await context.read<AppProvider>().repo.object(_o.id);
    if (!mounted || fresh == null) return;
    setState(() => _o = fresh);
    final r = _route;
    if (r != null) screenStack.note(r, tab: EquipmentScreen.tab(widget.equipment), object: fresh.copy());
  }

  /// Écran propre de l'équipement (galerie, liens fibres) ; au retour, le support est relu.
  Future<void> _open(Widget screen, [RouteSettings? settings]) async {
    await Navigator.push(context, MaterialPageRoute(settings: settings, builder: (_) => screen));
    await _reload();
  }

  Future<void> _splices() =>
      _open(SpliceScreen(node: _o, equipment: widget.equipment), tabSettings(_o, SpliceScreen.tab(widget.equipment)));

  Future<void> _addVisual() async {
    await addFreeVisual(context, _o, equipment: widget.equipment);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    if (app.revision != _revision) {
      _revision = app.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    final ref = app.referenceData;
    final e = SupportEquipment.find(_o, widget.equipment);
    final present = e != null && e['DATE_ABD'] == null;
    final opt = Optical.of(_o, widget.equipment);
    final mat = ref.row('infra', 'MAT_EQUIP', 'MAT_ID', e?['MAT_KEY']);
    final title = e == null ? tr('Équipement') : SupportEquipment.title(_o, e, ref);
    final type = ref.equipmentType(opt?['OTYP_KEY'] as int?);
    final splices = present && EquipmentScreen.hasSplices(_o, widget.equipment, mat);
    final visuals = Visual.ofEquipment(_o, widget.equipment, ref);
    final quantity = e?['EQU_QTE'] as int? ?? 1;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Nge.barBackground,
      appBar: AppBar(
        title: ScreenTitle(title, [type ?? tr('équipement'), _o.lib ?? tr('Sans étiquette')].join(' · ')),
        actions: [
          SupportMenu(
            object: _o,
            actions: [
              if (splices) (icon: Icons.cable_outlined, label: tr('Optique'), onSelected: _splices),
              // autre équipement du support (la barre basse porte la saisie, notes rep16)
              if (SupportEquipment.presentOf(_o).length > 1)
                (
                  icon: Icons.swap_horiz,
                  label: tr('Autre équipement'),
                  onSelected: () => openEquipment(context, _o, current: widget.equipment),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SupportBar(
        object: _o,
        next: _reload,
        // visuel libre de l'équipement, pas du support
        addItem: BarItem(icon: Icons.add, label: tr('Ajouter'), onPressed: present ? _addVisual : null),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Section(
            title: tr('Équipement'),
            spacing: 4,
            children: [
              if (e == null)
                Text(tr('Équipement absent du support.'), style: t.bodySmall)
              else if (!present)
                Text(tr('Équipement retiré du support.'), style: t.bodySmall),
              if (type != null) InfoLine(tr('Type'), type),
              if (mat != null) InfoLine(tr('Matériel'), SupportEquipment.label(mat)),
              if (quantity > 1) InfoLine(tr('Quantité'), '$quantity'),
              if (opt?['EQO_CAPA'] != null)
                InfoLine(tr('Capacité'), trn(opt!['EQO_CAPA'] as num, '{0} fibre', '{0} fibres')),
              if (opt?['EQO_EMPLACEMENT'] != null) InfoLine(tr('Emplacement'), '${opt!['EQO_EMPLACEMENT']}'),
              if (opt?['EQO_PARENT_KEY'] != null)
                InfoLine(tr('Dans'), Optical.of(_o, opt!['EQO_PARENT_KEY'] as String?)?['EQO_LIB'] as String? ?? '?'),
              if (opt?['AVCT_KEY'] != null) InfoLine(tr('Avancement'), ref.progress(opt!['AVCT_KEY'] as int?) ?? '?'),
              if (splices)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _splices,
                      icon: const Icon(Icons.cable_outlined),
                      label: Text(tr('Optique')),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: VisualGrid(
              visuals: visuals,
              card: (v) {
                final photos = _o.photos(v);
                return VisualCard(
                  visual: v,
                  count: photos.length,
                  reference: photos.isEmpty ? null : photoImage(app, photos.first),
                  onOpen: () => _open(GalleryScreen(object: _o, visual: v, owner: title)),
                  onPhoto: () async {
                    if (await takePhoto(context, _o, v)) await _reload();
                  },
                );
              },
            ),
          ),
          if (visuals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr('Aucun visuel attendu pour les équipements. « Ajouter » crée un visuel libre.'),
                style: t.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
