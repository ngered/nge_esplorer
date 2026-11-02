import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../carte/couleurs.dart';
import '../carte/tile_source.dart';
import '../data/objet.dart';
import '../data/referentiels.dart';
import '../modules/poteau/rosace_screen.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/barre_basse.dart';
import 'parametres_screen.dart';
import 'visuels_screen.dart';

/// Écran principal : accueil tant qu'aucun paquet n'est chargé, puis carte de la zone.
class CarteScreen extends StatelessWidget {
  const CarteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return app.ouvert ? const _Carte() : const _Accueil();
  }
}

/// Ouvre un paquet de zone, qui remplace le paquet en cours. Web : les modifications non exportées, gardées en
/// mémoire seulement, seraient perdues ; confirmation demandée (exporter, abandonner ou annuler).
Future<void> ouvrirPaquet(BuildContext context) async {
  final app = context.read<AppProvider>();
  if (kIsWeb && app.aExporter) {
    final choix = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Modifications non exportées'),
        content: Text('${app.nbModifies} objet(s) modifié(s) dans le paquet en cours n\'ont pas été exportés. '
            'Ouvrir un autre paquet les effacera.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, 'abandonner'), child: const Text('Abandonner les modifications')),
          FilledButton(onPressed: () => Navigator.pop(c, 'exporter'), child: const Text('Exporter le retour')),
        ],
      ),
    );
    if (choix == null || !context.mounted) return;
    if (choix == 'exporter') await exporterRetour(context);
  }
  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['zip'], dialogTitle: 'Paquet de zone');
  if (f == null) return;
  await app.chargerPaquet(await f.readAsBytes());
}

/// Exporte le paquet de retour (objets modifiés et intervention).
Future<void> exporterRetour(BuildContext context) async {
  final app = context.read<AppProvider>();
  final messager = ScaffoldMessenger.of(context);
  final (nom, zip) = await app.paquetRetour();
  final f = await FilePicker.saveFile(fileName: nom, bytes: zip, mimeType: 'application/zip', dialogTitle: 'Paquet de retour');
  if (f == null) {
    messager.showSnackBar(const SnackBar(content: Text('Export annulé')));
    return;
  }
  app.marquerExporte();
  messager.showSnackBar(SnackBar(content: Text('Paquet de retour : $nom (${app.nbModifies} objet(s))')));
}

/// Écran de démarrage (support de marque, bleu nuit) : logo NGE, compte, ouverture d'un paquet de zone.
class _Accueil extends StatelessWidget {
  const _Accueil();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      backgroundColor: Nge.bleuNuit,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                          child: SvgPicture.asset('assets/nge/nge_es_logo.svg', semanticsLabel: 'NGE Energies Solutions'),
                        ),
                        const SizedBox(height: 32),
                        const Text('NgeEsPlorer',
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 6),
                        const Text('Saisie terrain · télécoms et électricité',
                            style: TextStyle(fontSize: 16, color: Nge.texteSurFonce)),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(width: 48, height: Nge.epaisseurFilet, color: Nge.jaune),
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        _Compte(nom: app.auteur, onChanged: app.definirAuteur),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          onPressed: app.chargement ? null : () => ouvrirPaquet(context),
                          icon: app.chargement
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.folder_open_outlined),
                          label: const Text('Ouvrir un paquet de zone'),
                        ),
                        if (app.erreur != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Text(app.erreur!, style: const TextStyle(color: Nge.rouge)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          'Version web de développement : données de test uniquement, conservées en mémoire '
                          'jusqu\'au rechargement de la page. Exportez le paquet de retour avant de fermer.',
                          style: TextStyle(fontSize: 13, color: Nge.texteSurFonce),
                          textAlign: TextAlign.center,
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compte de l'utilisateur sur l'écran de démarrage (provisoire : nom saisi, en attendant le jeton abonné).
class _Compte extends StatelessWidget {
  const _Compte({required this.nom, required this.onChanged});

  final String nom;
  final ValueChanged<String> onChanged;

  String get _initiales {
    final mots = nom.split(RegExp(r'[\s._-]+')).where((m) => m.isNotEmpty).take(2);
    return mots.map((m) => m[0].toUpperCase()).join();
  }

  Future<void> _modifier(BuildContext context) async {
    var saisi = nom;
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Compte'),
        content: TextFormField(
          initialValue: nom,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom', helperText: 'Provisoire, en attendant le jeton abonné'),
          onChanged: (t) => saisi = t,
          onFieldSubmitted: (t) => Navigator.pop(c, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, saisi), child: const Text('Valider')),
        ],
      ),
    );
    if (res != null) onChanged(res);
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Nge.ardoise,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Nge.ardoiseClaire),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _modifier(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Nge.jaune,
                child: Text(_initiales,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Nge.ardoiseFoncee)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nom, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white)),
                  const Text('Compte provisoire', style: TextStyle(fontSize: 14, color: Nge.texteSurFonce)),
                ]),
              ),
              const Icon(Icons.edit_outlined, color: Nge.texteSurFonce, semanticLabel: 'Modifier le compte'),
              const SizedBox(width: 8),
            ]),
          ),
        ),
      );
}

class _Carte extends StatefulWidget {
  const _Carte();

  @override
  State<_Carte> createState() => _CarteState();
}

class _CarteState extends State<_Carte> {
  final _carte = MapController();
  late TileSource _fond = fondParDefaut(context.read<AppProvider>().emprise);
  final Set<Couche> _couches = {Couche.aerien, Couche.souterrain};
  List<Objet> _visibles = [];
  Objet? _selection;
  Timer? _attente;
  int _revision = -1;
  double _zoom = 16;
  TileProvider? _fournisseur;
  (bool, bool)? _reglages;

  /// Mention de copyright de la vue (null : mention fixe du fond, en attendant).
  String? _mention;

  /// Paquet affiché (compteur de chargements de l'AppProvider).
  int? _paquet;

  /// Cadrage sur l'emprise de la zone [minLon, minLat, maxLon, maxLat].
  static CameraFit? _cadrage(List<double>? e) => e == null
      ? null
      : CameraFit.bounds(
          bounds: LatLngBounds(LatLng(e[1], e[0]), LatLng(e[3], e[2])),
          padding: const EdgeInsets.all(32),
          maxZoom: 19,
        );

  /// Nouveau paquet : cadrage sur sa zone, fond par défaut de la zone (sauf fond Google choisi), sélection vidée.
  void _nouveauPaquet(AppProvider app) {
    if (_fond is! GoogleTiles) _fond = fondParDefaut(app.emprise);
    _selection = null;
    _mention = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _cadrage(context.read<AppProvider>().emprise);
      if (c != null) _carte.fitCamera(c);
      _recharger();
    });
  }

  /// Fournisseur de tuiles, recréé seulement quand l'option d'annulation ou le secours permis par le fond change
  /// (le TileLayer libère le courant).
  TileProvider _tuiles(bool annuler) {
    final reglages = (annuler, _fond.secours);
    if (_fournisseur == null || _reglages != reglages) {
      final ancien = _fournisseur;
      if (ancien != null) WidgetsBinding.instance.addPostFrameCallback((_) => ancien.dispose());
      _fournisseur = fournisseurTuiles(annulerObsoletes: annuler, secours: _fond.secours);
      _reglages = reglages;
    }
    return _fournisseur!;
  }

  Future<void> _majAttribution() async {
    final fond = _fond;
    try {
      final c = _carte.camera;
      final m = await fond.attributionVue(c.visibleBounds, c.zoom.round());
      if (mounted && fond == _fond && m != _mention) setState(() => _mention = m);
    } catch (_) {
      // sans connexion : la mention précédente reste affichée
    }
  }

  /// Fonds proposés (identifiant, nom) : les fonds Google seulement avec une clé renseignée.
  List<(String, String)> _fonds(String cleGoogle) => [
        ('plan', 'Plan IGN'),
        ('ortho', 'Photographies aériennes IGN'),
        ('osm', 'OpenStreetMap'),
        if (cleGoogle.isNotEmpty)
          for (final g in TypeGoogle.values) (g.name, g.nom),
      ];

  Future<void> _choisirFond(String id) async {
    final messager = ScaffoldMessenger.of(context);
    final cle = context.read<AppProvider>().cleGoogle;
    try {
      final google = TypeGoogle.values.where((g) => g.name == id).firstOrNull;
      final fond = switch (id) {
        _ when google != null => await GoogleTiles.ouvrir(google, cle),
        'ortho' => OrthoIgn(),
        'osm' => Osm(),
        _ => PlanIgn(),
      };
      if (!mounted) return;
      setState(() {
        _fond = fond;
        _mention = null;
      });
      _majAttribution();
    } catch (e) {
      messager.showSnackBar(SnackBar(content: Text('Fond de plan indisponible : $e')));
    }
  }

  @override
  void dispose() {
    _attente?.cancel();
    super.dispose();
  }

  /// Recharge les objets dont l'emprise coupe la vue (jamais toute la zone d'un coup).
  void _recharger() {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 150), () async {
      if (!mounted) return;
      final app = context.read<AppProvider>();
      final b = _carte.camera.visibleBounds;
      _zoom = _carte.camera.zoom;
      _majAttribution();
      final objets = await app.repo.objetsDansEmprise(
        [b.west, b.south, b.east, b.north],
        classes: {Classe.noe, Classe.lin, if (_couches.contains(Couche.administratif) && _zoom >= 16) Classe.adr},
      );
      // un support supprimé (abandonné) quitte la sélection
      final sel = _selection == null ? null : await app.repo.objet(_selection!.id);
      if (mounted) {
        setState(() {
          _visibles = objets;
          _selection = sel == null || sel.abandonne ? null : sel;
        });
      }
    });
  }

  /// Support choisi dans le bandeau de recherche : sélectionné et centré.
  void _choisirResultat(Objet o) {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = o.point;
    if (p != null) _carte.move(p, _carte.camera.zoom < 19 ? 19 : _carte.camera.zoom);
    setState(() => _selection = o);
    _recharger();
  }

  /// Panneau Couches : couches métier (œil) et fond de plan.
  void _ouvrirCouches() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (feuille) => StatefulBuilder(builder: (feuille, majFeuille) {
        final app = context.read<AppProvider>();
        final t = Theme.of(feuille).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Couches', style: t.titleMedium),
              for (final k in Couche.values)
                Builder(builder: (_) {
                  final visible = _couches.contains(k);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(color: k.couleur, borderRadius: BorderRadius.circular(3)),
                    ),
                    title: Text(k.lib),
                    subtitle: Text(k.detail),
                    trailing: Icon(
                      visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: visible ? Nge.ardoise : Nge.texteSecondaire,
                      semanticLabel: visible ? 'affichée' : 'masquée',
                    ),
                    onTap: () {
                      setState(() => visible ? _couches.remove(k) : _couches.add(k));
                      majFeuille(() {});
                      _recharger();
                    },
                  );
                }),
              const Divider(height: 24),
              Text('Fond de plan', style: t.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (id, nom) in _fonds(app.cleGoogle))
                  ChoiceChip(
                    label: Text(nom),
                    selected: _fond.nom == nom,
                    onSelected: (_) async {
                      await _choisirFond(id);
                      if (feuille.mounted) majFeuille(() {});
                    },
                  ),
              ]),
              if (app.cleGoogle.isEmpty) ...[
                const SizedBox(height: 8),
                Text('Fonds Google : renseigner votre clé Map Tiles dans les Paramètres.', style: t.bodySmall),
              ],
            ]),
          ),
        );
      }),
    );
  }

  bool _visible(Objet o, Referentiels ref) {
    final k = Couche.de(o, ref);
    return k == null || _couches.contains(k);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    if (app.revision != _revision) {
      _revision = app.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recharger());
    }
    // premier paquet : cadrage initial de la carte ; suivants : recadrage
    if (_paquet != app.paquets) {
      if (_paquet != null) _nouveauPaquet(app);
      _paquet = app.paquets;
    }
    final fond = _fond;
    if (fond is GoogleTiles && fond.cle != app.cleGoogle) {
      // clé Google retirée ou changée : retour au fond par défaut de la zone
      _fond = fondParDefaut(app.emprise);
      _mention = null;
    }
    final e = app.emprise;
    final ref = app.referentiels;
    final affiches = _visibles.where((o) => _visible(o, ref)).toList();
    final noeuds = affiches.where((o) => o.classe != Classe.lin).toList()
      ..sort((a, b) => a.classe.index.compareTo(b.classe.index) == 0 ? 0 : (a.classe == Classe.adr ? -1 : 1));
    // le support sélectionné au-dessus des autres
    final sel = _selection;
    final iSel = sel == null ? -1 : noeuds.indexWhere((n) => n.id == sel.id);
    if (iSel >= 0) noeuds.add(noeuds.removeAt(iSel));
    return Scaffold(
      bottomNavigationBar: BarreBasse(entrees: [
        EntreeBarre(icone: Icons.layers_outlined, libelle: 'Couches', onPressed: _ouvrirCouches),
        // création d'un support sur la carte : à venir
        const EntreeBarre(icone: Icons.add_location_alt_outlined, libelle: 'Créer'),
        EntreeBarre(
          icone: Icons.outbox_outlined,
          libelle: 'Retour',
          badge: app.nbModifies,
          onPressed: app.nbModifies == 0 ? null : () => exporterRetour(context),
        ),
        EntreeBarre(
          icone: Icons.settings_outlined,
          libelle: 'Paramètres',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ParametresScreen())),
        ),
      ]),
      body: Column(children: [
        _Bandeau(zone: app.titre, auteur: app.auteur, onChoisi: _choisirResultat),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _carte,
              options: MapOptions(
                initialCameraFit: _cadrage(e),
                initialCenter: const LatLng(46.6, 2.4),
                initialZoom: 6,
                maxZoom: 21,
                onMapReady: _recharger,
                onMapEvent: (ev) {
                  if (ev is MapEventMoveEnd || ev is MapEventFlingAnimationEnd || ev is MapEventDoubleTapZoomEnd ||
                      ev is MapEventScrollWheelZoom) {
                    _recharger();
                  }
                },
                onTap: (_, _) => setState(() => _selection = null),
              ),
              children: [
                TileLayer(
                  urlTemplate: _fond.urlTemplate,
                  maxNativeZoom: _fond.zoomMax,
                  userAgentPackageName: 'fr.nge.esplorer',
                  tileProvider: _tuiles(app.annulerTuilesObsoletes),
                ),
                PolylineLayer(polylines: [
                  for (final l in affiches.where((o) => o.classe == Classe.lin)) _trait(l, ref),
                ]),
                MarkerLayer(markers: [for (final n in noeuds) _marqueur(n, ref)]),
              ],
            ),
            // l'aperçu au-dessus de l'attribution, qui ne doit jamais être masquée
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (sel != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _Apercu(objet: sel, referentiels: ref),
                  ),
                _Attribution(logo: _fond.logo, mention: _mention ?? _fond.attribution),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Polyline _trait(Objet l, Referentiels ref) {
    final famille = ref.codeFamille(l.typeKey);
    final modifie = l.statut != null;
    final couleur = switch (famille) {
      'LIN-AER' => l.props['IMPL_KEY'] == 1 ? couleurEnergie : couleurTelecom,
      'LIN-FAC' => couleurFacade,
      'LIN-SOUT' => couleurSouterrain,
      _ => Colors.grey,
    };
    return Polyline(
      points: l.ligne,
      color: modifie ? couleurModifie : couleur,
      strokeWidth: modifie ? 4 : 2.5,
      pattern: famille == 'LIN-AER' ? const StrokePattern.solid() : StrokePattern.dashed(segments: const [8, 5]),
    );
  }

  /// Support : forme et couleur du métier ; sélection en jaune cerclé de bleu ; modifié cerclé de magenta ;
  /// étiquette encadrée à la couleur du métier à partir du zoom 18 (et toujours pour la sélection).
  Marker _marqueur(Objet n, Referentiels ref) {
    final famille = ref.codeFamille(n.typeKey);
    final selectionne = _selection?.id == n.id;
    final taille = n.classe == Classe.adr ? 8.0 : (selectionne ? 20.0 : (_zoom >= 17 ? 16.0 : 11.0));
    final (couleur, forme) = switch (famille) {
      'POT' => (n.typeKey == 15 ? couleurEnergie : couleurTelecom, BoxShape.rectangle),
      'CHB' => (couleurSouterrain, BoxShape.rectangle),
      'FAC' => (couleurFacade, BoxShape.circle),
      _ when n.classe == Classe.adr => (couleurAdresse, BoxShape.circle),
      _ => (Colors.grey, BoxShape.circle),
    };
    final etiquette = (_zoom >= 18 || selectionne) && n.classe == Classe.noe && n.lib != null;
    final (fond, bord) = selectionne
        ? (Nge.jaune, Nge.ardoise)
        : (
            famille == 'CHB' ? couleur.withValues(alpha: 0.25) : couleur,
            n.statut != null ? couleurModifie : (famille == 'CHB' ? couleur : Colors.white),
          );
    // le symbole reste sur le point, l'étiquette dessous
    final hauteur = taille + 8 + (etiquette ? 22 : 0);
    return Marker(
      point: n.point!,
      width: etiquette ? 140 : taille + 8,
      height: hauteur,
      alignment: etiquette ? Alignment(0, 1 - (taille + 8) / hauteur) : Alignment.center,
      child: GestureDetector(
        onTap: n.classe == Classe.adr ? null : () => setState(() => _selection = n),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: taille,
            height: taille,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: forme,
              color: fond,
              border: Border.all(color: bord, width: selectionne ? 3 : 1.5),
            ),
          ),
          if (etiquette)
            Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selectionne ? Nge.jaune : Colors.white.withValues(alpha: 0.9),
                border: Border.all(color: selectionne ? Nge.ardoise : couleur, width: selectionne ? 1.5 : 1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(n.lib!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, height: 1.5, fontWeight: FontWeight.w700, color: Nge.ardoiseFoncee)),
            ),
        ]),
      ),
    );
  }
}

/// Couches métier du panneau Couches.
enum Couche {
  aerien('Aérien', 'Poteaux, portées, façades', couleurTelecom),
  souterrain('Souterrain', 'Chambres, fourreaux', couleurSouterrain),
  administratif('Administratif', 'Adresses, à partir du zoom 16', couleurAdresse);

  const Couche(this.lib, this.detail, this.couleur);
  final String lib;
  final String detail;
  final Color couleur;

  /// Couche d'un objet (null : toujours affiché).
  static Couche? de(Objet o, Referentiels ref) {
    if (o.classe == Classe.adr) return administratif;
    return switch (ref.codeFamille(o.typeKey)) {
      'POT' || 'FAC' || 'LIN-AER' || 'LIN-FAC' => aerien,
      'CHB' || 'LIN-SOUT' => souterrain,
      _ => null,
    };
  }
}

/// Attribution du fond, en bas de la carte : logo éventuel à gauche (hauteur 18 dp, marges libres de 10 dp et 5 dp en
/// bas, règles Google Maps Platform), mention de copyright sur une ligne à droite.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.logo, required this.mention});

  final String? logo;
  final String mention;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (logo != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
          child: Semantics(label: 'Google Maps', image: true, child: Image.asset(logo!, height: 18)),
        ),
      const Spacer(),
      if (mention.isNotEmpty)
        Flexible(
          flex: 4,
          child: Container(
            color: Colors.white.withValues(alpha: 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(mention,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right),
          ),
        ),
    ]);
  }
}

/// Bandeau « Identification support » (maquette Figma) : recherche d'un support par son étiquette, menu de la zone.
class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.zone, required this.auteur, required this.onChoisi});

  final String zone;
  final String auteur;
  final ValueChanged<Objet> onChoisi;

  static const _arrondi = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return Container(
      decoration: const BoxDecoration(
        color: Nge.ardoise,
        border: Border(bottom: BorderSide(color: Nge.jaune, width: Nge.epaisseurFilet)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Autocomplete<Objet>(
                  displayStringForOption: (o) => o.lib ?? '',
                  optionsBuilder: (v) => v.text.trim().isEmpty ? const <Objet>[] : app.repo.rechercher(v.text),
                  onSelected: onChoisi,
                  fieldViewBuilder: (context, ctl, focus, valider) => TextField(
                    controller: ctl,
                    focusNode: focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => valider(),
                    decoration: InputDecoration(
                      hintText: 'Identification support',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, color: Nge.ardoiseFoncee),
                      border: const OutlineInputBorder(borderRadius: _arrondi),
                      enabledBorder: const OutlineInputBorder(borderRadius: _arrondi, borderSide: BorderSide.none),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: _arrondi,
                        borderSide: BorderSide(color: Nge.jaune, width: 2),
                      ),
                      suffixIcon: ListenableBuilder(
                        listenable: ctl,
                        builder: (context, _) => ctl.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: 'Effacer',
                                icon: const Icon(Icons.close, color: Nge.texteSecondaire),
                                onPressed: ctl.clear,
                              ),
                      ),
                    ),
                  ),
                  optionsViewBuilder: (context, choisir, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 320, maxWidth: c.maxWidth),
                        child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                          for (final o in options)
                            ListTile(
                              title: Text(o.lib ?? ''),
                              subtitle: Text(app.referentiels.libType(o.typeKey)),
                              onTap: () => choisir(o),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) {
                if (v == 'ouvrir') ouvrirPaquet(context);
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text('Zone : $zone')),
                PopupMenuItem(enabled: false, child: Text('Compte : $auteur')),
                const PopupMenuItem(value: 'ouvrir', child: Text('Ouvrir un autre paquet')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Aperçu du support sélectionné, avant d'ouvrir sa fiche.
class _Apercu extends StatelessWidget {
  const _Apercu({required this.objet, required this.referentiels});

  final Objet objet;
  final Referentiels referentiels;

  @override
  Widget build(BuildContext context) {
    final famille = referentiels.codeFamille(objet.typeKey);
    final t = Theme.of(context).textTheme;
    return Card(
      elevation: 4,
      shadowColor: Nge.ardoiseFoncee.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(objet.lib ?? 'Sans étiquette', style: t.titleMedium?.copyWith(fontSize: 18)),
          Text(
            [
              referentiels.libType(objet.typeKey),
              if (objet.statut == 'C') 'créé',
              if (objet.statut == 'M') 'modifié',
              if (objet.horsZone) 'hors zone',
            ].join(' · '),
            style: t.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(children: [
            if (famille == 'POT' && objet.point != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => RosaceScreen(poteau: objet))),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Portées'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                onPressed: () => ouvrirSupport(context, objet),
                child: const Text('Ouvrir'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
