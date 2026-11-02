import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/objet.dart';
import '../data/referentiels.dart';
import '../modules/chambre/chambre_resume.dart';
import '../modules/poteau/poteau_fiche.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/barre_support.dart';
import '../widgets/champs.dart';
import '../widgets/retour_carte.dart';
import '../widgets/saisie.dart';
import '../widgets/titre_ecran.dart';
import 'visuels_screen.dart';

/// Saisie d'un support (crayon des visuels) : identification et commentaire (noyau), caractéristiques et contrôles
/// du module selon le type, linéaires rattachés, suppression. Les photos sont dans les visuels.
/// La saisie travaille sur une copie, écrite dans le dépôt à l'enregistrement.
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

  /// Avant d'ouvrir les portées ou d'ajouter un visuel : la saisie en cours est enregistrée.
  Future<bool> _avant() async {
    if (_modifie) await _enregistrer();
    return mounted;
  }

  /// Ensuite : l'objet a pu changer (orientation, photos), les linéaires aussi.
  Future<void> _apres() async {
    final frais = await context.read<AppProvider>().repo.objet(_o.id);
    if (!mounted || frais == null) return;
    setState(() => _o = frais.copie());
    _extremites.clear();
    await _chargerLineaires();
  }

  /// Supprimer le support : abandon (DATE_ABD), validé au contrôle du retour ; retour à la carte.
  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer le support ?'),
        content: Text('${_o.lib ?? 'Le support'} sera marqué supprimé. '
            'La suppression sera validée au contrôle du retour.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nge.rouge, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppProvider>().enregistrer(_o, abandon: true);
    if (!mounted) return;
    setState(() => _modifie = false);
    signalerEnregistre(context, 'Support supprimé');
    await WidgetsBinding.instance.endOfFrame; // l'écran ne demande plus confirmation avant de se fermer
    if (mounted) await revenirALaCarte(context);
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<AppProvider>().referentiels;
    final famille = ref.codeFamille(_o.typeKey);
    return EcranSaisie(
      modifie: _modifie,
      child: Scaffold(
        appBar: AppBar(
          title: TitreEcran(
            _o.lib ?? 'Sans étiquette',
            ['saisie du support', if (_o.statut == 'C') 'créé', if (_o.statut == 'M') 'modifié'].join(' · '),
          ),
        ),
        bottomNavigationBar: BarreSupport(objet: _o, avant: _avant, apres: _apres),
        floatingActionButton: boutonEnregistrer(visible: _modifie, onPressed: _enregistrer),
        body: ListView(
          padding: const EdgeInsets.only(bottom: margeBoutonFlottant),
          children: [
            _identification(ref),
            if (famille == 'POT') ...[
              PoteauCaracteristiques(noeud: _o, referentiels: ref, onChanged: _changer),
              PoteauControles(noeud: _o, onChanged: _changer),
            ],
            if (famille == 'CHB') ChambreResume(noeud: _o, referentiels: ref),
            _listeLineaires(ref),
            if (_o.classe == Classe.noe && !_o.horsZone)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Nge.rouge,
                    side: const BorderSide(color: Color(0xFFE8B4B4)),
                  ),
                  onPressed: _supprimer,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer le support'),
                ),
              ),
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
                : () => ouvrirSupport(context, autre),
          );
        }),
    ]);
  }
}
