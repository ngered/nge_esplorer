import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../data/visuals.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../screens/gallery_screen.dart';
import '../../theme.dart';
import '../../widgets/back_to_map.dart';
import '../../widgets/bottom_bar.dart';
import '../../widgets/support_bar.dart';
import '../../widgets/entry_screen.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/side_sheet.dart';
import '../../widgets/support_link.dart';
import 'mask_editor.dart';
import '../../widgets/messages.dart';

/// État d'une conduite (DEF_CD_ETAT) : identifiant, code, libellé, couleur.
typedef DuctState = ({int id, String code, String lib, Color color});

List<DuctState> ductStates(ReferenceData ref) => [
      for (final e in ref.table('infra', 'DEF_CD_ETAT'))
        (
          id: e['ETAT_ID'] as int,
          code: e['ETAT_CODE'] as String,
          lib: e['ETAT_LIB'] as String,
          color: colorFromHex(e['ETAT_COULEUR'] as String?) ?? Colors.white,
        ),
    ];

Color? colorFromHex(String? hex) {
  final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Masques d'une chambre (maquette Figma `support_sout_saisie_grid`) : une face en plein écran à ses dimensions
/// réelles, grille de cellules carrées de 5 cm parcourue par déplacement et zoom quand elle dépasse l'écran ; une
/// alvéole par conduite, en vraie grandeur, colorée selon son état. Toucher la grille place une alvéole, le double
/// toucher d'une alvéole ouvre son panneau (7 novembre 2026 : ouvert d'un simple toucher, il gênait le déplacement) ;
/// le toucher simple la désigne, et un glissement la déplace alors ; l'appui long déplace toute alvéole. Le choix de
/// la face au-dessus de la grille ; en portrait, le
/// panneau de l'alvéole (ou la légende) dessous ; en paysage (tablette, Windows), la grille à gauche, le panneau ou la
/// légende dans une colonne à droite ([maskSideWidth]), où se déplie aussi la création d'une alvéole.
class MaskScreen extends StatefulWidget {
  const MaskScreen({super.key, required this.chamber, this.face, this.selection});

  final GeoObject chamber;

  /// Face ouverte (A à D) ; par défaut la première face relevée.
  final String? face;

  /// Alvéole sélectionnée à l'ouverture (CD_KEY) : arrivée d'un parcours suivi depuis un autre support, chambre
  /// rouverte par le menu ⋮ ; conduite pas encore placée ici : son alvéole à placer en miroir, mise en évidence.
  final String? selection;

  @override
  State<MaskScreen> createState() => _MaskScreenState();
}

class _MaskScreenState extends State<MaskScreen> with UndoMessage {
  late final MaskEditor _editor;
  Route<dynamic>? _route;

  /// Largeur de la colonne latérale (paysage), null en portrait : la création d'une alvéole s'y déplie ; hauteur du
  /// corps, qui décide des grandes cases.
  double? _side;
  double? _bodyHeight;

  /// Derniers choix à la création d'une alvéole (saisie en série) ; parcours null : sans destination connue.
  GeoObject? _lastLinear;
  bool _routeChosen = false;
  double _lastDiameter = 45;
  int _lastState = 0;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    _editor = MaskEditor(app.repo, widget.chamber,
        author: app.author, face: widget.face, referenceData: app.referenceData)
      ..addListener(_note);
    _editor.load().then((_) {
      // alvéole choisie à l'ouverture, si elle est toujours placée sur la face (une alvéole jamais enregistrée a
      // disparu, et le premier toucher de la grille ne servirait qu'à la désélectionner) ; conduite que cette chambre
      // n'a pas encore placée (arrivée d'un « Vers … ») : son alvéole à placer en miroir, mise en évidence
      final s = widget.selection;
      if (!mounted || s == null) return;
      if (_editor.bores().any((a) => a.cd == s)) {
        _editor.select(s);
      } else {
        _editor.focusMirror(s);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _note();
  }

  /// Face et alvéole choisies, notées pour rouvrir la grille dans le même état si l'on quitte la chambre (menu ⋮).
  void _note() {
    // toute autre action rend caduc le « Annuler » d'une imbrication
    if (!_nesting) hideUndo();
    final r = _route;
    if (r != null) screenStack.note(r, tab: 'masques:${_editor.face}', selection: _editor.selection ?? _editor.focus);
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppProvider>();
    await _editor.validate();
    await app.afterWrite();
    if (mounted) showSaved(context);
  }

  /// « Vers … » du panneau de l'alvéole : d'une touche, la chambre d'en face remplace celle-ci, directement sur la
  /// grille de la face où le parcours arrive (sur l'alvéole de la même conduite si elle y est placée), sans carton ;
  /// un autre support s'ouvre sur ses portées ou ses visuels. La saisie en cours est enregistrée avant.
  Future<void> _follow(MaskBore a) async {
    final linear = a.linear, other = a.linear == null ? null : _editor.destinations[a.linear!.id];
    if (linear == null || other == null) return;
    if (_editor.changed) await _save();
    if (mounted) await follow(context, linear, other, cd: a.cd);
  }

  /// Place une alvéole en ([x], [y]) : linéaire de la conduite (ou sans destination connue), diamètre et état, choisis
  /// dans une feuille qui monte du bas (portrait) ou, en paysage, dans un volet qui se déplie depuis la droite sur la
  /// colonne latérale (notes rep9 : la grille reste visible).
  Future<void> _add(double x, double y) async {
    final states = ductStates(context.read<AppProvider>().referenceData);
    final last = _lastLinear;
    final side = _side;
    Widget form({bool wide = false}) => _NewBore(
          editor: _editor,
          states: states,
          linear: _routeChosen && (last == null || _editor.linears.contains(last))
              ? last
              : _editor.linears.firstOrNull,
          diameter: _lastDiameter,
          state: _lastState,
          wide: wide,
        );
    final sheet = side == null
        ? showModalBottomSheet<(GeoObject?, double, int)>(
            context: context,
            isScrollControlled: true,
            builder: (c) => form(),
          )
        : showSideSheet<(GeoObject?, double, int)>(context,
            width: side, builder: (c) => form(wide: (_bodyHeight ?? 0) >= wideSideHeight));
    final choice = await sheet;
    if (choice == null) return;
    final (linear, diameter, state) = choice;
    _lastLinear = linear;
    _routeChosen = true;
    _lastDiameter = diameter;
    _lastState = state;
    _editor.add(linear: linear, x: x, y: y, diameter: diameter, state: state);
  }

  /// Libellé d'une source du miroir : « C598 · face B ».
  String _sourceLabel(MirrorSource s) {
    final other = _editor.mirrorSources().where((m) => m.source == s).firstOrNull?.chamber ??
        _editor.destinations.values.where((d) => d.id == s.chamber).firstOrNull;
    return tr('{0} · face {1}', [other?.lib ?? tr('Sans étiquette'), s.face]);
  }

  /// Bouton Miroir (notes rep15) : ouvre le miroir sur la face affichée, depuis la face de la chambre d'en face
  /// choisie s'il y en a plusieurs ; le referme s'il est ouvert.
  Future<void> _toggleMirror() async {
    if (_editor.mirrorSource != null) {
      _editor.showMirror(null);
      return;
    }
    await _chooseMirror();
  }

  /// Face de la chambre d'en face dont les alvéoles sont proposées en pointillé sur la face affichée : d'emblée
  /// s'il n'y en a qu'une, sinon choisie dans une liste.
  Future<void> _chooseMirror() async {
    final sources = _editor.mirrorSources();
    if (sources.isEmpty) return;
    final source = sources.length == 1
        ? sources.single.source
        : await showModalBottomSheet<MirrorSource>(
            context: context,
            isScrollControlled: true,
            builder: (c) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(tr('Miroir sur la face {0}, depuis', [_editor.face]),
                        style: Theme.of(c).textTheme.titleMedium),
                  ),
                  for (final s in sources)
                    ListTile(
                      leading: const Icon(Icons.flip),
                      title: Text(tr('{0} · face {1}', [s.chamber.lib ?? tr('Sans étiquette'), s.source.face])),
                      subtitle: Text(trn(s.count, '{0} alvéole à placer', '{0} alvéoles à placer')),
                      selected: s.source == _editor.mirrorSource,
                      onTap: () => Navigator.pop(c, s.source),
                    ),
                ]),
              ),
            ),
          );
    if (source != null && mounted) _editor.showMirror(source);
  }

  /// Alvéole déposée (fin d'un appui long) dans une plus grande : elle en devient un sous-tube, comme dans FOA
  /// Explorer (notes rep15), avec « Annuler » ; une alvéole d'un autre parcours ne le peut pas, et le message le dit.
  void _drop(MaskBore a, Offset from) {
    final parent = _editor.nestTarget(a);
    // sous-tube resté dans son alvéole, ou alvéole déposée hors de toute autre : simple déplacement
    if (a.subduct ? parent?.cd == a.parent : parent == null) return;
    // « Annuler » ramène aussi l'alvéole où elle était avant le glissement
    void back() {
      final b = _editor.bores().where((b) => b.cd == a.cd).firstOrNull;
      if (b != null) _editor.move(b, from.dx, from.dy);
    }

    final label = a.label;
    String now() => _editor.bores().where((b) => b.cd == a.cd).firstOrNull?.label ?? '?';
    if (parent == null) {
      // sous-tube glissé hors de son alvéole : il en est détaché (InfraExplorer, notes rep17)
      _nesting = true;
      final undo = _editor.unnest(a);
      _nesting = false;
      showUndo(tr('Sous-tube {0} détaché : alvéole {1}', [label, now()]), () {
        undo();
        back();
      });
      return;
    }
    if (!_editor.canNest(a, parent)) {
      // un sous-tube refusé retourne dans son alvéole
      if (a.subduct) back();
      ScaffoldMessenger.of(context).replaceSnackBar(SnackBar(
          content: Text(tr('Alvéole {0} d\'un autre parcours : elle ne peut pas être sous-tube de l\'alvéole {1}.',
              [a.label, parent.label]))));
      return;
    }
    _nesting = true;
    final undo = _editor.nest(a, parent);
    _nesting = false;
    showUndo(tr('Alvéole {0} devenue sous-tube {1}', [label, now()]), () {
      undo();
      back();
    });
  }

  /// Imbrication en cours : sa notification ne ferme pas son propre « Annuler ».
  bool _nesting = false;

  /// « Tout placer » : place d'un coup les alvéoles à placer de la face affichée.
  void _placeMirrors() {
    final n = _editor.placeMirrors();
    ScaffoldMessenger.of(context).replaceSnackBar(SnackBar(
        content: Text(trn(n, '{0} alvéole placée en miroir', '{0} alvéoles placées en miroir'))));
  }

  /// Sous-tubage de l'alvéole [a] : nombre et diamètre des sous-tubes, choisis dans un dialogue.
  Future<void> _subduct(MaskBore a) async {
    final choice = await showDialog<(int, double)>(
      context: context,
      builder: (_) => _SubductDialog(bore: a, diameters: subductDiameters(_editor.referenceData)),
    );
    if (choice != null) _editor.subduct(a, choice.$1, choice.$2);
  }

  /// Câble d'un autre diamètre que ceux proposés, saisi en mm.
  Future<void> _otherCable(MaskBore a) async {
    final mm = await showDialog<double>(context: context, builder: (_) => const _CableDiameterDialog());
    if (mm != null) _editor.addCable(a, mm, _editor.cableNature);
  }

  /// Retire l'alvéole choisie ; avec ses sous-tubes, après confirmation.
  Future<void> _remove(MaskBore a) async {
    final n = _editor.children(a).length;
    if (n > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Retirer l\'alvéole {0}', [a.label])),
          content: Text(trn(n, 'Son sous-tube sera retiré avec elle.', 'Ses {0} sous-tubes seront retirés avec elle.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Retirer'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    _editor.remove(a);
  }

  /// Ajout depuis la barre basse : au centre de la face, décalé (en m) s'il y est déjà une alvéole.
  void _addAtCenter() {
    final (x, y) = _editor.freePlace(_lastDiameter);
    _add(x, y);
  }

  /// Dimensions de la face affichée ; Valider garde ses alvéoles centrées (MaskEditor.resize).
  Future<void> _resize() async {
    final size = await showDialog<(double, double)>(context: context, builder: (_) => _FaceSizeDialog(editor: _editor));
    if (size == null) return;
    final (width, height) = size;
    int mm(double m) => (m * 1000).round();
    if (mm(width) != mm(_editor.width) || mm(height) != mm(_editor.height)) _editor.resize(width, height);
  }

  Future<void> _photos() async {
    final app = context.read<AppProvider>();
    final chamber = await app.repo.object(_editor.chamber.id) ?? _editor.chamber;
    final v = Visual.of(chamber, app.referenceData).where((v) => v.code == _editor.face).firstOrNull;
    if (!mounted) return;
    if (v == null) {
      ScaffoldMessenger.of(context)
          .replaceSnackBar(SnackBar(content: Text(tr('Pas de visuel attendu pour la face {0}', [_editor.face]))));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryScreen(object: chamber, visual: v)));
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.read<AppProvider>().referenceData;
    final states = ductStates(ref);
    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) {
        final bores = _editor.bores();
        // alvéoles, sous-tubes non comptés
        final n = bores.where((b) => !b.subduct).length;
        final sel = _editor.selectedBore;
        // miroir : alvéoles à placer en tout (pastille du bouton), celles affichées sur la face
        final pending = _editor.loaded ? _editor.pendingMirrors : 0;
        final mirrors = _editor.mirrors(_editor.face).length;
        // la chambre relue dans le dépôt au chargement de la session (l'objet passé a pu vieillir)
        final chamber = _editor.chamber;
        return EntryScreen(
          changed: _editor.changed,
          onSave: _save,
          message: tr('Les masques ont été modifiés.'),
          child: Scaffold(
            appBar: AppBar(
              title: ScreenTitle(
                chamber.lib ?? tr('Sans étiquette'),
                trn(n, 'masque {1} · {0} alvéole', 'masque {1} · {0} alvéoles', [_editor.face]),
              ),
              actions: [
                // menu ⋮ à la place des pictos (notes rep8) : actions de la face, visuels et saisie du support
                SupportMenu(object: chamber, actions: [
                  (icon: Icons.image_outlined, label: tr('Photos de la face'), onSelected: _photos),
                  (icon: Icons.aspect_ratio, label: tr('Dimensions de la face'), onSelected: _resize),
                  if (mirrors > 0)
                    (icon: Icons.flip, label: tr('Tout placer en miroir ({0})', [mirrors]), onSelected: _placeMirrors),
                ]),
              ],
            ),
            bottomNavigationBar: SupportBar(
              object: chamber,
              inModule: true,
              addItem: BarItem(
                icon: Icons.add_circle_outline,
                label: tr('Alvéole'),
                onPressed: _editor.loaded ? _addAtCenter : null,
              ),
            ),
            floatingActionButton: sel == null ? saveButton(visible: _editor.changed, onPressed: _save) : null,
            // aucun champ dans le corps : le clavier des dimensions de la face ne réduit pas la grille derrière le
            // dialogue (un téléphone en portrait passerait sinon en paysage)
            resizeToAvoidBottomInset: false,
            body: !_editor.loaded
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final faces = Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      // choix de la face, puis le bouton Miroir (notes rep15)
                      child: Row(children: [
                        Expanded(child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          for (final f in chamberFaces)
                            ButtonSegment(
                              value: f,
                              // nombre d'alvéoles placées ; réduit plutôt que de déborder (téléphone, grands caractères)
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(() {
                                  final placed = _editor.bores(f).where((b) => !b.subduct).length;
                                  return placed == 0 ? f : '$f · $placed';
                                }()),
                              ),
                            ),
                        ],
                        selected: {_editor.face},
                        onSelectionChanged: (s) => _editor.selectFace(s.first),
                      )),
                        const SizedBox(width: 8),
                        Badge(
                          isLabelVisible: pending > 0 && _editor.mirrorSource == null,
                          label: Text('$pending'),
                          backgroundColor: Nge.yellow,
                          textColor: Nge.slateDark,
                          child: IconButton(
                            isSelected: _editor.mirrorSource != null,
                            tooltip: _editor.mirrorSource != null
                                ? tr('Fermer le miroir')
                                : trn(pending, 'Miroir · {0} alvéole à placer', 'Miroir · {0} alvéoles à placer'),
                            style: IconButton.styleFrom(
                              side: const BorderSide(color: Nge.border),
                              backgroundColor: _editor.mirrorSource != null ? Nge.yellow : Colors.white,
                              foregroundColor: Nge.slateDark,
                            ),
                            icon: const Icon(Icons.flip),
                            onPressed: pending == 0 && _editor.mirrorSource == null ? null : _toggleMirror,
                          ),
                        ),
                      ]),
                    );
                    final grid = MaskGrid(
                      editor: _editor,
                      states: states,
                      onPlace: _add,
                      onDrop: _drop,
                      initial: widget.selection,
                    );
                    // [wide] : colonne latérale haute (tablette, Windows en paysage), légende et choix en grand ;
                    // [actions] : « Retirer du masque » et « Enregistrer » dans le panneau (sinon épinglés à part)
                    // sans alvéole choisie : alvéoles à placer en miroir sur la face, puis la légende
                    Widget panelOf({bool wide = false, bool actions = true}) => sel == null
                        ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (_editor.mirrorSource case final source?)
                              _MirrorBanner(
                                source: _sourceLabel(source),
                                count: mirrors,
                                face: _editor.face,
                                wide: wide,
                                onPlaceAll: mirrors > 0 ? _placeMirrors : null,
                                onChange: _editor.mirrorSources().length > 1 ? _chooseMirror : null,
                                onClose: () => _editor.showMirror(null),
                              ),
                            _Legend(states: states, wide: wide),
                          ])
                        : _BorePanel(
                            bore: sel,
                            editor: _editor,
                            states: states,
                            onSave: _editor.changed ? _save : null,
                            onFollow: _follow,
                            onSubduct: _subduct,
                            onOtherCable: _otherCable,
                            onRemove: _remove,
                            wide: wide,
                            actions: actions,
                          );
                    // paysage : corps plus large que haut, comme la rosace des portées
                    if (c.maxWidth > c.maxHeight) {
                      final side = math.min(maskSideWidth, c.maxWidth * 0.4);
                      _side = side;
                      _bodyHeight = c.maxHeight;
                      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        // les noms des faces au-dessus de la grille (notes rep9) ; la colonne de droite pour la légende
                        // et l'alvéole choisie
                        Expanded(
                          child: Column(children: [
                            Center(
                              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maskSideWidth), child: faces),
                            ),
                            Expanded(child: grid),
                          ]),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: side,
                          child: SafeArea(
                            top: false,
                            left: false,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  // chaque alvéole choisie, ou la légende, s'ouvre en haut de la colonne
                                  key: ValueKey(sel?.cd),
                                  // la fin de la légende au-dessus du bouton flottant « Enregistrer »
                                  padding: EdgeInsets.only(bottom: sel == null && _editor.changed ? fabMargin : 0),
                                  // grandes cases si la colonne peut les montrer (sinon la présentation compacte)
                                  child: panelOf(
                                    wide: c.maxHeight >= (sel == null ? wideLegendHeight : wideSideHeight),
                                    actions: false,
                                  ),
                                ),
                              ),
                              // « Retirer du masque » et « Enregistrer » toujours visibles, en bas de la colonne, même
                              // quand le panneau défile (paysage peu haut, téléphone, grands caractères)
                              if (sel != null) ...[
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                                  child: _BoreActions(bore: sel, onRemove: _remove, onSave: _editor.changed ? _save : null),
                                ),
                              ],
                            ]),
                          ),
                        ),
                      ]);
                    }
                    _side = null;
                    // portrait : le panneau prend au plus 45 % du corps et défile au-delà (lien « Vers … », grands
                    // caractères), « Retirer du masque » et « Enregistrer » épinglés dessous : la grille garde sa place
                    return Column(children: [
                      faces,
                      Expanded(child: grid),
                      const Divider(height: 1),
                      SafeArea(
                        top: false,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: c.maxHeight * 0.45),
                            child: SingleChildScrollView(key: ValueKey(sel?.cd), child: panelOf(actions: false)),
                          ),
                          if (sel != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                              child: _BoreActions(bore: sel, onRemove: _remove, onSave: _editor.changed ? _save : null),
                            ),
                        ]),
                      ),
                    ]);
                  }),
          ),
        );
      },
    );
  }
}

/// Largeur de la colonne latérale en paysage (panneau de l'alvéole ou légende, volet de création) : au plus 40 % de la
/// largeur du corps (notes rep8 : la place libre d'une tablette rend la légende lisible et les choix faciles à toucher).
const maskSideWidth = 480.0;

/// Hauteur du corps à partir de laquelle, en paysage, les choix de l'alvéole s'affichent en grandes cases : le
/// panneau large y tient avec ses actions (tablette 1280 × 800, Windows ; pas une tablette 1024 × 600 ni un téléphone
/// en paysage, qui gardent la présentation compacte).
const wideSideHeight = 560.0;

/// Hauteur du corps à partir de laquelle, en paysage, la légende s'affiche en grand, un état par ligne.
const wideLegendHeight = 420.0;

/// Taille à l'écran (px) d'une cellule de 5 cm, bornée : la face entière quand elle tient dans la vue, sinon toute
/// sa hauteur (ou sa largeur) et parcourue par déplacement dans l'autre sens ; le zoom s'y ajoute.
const minCellPixels = 28.0;
const maxCellPixels = 56.0;

/// Cible du toucher d'une alvéole (px) au moins, autour du disque d'un petit sous-tube.
const _minTouch = 28.0;

/// Grille d'une face aux dimensions réelles : cellules carrées de 5 cm, alvéoles en vraie grandeur ; déplacement et
/// zoom de la vue, ajout au toucher, alvéole désignée d'un toucher et déplacée d'un glissement, panneau d'une alvéole
/// au double toucher, déplacement de toute alvéole par appui long. Positions en m.
class MaskGrid extends StatefulWidget {
  const MaskGrid({
    super.key,
    required this.editor,
    required this.states,
    required this.onPlace,
    this.onDrop,
    this.initial,
  });

  /// Fin du déplacement d'une alvéole (appui long relâché) : sous-tubage par glisser-déposer.
  final void Function(MaskBore bore, Offset from)? onDrop;

  final MaskEditor editor;
  final List<DuctState> states;

  /// Alvéole choisie à l'ouverture (MaskScreen.selection), amenée dans la vue.
  final String? initial;

  /// Toucher hors alvéole : centre de la nouvelle alvéole, en m depuis la gauche et le haut de la face.
  final void Function(double x, double y) onPlace;

  @override
  State<MaskGrid> createState() => _MaskGridState();
}

class _MaskGridState extends State<MaskGrid> {
  final _gridKey = GlobalKey();
  final _view = TransformationController();

  /// Écart du doigt au centre de l'alvéole déplacée (m).
  Offset _grab = Offset.zero;

  /// Position de l'alvéole déplacée au début du glissement (m) : « Annuler » d'une imbrication l'y ramène.
  Offset _from = Offset.zero;

  /// Alvéole sur laquelle la vue a été centrée (arrivée d'un « Vers … », chambre rouverte) : une seule fois.
  String? _centered;

  /// Alvéole désignée d'un toucher simple (7 novembre 2026) : cerclée comme l'alvéole choisie, sans son panneau,
  /// et prête à être déplacée d'un simple glissement (sans appui long).
  String? _marked;

  void _mark(String? cd) => setState(() => _marked = cd);

  /// Toucher hors d'une alvéole ou sur une alvéole à placer en miroir : referme le panneau et retire la désignation ;
  /// vrai s'il y avait l'un ou l'autre (le toucher ne fait rien d'autre).
  bool _release() {
    final e = widget.editor;
    if (e.selection == null && _marked == null) return false;
    e.select(null);
    _mark(null);
    return true;
  }

  /// Début du déplacement de [held] : écart du doigt à son centre, gardé pendant le déplacement. L'alvéole n'est pas
  /// choisie : son panneau, en s'ouvrant, recentrerait la grille sous le doigt et cacherait la face.
  void _startMove(MaskBore held, Offset global, double scale) {
    final p = _toFace(global, scale);
    _from = Offset(held.x, held.y);
    _grab = p == null ? Offset.zero : p - _from;
  }

  void _updateMove(MaskBore held, Offset global, double scale) {
    final p = _toFace(global, scale);
    if (p != null) widget.editor.move(held, p.dx - _grab.dx, p.dy - _grab.dy);
  }

  /// Fin du déplacement : l'alvéole déposée (sous-tubage par glisser-déposer).
  void _endMove(MaskBore held) {
    final moved = widget.editor.bores().where((b) => b.cd == held.cd).firstOrNull;
    if (moved != null) widget.onDrop?.call(moved, _from);
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// Amène au centre de la vue ([viewport]) l'alvéole à placer mise en évidence, sinon l'alvéole choisie à
  /// l'ouverture ([MaskGrid.initial]) : sur une grande face, elle serait hors de l'écran. Une seule fois par
  /// alvéole ; une face qui tient dans la vue n'a pas à défiler.
  void _center(Size viewport, double width, double height, double scale) {
    final e = widget.editor;
    final cd = e.focus ?? (e.selection == widget.initial ? widget.initial : null);
    if (cd == null || cd == _centered) return;
    final m = e.mirrors(e.face).where((m) => m.cd == cd).firstOrNull;
    final b = m == null ? e.bores().where((b) => b.cd == cd).firstOrNull : null;
    final (x, y) = m != null ? (m.x, m.y) : b != null ? (b.x, b.y) : (null, null);
    if (x == null || y == null) return;
    _centered = cd;
    final contentWidth = math.max(viewport.width, width + 24), contentHeight = math.max(viewport.height, height + 24);
    double shift(double content, double view, double face, double at) {
      if (content <= view) return 0;
      final px = (content - face - 24) / 2 + 12 + at;
      return (view / 2 - px).clamp(view - content, 0.0);
    }

    _view.value = Matrix4.translationValues(
        shift(contentWidth, viewport.width, width, x * scale), shift(contentHeight, viewport.height, height, y * scale), 0);
  }

  /// Point de la face (m) sous une position de l'écran ; [scale] en px par m.
  Offset? _toFace(Offset global, double scale) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(global) / scale;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.editor;
    return LayoutBuilder(builder: (context, c) {
      // vue trop petite pour la grille (grands caractères sur un petit écran) : rien plutôt qu'une échelle nulle
      if (c.maxWidth <= 24 || c.maxHeight <= 24) return const SizedBox.shrink();
      final faceWidth = e.width, faceHeight = e.height;
      // cellule de 5 cm (marges de 12 comprises) : la face entière si elle tient dans la vue à la taille minimale,
      // sinon la vue remplie dans un sens (une grande face C ou D : sa hauteur) et parcourue dans l'autre ; bornée
      final fitWidth = (c.maxWidth - 24) * gridCell / faceWidth, fitHeight = (c.maxHeight - 24) * gridCell / faceHeight;
      final whole = math.min(fitWidth, fitHeight);
      final cell = (whole >= minCellPixels ? whole : math.max(fitWidth, fitHeight)).clamp(minCellPixels, maxCellPixels);
      final scale = cell / gridCell; // px par m
      final width = faceWidth * scale, height = faceHeight * scale;
      final colors = {for (final s in widget.states) s.id: s.color};
      final viewport = Size(c.maxWidth, c.maxHeight);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _center(viewport, width, height, scale);
      });
      final face = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (!_release()) widget.onPlace(d.localPosition.dx / scale, d.localPosition.dy / scale);
        },
        child: SizedBox(
          key: _gridKey,
          width: width,
          height: height,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: _GridPainter(scale))),
            for (final a in e.bores())
              () {
                final d = boreDiameter(a.diameter) * scale;
                // un sous-tube à sa taille : le bord de son alvéole reste à toucher (les sous-tubes se choisissent
                // aussi dans le panneau de l'alvéole)
                final touch = a.subduct ? d : math.max(d, _minTouch);
                final opened = a.cd == e.selection;
                final marked = a.cd == _marked;
                // l'appui long d'un sous-tube déplace son alvéole, avec tous ses sous-tubes ; désigné, son glissement
                // le déplace seul : hors de son alvéole il en est détaché, dans une autre il en devient sous-tube
                // (InfraExplorer, notes rep17)
                final held = a.subduct ? e.bores().where((b) => b.cd == a.parent).firstOrNull ?? a : a;
                return Positioned(
                  left: a.x * scale - touch / 2,
                  top: a.y * scale - touch / 2,
                  width: touch,
                  height: touch,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 7 novembre 2026 : le toucher simple désigne l'alvéole (un panneau ouvert se referme), un second
                    // la libère ; le double toucher ouvre ou ferme son panneau ; ouvert d'un toucher, il gênait le
                    // déplacement
                    onTap: () {
                      final wasOpened = e.selection != null;
                      if (wasOpened) e.select(null);
                      _mark(marked && !wasOpened ? null : a.cd);
                    },
                    // (panneau fermé, plus rien n'est désigné : le toucher suivant sur la grille place une alvéole)
                    onDoubleTap: () {
                      e.select(opened ? null : a.cd);
                      _mark(null);
                    },
                    // alvéole désignée ou ouverte : un simple glissement la déplace (la vue ne défile pas sous elle),
                    // depuis le point touché (sans le seuil du glissement, l'alvéole resterait en retard sur le doigt)
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: marked || opened ? (s) => _startMove(a, s.globalPosition, scale) : null,
                    onPanUpdate: marked || opened ? (m) => _updateMove(a, m.globalPosition, scale) : null,
                    onPanEnd: marked || opened ? (_) => _endMove(a) : null,
                    // toute alvéole : l'appui long la déplace
                    onLongPressStart: (s) => _startMove(held, s.globalPosition, scale),
                    onLongPressMoveUpdate: (m) => _updateMove(held, m.globalPosition, scale),
                    onLongPressEnd: (_) => _endMove(held),
                    child: Center(
                      child: SizedBox.square(
                        dimension: d,
                        child: BoreTile(
                          color: a.duct == null ? Nge.hoverPressed : colors[a.state] ?? Colors.white,
                          label: a.label,
                          chosen: opened || marked,
                          diameter: d,
                          occupancy: occupancyOf(a.duct, e.referenceData),
                        ),
                      ),
                    ),
                  ),
                );
              }(),
            // alvéoles à placer en miroir, au-dessus des alvéoles placées (un sous-tube à placer seul est dans son
            // alvéole) et translucides : les toucher les place ; avec une alvéole choisie, le toucher la désélectionne,
            // comme sur la grille
            for (final m in e.mirrors())
              if (m.face == e.face)
                () {
                  final d = boreDiameter(m.diameter) * scale;
                  final touch = math.max(d, _minTouch);
                  return Positioned(
                    left: m.x * scale - touch / 2,
                    top: m.y * scale - touch / 2,
                    width: touch,
                    height: touch,
                    child: Semantics(
                      button: true,
                      label: tr('Placer l\'alvéole {0} en miroir', [m.label]),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!_release()) e.placeMirror(m);
                        },
                        child: Center(
                          child: SizedBox.square(
                            dimension: d,
                            child: MirrorTile(
                              color: colors[m.state] ?? Colors.white,
                              label: m.label,
                              diameter: d,
                              focused: m.cd == e.focus,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
          ]),
        ),
      );
      return ColoredBox(
        color: Nge.barBackground,
        child: InteractiveViewer(
          transformationController: _view,
          constrained: false,
          // dézoom jusqu'à voir toute une grande face
          minScale: math.min(0.4, math.min(c.maxWidth / (width + 24), c.maxHeight / (height + 24))),
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(48),
          // face plus petite que la vue : centrée
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: c.hasBoundedWidth ? c.maxWidth : 0,
              minHeight: c.hasBoundedHeight ? c.maxHeight : 0,
            ),
            child: Center(child: Padding(padding: const EdgeInsets.all(12), child: face)),
          ),
        ),
      );
    });
  }
}

/// Une alvéole : disque à la couleur de l'état, numéro de la conduite (« 3.2 » pour un sous-tube) et, dans un disque
/// assez grand, son taux d'occupation ([occupancy], %) ; cerclée de jaune si choisie.
class BoreTile extends StatelessWidget {
  const BoreTile({
    super.key,
    required this.color,
    required this.label,
    required this.chosen,
    required this.diameter,
    this.occupancy,
  });

  final Color color;
  final String label;
  final bool chosen;
  final double diameter;
  final double? occupancy;

  /// Diamètre à l'écran (px) à partir duquel le taux d'occupation s'écrit sous le numéro.
  static const occupancyDiameter = 52.0;

  @override
  Widget build(BuildContext context) {
    final ink = color.computeLuminance() > 0.45 ? Nge.text : Colors.white;
    final rate = occupancy;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: chosen ? Nge.yellow : Nge.text, width: chosen ? 4 : 1.5),
        boxShadow: chosen ? const [BoxShadow(color: Nge.slate, spreadRadius: 2)] : null,
      ),
      child: Center(
        child: FittedBox(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              label,
              style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: (diameter * 0.38).clamp(10, 18)),
            ),
            if (rate != null && rate > 0 && diameter >= occupancyDiameter)
              Text('${rate.round()} %', style: TextStyle(color: ink, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Alvéole à placer en miroir : disque en pointillé, teinté de l'état de sa conduite, son numéro ; mise en évidence
/// en jaune ([focused]) à l'arrivée d'un « Vers … ».
class MirrorTile extends StatelessWidget {
  const MirrorTile({super.key, required this.color, required this.label, required this.diameter, this.focused = false});

  final Color color;
  final String label;
  final double diameter;
  final bool focused;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedCirclePainter(fill: color.withValues(alpha: 0.35), stroke: focused ? Nge.amber : Nge.slate,
            width: focused ? 3 : 1.5),
        child: Center(
          child: FittedBox(
            child: Text(label,
                style: TextStyle(color: Nge.slate, fontWeight: FontWeight.w700, fontSize: (diameter * 0.38).clamp(10, 18))),
          ),
        ),
      );
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.fill, required this.stroke, required this.width});

  final Color fill;
  final Color stroke;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - width / 2;
    canvas.drawCircle(center, radius, Paint()..color = fill);
    final paint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    // tirets d'environ 6 px, au moins huit par tour
    final dashes = math.max(8, (2 * math.pi * radius / 9).floor());
    final step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), i * step, step * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.fill != fill || old.stroke != stroke || old.width != width;
}

/// Face à ses dimensions exactes (contour) et cellules carrées de 5 cm depuis le coin haut gauche, origine des
/// positions : la dernière cellule de chaque rangée et de chaque colonne est éventuellement partielle.
class _GridPainter extends CustomPainter {
  _GridPainter(this.scale);

  /// Échelle (px par m).
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final linePaint = Paint()
      ..color = Nge.rule
      ..strokeWidth = 1;
    final step = gridCell * scale;
    // pas de ligne sur le contour quand la face fait un nombre entier de cellules
    for (var i = 1; i * step < size.width - 0.5; i++) {
      canvas.drawLine(Offset(i * step, 0), Offset(i * step, size.height), linePaint);
    }
    for (var j = 1; j * step < size.height - 0.5; j++) {
      canvas.drawLine(Offset(0, j * step), Offset(size.width, j * step), linePaint);
    }
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Nge.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.scale != scale;
}

/// Légende des états, sous la grille (portrait) ou dans la colonne latérale (paysage), qui tient les marges sûres ;
/// [wide] (colonne latérale haute) : un état par ligne, en grand.
class _Legend extends StatelessWidget {
  const _Legend({required this.states, this.wide = false});

  final List<DuctState> states;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hint = Text(
        tr('Toucher la grille : placer une alvéole · toucher puis glisser : déplacer · double toucher : ouvrir'),
        style: wide ? t.bodyMedium : t.bodySmall);
    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final s in states)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                _Dot(color: s.color, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Text('${s.code} ${s.lib}', style: const TextStyle(fontSize: 17))),
              ]),
            ),
          const SizedBox(height: 8),
          hint,
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final s in states)
            Row(mainAxisSize: MainAxisSize.min, children: [
              _Dot(color: s.color),
              const SizedBox(width: 4),
              // à la ligne plutôt que de déborder (grands caractères)
              Flexible(child: Text('${s.code} ${s.lib}', style: const TextStyle(fontSize: 13))),
            ]),
        ]),
        const SizedBox(height: 4),
        hint,
      ]),
    );
  }
}

/// Choix en grille de [columns] colonnes égales, sur toute la largeur (colonne latérale haute).
class _Tiles extends StatelessWidget {
  const _Tiles({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final width = ((c.maxWidth - _gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(spacing: _gap, runSpacing: _gap, children: [
          for (final child in children) SizedBox(width: width, child: child),
        ]);
      });
}

/// Choix large, facile à toucher : pastille éventuelle ([dot]), texte ; fond et bord marqués quand il est choisi.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap, this.dot, this.center = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: Nge.text),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Nge.slate.withValues(alpha: 0.12) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? Nge.slate : Nge.border, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                if (dot != null) ...[_Dot(color: dot!, size: 20), const SizedBox(width: 10)],
                Expanded(child: text),
                if (selected && !center) const Icon(Icons.check, size: 20, color: Nge.slate),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Nge.text)),
      );
}

/// Alvéole choisie : destination (« Vers … » mène au support d'en face, [onFollow]), état, diamètre, sous-tubes
/// ([onSubduct]), câbles constatés et taux d'occupation, retrait ; [wide] (colonne latérale haute) : état et diamètre
/// en grandes cases, libellés entiers.
class _BorePanel extends StatelessWidget {
  const _BorePanel({
    required this.bore,
    required this.editor,
    required this.states,
    required this.onRemove,
    this.onSave,
    this.onFollow,
    this.onSubduct,
    this.onOtherCable,
    this.wide = false,
    this.actions = true,
  });

  final MaskBore bore;
  final MaskEditor editor;
  final List<DuctState> states;
  final void Function(MaskBore bore) onRemove;
  final VoidCallback? onSave;
  final void Function(MaskBore bore)? onFollow;
  final void Function(MaskBore bore)? onSubduct;
  final void Function(MaskBore bore)? onOtherCable;
  final bool wide;

  /// « Retirer du masque » et « Enregistrer » en bas du panneau ; faux : épinglés à part ([_BoreActions]).
  final bool actions;

  @override
  Widget build(BuildContext context) {
    final a = bore;
    final t = Theme.of(context).textTheme;
    final l = a.linear;
    final destination = l == null ? null : editor.destinations[l.id];
    // support d'en face supprimé : « Vers … » ne mène plus nulle part, et le panneau le dit
    final gone = destination?.abandoned ?? false;
    // marges sûres tenues par la disposition (sous la grille en portrait, colonne latérale en paysage)
    // « Vers … » : lien d'une touche vers le support d'en face, sur l'alvéole de la même conduite (ni carton ni
    // infobulle, qui en aurait l'air), sur sa ligne, avec le type et le pictogramme du support (notes rep10)
    final link = a.duct != null && destination != null && !gone && onFollow != null;
    // sous-tube : diamètres du sous-tubage ; alvéole : diamètres normalisés
    final diameters = {...a.subduct ? subductDiameters(editor.referenceData) : standardDiameters, ?a.diameter}.toList()
      ..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${a.subduct ? tr('Sous-tube {0}', [a.label]) : tr('Alvéole {0}', [a.label])}'
              '${link ? '' : ' · ${a.duct == null ? tr('conduite absente du paquet') : editor.linearLabel(l)}'}'
              '${gone ? ' · ${tr('support supprimé')}' : ''}${a.mirror ? ' · ${tr('miroir')}' : ''}',
              style: t.titleSmall,
            ),
          ),
          IconButton(
            tooltip: tr('Fermer'),
            icon: const Icon(Icons.close),
            onPressed: () => editor.select(null),
          ),
        ]),
        if (link) ...[
          SupportLink(target: destination, referenceData: editor.referenceData, onPressed: () => onFollow!(a)),
          const SizedBox(height: 8),
        ],
        if (a.duct != null && wide) ...[
          const SizedBox(height: 4),
          Text(tr('État'), style: t.titleSmall),
          const SizedBox(height: 6),
          _Tiles(columns: 2, children: [
            for (final s in states)
              _ChoiceTile(
                label: '${s.code} ${s.lib}',
                dot: s.color,
                selected: a.state == s.id,
                onTap: () => editor.setDuctState(a, s.id),
              ),
          ]),
          if (editor.occupied(a)) _OccupiedNote(bore: a, editor: editor),
          const SizedBox(height: 14),
          Text(tr('Diamètre (mm)'), style: t.titleSmall),
          const SizedBox(height: 6),
          _Tiles(columns: 4, children: [
            for (final d in diameters)
              _ChoiceTile(
                label: d.toStringAsFixed(0),
                center: true,
                selected: a.diameter == d,
                onTap: () => editor.setDiameter(a, d),
              ),
          ]),
          const SizedBox(height: 10),
        ] else if (a.duct != null) ...[
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final s in states)
              ChoiceChip(
                avatar: _Dot(color: s.color, size: 16),
                label: Text(s.code),
                tooltip: s.lib,
                selected: a.state == s.id,
                onSelected: (_) => editor.setDuctState(a, s.id),
              ),
          ]),
          if (editor.occupied(a)) _OccupiedNote(bore: a, editor: editor),
          const SizedBox(height: 6),
          // diamètres à la ligne : sur un téléphone, une rangée qui défile cachait les derniers (150)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Ø', style: t.titleSmall)),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final d in diameters)
                  ChoiceChip(
                    label: Text(d.toStringAsFixed(0)),
                    selected: a.diameter == d,
                    onSelected: (_) => editor.setDiameter(a, d),
                  ),
              ]),
            ),
          ]),
        ],
        if (a.duct != null) ...[
          const SizedBox(height: 10),
          _SubductSection(bore: a, editor: editor, states: states, onSubduct: onSubduct),
          const SizedBox(height: 10),
          _CableSection(bore: a, editor: editor, onOther: onOtherCable),
          const SizedBox(height: 6),
        ],
        if (actions) _BoreActions(bore: a, onRemove: onRemove, onSave: onSave),
      ]),
    );
  }
}

/// Alvéole occupée d'office (câbles, sous-tubes) : l'état ne peut pas repasser à vide (règle de FOA Explorer).
class _OccupiedNote extends StatelessWidget {
  const _OccupiedNote({required this.bore, required this.editor});

  final MaskBore bore;
  final MaskEditor editor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          editor.subductsOf(bore).isNotEmpty
              ? tr('Occupée : l\'alvéole est sous-tubée.')
              : tr('Occupée : l\'alvéole porte des câbles.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

/// Sous-tubage : pour un sous-tube, son alvéole ; pour une alvéole sous-tubée, ses sous-tubes, chacun choisi d'une
/// touche (plus commode que dans la grille, où ils sont petits) ; sinon « Sous-tuber » si des sous-tubes y tiennent.
class _SubductSection extends StatelessWidget {
  const _SubductSection({required this.bore, required this.editor, required this.states, this.onSubduct});

  final MaskBore bore;
  final MaskEditor editor;
  final List<DuctState> states;
  final void Function(MaskBore bore)? onSubduct;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = bore;
    final colors = {for (final s in states) s.id: s.color};
    if (a.subduct) {
      return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        Text(tr('Sous-tube de l\'alvéole {0}', [a.parentNumber ?? '?']), style: t.bodyMedium),
        if (editor.bores().any((b) => b.cd == a.parent))
          TextButton(onPressed: () => editor.select(a.parent), child: Text(tr('Voir l\'alvéole'))),
        // le glisser-déposer imbrique ; ce bouton défait l'imbrication
        TextButton(onPressed: () => editor.unnest(a), child: Text(tr('Détacher de l\'alvéole'))),
      ]);
    }
    final kids = editor.children(a);
    // sous-tubes de la conduite que cette chambre n'a pas encore placés (sous-tubage fait dans la chambre d'en face)
    final missing = editor.pendingSubducts(a);
    if (kids.isNotEmpty || editor.subductsOf(a).isNotEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Sous-tubes'), style: t.titleSmall),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final k in kids)
            ActionChip(
              avatar: _Dot(color: colors[k.state] ?? Colors.white, size: 16),
              label: Text('${k.label} · ${k.diameter?.toStringAsFixed(0) ?? '?'}'),
              tooltip: tr('Choisir le sous-tube {0}', [k.label]),
              onPressed: () => editor.select(k.cd),
            ),
          if (missing > 0)
            TextButton.icon(
              icon: const Icon(Icons.flip),
              label: Text(trn(missing, 'Placer {0} sous-tube en miroir', 'Placer {0} sous-tubes en miroir')),
              onPressed: () => editor.placeSubductMirrors(a),
            ),
        ]),
      ]);
    }
    final fits = subductDiameters(editor.referenceData).any((d) => MaskEditor.subductFits(a.diameter, 3, d));
    if (!fits || onSubduct == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.bubble_chart_outlined),
        label: Text(tr('Sous-tuber')),
        onPressed: () => onSubduct!(a),
      ),
    );
  }
}

/// Diamètre en mm sans décimale inutile : « 10 », « 10,5 ».
String _mm(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v'.replaceAll('.', ',');

/// Câbles constatés dans la conduite (FOA Explorer, « Occupation alvéole ») : une pastille par ligne (diamètre,
/// nature, nombre ; la toucher retire un câble), la jauge du taux d'occupation, puis l'ajout d'un câble d'une touche :
/// nature (Fo, Cu, retenue pour la saisie en série) et diamètre parmi ceux de FOA Explorer, ou un autre ([onOther]).
class _CableSection extends StatelessWidget {
  const _CableSection({required this.bore, required this.editor, this.onOther});

  final MaskBore bore;
  final MaskEditor editor;
  final void Function(MaskBore bore)? onOther;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = bore;
    final cables = cablesOf(a.duct);
    final rate = occupancyOf(a.duct, editor.referenceData);
    final over = (rate ?? 0) > 100;
    String name(Map<String, dynamic> c) {
      final mat = editor.referenceData.cable((c['MAT_KEY'] as num?)?.toInt())?['MAT_LIB'];
      final d = (c['CDC_DIAM'] as num?)?.toDouble();
      return [
        if (mat != null) '$mat',
        if (d != null) '${_mm(d)} mm',
        if (c['CDC_NATURE'] != null) natureLabel(c['CDC_NATURE']),
      ].join(' · ');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // à la ligne plutôt que de déborder (grands caractères)
      Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
        Text(trn(a.nbCables, '{0} câble', '{0} câbles'), style: t.titleSmall),
        Text(rate == null ? tr('Occupation inconnue') : tr('Occupation {0} %', [rate.round()]),
            style: t.bodyMedium?.copyWith(color: over ? Nge.red : null, fontWeight: over ? FontWeight.w700 : null)),
      ]),
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: ((rate ?? 0) / 100).clamp(0.0, 1.0),
        minHeight: 6,
        borderRadius: BorderRadius.circular(3),
        color: over ? Nge.red : Nge.petrolBlue,
        backgroundColor: Nge.rule,
        semanticsLabel: tr('Taux d\'occupation'),
      ),
      if (cables.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final c in cables)
            InputChip(
              label: Text('${name(c)} × ${(c['CDC_NB'] as num?)?.toInt() ?? 1}'),
              deleteButtonTooltipMessage: tr('Retirer un câble'),
              onDeleted: () => editor.removeCable(a, c),
            ),
        ]),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [for (final n in cableNatures) ButtonSegment(value: n, label: Text(natureLabel(n)))],
          selected: {editor.cableNature},
          onSelectionChanged: (s) => editor.setCableNature(s.first),
        ),
        for (final d in cableDiameters)
          ActionChip(
            label: Text('+${_mm(d)}'),
            tooltip: tr('Ajouter un câble de {0} mm', [_mm(d)]),
            onPressed: () => editor.addCable(a, d, editor.cableNature),
          ),
        if (onOther != null) ActionChip(label: Text(tr('Autre Ø')), onPressed: () => onOther!(a)),
      ]),
    ]);
  }
}

/// Actions de l'alvéole choisie : la retirer du masque ([onRemove]), enregistrer les masques ([onSave] null : rien à
/// enregistrer).
class _BoreActions extends StatelessWidget {
  const _BoreActions({required this.bore, required this.onRemove, this.onSave});

  final MaskBore bore;
  final void Function(MaskBore bore) onRemove;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) =>
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Nge.red),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Retirer du masque')),
          onPressed: () => onRemove(bore),
        ),
        if (onSave != null)
          FilledButton.icon(onPressed: onSave, icon: const Icon(Icons.save), label: Text(tr('Enregistrer'))),
      ]);
}

/// Miroir ouvert (bouton Miroir, notes rep15), au-dessus de la légende : face d'en face d'où viennent les alvéoles
/// proposées en pointillé sur la face affichée, leur nombre ; « Tout placer » ([onPlaceAll]) les valide d'un coup,
/// « Changer » ([onChange]) prend une autre face d'en face, la croix ([onClose]) ferme le miroir. Toucher une alvéole
/// en pointillé la valide seule ; changer de face affichée y applique le même miroir.
class _MirrorBanner extends StatelessWidget {
  const _MirrorBanner({
    required this.source,
    required this.count,
    required this.face,
    required this.onClose,
    this.onPlaceAll,
    this.onChange,
    this.wide = false,
  });

  /// « C598 · face B ».
  final String source;
  final int count;

  /// Face affichée, où le miroir s'applique.
  final String face;
  final VoidCallback onClose;
  final VoidCallback? onPlaceAll;
  final VoidCallback? onChange;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Nge.yellow.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Nge.yellow),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 10), child: Icon(Icons.flip, color: Nge.amber, size: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Miroir de {0} sur la face {1}', [source, face]), style: wide ? t.titleMedium : t.titleSmall),
                    Text(
                      count == 0
                          ? tr('Rien à placer sur cette face.')
                          : '${trn(count, '{0} alvéole à valider', '{0} alvéoles à valider')} · '
                              '${tr('en pointillé dans la grille, une touche la place ici.')}',
                      style: wide ? t.bodyMedium : t.bodySmall,
                    ),
                  ]),
                ),
              ),
              IconButton(tooltip: tr('Fermer le miroir'), icon: const Icon(Icons.close), onPressed: onClose),
            ]),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              if (onChange != null) TextButton(onPressed: onChange, child: Text(tr('Changer'))),
              if (onPlaceAll != null)
                FilledButton.tonalIcon(onPressed: onPlaceAll, icon: const Icon(Icons.flip), label: Text(tr('Tout placer'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Sous-tubage d'une alvéole : nombre de sous-tubes (3 en triangle, 4 en carré, gabarits de FOA Explorer) et leur
/// diamètre, parmi ceux qui tiennent dans l'alvéole ([MaskEditor.subductFits]). Rend (nombre, diamètre en mm).
class _SubductDialog extends StatefulWidget {
  const _SubductDialog({required this.bore, required this.diameters});

  final MaskBore bore;
  final List<double> diameters;

  @override
  State<_SubductDialog> createState() => _SubductDialogState();
}

class _SubductDialogState extends State<_SubductDialog> {
  late int _count = widget.diameters.any((d) => _fits(4, d)) ? 4 : 3;
  late double? _diameter = widget.diameters.where((d) => _fits(_count, d)).lastOrNull;

  bool _fits(int count, double d) => MaskEditor.subductFits(widget.bore.diameter, count, d);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = _diameter;
    return AlertDialog(
      title: Text(tr('Sous-tuber l\'alvéole {0}', [widget.bore.label])),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Nombre de sous-tubes'), style: t.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final n in const [3, 4])
                ButtonSegment(value: n, label: Text('$n'), enabled: widget.diameters.any((d) => _fits(n, d))),
            ],
            selected: {_count},
            onSelectionChanged: (s) => setState(() {
              _count = s.first;
              if (d == null || !_fits(_count, d)) _diameter = widget.diameters.where((x) => _fits(_count, x)).lastOrNull;
            }),
          ),
          const SizedBox(height: 12),
          Text(tr('Diamètre (mm)'), style: t.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final x in widget.diameters)
              ChoiceChip(
                label: Text(x.toStringAsFixed(0)),
                selected: d == x,
                onSelected: _fits(_count, x) ? (_) => setState(() => _diameter = x) : null,
              ),
          ]),
          const SizedBox(height: 8),
          Text(tr('Alvéole de {0} mm : seuls les sous-tubes qui y tiennent sont proposés.',
              [widget.bore.diameter?.toStringAsFixed(0) ?? '?']), style: t.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(
          onPressed: d == null ? null : () => Navigator.pop(context, (_count, d)),
          child: Text(tr('Sous-tuber')),
        ),
      ],
    );
  }
}

/// Diamètre d'un câble autre que ceux proposés, en mm (au demi-millimètre, de 1 à 150) ; null si l'on annule.
class _CableDiameterDialog extends StatefulWidget {
  const _CableDiameterDialog();

  @override
  State<_CableDiameterDialog> createState() => _CableDiameterDialogState();
}

class _CableDiameterDialogState extends State<_CableDiameterDialog> {
  final _txtDiameter = TextEditingController();

  @override
  void dispose() {
    _txtDiameter.dispose();
    super.dispose();
  }

  double? get _value {
    final v = double.tryParse(_txtDiameter.text.replaceAll(',', '.').trim());
    if (v == null || !v.isFinite || v < 1 || v > 150) return null;
    return (v * 2).round() / 2;
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    return AlertDialog(
      title: Text(tr('Diamètre du câble')),
      content: TextField(
        controller: _txtDiameter,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          suffixText: 'mm',
          errorText: _txtDiameter.text.isNotEmpty && v == null ? tr('De {0} à {1} mm', [1, 150]) : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(onPressed: v == null ? null : () => Navigator.pop(context, v), child: Text(tr('Ajouter'))),
      ],
    );
  }
}

/// Création d'une alvéole : parcours de la conduite (destination), diamètre, état ; [wide] (volet de droite, en
/// paysage) : diamètre et état en grandes cases, comme le panneau de l'alvéole.
class _NewBore extends StatefulWidget {
  const _NewBore({
    required this.editor,
    required this.states,
    required this.linear,
    required this.diameter,
    required this.state,
    this.wide = false,
  });

  final MaskEditor editor;
  final List<DuctState> states;

  /// Parcours proposé ; null : sans destination connue (conduite portée par la chambre).
  final GeoObject? linear;
  final double diameter;
  final int state;
  final bool wide;

  @override
  State<_NewBore> createState() => _NewBoreState();
}

class _NewBoreState extends State<_NewBore> {
  late GeoObject? _linear = widget.linear;
  late double _diameter = widget.diameter;
  late int _state = widget.state;

  @override
  Widget build(BuildContext context) {
    final e = widget.editor;
    final t = Theme.of(context).textTheme;
    // « Placer l'alvéole » toujours visible, sous la partie qui défile (nombreux parcours, écran peu haut)
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Nouvelle alvéole · face {0}', [e.face]), style: t.titleMedium),
              const SizedBox(height: 8),
              Text(tr('Parcours'), style: t.titleSmall),
              RadioGroup<GeoObject?>(
                groupValue: _linear,
                onChanged: (l) => setState(() => _linear = l),
                child: Column(children: [
                  for (final l in [...e.linears, null])
                    RadioListTile<GeoObject?>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: l,
                      title: Text(e.linearLabel(l)),
                      subtitle: Text(trn(MaskEditor.ductsOf(l ?? e.chamber).length, '{0} conduite', '{0} conduites')),
                    ),
                ]),
              ),
              Text(tr('Diamètre (mm)'), style: t.titleSmall),
              if (widget.wide) ...[
                const SizedBox(height: 6),
                _Tiles(columns: 4, children: [
                  for (final d in standardDiameters)
                    _ChoiceTile(
                      label: d.toStringAsFixed(0),
                      center: true,
                      selected: _diameter == d,
                      onTap: () => setState(() => _diameter = d),
                    ),
                ]),
              ] else
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final d in standardDiameters)
                    ChoiceChip(
                      label: Text(d.toStringAsFixed(0)),
                      selected: _diameter == d,
                      onSelected: (_) => setState(() => _diameter = d),
                    ),
                ]),
              const SizedBox(height: 8),
              Text(tr('État'), style: t.titleSmall),
              if (widget.wide) ...[
                const SizedBox(height: 6),
                _Tiles(columns: 2, children: [
                  for (final s in widget.states)
                    _ChoiceTile(
                      label: '${s.code} ${s.lib}',
                      dot: s.color,
                      selected: _state == s.id,
                      onTap: () => setState(() => _state = s.id),
                    ),
                ]),
              ] else
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final s in widget.states)
                    ChoiceChip(
                      avatar: _Dot(color: s.color, size: 16),
                      label: Text(s.lib),
                      selected: _state == s.id,
                      onSelected: (_) => setState(() => _state = s.id),
                    ),
                ]),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: FilledButton(
            onPressed: () => Navigator.pop(context, (_linear, _diameter, _state)),
            child: Text(tr('Placer l\'alvéole')),
          ),
        ),
      ]),
    );
  }
}

/// Dimensions de la face affichée, en centimètres : largeur et hauteur saisies, ou celles de la chambre quand elles
/// sont connues (largeur pour A et B, longueur pour C et D, hauteur de la chambre). Rend (largeur, hauteur) en m,
/// au millimètre près ; null si l'on annule.
class _FaceSizeDialog extends StatefulWidget {
  const _FaceSizeDialog({required this.editor});

  final MaskEditor editor;

  @override
  State<_FaceSizeDialog> createState() => _FaceSizeDialogState();
}

class _FaceSizeDialogState extends State<_FaceSizeDialog> {
  late final _txtWidth = TextEditingController(text: centimeters(widget.editor.width));
  late final _txtHeight = TextEditingController(text: centimeters(widget.editor.height));

  @override
  void dispose() {
    _txtWidth.dispose();
    _txtHeight.dispose();
    super.dispose();
  }

  /// Dimension saisie en cm, rendue en m au millimètre près ; null si elle est illisible ou hors des bornes.
  static double? _meters(TextEditingController t) {
    final cm = double.tryParse(t.text.replaceAll(',', '.').trim());
    if (cm == null || !cm.isFinite) return null;
    final m = (cm * 10).round() / 1000;
    return m < minFaceSize || m > maxFaceSize ? null : m;
  }

  Widget _field(TextEditingController t, String label) => TextField(
        controller: t,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'cm',
          errorText: _meters(t) == null
              ? tr('De {0} à {1} cm', [centimeters(minFaceSize), centimeters(maxFaceSize)])
              : null,
        ),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final e = widget.editor;
    final chamber = e.chamberSize();
    final width = _meters(_txtWidth), height = _meters(_txtHeight);
    final small = Theme.of(context).textTheme.bodySmall;
    String known(double? m) => m == null ? '?' : centimeters(m);
    return AlertDialog(
      title: Text(tr('Dimensions de la face {0}', [e.face])),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _field(_txtWidth, tr('Largeur')),
            _field(_txtHeight, tr('Hauteur')),
            if (chamber.width != null || chamber.height != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.straighten),
                label: Text(tr('Dimensions de la chambre ({0})', ['${known(chamber.width)} × ${known(chamber.height)} cm'])),
                onPressed: () => setState(() {
                  if (chamber.width != null) _txtWidth.text = centimeters(chamber.width!);
                  if (chamber.height != null) _txtHeight.text = centimeters(chamber.height!);
                }),
              ),
            if (e.bores().isNotEmpty) Text(tr('Les alvéoles restent centrées dans la face.'), style: small),
            Text(tr('Une grande face se parcourt en faisant glisser la grille.'), style: small),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(
          onPressed: width == null || height == null ? null : () => Navigator.pop(context, (width, height)),
          child: Text(tr('Valider')),
        ),
      ],
    );
  }
}
