import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../carte/tile_source.dart';
import '../data/objet.dart';
import '../data/referentiels.dart';
import '../modules/poteau/rosace_screen.dart';
import '../providers/app_provider.dart';
import 'objet_screen.dart';
import 'parametres_screen.dart';

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

class _Accueil extends StatelessWidget {
  const _Accueil();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('NgeEsPlorer', style: t.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Saisie terrain : chambres, poteaux, portées', style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              TextFormField(
                initialValue: app.auteur,
                decoration: const InputDecoration(labelText: 'Compte', helperText: 'Provisoire, en attendant le jeton abonné'),
                onChanged: app.definirAuteur,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: app.chargement ? null : () => ouvrirPaquet(context),
                icon: app.chargement
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.folder_open),
                label: const Text('Ouvrir un paquet de zone (.zip)'),
              ),
              if (app.erreur != null) ...[
                const SizedBox(height: 16),
                Text(app.erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              Text(
                'Version web de développement : données de test uniquement, conservées en mémoire '
                'jusqu\'au rechargement de la page. Exportez le paquet de retour avant de fermer.',
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Carte extends StatefulWidget {
  const _Carte();

  @override
  State<_Carte> createState() => _CarteState();
}

class _CarteState extends State<_Carte> {
  final _carte = MapController();
  late TileSource _fond = fondParDefaut(context.read<AppProvider>().emprise);
  bool _adresses = false;
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
        classes: {Classe.noe, Classe.lin, if (_adresses && _zoom >= 16) Classe.adr},
      );
      final sel = _selection == null ? null : await app.repo.objet(_selection!.id);
      if (mounted) {
        setState(() {
          _visibles = objets;
          _selection = sel;
        });
      }
    });
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
    final noeuds = _visibles.where((o) => o.classe != Classe.lin).toList()
      ..sort((a, b) => a.classe.index.compareTo(b.classe.index) == 0 ? 0 : (a.classe == Classe.adr ? -1 : 1));
    return Scaffold(
      appBar: AppBar(
        title: Text(app.titre),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Fond de plan : ${_fond.nom}',
            icon: const Icon(Icons.layers_outlined),
            onSelected: _choisirFond,
            itemBuilder: (_) => [
              for (final (id, nom) in _fonds(app.cleGoogle))
                CheckedPopupMenuItem(value: id, checked: _fond.nom == nom, child: Text(nom)),
            ],
          ),
          IconButton(
            tooltip: _adresses ? 'Masquer les adresses' : 'Afficher les adresses',
            icon: Icon(_adresses ? Icons.location_city : Icons.location_city_outlined),
            onPressed: () {
              setState(() => _adresses = !_adresses);
              _recharger();
            },
          ),
          IconButton(
            tooltip: 'Exporter le paquet de retour',
            onPressed: app.nbModifies == 0 ? null : () => exporterRetour(context),
            icon: Badge(
              isLabelVisible: app.nbModifies > 0,
              label: Text('${app.nbModifies}'),
              child: const Icon(Icons.outbox_outlined),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'ouvrir') ouvrirPaquet(context);
              if (v == 'parametres') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ParametresScreen()));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'ouvrir', child: Text('Ouvrir un autre paquet')),
              const PopupMenuItem(value: 'parametres', child: Text('Paramètres')),
              PopupMenuItem(enabled: false, child: Text('Compte : ${app.auteur}')),
            ],
          ),
        ],
      ),
      body: Stack(children: [
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
              for (final l in _visibles.where((o) => o.classe == Classe.lin)) _trait(l, ref),
            ]),
            MarkerLayer(markers: [for (final n in noeuds) _marqueur(n, ref)]),
          ],
        ),
        // le bandeau d'identification au-dessus de l'attribution, qui ne doit jamais être masquée
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_selection != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _Identification(objet: _selection!, referentiels: ref),
              ),
            _Attribution(logo: _fond.logo, mention: _mention ?? _fond.attribution),
          ]),
        ),
      ]),
    );
  }

  Polyline _trait(Objet l, Referentiels ref) {
    final famille = ref.codeFamille(l.typeKey);
    final modifie = l.statut != null;
    final couleur = switch (famille) {
      'LIN-AER' => l.props['IMPL_KEY'] == 1 ? const Color(0xFF0080CA) : const Color(0xFF26B424),
      'LIN-FAC' => const Color(0xFFE67E22),
      'LIN-SOUT' => const Color(0xFF7B3FA0),
      _ => Colors.grey,
    };
    return Polyline(
      points: l.ligne,
      color: modifie ? const Color(0xFFD5168B) : couleur,
      strokeWidth: modifie ? 4 : 2.5,
      pattern: famille == 'LIN-AER' ? const StrokePattern.solid() : StrokePattern.dashed(segments: const [8, 5]),
    );
  }

  Marker _marqueur(Objet n, Referentiels ref) {
    final famille = ref.codeFamille(n.typeKey);
    final taille = n.classe == Classe.adr ? 8.0 : (_zoom >= 17 ? 16.0 : 11.0);
    final (couleur, forme) = switch (famille) {
      'POT' => (n.typeKey == 15 ? const Color(0xFF0080CA) : const Color(0xFF26B424), BoxShape.rectangle),
      'CHB' => (const Color(0xFF7B3FA0), BoxShape.rectangle),
      'FAC' => (const Color(0xFFE67E22), BoxShape.circle),
      _ when n.classe == Classe.adr => (const Color(0xFFF39C12), BoxShape.circle),
      _ => (Colors.grey, BoxShape.circle),
    };
    final selectionne = _selection?.id == n.id;
    final etiquette = _zoom >= 18 && n.classe == Classe.noe && n.lib != null;
    return Marker(
      point: n.point!,
      width: etiquette ? 120 : taille + 8,
      height: taille + 8 + (etiquette ? 14 : 0),
      alignment: etiquette ? const Alignment(0, 0.35) : Alignment.center,
      child: GestureDetector(
        onTap: n.classe == Classe.adr ? null : () => setState(() => _selection = n),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: taille,
            height: taille,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: forme,
              color: famille == 'CHB' ? couleur.withValues(alpha: 0.25) : couleur,
              border: Border.all(
                color: selectionne || n.statut != null ? const Color(0xFFD5168B) : (famille == 'CHB' ? couleur : Colors.white),
                width: selectionne ? 3 : 1.5,
              ),
            ),
          ),
          if (etiquette)
            Text(n.lib!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, backgroundColor: Color(0xCCFFFFFF))),
        ]),
      ),
    );
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

/// Bandeau « Identification support » (maquette Figma) : objet sélectionné et actions.
class _Identification extends StatelessWidget {
  const _Identification({required this.objet, required this.referentiels});

  final Objet objet;
  final Referentiels referentiels;

  @override
  Widget build(BuildContext context) {
    final famille = referentiels.codeFamille(objet.typeKey);
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(objet.lib ?? 'Sans étiquette', style: Theme.of(context).textTheme.titleMedium),
              Text([
                referentiels.libType(objet.typeKey),
                if (objet.statut == 'C') 'créé',
                if (objet.statut == 'M') 'modifié',
                if (objet.horsZone) 'hors zone',
              ].join(' · ')),
            ]),
          ),
          if (famille == 'POT' && objet.point != null)
            IconButton(
              tooltip: 'Rosace des portées',
              icon: const Icon(Icons.explore_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RosaceScreen(poteau: objet))),
            ),
          FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ObjetScreen(objet: objet))),
            child: const Text('Fiche'),
          ),
        ]),
      ),
    );
  }
}
