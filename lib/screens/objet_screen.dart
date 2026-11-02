import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/objet.dart';
import '../data/referentiels.dart';
import '../modules/chambre/chambre_resume.dart';
import '../modules/poteau/poteau_fiche.dart';
import '../modules/poteau/rosace_edition.dart' show typePorteeAerienne, typeParcoursFacade;
import '../modules/poteau/rosace_screen.dart';
import '../providers/app_provider.dart';
import '../widgets/champs.dart';
import '../widgets/retour_carte.dart';
import '../widgets/saisie.dart';

/// Fiche d'un nœud : identification (noyau), section du module selon le type, visuels et linéaires rattachés.
/// La fiche travaille sur une copie, écrite dans le dépôt à l'enregistrement.
class ObjetScreen extends StatefulWidget {
  const ObjetScreen({super.key, required this.objet});

  final Objet objet;

  @override
  State<ObjetScreen> createState() => _ObjetScreenState();
}

class _ObjetScreenState extends State<ObjetScreen> {
  late Objet _o = widget.objet.copie();
  bool _modifie = false;
  List<Objet> _lineaires = [];
  final Map<String, Objet?> _extremites = {};

  @override
  void initState() {
    super.initState();
    _chargerLineaires();
  }

  Future<void> _chargerLineaires() async {
    final repo = context.read<AppProvider>().repo;
    final l = await repo.lineairesDe(_o.id);
    for (final lin in l) {
      final autre = lin.noe1 == _o.id ? lin.noe2 : lin.noe1;
      if (autre != null) _extremites[autre] = await repo.objet(autre);
    }
    if (mounted) setState(() => _lineaires = l);
  }

  void _changer() => setState(() => _modifie = true);

  Future<void> _enregistrer() async {
    final app = context.read<AppProvider>();
    await app.enregistrer(_o);
    final frais = await app.repo.objet(_o.id);
    if (!mounted) return;
    setState(() {
      _o = frais!.copie();
      _modifie = false;
    });
    signalerEnregistre(context);
  }

  Future<void> _rosace() async {
    if (_modifie) await _enregistrer();
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RosaceScreen(poteau: _o)));
    _extremites.clear();
    await _chargerLineaires();
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<AppProvider>().referentiels;
    final famille = ref.codeFamille(_o.typeKey);
    return EcranSaisie(
      modifie: _modifie,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_o.lib ?? 'Sans étiquette'),
          actions: [
            if (_o.statut != null) Chip(label: Text(_o.statut == 'C' ? 'Créé' : 'Modifié')),
            const BoutonCarte(),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: boutonEnregistrer(visible: _modifie, onPressed: _enregistrer),
        body: ListView(
          padding: const EdgeInsets.only(bottom: margeBoutonFlottant),
          children: [
            _identification(ref),
            if (famille == 'POT') ...[
              Section(
                titre: 'Portées',
                action: FilledButton.tonalIcon(
                  onPressed: _o.point == null ? null : _rosace,
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Rosace'),
                ),
                enfants: [
                  Text('${_lineaires.where((l) => l.typeKey == typePorteeAerienne || l.typeKey == typeParcoursFacade).length}'
                      ' portée(s) ; directions, destinations et câbles portés sur la rosace.'),
                ],
              ),
              PoteauCaracteristiques(noeud: _o, referentiels: ref, onChanged: _changer),
              PoteauControles(noeud: _o, onChanged: _changer),
            ],
            if (famille == 'CHB') ChambreResume(noeud: _o, referentiels: ref),
            _visuels(ref),
            _listeLineaires(ref),
          ],
        ),
      ),
    );
  }

  Widget _identification(Referentiels ref) {
    final p = _o.point;
    return Section(titre: ref.libType(_o.typeKey), enfants: [
      ChampTexte(m: _o.props, cle: 'NOE_LIB', libelle: 'Étiquette (n° d\'appui, de chambre…)', onChanged: _changer),
      ChampTexte(m: _o.props, cle: 'NOE_COMMENT', libelle: 'Commentaire', lignes: 2, onChanged: _changer),
      const SizedBox(height: 8),
      Text(
        [
          if (p != null) '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
          if (_o.props['GEOL_MOD_KEY'] == 8) 'position à relever',
          if (_o.horsZone) 'hors zone (consultation)',
          'id ${_o.id}',
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }

  /// Vues attendues pour le type (DEF_VUE) et photos présentes.
  Widget _visuels(Referentiels ref) {
    final types = <int?>{_o.typeKey, ref.type(_o.typeKey)?['TYPE_PARENT_KEY'] as int?};
    final vues = ref.table('noyau', 'DEF_VUE').where((v) => types.contains(v['TYPE_KEY'])).toList()
      ..sort((a, b) => (a['VUE_ORDRE'] as int).compareTo(b['VUE_ORDRE'] as int));
    if (vues.isEmpty) return const SizedBox.shrink();
    final fichiers = [for (final f in (_o.props['fichiers'] as List?) ?? const []) (f as Map).cast<String, dynamic>()];
    final repo = context.read<AppProvider>().repo;
    return Section(titre: 'Visuels', enfants: [
      for (final v in vues)
        Builder(builder: (context) {
          final photos = fichiers.where((f) => f['VUE_CODE'] == v['VUE_CODE']).toList();
          final octets = photos.map((f) => f['fichier'] == null ? null : repo.fichier(f['fichier'] as String)).nonNulls.toList();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: octets.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(octets.first, width: 48, height: 48, fit: BoxFit.cover))
                : Icon(photos.isEmpty ? Icons.photo_camera_outlined : Icons.photo_outlined),
            title: Text('${v['VUE_LIB']}${v['VUE_OBLIGATOIRE'] == 'OUI' ? ' *' : ''}'),
            subtitle: Text(photos.isEmpty
                ? 'Aucune photo'
                : '${photos.length} photo(s)${octets.length < photos.length ? ', non embarquées' : ''}'),
          );
        }),
      Text('* obligatoire. Prise de photos : à venir.', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _listeLineaires(Referentiels ref) {
    if (_lineaires.isEmpty) return const SizedBox.shrink();
    return Section(titre: 'Linéaires', enfants: [
      for (final l in _lineaires)
        Builder(builder: (context) {
          final autre = _extremites[l.noe1 == _o.id ? l.noe2 : l.noe1];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${ref.libType(l.typeKey)} vers ${autre?.lib ?? autre?.id ?? '?'}'),
            subtitle: Text([
              if (l.props['LIN_LNG'] != null) '${l.props['LIN_LNG']} m',
              if ((l.espace('inf')?['conduites'] as List?)?.isNotEmpty ?? false)
                '${(l.espace('inf')!['conduites'] as List).length} conduite(s)',
              if (l.espace('inf')?['portee'] != null) '${((l.espace('inf')!['portee'] as Map)['cables'] as List?)?.length ?? 0} câble(s) porté(s)',
            ].join(' · ')),
            trailing: autre == null ? null : const Icon(Icons.chevron_right),
            onTap: autre == null
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ObjetScreen(objet: autre))),
          );
        }),
    ]);
  }
}
