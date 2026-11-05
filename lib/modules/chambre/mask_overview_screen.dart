import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../theme.dart';
import '../../widgets/back_to_map.dart';
import '../../widgets/fields.dart';
import '../../widgets/linear_list.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/support_bar.dart';
import 'mask_editor.dart';
import 'mask_screen.dart';

/// Aperçu des masques de la chambre (bouton Masques de la barre basse) : une ligne par face, toucher une face ouvre
/// sa grille ; dessous, les conduites (parcours vers les autres supports, conduites sans destination connue).
/// Chaque parcours porte une pastille jaune de direction (notes rep11, plus de carton intermédiaire) : la toucher, ou
/// toucher le parcours, ouvre d'emblée le support d'en face à la place de celui-ci, sur le même écran ; le parcours
/// d'arrivée y est mis en évidence ([linear]).
/// L'objet et ses linéaires sont relus dans le dépôt à l'ouverture et au retour de la grille.
class MaskOverviewScreen extends StatefulWidget {
  const MaskOverviewScreen({super.key, required this.chamber, this.linear});

  final GeoObject chamber;

  /// Parcours mis en évidence à l'ouverture (arrivée d'un parcours suivi, chambre rouverte par le menu ⋮).
  final String? linear;

  @override
  State<MaskOverviewScreen> createState() => _MaskOverviewScreenState();
}

class _MaskOverviewScreenState extends State<MaskOverviewScreen> {
  late GeoObject _o = widget.chamber;
  Linears _linears = (linears: const [], ends: const {});

  /// Parcours mis en évidence (identifiant du linéaire) : celui par lequel on est arrivé.
  late final String? _selected = widget.linear;
  Route<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    // noté pour rouvrir l'aperçu dans le même état (menu ⋮)
    final r = _route;
    if (r != null) screenStack.note(r, tab: 'masques', selection: _selected);
  }

  Future<void> _reload() async {
    final repo = context.read<AppProvider>().repo;
    final fresh = await repo.object(_o.id);
    if (fresh == null) return;
    final l = await loadLinears(repo, fresh);
    if (mounted) {
      setState(() {
        _o = fresh;
        _linears = l;
      });
    }
  }

  /// Grille de la face (route nommée : la face et l'alvéole choisies sont retenues si l'on quitte la chambre).
  Future<void> _open(String face) async {
    await Navigator.push(
        context, MaterialPageRoute(settings: tabSettings(_o, 'masques:$face'), builder: (_) => MaskScreen(chamber: _o, face: face)));
    await _reload();
  }

  /// Masques de la chambre où sont placées les conduites du parcours [linear] (notes rep13) : « masque A »,
  /// « masques A, B » ; null si aucune n'y est placée.
  String? _masksOf(GeoObject linear) {
    final ducts = {for (final c in MaskEditor.ductsOf(linear)) c['CD_CODE_EXT']};
    final faces = [
      for (final f in (_o.namespace('chb')?['faces'] as List?) ?? const [])
        if (((f as Map)['positions'] as List?)?.any((p) => (p as Map)['DATE_ABD'] == null && ducts.contains(p['CD_KEY'])) ??
            false)
          '${f['FAC_CODE']}',
    ]..sort();
    return faces.isEmpty ? null : trn(faces.length, 'masque {1}', 'masques {1}', [faces.join(', ')]);
  }

  /// Suit le parcours jusqu'au support d'en face, qui remplace la chambre, sur le même écran.
  Future<void> _navigate(GeoObject linear, GeoObject other) => follow(context, linear, other, route: true);

  @override
  Widget build(BuildContext context) {
    final noDestination = MaskEditor.ductsOf(_o).length;
    final ref = context.watch<AppProvider>().referenceData;
    return Scaffold(
      appBar: AppBar(
        title: ScreenTitle(_o.lib ?? tr('Sans étiquette'), tr('masques')),
        actions: [SupportMenu(object: _o)],
      ),
      bottomNavigationBar: SupportBar(object: _o, inModule: true, next: _reload),
      body: LayoutBuilder(builder: (context, c) {
        final conduits = LinearList(
          node: _o,
          data: _linears,
          referenceData: ref,
          title: tr('Conduites'),
          selected: _selected,
          onOpen: _navigate,
          note: _masksOf,
          extra: [
            if (noDestination > 0)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Sans destination connue')),
                subtitle: Text(trn(noDestination, '{0} conduite', '{0} conduites')),
              ),
          ],
        );
        // paysage (notes rep10) : les faces à gauche, en tuiles avec la miniature de leur masque, les conduites à
        // droite ; en portrait, une ligne par face, puis les conduites
        // tuiles sur un écran assez haut ; téléphone en paysage : une ligne par face, les quatre visibles
        if (c.maxWidth > c.maxHeight && c.maxWidth >= 600) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
                c.maxHeight >= wideLegendHeight
                    ? ChamberMaskTiles(node: _o, linears: _linears.linears, referenceData: ref, onOpen: _open)
                    : ChamberMasks(node: _o, linears: _linears.linears, onOpen: _open),
              ]),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [conduits])),
          ]);
        }
        return ListView(padding: const EdgeInsets.only(bottom: 12), children: [
          ChamberMasks(node: _o, linears: _linears.linears, onOpen: _open),
          conduits,
        ]);
      }),
    );
  }
}

/// Conduites sous-tubes (CD_PARENT_KEY) des porteurs [carriers] : non comptées comme des alvéoles.
Set<Object?> subductCodes(List<GeoObject> carriers) => {
      for (final l in carriers)
        for (final c in MaskEditor.ductsOf(l))
          if (c['CD_PARENT_KEY'] != null) c['CD_CODE_EXT'],
    };

/// Masques de la chambre : une ligne par face (alvéoles, dimensions de la face) ; toucher une face ouvre sa grille.
class ChamberMasks extends StatelessWidget {
  const ChamberMasks({super.key, required this.node, this.linears = const [], required this.onOpen});

  final GeoObject node;

  /// Linéaires de la chambre, porteurs des conduites (sous-tubes non comptés).
  final List<GeoObject> linears;
  final void Function(String face) onOpen;

  @override
  Widget build(BuildContext context) {
    final faces = {
      for (final f in (node.namespace('chb')?['faces'] as List?) ?? const []) '${(f as Map)['FAC_CODE']}': f,
    };
    final subducts = subductCodes([...linears, node]);
    return Section(title: tr('Masques'), children: [
      for (final code in chamberFaces)
        Builder(builder: (context) {
          final f = faces[code];
          final n = ((f?['positions'] as List?) ?? const [])
              .where((p) => (p as Map)['DATE_ABD'] == null && !subducts.contains(p['CD_KEY']))
              .length;
          final (width, height) = (f?['FAC_LARG'], f?['FAC_HAUT']);
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, child: Text(code)),
            title: Text(n == 0 ? tr('Face vide') : trn(n, '{0} alvéole', '{0} alvéoles')),
            subtitle: width is num && height is num ? Text(faceSizeLabel(width.toDouble(), height.toDouble())) : null,
            trailing: const Icon(Icons.grid_on_outlined),
            onTap: () => onOpen(code),
          );
        }),
    ]);
  }
}

/// Masques de la chambre en tuiles (aperçu en paysage, notes rep10) : pour chaque face, la miniature de son masque
/// ([MaskPreview]), puis sa lettre, ses alvéoles et ses dimensions ; toucher une tuile ouvre sa grille. Tuiles sans
/// cadre, la miniature seule se détachant de la section (notes rep12 : pas de tuiles imbriquées).
class ChamberMaskTiles extends StatelessWidget {
  const ChamberMaskTiles({
    super.key,
    required this.node,
    required this.linears,
    required this.referenceData,
    required this.onOpen,
  });

  final GeoObject node;

  /// Linéaires de la chambre, porteurs des conduites (état et diamètre des alvéoles).
  final List<GeoObject> linears;
  final ReferenceData referenceData;
  final void Function(String face) onOpen;

  /// Largeur minimale d'une tuile : deux par rangée sur une tablette en paysage, quatre sur un écran très large.
  static const minWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final faces = {
      for (final f in (node.namespace('chb')?['faces'] as List?) ?? const []) '${(f as Map)['FAC_CODE']}': f,
    };
    final ducts = {
      for (final l in [...linears, node])
        for (final c in MaskEditor.ductsOf(l)) c['CD_CODE_EXT']: c,
    };
    final colors = {for (final s in ductStates(referenceData)) s.id: s.color};
    final subducts = subductCodes([...linears, node]);
    return Section(title: tr('Masques'), children: [
      LayoutBuilder(builder: (context, c) {
        const gap = 12.0;
        final columns = math.max(1, ((c.maxWidth + gap) / (minWidth + gap)).floor());
        final width = ((c.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(spacing: gap, runSpacing: 4, children: [
          for (final code in chamberFaces)
            Builder(builder: (context) {
              final f = faces[code];
              final positions = [
                for (final p in (f?['positions'] as List?) ?? const [])
                  if ((p as Map)['DATE_ABD'] == null && p['CD_KEY'] is String) p,
              ];
              final size = MaskEditor.faceSizeOf(node, referenceData, code);
              // alvéoles, sous-tubes non comptés
              final bores = positions.where((p) => !subducts.contains(p['CD_KEY'])).length;
              final (w, h) = (f?['FAC_LARG'], f?['FAC_HAUT']);
              return SizedBox(
                width: width,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onOpen(code),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: MaskPreview(
                            width: size.width,
                            height: size.height,
                            positions: positions,
                            ducts: ducts,
                            colors: colors,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        CircleAvatar(radius: 12, child: Text(code, style: const TextStyle(fontSize: 12))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(bores == 0 ? tr('Face vide') : trn(bores, '{0} alvéole', '{0} alvéoles'),
                                style: t.titleSmall),
                            if (w is num && h is num) Text(faceSizeLabel(w.toDouble(), h.toDouble()), style: t.bodySmall),
                          ]),
                        ),
                      ]),
                    ]),
                  ),
                ),
              );
            }),
        ]);
      }),
    ]);
  }
}

/// Miniature d'une face : un aplat aux proportions réelles ([width] × [height], m), sans quadrillage (notes rep12),
/// ses alvéoles à leur place, à l'échelle, à la couleur de l'état de leur conduite (gris si elle manque au paquet).
class MaskPreview extends StatelessWidget {
  const MaskPreview({
    super.key,
    required this.width,
    required this.height,
    required this.positions,
    required this.ducts,
    required this.colors,
  });

  final double width;
  final double height;
  final List<Map> positions;

  /// Conduites par CD_CODE_EXT (CD_DIAM, ETAT_KEY).
  final Map<Object?, Map<String, dynamic>> ducts;
  final Map<int, Color> colors;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: width / height,
        child: CustomPaint(painter: _PreviewPainter(this)),
      );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.preview);

  final MaskPreview preview;

  @override
  void paint(Canvas canvas, Size size) {
    final p = preview;
    final scale = size.width / p.width; // px par m
    // une grosse alvéole au bord ne déborde pas de la face
    final face = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.clipRRect(face);
    canvas.drawRRect(face, Paint()..color = Nge.barBackground);
    canvas.drawRRect(
        face.deflate(0.5),
        Paint()
          ..color = Nge.rule
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    for (final pos in p.positions) {
      final duct = p.ducts[pos['CD_KEY']];
      final center = Offset(((pos['POS_X'] as num?)?.toDouble() ?? 0) * scale, ((pos['POS_Y'] as num?)?.toDouble() ?? 0) * scale);
      final radius = math.max(3.0, boreDiameter((duct?['CD_DIAM'] as num?)?.toDouble()) * scale / 2);
      canvas.drawCircle(center, radius,
          Paint()..color = duct == null ? Nge.hoverPressed : p.colors[duct['ETAT_KEY']] ?? Colors.white);
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = Nge.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
