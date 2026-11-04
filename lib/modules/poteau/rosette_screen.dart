import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../theme.dart';
import '../../widgets/bottom_bar.dart';
import '../../widgets/support_bar.dart';
import '../../widgets/entry_screen.dart';
import '../../widgets/screen_title.dart';
import '../infra/cables.dart';
import '../completion.dart';
import 'rosette_editor.dart';
import 'rosette_view.dart';

/// Rosace des portées d'un poteau (maquette Figma) : rosace en haut, portées puis câbles portés en accordéon
/// dessous ; directions (angles), destinations et câbles. Barre commune du support, Portées active ; « Direction »
/// ajoute une portée.
class RosetteScreen extends StatefulWidget {
  const RosetteScreen({super.key, required this.pole});

  final GeoObject pole;

  @override
  State<RosetteScreen> createState() => _RosetteScreenState();
}

class _RosetteScreenState extends State<RosetteScreen> {
  late final RosetteEditor _editor;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    _editor = RosetteEditor(app.repo, widget.pole, author: app.author)..load();
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppProvider>();
    await _editor.validate();
    // l'orientation des portées compte dans le renseignement du poteau (POT_NIVEAU)
    final pot = await app.repo.object(widget.pole.id);
    if (pot != null) {
      final copy = pot.copy();
      await saveLevel(copy, app.referenceData, app.repo);
      if (copy.namespace('pot')?['POT_NIVEAU'] != pot.namespace('pot')?['POT_NIVEAU']) await app.save(copy);
    }
    await app.afterWrite();
    if (mounted) showSaved(context);
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.read<AppProvider>().referenceData;
    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) {
        final n = _editor.activeSpans.length;
        return EntryScreen(
          changed: _editor.changed,
          message: tr('Les portées modifiées ne seront pas enregistrées.'),
          child: Scaffold(
            appBar: AppBar(
              title: ScreenTitle(
                widget.pole.lib ?? widget.pole.id,
                trn(n, 'portées · {0} direction', 'portées · {0} directions'),
              ),
            ),
            bottomNavigationBar: SupportBar(
              object: widget.pole,
              inModule: true,
              addItem: BarItem(
                icon: Icons.add,
                label: tr('Direction'),
                onPressed: _editor.loaded ? () => addSpan(context, _editor, ref) : null,
              ),
            ),
            floatingActionButton: saveButton(visible: _editor.changed, onPressed: _save),
            body: !_editor.loaded
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final rosette = Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(child: RosetteView(editor: _editor, referenceData: ref)),
                    );
                    final panel = _Panel(editor: _editor, referenceData: ref);
                    if (c.maxWidth > c.maxHeight) {
                      return Row(children: [
                        Expanded(flex: 3, child: rosette),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 2, child: panel),
                      ]);
                    }
                    return Column(children: [
                      SizedBox(height: c.maxWidth.clamp(0, c.maxHeight * 0.5), child: rosette),
                      const Divider(height: 1),
                      Expanded(child: panel),
                    ]);
                  }),
          ),
        );
      },
    );
  }
}

/// Ajoute une portée : destination existante proche, ou nouvelle (position provisoire, à relever).
Future<void> addSpan(BuildContext context, RosetteEditor editor, ReferenceData referenceData) async {
  final nearby = await editor.nearbyDestinations();
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (c, scrollController) => ListView(
        controller: scrollController,
        children: [
          ListTile(title: Text(tr('Destination de la portée'))),
          for (final e in destinationTypes.entries)
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: Text(tr('Nouveau : {0}', [tr(e.value)])),
              subtitle: Text(tr('Position provisoire, à relever')),
              onTap: () => Navigator.pop(c, e.key),
            ),
          const Divider(),
          if (nearby.isEmpty) ListTile(title: Text(tr('Aucun nœud à moins de 150 m'))),
          for (final (o, d) in nearby)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(o.lib ?? o.id),
              subtitle: Text('${referenceData.typeLabel(o.typeKey)} · ${d.round()} m'),
              onTap: () => Navigator.pop(c, o),
            ),
        ],
      ),
    ),
  );
  if (choice is GeoObject) {
    editor.add(existing: choice);
  } else if (choice is int && context.mounted) {
    final lib = await _askText(context, tr('Étiquette de la destination'), tr('N° d\'appui, adresse…'));
    if (lib == null) return;
    editor.add(newType: choice, newLabel: lib, angle: 0);
  }
}

/// Panneau sous (ou à côté de) la rosace : liste des portées, ou détail de la portée sélectionnée avec ses câbles
/// portés en accordéon (un seul ouvert à la fois).
class _Panel extends StatefulWidget {
  const _Panel({required this.editor, required this.referenceData});

  final RosetteEditor editor;
  final ReferenceData referenceData;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  /// Câble ouvert dans l'accordéon (rang), pour la portée [_span].
  int? _expanded;
  String? _span;

  /// Bouton de pas de l'angle, 44 × 48 dp : quatre tiennent avec la valeur sur un téléphone.
  Widget _stepButton(PoleSpan p, double step) => SizedBox(
        width: 44,
        child: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(44, 48), padding: EdgeInsets.zero),
          onPressed: () => editor.orient(p, p.angle + step),
          child: Text('${step > 0 ? '+' : '−'}${step.abs() == 1 ? '1' : '0,1'}'),
        ),
      );

  RosetteEditor get editor => widget.editor;
  ReferenceData get referenceData => widget.referenceData;

  @override
  Widget build(BuildContext context) {
    final s = editor.selection;
    if (s?.id != _span) {
      _span = s?.id;
      _expanded = null;
    }
    return s == null ? _list(context) : _detail(context, s);
  }

  Widget _list(BuildContext context) {
    final spans = editor.activeSpans.toList()..sort((a, b) => a.angle.compareTo(b.angle));
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: fabMargin),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            spans.isEmpty
                ? tr('Aucune portée. « Direction » en ajoute une ; orientez ensuite l\'aiguille en la faisant glisser.')
                : tr('Touchez une aiguille ou une portée pour la modifier.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final p in spans)
          ListTile(
            leading: _Dots(span: p, referenceData: referenceData),
            title: Text(p.destinationLabel),
            subtitle: Text('${p.angle.toStringAsFixed(1)} gr'
                '${p.surveyedAngle == null ? ' (${tr('géométrie')})' : ''}'
                ' · ${trn(p.cables.length, '{0} câble', '{0} câbles')}'
                '${editor.newNodes.containsKey(p.destinationId) ? ' · ${tr('destination nouvelle')}' : ''}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (p.changed) const Icon(Icons.edit, size: 16),
              const Icon(Icons.chevron_right),
            ]),
            onTap: () => editor.select(p),
          ),
      ],
    );
  }

  Widget _detail(BuildContext context, PoleSpan p) {
    final t = Theme.of(context).textTheme;
    final lng = (p.span['PRT_LNG'] as num?)?.toDouble();
    final cables = [...p.cables]..sort((a, b) => (a['PCB_RANG'] as int).compareTo(b['PCB_RANG'] as int));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, fabMargin),
      children: [
        Row(children: [
          IconButton(onPressed: () => editor.select(null), icon: const Icon(Icons.arrow_back), tooltip: tr('Portées')),
          Expanded(child: Text(p.destinationLabel, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
          Text(referenceData.typeLabel(p.destination?.typeKey), style: t.bodySmall),
        ]),
        Row(children: [
          Text(tr('Angle')),
          const Spacer(),
          for (final step in [-1.0, -0.1]) _stepButton(p, step),
          SizedBox(
            width: 72,
            child: Text('${p.angle.toStringAsFixed(1)} gr',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final step in [0.1, 1.0]) _stepButton(p, step),
        ]),
        if (p.surveyedAngle == null)
          Text(tr('Angle calculé depuis la géométrie : orientez l\'aiguille pour le relever.'), style: t.bodySmall),
        const SizedBox(height: 8),
        _NumberInput(
          key: ValueKey('lng-${p.id}'),
          label: tr('Longueur de la portée (m)'),
          value: lng,
          onChanged: (v) => editor.setLength(p, v),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text('CÂBLES PORTÉS',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Nge.petrolBlue)),
        ),
        for (final cable in cables) _cableTile(context, p, cable),
        if (cables.isEmpty) Padding(padding: const EdgeInsets.all(4), child: Text(tr('Aucun câble porté.'), style: t.bodySmall)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final rank = editor.nextRank(p);
            editor.setCable(p, {'PCB_RANG': rank, 'PCB_NAPPE': 1, 'PCB_TENSION': 'STD_AGGLO'});
            setState(() => _expanded = rank);
          },
          icon: const Icon(Icons.add),
          label: Text(tr('Ajouter un câble')),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => editor.abandon(p),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Supprimer la portée')),
          style: TextButton.styleFrom(foregroundColor: Nge.red),
        ),
      ],
    );
  }

  /// Câble porté (`INF_PORTEE_CABLE`) dans l'accordéon : en-tête (flèche, type, nappe, longueur, pose), détail
  /// modifiable sur place quand il est ouvert.
  Widget _cableTile(BuildContext context, PoleSpan p, Map<String, dynamic> cable) {
    final rank = cable['PCB_RANG'] as int;
    final isOpen = _expanded == rank;
    final keyId = '${p.id}-$rank';
    void put(String col, Object? v) => editor.setCable(p, Map.of(cable)..[col] = v..removeWhere((_, x) => x == null));
    final catalog = referenceData.table('infra', 'MAT_CABLE')
      ..sort((a, b) => (a['MAT_LIB'] as String).compareTo(b['MAT_LIB'] as String));
    final current = referenceData.cable(cable['MAT_KEY'] as int?);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: _Arrow(style: CableStyle.of(referenceData, cable['MAT_KEY'] as int?)),
          title: Text(current?['MAT_LIB'] as String? ?? (cable['PCB_COMMENT'] as String? ?? tr('Câble n° {0} à identifier', [rank]))),
          subtitle: Text([
            if (cable['PCB_NAPPE'] != null) tr('nappe {0}', [cable['PCB_NAPPE']]),
            if (cable['PCB_LNG'] != null) '${cable['PCB_LNG']} m',
            tr(voltages[cable['PCB_TENSION']] ?? ''),
          ].where((t) => t.isNotEmpty).join(' · ')),
          trailing: Icon(isOpen ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _expanded = isOpen ? null : rank),
        ),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Autocomplete<Map<String, dynamic>>(
                key: ValueKey('type-$keyId'),
                initialValue: TextEditingValue(text: current?['MAT_LIB'] as String? ?? ''),
                displayStringForOption: (o) => o['MAT_LIB'] as String,
                optionsBuilder: (v) {
                  final q = v.text.toLowerCase().replaceAll(' ', '');
                  return catalog
                      .where((o) => (o['MAT_LIB'] as String).toLowerCase().replaceAll(' ', '').contains(q))
                      .take(40);
                },
                onSelected: (o) => put('MAT_KEY', o['MAT_ID']),
                fieldViewBuilder: (context, ctl, focus, _) => TextField(
                  controller: ctl,
                  focusNode: focus,
                  decoration: InputDecoration(labelText: tr('Type de câble (catalogue)')),
                ),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: _NumberInput(
                    key: ValueKey('pcblng-$keyId'),
                    label: tr('Longueur (m)'),
                    value: (cable['PCB_LNG'] as num?)?.toDouble(),
                    onChanged: (v) => put('PCB_LNG', v),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Nappe'), style: Theme.of(context).textTheme.bodySmall),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                    ],
                    selected: {?cable['PCB_NAPPE'] as int?},
                    onSelectionChanged: (s) => put('PCB_NAPPE', s.firstOrNull),
                  ),
                ]),
              ]),
              const SizedBox(height: 12),
              Text(tr('Pose'), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in voltages.entries)
                  ChoiceChip(
                    label: Text(tr(e.value)),
                    selected: (cable['PCB_TENSION'] ?? 'STD_AGGLO') == e.key,
                    onSelected: (_) => put('PCB_TENSION', e.key),
                  ),
              ]),
              if (cable['PCB_TENSION'] == 'RELEVE') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _NumberInput(
                      key: ValueKey('fleche-$keyId'),
                      label: tr('Flèche relevée (m)'),
                      value: (cable['PCB_FLECHE'] as num?)?.toDouble(),
                      onChanged: (v) => put('PCB_FLECHE', v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberInput(
                      key: ValueKey('temp-$keyId'),
                      label: tr('Température (°C)'),
                      value: (cable['PCB_TEMP'] as num?)?.toDouble(),
                      onChanged: (v) => put('PCB_TEMP', v),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Nge.red,
                  side: const BorderSide(color: Color(0xFFE8B4B4)),
                ),
                onPressed: () {
                  final previous = Map.of(cable);
                  editor.removeCable(p, rank);
                  setState(() => _expanded = null);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: Text(tr('Câble supprimé')),
                      action: SnackBarAction(label: 'ANNULER', onPressed: () => editor.setCable(p, previous)),
                    ));
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Supprimer ce câble')),
              ),
            ]),
          ),
      ]),
    );
  }
}

Future<String?> _askText(BuildContext context, String title, String hint) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler'))),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

class _NumberInput extends StatefulWidget {
  const _NumberInput({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late final _txtValue = TextEditingController(text: widget.value?.toString().replaceAll('.', ',') ?? '');

  @override
  void dispose() {
    _txtValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _txtValue,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: widget.label),
        onChanged: (t) => widget.onChanged(double.tryParse(t.replaceAll(',', '.').trim())),
      );
}

/// Pastilles des câbles d'une portée dans la liste.
class _Dots extends StatelessWidget {
  const _Dots({required this.span, required this.referenceData});

  final PoleSpan span;
  final ReferenceData referenceData;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        child: Wrap(spacing: 2, runSpacing: 2, children: [
          for (final c in span.cables)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: networkColor(CableStyle.of(referenceData, c['MAT_KEY'] as int?).network), shape: BoxShape.circle),
            ),
        ]),
      );
}

/// Flèche miniature (couleur du réseau, tireté pour un branchement).
class _Arrow extends StatelessWidget {
  const _Arrow({required this.style});

  final CableStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 28,
        height: 12,
        child: CustomPaint(painter: _ArrowPainter(style)),
      );
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.style);

  final CableStyle style;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = networkColor(style.network)
      ..strokeWidth = 3;
    final y = s.height / 2;
    if (style.drop) {
      for (var x = 0.0; x < s.width - 8; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), p);
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(s.width - 8, y), p);
    }
    canvas.drawPath(
        Path()
          ..moveTo(s.width, y)
          ..lineTo(s.width - 8, 0)
          ..lineTo(s.width - 8, s.height)
          ..close(),
        p);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.style.network != style.network || old.style.drop != style.drop;
}
