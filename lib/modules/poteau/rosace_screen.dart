import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/objet.dart';
import '../../data/referentiels.dart';
import '../../providers/app_provider.dart';
import '../../widgets/retour_carte.dart';
import '../../widgets/saisie.dart';
import '../infra/cables.dart';
import 'rosace_edition.dart';
import 'rosace_vue.dart';

/// Rosace des portées d'un poteau : saisie des directions (angles), des destinations et des câbles portés.
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
    await app.apresEcriture();
    if (mounted) signalerEnregistre(context);
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.read<AppProvider>().referentiels;
    return ListenableBuilder(
      listenable: _edition,
      builder: (context, _) => EcranSaisie(
        modifie: _edition.modifiee,
        message: 'Les portées modifiées ne seront pas enregistrées.',
        child: Scaffold(
          appBar: AppBar(
            title: Text('Rosace — ${widget.poteau.lib ?? widget.poteau.id}'),
            actions: const [BoutonCarte(), SizedBox(width: 8)],
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
                    SizedBox(height: c.maxWidth.clamp(0, c.maxHeight * 0.6), child: rosace),
                    const Divider(height: 1),
                    Expanded(child: panneau),
                  ]);
                }),
        ),
      ),
    );
  }
}

/// Panneau sous (ou à côté de) la rosace : liste des portées, ou détail de la portée sélectionnée.
class _Panneau extends StatelessWidget {
  const _Panneau({required this.edition, required this.referentiels});

  final RosaceEdition edition;
  final Referentiels referentiels;

  @override
  Widget build(BuildContext context) {
    final s = edition.selection;
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
                ? 'Aucune portée. Ajoutez une direction, puis orientez l\'aiguille en la faisant glisser.'
                : 'Touchez une aiguille ou une portée pour la modifier.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final p in portees)
          ListTile(
            dense: true,
            leading: _Pastilles(portee: p, referentiels: referentiels),
            title: Text(p.libelleDestination),
            subtitle: Text('${p.angle.toStringAsFixed(1)} gr'
                '${p.angleReleve == null ? ' (géométrie)' : ''}'
                ' · ${p.cables.length} câble${p.cables.length > 1 ? 's' : ''}'
                '${edition.nouveauxNoeuds.containsKey(p.destinationId) ? ' · destination nouvelle' : ''}'),
            trailing: p.modifiee ? const Icon(Icons.edit, size: 16) : null,
            onTap: () => edition.selectionner(p),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => _ajouterPortee(context),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une portée'),
          ),
        ),
      ],
    );
  }

  Widget _detail(BuildContext context, PorteeAuPoteau p) {
    final lng = (p.portee['PRT_LNG'] as num?)?.toDouble();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, margeBoutonFlottant),
      children: [
        Row(children: [
          IconButton(onPressed: () => edition.selectionner(null), icon: const Icon(Icons.arrow_back), tooltip: 'Portées'),
          Expanded(
            child: Text(p.libelleDestination, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
          ),
          Text(referentiels.libType(p.destination?.typeKey), style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Angle'),
          const Spacer(),
          for (final pas in [-1.0, -0.1])
            IconButton(onPressed: () => edition.orienter(p, p.angle + pas), icon: Text(pas > -1 ? '−0,1' : '−1')),
          SizedBox(
            width: 72,
            child: Text('${p.angle.toStringAsFixed(1)} gr',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final pas in [0.1, 1.0])
            IconButton(onPressed: () => edition.orienter(p, p.angle + pas), icon: Text(pas < 1 ? '+0,1' : '+1')),
        ]),
        if (p.angleReleve == null)
          Text('Angle calculé depuis la géométrie : orientez l\'aiguille pour le relever.',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _ChampNombre(
          key: ValueKey('lng-${p.id}'),
          libelle: 'Longueur de la portée (m)',
          valeur: lng,
          onChanged: (v) => edition.poserLongueur(p, v),
        ),
        const SizedBox(height: 16),
        Text('Câbles portés', style: Theme.of(context).textTheme.titleSmall),
        for (final cable in [...p.cables]..sort((a, b) => (a['PCB_RANG'] as int).compareTo(b['PCB_RANG'] as int)))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: _Fleche(style: StyleCable.de(referentiels, cable['MAT_KEY'] as int?)),
            title: Text(referentiels.cable(cable['MAT_KEY'] as int?)?['MAT_LIB'] as String? ??
                (cable['PCB_COMMENT'] as String? ?? 'Câble non identifié')),
            subtitle: Text([
              if (cable['PCB_NAPPE'] != null) 'nappe ${cable['PCB_NAPPE']}',
              if (cable['PCB_LNG'] != null) '${cable['PCB_LNG']} m',
              tensions[cable['PCB_TENSION']] ?? '',
            ].where((t) => t.isNotEmpty).join(' · ')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Retirer',
              onPressed: () => edition.retirerCable(p, cable['PCB_RANG'] as int),
            ),
            onTap: () => _editerCable(context, p, cable),
          ),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => _editerCable(context, p, null),
            icon: const Icon(Icons.add),
            label: const Text('Câble'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => edition.abandonner(p),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer la portée'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          ),
        ]),
      ],
    );
  }

  Future<void> _ajouterPortee(BuildContext context) async {
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

  Future<void> _editerCable(BuildContext context, PorteeAuPoteau p, Map<String, dynamic>? cable) async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => _CableDialog(
        referentiels: referentiels,
        cable: cable ?? {'PCB_RANG': edition.rangSuivant(p), 'PCB_NAPPE': 1, 'PCB_TENSION': 'STD_AGGLO'},
      ),
    );
    if (res != null) edition.poserCable(p, res);
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

/// Saisie d'un câble porté (`INF_PORTEE_CABLE`).
class _CableDialog extends StatefulWidget {
  const _CableDialog({required this.referentiels, required this.cable});

  final Referentiels referentiels;
  final Map<String, dynamic> cable;

  @override
  State<_CableDialog> createState() => _CableDialogState();
}

class _CableDialogState extends State<_CableDialog> {
  late final Map<String, dynamic> _c = Map.of(widget.cable);

  @override
  Widget build(BuildContext context) {
    final catalogue = widget.referentiels.table('infra', 'MAT_CABLE')
      ..sort((a, b) => (a['MAT_LIB'] as String).compareTo(b['MAT_LIB'] as String));
    final actuel = widget.referentiels.cable(_c['MAT_KEY'] as int?);
    return AlertDialog(
      title: Text('Câble porté n° ${_c['PCB_RANG']}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Autocomplete<Map<String, dynamic>>(
              initialValue: TextEditingValue(text: actuel?['MAT_LIB'] as String? ?? ''),
              displayStringForOption: (o) => o['MAT_LIB'] as String,
              optionsBuilder: (v) {
                final q = v.text.toLowerCase().replaceAll(' ', '');
                return catalogue.where((o) => (o['MAT_LIB'] as String).toLowerCase().replaceAll(' ', '').contains(q)).take(40);
              },
              onSelected: (o) => setState(() => _c['MAT_KEY'] = o['MAT_ID']),
              fieldViewBuilder: (context, ctl, focus, _) => TextField(
                controller: ctl,
                focusNode: focus,
                decoration: const InputDecoration(labelText: 'Type de câble (catalogue)'),
              ),
            ),
            if (actuel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  _Fleche(style: StyleCable.de(widget.referentiels, actuel['MAT_ID'] as int?)),
                  const SizedBox(width: 8),
                  Text('${actuel['CAB_TYPE'] ?? ''} ${actuel['CAB_USAGE'] == 'BRANCHEMENT' ? '· branchement' : actuel['CAB_USAGE'] == 'RESEAU' ? '· réseau' : ''}'),
                ]),
              ),
            const SizedBox(height: 8),
            _ChampNombre(libelle: 'Longueur (m)', valeur: (_c['PCB_LNG'] as num?)?.toDouble(), onChanged: (v) => Objet.poser(_c, 'PCB_LNG', v)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _c['PCB_NAPPE'] as int?,
              decoration: const InputDecoration(labelText: 'Nappe (n° de traverse)'),
              items: [for (final n in [1, 2, 3]) DropdownMenuItem(value: n, child: Text('$n'))],
              onChanged: (v) => Objet.poser(_c, 'PCB_NAPPE', v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _c['PCB_TENSION'] as String? ?? 'STD_AGGLO',
              decoration: const InputDecoration(labelText: 'Tension de pose'),
              items: [for (final t in tensions.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: (v) => setState(() => _c['PCB_TENSION'] = v),
            ),
            if (_c['PCB_TENSION'] == 'RELEVE') ...[
              const SizedBox(height: 8),
              _ChampNombre(libelle: 'Flèche relevée (m)', valeur: (_c['PCB_FLECHE'] as num?)?.toDouble(), onChanged: (v) => Objet.poser(_c, 'PCB_FLECHE', v)),
              const SizedBox(height: 8),
              _ChampNombre(libelle: 'Température (°C)', valeur: (_c['PCB_TEMP'] as num?)?.toDouble(), onChanged: (v) => Objet.poser(_c, 'PCB_TEMP', v)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, _c), child: const Text('OK')),
      ],
    );
  }
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
