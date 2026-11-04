import 'dart:math' as math;

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
/// alvéole par conduite, en vraie grandeur, colorée selon son état. Toucher la grille place une alvéole, toucher une
/// alvéole la sélectionne, l'appui long la déplace. Le choix de la face au-dessus de la grille ; en portrait, le
/// panneau de l'alvéole (ou la légende) dessous ; en paysage (tablette, Windows), la grille à gauche, le panneau ou la
/// légende dans une colonne à droite ([maskSideWidth]), où se déplie aussi la création d'une alvéole.
class MaskScreen extends StatefulWidget {
  const MaskScreen({super.key, required this.chamber, this.face, this.selection});

  final GeoObject chamber;

  /// Face ouverte (A à D) ; par défaut la première face relevée.
  final String? face;

  /// Alvéole sélectionnée à l'ouverture (CD_KEY) : arrivée d'un parcours suivi depuis un autre support, chambre
  /// rouverte par le menu ⋮.
  final String? selection;

  @override
  State<MaskScreen> createState() => _MaskScreenState();
}

class _MaskScreenState extends State<MaskScreen> {
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
      // disparu, et le premier toucher de la grille ne servirait qu'à la désélectionner)
      final s = widget.selection;
      if (mounted && s != null && _editor.bores().any((a) => a.cd == s)) _editor.select(s);
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
    final r = _route;
    if (r != null) screenStack.note(r, tab: 'masques:${_editor.face}', selection: _editor.selection);
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
        final n = bores.length;
        final sel = _editor.selectedBore;
        // la chambre relue dans le dépôt au chargement de la session (l'objet passé a pu vieillir)
        final chamber = _editor.chamber;
        return EntryScreen(
          changed: _editor.changed,
          message: tr('Les masques modifiés ne seront pas enregistrés.'),
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
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          for (final f in chamberFaces)
                            ButtonSegment(
                              value: f,
                              label: Text(
                                  _editor.bores(f).isEmpty ? f : '$f · ${_editor.bores(f).length}'),
                            ),
                        ],
                        selected: {_editor.face},
                        onSelectionChanged: (s) => _editor.selectFace(s.first),
                      ),
                    );
                    final grid = MaskGrid(
                      editor: _editor,
                      states: states,
                      onPlace: _add,
                    );
                    // [wide] : colonne latérale haute (tablette, Windows en paysage), légende et choix en grand ;
                    // [actions] : « Retirer du masque » et « Enregistrer » dans le panneau (sinon épinglés à part)
                    Widget panelOf({bool wide = false, bool actions = true}) => sel == null
                        ? _Legend(states: states, wide: wide)
                        : _BorePanel(
                            bore: sel,
                            editor: _editor,
                            states: states,
                            onSave: _editor.changed ? _save : null,
                            onFollow: _follow,
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
                                  child: _BoreActions(bore: sel, editor: _editor, onSave: _editor.changed ? _save : null),
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
                              child: _BoreActions(bore: sel, editor: _editor, onSave: _editor.changed ? _save : null),
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
/// zoom de la vue, ajout au toucher, déplacement d'une alvéole par appui long. Positions en m.
class MaskGrid extends StatefulWidget {
  const MaskGrid({super.key, required this.editor, required this.states, required this.onPlace});

  final MaskEditor editor;
  final List<DuctState> states;

  /// Toucher hors alvéole : centre de la nouvelle alvéole, en m depuis la gauche et le haut de la face.
  final void Function(double x, double y) onPlace;

  @override
  State<MaskGrid> createState() => _MaskGridState();
}

class _MaskGridState extends State<MaskGrid> {
  final _gridKey = GlobalKey();

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
      final face = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (e.selection != null) {
            e.select(null);
          } else {
            widget.onPlace(d.localPosition.dx / scale, d.localPosition.dy / scale);
          }
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
                final touch = math.max(d, _minTouch);
                final chosen = a.cd == e.selection;
                return Positioned(
                  left: a.x * scale - touch / 2,
                  top: a.y * scale - touch / 2,
                  width: touch,
                  height: touch,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => e.select(chosen ? null : a.cd),
                    onLongPressStart: (_) => e.select(a.cd),
                    onLongPressMoveUpdate: (m) {
                      final p = _toFace(m.globalPosition, scale);
                      if (p != null) e.move(a, p.dx, p.dy);
                    },
                    child: Center(
                      child: SizedBox.square(
                        dimension: d,
                        child: BoreTile(
                          color: a.duct == null ? Nge.hoverPressed : colors[a.state] ?? Colors.white,
                          number: a.number,
                          chosen: chosen,
                          diameter: d,
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

/// Une alvéole : disque à la couleur de l'état, numéro de la conduite ; cerclée de jaune si choisie.
class BoreTile extends StatelessWidget {
  const BoreTile({super.key, required this.color, required this.number, required this.chosen, required this.diameter});

  final Color color;
  final int? number;
  final bool chosen;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final ink = color.computeLuminance() > 0.45 ? Nge.text : Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: chosen ? Nge.yellow : Nge.text, width: chosen ? 4 : 1.5),
        boxShadow: chosen ? const [BoxShadow(color: Nge.slate, spreadRadius: 2)] : null,
      ),
      child: Center(
        child: Text(
          number == null ? '?' : '$number',
          style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: (diameter * 0.38).clamp(10, 18)),
        ),
      ),
    );
  }
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
    final hint = Text(tr('Toucher la grille pour placer une alvéole · appui long pour la déplacer'),
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

/// Alvéole choisie : destination (« Vers … » mène au support d'en face, [onFollow]), état, diamètre, retrait ;
/// [wide] (colonne latérale haute) : état et diamètre en grandes cases, libellés entiers.
class _BorePanel extends StatelessWidget {
  const _BorePanel({
    required this.bore,
    required this.editor,
    required this.states,
    this.onSave,
    this.onFollow,
    this.wide = false,
    this.actions = true,
  });

  final MaskBore bore;
  final MaskEditor editor;
  final List<DuctState> states;
  final VoidCallback? onSave;
  final void Function(MaskBore bore)? onFollow;
  final bool wide;

  /// « Retirer du masque » et « Enregistrer » en bas du panneau ; faux : épinglés à part ([_BoreActions]).
  final bool actions;

  @override
  Widget build(BuildContext context) {
    final a = bore;
    final t = Theme.of(context).textTheme;
    final l = a.linear;
    final cables = a.nbCables;
    final destination = l == null ? null : editor.destinations[l.id];
    // support d'en face supprimé : « Vers … » ne mène plus nulle part, et le panneau le dit
    final gone = destination?.abandoned ?? false;
    final rest = '${cables > 0 ? ' · ${trn(cables, '{0} câble', '{0} câbles')}' : ''}${a.mirror ? ' · ${tr('miroir')}' : ''}';
    // marges sûres tenues par la disposition (sous la grille en portrait, colonne latérale en paysage)
    // « Vers … » : lien d'une touche vers le support d'en face, sur l'alvéole de la même conduite (ni carton ni
    // infobulle, qui en aurait l'air), sur sa ligne, avec le type et le pictogramme du support (notes rep10)
    final link = a.duct != null && destination != null && !gone && onFollow != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${tr('Alvéole {0}', [a.number ?? '?'])}'
              '${link ? '' : ' · ${a.duct == null ? tr('conduite absente du paquet') : editor.linearLabel(l)}'}'
              '${gone ? ' · ${tr('support supprimé')}' : ''}$rest',
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
          const SizedBox(height: 14),
          Text(tr('Diamètre (mm)'), style: t.titleSmall),
          const SizedBox(height: 6),
          _Tiles(columns: 4, children: [
            for (final d in {...standardDiameters, ?a.diameter}.toList()..sort())
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
          const SizedBox(height: 6),
          // diamètres à la ligne : sur un téléphone, une rangée qui défile cachait les derniers (150)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Ø', style: t.titleSmall)),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final d in {...standardDiameters, ?a.diameter}.toList()..sort())
                  ChoiceChip(
                    label: Text(d.toStringAsFixed(0)),
                    selected: a.diameter == d,
                    onSelected: (_) => editor.setDiameter(a, d),
                  ),
              ]),
            ),
          ]),
        ],
        if (actions) _BoreActions(bore: a, editor: editor, onSave: onSave),
      ]),
    );
  }
}

/// Actions de l'alvéole choisie : la retirer du masque, enregistrer les masques ([onSave] null : rien à enregistrer).
class _BoreActions extends StatelessWidget {
  const _BoreActions({required this.bore, required this.editor, this.onSave});

  final MaskBore bore;
  final MaskEditor editor;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) =>
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Nge.red),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Retirer du masque')),
          onPressed: () => editor.remove(bore),
        ),
        if (onSave != null)
          FilledButton.icon(onPressed: onSave, icon: const Icon(Icons.save), label: Text(tr('Enregistrer'))),
      ]);
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
