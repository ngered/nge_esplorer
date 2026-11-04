import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../data/visuals.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../screens/gallery_screen.dart';
import '../../theme.dart';
import '../../widgets/bottom_bar.dart';
import '../../widgets/support_bar.dart';
import '../../widgets/entry_screen.dart';
import '../../widgets/screen_title.dart';
import 'mask_editor.dart';

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

/// Masques d'une chambre (maquette Figma `support_sout_saisie_grid`) : une face en plein écran, grille plus grande
/// que l'écran parcourue par déplacement ; une alvéole par conduite, colorée selon son état. Toucher la grille place
/// une alvéole, toucher une alvéole la sélectionne, l'appui long la déplace.
class MaskScreen extends StatefulWidget {
  const MaskScreen({super.key, required this.chamber, this.face});

  final GeoObject chamber;

  /// Face ouverte (A à D) ; par défaut la première face relevée.
  final String? face;

  @override
  State<MaskScreen> createState() => _MaskScreenState();
}

class _MaskScreenState extends State<MaskScreen> {
  late final MaskEditor _editor;

  /// Derniers choix à la création d'une alvéole (saisie en série) ; parcours null : sans destination connue.
  GeoObject? _lastLinear;
  bool _routeChosen = false;
  double _lastDiameter = 45;
  int _lastState = 0;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    _editor = MaskEditor(app.repo, widget.chamber, author: app.author, face: widget.face)..load();
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppProvider>();
    await _editor.validate(app.referenceData);
    await app.afterWrite();
    if (mounted) showSaved(context);
  }

  /// Place une alvéole en ([x], [y]) : linéaire de la conduite (ou sans destination connue), diamètre et état.
  Future<void> _add(double x, double y) async {
    final states = ductStates(context.read<AppProvider>().referenceData);
    final last = _lastLinear;
    final choice = await showModalBottomSheet<(GeoObject?, double, int)>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _NewBore(
        editor: _editor,
        states: states,
        linear: _routeChosen && (last == null || _editor.linears.contains(last))
            ? last
            : _editor.linears.firstOrNull,
        diameter: _lastDiameter,
        state: _lastState,
      ),
    );
    if (choice == null) return;
    final (linear, diameter, state) = choice;
    _lastLinear = linear;
    _routeChosen = true;
    _lastDiameter = diameter;
    _lastState = state;
    _editor.add(linear: linear, x: x, y: y, diameter: diameter, state: state);
  }

  /// Ajout depuis la barre basse : au centre de la face, décalé s'il y est déjà une alvéole.
  void _addAtCenter() {
    var x = _editor.columns / 2, y = _editor.rows / 2;
    while (_editor.bores().any((a) => (a.x - x).abs() < 0.5 && (a.y - y).abs() < 0.5)) {
      x += 1;
      if (x > _editor.columns - 0.5) (x, y) = (0.5, y + 1);
    }
    _add(x, y);
  }

  Future<void> _resize() async {
    var col = _editor.columns, row = _editor.rows;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: Text(tr('Grille de la face {0}', [_editor.face])),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _Counter(label: tr('Colonnes'), value: col, onChanged: (v) => setDialogState(() => col = v)),
            _Counter(label: tr('Lignes'), value: row, onChanged: (v) => setDialogState(() => row = v)),
            const SizedBox(height: 8),
            Text(tr('Une grande face se parcourt en faisant glisser la grille.'), style: const TextStyle(fontSize: 13)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Valider'))),
          ],
        ),
      ),
    );
    if (ok == true && (col != _editor.columns || row != _editor.rows)) _editor.resize(col, row);
  }

  Future<void> _photos() async {
    final app = context.read<AppProvider>();
    final chamber = await app.repo.object(widget.chamber.id) ?? widget.chamber;
    final v = Visual.of(chamber, app.referenceData).where((v) => v.code == _editor.face).firstOrNull;
    if (!mounted) return;
    if (v == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Pas de visuel attendu pour la face {0}', [_editor.face]))));
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
        return EntryScreen(
          changed: _editor.changed,
          message: tr('Les masques modifiés ne seront pas enregistrés.'),
          child: Scaffold(
            appBar: AppBar(
              title: ScreenTitle(
                widget.chamber.lib ?? widget.chamber.id,
                trn(n, 'masque {1} · {0} alvéole', 'masque {1} · {0} alvéoles', [_editor.face]),
              ),
              actions: [
                IconButton(tooltip: tr('Photos de la face'), icon: const Icon(Icons.photo_library_outlined), onPressed: _photos),
                IconButton(tooltip: tr('Taille de la grille'), icon: const Icon(Icons.aspect_ratio), onPressed: _resize),
              ],
            ),
            bottomNavigationBar: SupportBar(
              object: widget.chamber,
              inModule: true,
              addItem: BarItem(
                icon: Icons.add_circle_outline,
                label: tr('Alvéole'),
                onPressed: _editor.loaded ? _addAtCenter : null,
              ),
            ),
            floatingActionButton: sel == null ? saveButton(visible: _editor.changed, onPressed: _save) : null,
            body: !_editor.loaded
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    Padding(
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
                    ),
                    Expanded(
                      child: MaskGrid(
                        editor: _editor,
                        states: states,
                        onPlace: _add,
                      ),
                    ),
                    const Divider(height: 1),
                    if (sel == null)
                      _Legend(states: states)
                    else
                      _BorePanel(
                        bore: sel,
                        editor: _editor,
                        states: states,
                        onSave: _editor.changed ? _save : null,
                      ),
                  ]),
          ),
        );
      },
    );
  }
}

/// Grille d'une face : cellules, alvéoles ; déplacement et zoom de la vue, ajout au toucher, déplacement d'une
/// alvéole par appui long.
class MaskGrid extends StatefulWidget {
  const MaskGrid({super.key, required this.editor, required this.states, required this.onPlace});

  final MaskEditor editor;
  final List<DuctState> states;
  final void Function(double x, double y) onPlace;

  @override
  State<MaskGrid> createState() => _MaskGridState();
}

class _MaskGridState extends State<MaskGrid> {
  final _gridKey = GlobalKey();

  /// Point de la grille (en cellules) sous une position de l'écran.
  Offset? _toCells(Offset global, double cell) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(global) / cell;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.editor;
    return LayoutBuilder(builder: (context, c) {
      final cell = ((c.maxWidth - 24) / e.columns).clamp(40.0, 72.0);
      final width = cell * e.columns, height = cell * e.rows;
      final colors = {for (final s in widget.states) s.id: s.color};
      return ColoredBox(
        color: Nge.barBackground,
        child: InteractiveViewer(
          constrained: false,
          minScale: 0.4,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(48),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (e.selection != null) {
                  e.select(null);
                } else {
                  widget.onPlace(d.localPosition.dx / cell, d.localPosition.dy / cell);
                }
              },
              child: SizedBox(
                key: _gridKey,
                width: width,
                height: height,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _GridPainter(e.columns, e.rows, cell)),
                  ),
                  for (final a in e.bores())
                    () {
                      final d = diameterInCells(a.diameter) * cell;
                      final chosen = a.cd == e.selection;
                      return Positioned(
                        left: a.x * cell - d / 2,
                        top: a.y * cell - d / 2,
                        width: d,
                        height: d,
                        child: GestureDetector(
                          onTap: () => e.select(chosen ? null : a.cd),
                          onLongPressStart: (_) => e.select(a.cd),
                          onLongPressMoveUpdate: (m) {
                            final p = _toCells(m.globalPosition, cell);
                            if (p != null) e.move(a, p.dx, p.dy);
                          },
                          child: BoreTile(
                            color: a.duct == null ? Nge.hoverPressed : colors[a.state] ?? Colors.white,
                            number: a.number,
                            chosen: chosen,
                            diameter: d,
                          ),
                        ),
                      );
                    }(),
                ]),
              ),
            ),
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

class _GridPainter extends CustomPainter {
  _GridPainter(this.columns, this.rows, this.cell);

  final int columns, rows;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final linePaint = Paint()
      ..color = Nge.rule
      ..strokeWidth = 1;
    for (var i = 1; i < columns; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), linePaint);
    }
    for (var j = 1; j < rows; j++) {
      canvas.drawLine(Offset(0, j * cell), Offset(size.width, j * cell), linePaint);
    }
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Nge.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.columns != columns || old.rows != rows || old.cell != cell;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.states});

  final List<DuctState> states;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 4, children: [
              for (final s in states)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _Dot(color: s.color),
                  const SizedBox(width: 4),
                  Text('${s.code} ${s.lib}', style: const TextStyle(fontSize: 13)),
                ]),
            ]),
            const SizedBox(height: 4),
            Text(tr('Toucher la grille pour placer une alvéole · appui long pour la déplacer'),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
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

/// Alvéole choisie : destination, état, diamètre, retrait.
class _BorePanel extends StatelessWidget {
  const _BorePanel({required this.bore, required this.editor, required this.states, this.onSave});

  final MaskBore bore;
  final MaskEditor editor;
  final List<DuctState> states;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final a = bore;
    final t = Theme.of(context).textTheme;
    final l = a.linear;
    final cables = a.nbCables;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${tr('Alvéole {0}', [a.number ?? '?'])} · '
                '${a.duct == null ? tr('conduite absente du paquet') : editor.linearLabel(l)}'
                '${cables > 0 ? ' · ${trn(cables, '{0} câble', '{0} câbles')}' : ''}${a.mirror ? ' · ${tr('miroir')}' : ''}',
                style: t.titleSmall,
              ),
            ),
            IconButton(
              tooltip: tr('Fermer'),
              icon: const Icon(Icons.close),
              onPressed: () => editor.select(null),
            ),
          ]),
          if (a.duct != null) ...[
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Text('Ø', style: t.titleSmall),
                const SizedBox(width: 6),
                for (final d in {...standardDiameters, ?a.diameter}.toList()..sort())
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(d.toStringAsFixed(0)),
                      selected: a.diameter == d,
                      onSelected: (_) => editor.setDiameter(a, d),
                    ),
                  ),
              ]),
            ),
          ],
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Nge.red),
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('Retirer du masque')),
              onPressed: () => editor.remove(a),
            ),
            if (onSave != null)
              FilledButton.icon(onPressed: onSave, icon: const Icon(Icons.save), label: Text(tr('Enregistrer'))),
          ]),
        ]),
      ),
    );
  }
}

/// Création d'une alvéole : parcours de la conduite (destination), diamètre, état.
class _NewBore extends StatefulWidget {
  const _NewBore({
    required this.editor,
    required this.states,
    required this.linear,
    required this.diameter,
    required this.state,
  });

  final MaskEditor editor;
  final List<DuctState> states;

  /// Parcours proposé ; null : sans destination connue (conduite portée par la chambre).
  final GeoObject? linear;
  final double diameter;
  final int state;

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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final s in widget.states)
              ChoiceChip(
                avatar: _Dot(color: s.color, size: 16),
                label: Text(s.lib),
                selected: _state == s.id,
                onSelected: (_) => setState(() => _state = s.id),
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_linear, _diameter, _state)),
            child: Text(tr('Placer l\'alvéole')),
          ),
        ]),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label)),
        IconButton(
            tooltip: tr('Moins'), icon: const Icon(Icons.remove), onPressed: value > 2 ? () => onChanged(value - 1) : null),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
            tooltip: tr('Plus'), icon: const Icon(Icons.add), onPressed: value < 40 ? () => onChanged(value + 1) : null),
      ]);
}
