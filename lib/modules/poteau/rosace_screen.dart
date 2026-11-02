import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/objet.dart';
import '../../data/referentiels.dart';
import '../../providers/app_provider.dart';
import '../../theme.dart';
import '../../widgets/barre_basse.dart';
import '../../widgets/barre_support.dart';
import '../../widgets/saisie.dart';
import '../../widgets/titre_ecran.dart';
import '../infra/cables.dart';
import '../renseignement.dart';
import 'rosace_edition.dart';
import 'rosace_vue.dart';

/// Rosace des portées d'un poteau (maquette Figma) : rosace en haut, portées puis câbles portés en accordéon
/// dessous ; directions (angles), destinations et câbles. Barre commune du support, Portées active ; « Direction »
/// ajoute une portée.
class RosaceScreen extends StatefulWidget {
  const RosaceScreen({super.key, required this.poteau});

  final Objet poteau;

  @override
  State<RosaceScreen> createState() => _RosaceScreenState();
}

class _RosaceScreenState extends State<RosaceScreen> {
  late final RosaceEdition _edition;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    _edition = RosaceEdition(app.repo, widget.poteau, auteur: app.auteur)..charger();
  }

  @override
  void dispose() {
    _edition.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final app = context.read<AppProvider>();
    await _edition.valider();
    // l'orientation des portées compte dans le renseignement du poteau (POT_NIVEAU)
    final pot = await app.repo.objet(widget.poteau.id);
    if (pot != null) {
      final copie = pot.copie();
      await poserNiveau(copie, app.referentiels, app.repo);
      if (copie.espace('pot')?['POT_NIVEAU'] != pot.espace('pot')?['POT_NIVEAU']) await app.enregistrer(copie);
    }
    await app.apresEcriture();
    if (mounted) signalerEnregistre(context);
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.read<AppProvider>().referentiels;
    return ListenableBuilder(
      listenable: _edition,
      builder: (context, _) {
        final n = _edition.visibles.length;
        return EcranSaisie(
          modifie: _edition.modifiee,
          message: 'Les portées modifiées ne seront pas enregistrées.',
          child: Scaffold(
            appBar: AppBar(
              title: TitreEcran(
                widget.poteau.lib ?? widget.poteau.id,
                'portées · $n direction${n > 1 ? 's' : ''}',
              ),
            ),
            bottomNavigationBar: BarreSupport(
              objet: widget.poteau,
              dansModule: true,
              ajout: EntreeBarre(
                icone: Icons.add,
                libelle: 'Direction',
                onPressed: _edition.charge ? () => ajouterPortee(context, _edition, ref) : null,
              ),
            ),
            floatingActionButton: boutonEnregistrer(visible: _edition.modifiee, onPressed: _enregistrer),
            body: !_edition.charge
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final rosace = Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(child: RosaceVue(edition: _edition, referentiels: ref)),
                    );
                    final panneau = _Panneau(edition: _edition, referentiels: ref);
                    if (c.maxWidth > c.maxHeight) {
                      return Row(children: [
                        Expanded(flex: 3, child: rosace),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 2, child: panneau),
                      ]);
                    }
                    return Column(children: [
                      SizedBox(height: c.maxWidth.clamp(0, c.maxHeight * 0.5), child: rosace),
                      const Divider(height: 1),
                      Expanded(child: panneau),
                    ]);
                  }),
          ),
        );
      },
    );
  }
}

/// Ajoute une portée : destination existante proche, ou nouvelle (position provisoire, à relever).
Future<void> ajouterPortee(BuildContext context, RosaceEdition edition, Referentiels referentiels) async {
  final proches = await edition.destinationsProches();
  if (!context.mounted) return;
  final choix = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (c, defil) => ListView(
        controller: defil,
        children: [
          const ListTile(title: Text('Destination de la portée')),
          for (final e in typesDestination.entries)
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: Text('Nouveau : ${e.value}'),
              subtitle: const Text('Position provisoire, à relever'),
              onTap: () => Navigator.pop(c, e.key),
            ),
          const Divider(),
          if (proches.isEmpty) const ListTile(title: Text('Aucun nœud à moins de 150 m')),
          for (final (o, d) in proches)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(o.lib ?? o.id),
              subtitle: Text('${referentiels.libType(o.typeKey)} · ${d.round()} m'),
              onTap: () => Navigator.pop(c, o),
            ),
        ],
      ),
    ),
  );
  if (choix is Objet) {
    edition.ajouter(existant: choix);
  } else if (choix is int && context.mounted) {
    final lib = await _saisirTexte(context, 'Étiquette de la destination', 'N° d\'appui, adresse…');
    if (lib == null) return;
    edition.ajouter(typeNouveau: choix, libNouveau: lib, angle: 0);
  }
}

/// Panneau sous (ou à côté de) la rosace : liste des portées, ou détail de la portée sélectionnée avec ses câbles
/// portés en accordéon (un seul ouvert à la fois).
class _Panneau extends StatefulWidget {
  const _Panneau({required this.edition, required this.referentiels});

  final RosaceEdition edition;
  final Referentiels referentiels;

  @override
  State<_Panneau> createState() => _PanneauState();
}

class _PanneauState extends State<_Panneau> {
  /// Câble ouvert dans l'accordéon (rang), pour la portée [_portee].
  int? _ouvert;
  String? _portee;

  /// Bouton de pas de l'angle, 44 × 48 dp : quatre tiennent avec la valeur sur un téléphone.
  Widget _boutonPas(PorteeAuPoteau p, double pas) => SizedBox(
        width: 44,
        child: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(44, 48), padding: EdgeInsets.zero),
          onPressed: () => edition.orienter(p, p.angle + pas),
          child: Text('${pas > 0 ? '+' : '−'}${pas.abs() == 1 ? '1' : '0,1'}'),
        ),
      );

  RosaceEdition get edition => widget.edition;
  Referentiels get referentiels => widget.referentiels;

  @override
  Widget build(BuildContext context) {
    final s = edition.selection;
    if (s?.id != _portee) {
      _portee = s?.id;
      _ouvert = null;
    }
    return s == null ? _liste(context) : _detail(context, s);
  }

  Widget _liste(BuildContext context) {
    final portees = edition.visibles.toList()..sort((a, b) => a.angle.compareTo(b.angle));
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: margeBoutonFlottant),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            portees.isEmpty
                ? 'Aucune portée. « Direction » en ajoute une ; orientez ensuite l\'aiguille en la faisant glisser.'
                : 'Touchez une aiguille ou une portée pour la modifier.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final p in portees)
          ListTile(
            leading: _Pastilles(portee: p, referentiels: referentiels),
            title: Text(p.libelleDestination),
            subtitle: Text('${p.angle.toStringAsFixed(1)} gr'
                '${p.angleReleve == null ? ' (géométrie)' : ''}'
                ' · ${p.cables.length} câble${p.cables.length > 1 ? 's' : ''}'
                '${edition.nouveauxNoeuds.containsKey(p.destinationId) ? ' · destination nouvelle' : ''}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (p.modifiee) const Icon(Icons.edit, size: 16),
              const Icon(Icons.chevron_right),
            ]),
            onTap: () => edition.selectionner(p),
          ),
      ],
    );
  }

  Widget _detail(BuildContext context, PorteeAuPoteau p) {
    final t = Theme.of(context).textTheme;
    final lng = (p.portee['PRT_LNG'] as num?)?.toDouble();
    final cables = [...p.cables]..sort((a, b) => (a['PCB_RANG'] as int).compareTo(b['PCB_RANG'] as int));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, margeBoutonFlottant),
      children: [
        Row(children: [
          IconButton(onPressed: () => edition.selectionner(null), icon: const Icon(Icons.arrow_back), tooltip: 'Portées'),
          Expanded(child: Text(p.libelleDestination, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
          Text(referentiels.libType(p.destination?.typeKey), style: t.bodySmall),
        ]),
        Row(children: [
          const Text('Angle'),
          const Spacer(),
          for (final pas in [-1.0, -0.1]) _boutonPas(p, pas),
          SizedBox(
            width: 72,
            child: Text('${p.angle.toStringAsFixed(1)} gr',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final pas in [0.1, 1.0]) _boutonPas(p, pas),
        ]),
        if (p.angleReleve == null)
          Text('Angle calculé depuis la géométrie : orientez l\'aiguille pour le relever.', style: t.bodySmall),
        const SizedBox(height: 8),
        _ChampNombre(
          key: ValueKey('lng-${p.id}'),
          libelle: 'Longueur de la portée (m)',
          valeur: lng,
          onChanged: (v) => edition.poserLongueur(p, v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text('CÂBLES PORTÉS',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Nge.petrole)),
        ),
        for (final cable in cables) _cable(context, p, cable),
        if (cables.isEmpty) Padding(padding: const EdgeInsets.all(4), child: Text('Aucun câble porté.', style: t.bodySmall)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final rang = edition.rangSuivant(p);
            edition.poserCable(p, {'PCB_RANG': rang, 'PCB_NAPPE': 1, 'PCB_TENSION': 'STD_AGGLO'});
            setState(() => _ouvert = rang);
          },
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un câble'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => edition.abandonner(p),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Supprimer la portée'),
          style: TextButton.styleFrom(foregroundColor: Nge.rouge),
        ),
      ],
    );
  }

  /// Câble porté (`INF_PORTEE_CABLE`) dans l'accordéon : en-tête (flèche, type, nappe, longueur, pose), détail
  /// modifiable sur place quand il est ouvert.
  Widget _cable(BuildContext context, PorteeAuPoteau p, Map<String, dynamic> cable) {
    final rang = cable['PCB_RANG'] as int;
    final ouvert = _ouvert == rang;
    final cle = '${p.id}-$rang';
    void poser(String col, Object? v) => edition.poserCable(p, Map.of(cable)..[col] = v..removeWhere((_, x) => x == null));
    final catalogue = referentiels.table('infra', 'MAT_CABLE')
      ..sort((a, b) => (a['MAT_LIB'] as String).compareTo(b['MAT_LIB'] as String));
    final actuel = referentiels.cable(cable['MAT_KEY'] as int?);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: _Fleche(style: StyleCable.de(referentiels, cable['MAT_KEY'] as int?)),
          title: Text(actuel?['MAT_LIB'] as String? ?? (cable['PCB_COMMENT'] as String? ?? 'Câble n° $rang à identifier')),
          subtitle: Text([
            if (cable['PCB_NAPPE'] != null) 'nappe ${cable['PCB_NAPPE']}',
            if (cable['PCB_LNG'] != null) '${cable['PCB_LNG']} m',
            tensions[cable['PCB_TENSION']] ?? '',
          ].where((t) => t.isNotEmpty).join(' · ')),
          trailing: Icon(ouvert ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _ouvert = ouvert ? null : rang),
        ),
        if (ouvert)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Autocomplete<Map<String, dynamic>>(
                key: ValueKey('type-$cle'),
                initialValue: TextEditingValue(text: actuel?['MAT_LIB'] as String? ?? ''),
                displayStringForOption: (o) => o['MAT_LIB'] as String,
                optionsBuilder: (v) {
                  final q = v.text.toLowerCase().replaceAll(' ', '');
                  return catalogue
                      .where((o) => (o['MAT_LIB'] as String).toLowerCase().replaceAll(' ', '').contains(q))
                      .take(40);
                },
                onSelected: (o) => poser('MAT_KEY', o['MAT_ID']),
                fieldViewBuilder: (context, ctl, focus, _) => TextField(
                  controller: ctl,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Type de câble (catalogue)'),
                ),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: _ChampNombre(
                    key: ValueKey('pcblng-$cle'),
                    libelle: 'Longueur (m)',
                    valeur: (cable['PCB_LNG'] as num?)?.toDouble(),
                    onChanged: (v) => poser('PCB_LNG', v),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nappe', style: Theme.of(context).textTheme.bodySmall),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                    ],
                    selected: {?cable['PCB_NAPPE'] as int?},
                    onSelectionChanged: (s) => poser('PCB_NAPPE', s.firstOrNull),
                  ),
                ]),
              ]),
              const SizedBox(height: 12),
              Text('Pose', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in tensions.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: (cable['PCB_TENSION'] ?? 'STD_AGGLO') == e.key,
                    onSelected: (_) => poser('PCB_TENSION', e.key),
                  ),
              ]),
              if (cable['PCB_TENSION'] == 'RELEVE') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _ChampNombre(
                      key: ValueKey('fleche-$cle'),
                      libelle: 'Flèche relevée (m)',
                      valeur: (cable['PCB_FLECHE'] as num?)?.toDouble(),
                      onChanged: (v) => poser('PCB_FLECHE', v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ChampNombre(
                      key: ValueKey('temp-$cle'),
                      libelle: 'Température (°C)',
                      valeur: (cable['PCB_TEMP'] as num?)?.toDouble(),
                      onChanged: (v) => poser('PCB_TEMP', v),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Nge.rouge,
                  side: const BorderSide(color: Color(0xFFE8B4B4)),
                ),
                onPressed: () {
                  final avant = Map.of(cable);
                  edition.retirerCable(p, rang);
                  setState(() => _ouvert = null);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: const Text('Câble supprimé'),
                      action: SnackBarAction(label: 'ANNULER', onPressed: () => edition.poserCable(p, avant)),
                    ));
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer ce câble'),
              ),
            ]),
          ),
      ]),
    );
  }
}

Future<String?> _saisirTexte(BuildContext context, String titre, String aide) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titre),
      content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: aide)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

class _ChampNombre extends StatefulWidget {
  const _ChampNombre({super.key, required this.libelle, required this.valeur, required this.onChanged});

  final String libelle;
  final double? valeur;
  final ValueChanged<double?> onChanged;

  @override
  State<_ChampNombre> createState() => _ChampNombreState();
}

class _ChampNombreState extends State<_ChampNombre> {
  late final _ctl = TextEditingController(text: widget.valeur?.toString().replaceAll('.', ',') ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: widget.libelle),
        onChanged: (t) => widget.onChanged(double.tryParse(t.replaceAll(',', '.').trim())),
      );
}

/// Pastilles des câbles d'une portée dans la liste.
class _Pastilles extends StatelessWidget {
  const _Pastilles({required this.portee, required this.referentiels});

  final PorteeAuPoteau portee;
  final Referentiels referentiels;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        child: Wrap(spacing: 2, runSpacing: 2, children: [
          for (final c in portee.cables)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: couleurReseau(StyleCable.de(referentiels, c['MAT_KEY'] as int?).reseau), shape: BoxShape.circle),
            ),
        ]),
      );
}

/// Flèche miniature (couleur du réseau, tireté pour un branchement).
class _Fleche extends StatelessWidget {
  const _Fleche({required this.style});

  final StyleCable style;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 28,
        height: 12,
        child: CustomPaint(painter: _FlechePeintre(style)),
      );
}

class _FlechePeintre extends CustomPainter {
  _FlechePeintre(this.style);

  final StyleCable style;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = couleurReseau(style.reseau)
      ..strokeWidth = 3;
    final y = s.height / 2;
    if (style.branchement) {
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
  bool shouldRepaint(covariant _FlechePeintre old) => old.style.reseau != style.reseau || old.style.branchement != style.branchement;
}
