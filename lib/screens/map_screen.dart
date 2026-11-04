import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../lng.dart';
import '../map/flight.dart';
import '../map/point_layer.dart';
import '../map/colors.dart';
import '../map/symbols.dart';
import '../map/selection.dart';
import '../map/tile_source.dart';
import '../data/geo_object.dart';
import '../data/reference_data.dart';
import '../modules/poteau/rosette_screen.dart';
import '../modules/completion.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/back_to_map.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/support_bar.dart';
import 'settings_screen.dart';
import 'visuals_screen.dart';
import '../widgets/messages.dart';

/// Écran principal : accueil tant qu'aucun paquet n'est chargé, puis carte de la zone.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return app.isOpen ? const _MapView() : const _Home();
  }
}

/// Ouvre un paquet de zone, qui remplace le paquet en cours. Web : les modifications non exportées, gardées en
/// mémoire seulement, seraient perdues ; confirmation demandée (exporter, abandonner ou annuler).
Future<void> openBundle(BuildContext context) async {
  final app = context.read<AppProvider>();
  if (kIsWeb && app.toExport) {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Modifications non exportées')),
        content: Text(trn(
            app.nbChanged,
            '{0} objet modifié dans le paquet en cours n\'a pas été exporté. Ouvrir un autre paquet l\'effacera.',
            '{0} objets modifiés dans le paquet en cours n\'ont pas été exportés. Ouvrir un autre paquet les effacera.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler'))),
          TextButton(onPressed: () => Navigator.pop(c, 'abandonner'), child: Text(tr('Abandonner les modifications'))),
          FilledButton(onPressed: () => Navigator.pop(c, 'exporter'), child: Text(tr('Exporter le retour'))),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'exporter') await exportReturn(context);
  }
  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['zip'], dialogTitle: tr('Paquet de zone'));
  if (f == null) return;
  await app.loadBundle(await f.readAsBytes());
}

/// Exporte le paquet de retour (objets modifiés et intervention), puis le marque exporté ([AppProvider.markExported] :
/// les commentaires qu'il contient sont figés).
///
/// Sur le web ([web]), file_picker télécharge le ZIP et ne rend jamais de fichier (mode téléchargement, par défaut) :
/// le téléchargement vaut export. Ailleurs, sans fichier rendu, l'export est annulé : le retour reste à exporter.
Future<void> exportReturn(BuildContext context, {bool web = kIsWeb}) async {
  final app = context.read<AppProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final (name, zip) = await app.returnBundle();
  final saved = await FilePicker.saveFile(fileName: name, bytes: zip, mimeType: 'application/zip', dialogTitle: tr('Paquet de retour'));
  if (saved == null && !web) {
    messenger.replaceSnackBar(SnackBar(content: Text(tr('Export annulé'))));
    return;
  }
  app.markExported();
  messenger.replaceSnackBar(SnackBar(content: Text(trn(app.nbChanged, 'Paquet de retour : {1} ({0} objet)', 'Paquet de retour : {1} ({0} objets)', [name]))));
}

/// Écran de démarrage (support de marque, bleu nuit) : logo NGE, compte, ouverture d'un paquet de zone.
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      backgroundColor: Nge.navyBlue,
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
                        Text(tr('Saisie terrain · télécoms et électricité'),
                            style: const TextStyle(fontSize: 16, color: Nge.textOnDark)),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(width: 48, height: Nge.ruleThickness, color: Nge.yellow),
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        _Account(name: app.author, onChanged: app.setAuthor),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          onPressed: app.loading ? null : () => openBundle(context),
                          icon: app.loading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.folder_open_outlined),
                          label: Text(tr('Ouvrir un paquet de zone')),
                        ),
                        if (app.error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Text(app.error!, style: const TextStyle(color: Nge.red)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          tr('Version web de développement : données de test uniquement, conservées en mémoire '
                             'jusqu\'au rechargement de la page. Exportez le paquet de retour avant de fermer.'),
                          style: const TextStyle(fontSize: 13, color: Nge.textOnDark),
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
class _Account extends StatelessWidget {
  const _Account({required this.name, required this.onChanged});

  final String name;
  final ValueChanged<String> onChanged;

  String get _initials {
    final words = name.split(RegExp(r'[\s._-]+')).where((m) => m.isNotEmpty).take(2);
    return words.map((m) => m[0].toUpperCase()).join();
  }

  Future<void> _edit(BuildContext context) async {
    var entered = name;
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Compte')),
        content: TextFormField(
          initialValue: name,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Nom'), helperText: tr('Provisoire, en attendant le jeton abonné')),
          onChanged: (t) => entered = t,
          onFieldSubmitted: (t) => Navigator.pop(c, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(c, entered), child: Text(tr('Valider'))),
        ],
      ),
    );
    if (res != null) onChanged(res);
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Nge.slate,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Nge.slateLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _edit(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Nge.yellow,
                child: Text(_initials,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Nge.slateDark)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white)),
                  Text(tr('Compte provisoire'), style: const TextStyle(fontSize: 14, color: Nge.textOnDark)),
                ]),
              ),
              Icon(Icons.edit_outlined, color: Nge.textOnDark, semanticLabel: tr('Modifier le compte')),
              const SizedBox(width: 8),
            ]),
          ),
        ),
      );
}

class _MapView extends StatefulWidget {
  const _MapView();

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> with TickerProviderStateMixin {
  final _mapController = MapController();
  late TileSource _baseMap = defaultBaseMap(context.read<AppProvider>().bounds);
  final Set<MapLayer> _layers = {MapLayer.aerial, MapLayer.underground};
  List<GeoObject> _inView = [];

  /// Statut de renseignement des supports visibles, par id.
  Map<String, Completion?> _statuses = {};

  /// Statuts déjà calculés, par id, avec l'objet lu dans le dépôt (vidé à chaque écriture).
  final Map<String, (GeoObject, Completion?)> _statusCache = {};

  /// Support sélectionné ([AppProvider.selectedSupport]), lu dans le dépôt.
  GeoObject? _selection;

  /// Route de la carte ; [_away] : un autre écran est au premier plan, quitté avec [_leftWith] sélectionné.
  Route<dynamic>? _route;
  bool _away = false;
  String? _leftWith;

  bool _screensScheduled = false;

  /// Vol de repérage en cours ([Flight]) et pulsations de la sélection à l'arrivée (trois battements amortis) ;
  /// contrôleurs créés à l'initialisation (créés à la demande, le premier aurait pu l'être au démontage).
  late final AnimationController _flightController;
  Flight? _flight;
  late final AnimationController _pulse;
  Timer? _debounce;
  int _revision = -1;
  double _zoom = 16;
  TileProvider? _tileProvider;
  (bool, bool)? _settings;

  /// Mention de copyright de la vue (null : mention fixe du fond, en attendant).
  String? _credit;

  /// Rechargement des tuiles du fond (trous laissés par des tuiles en échec).
  final _baseMapReload = StreamController<void>.broadcast();
  Timer? _scheduledReload;
  DateTime? _lastReload;

  /// Tuile en échec : rechargement du fond 3 s plus tard, au plus une fois toutes les 30 s (sans connexion, pas de
  /// boucle de requêtes).
  void _onTileError() {
    final d = _lastReload;
    if (_scheduledReload?.isActive ?? false) return;
    if (d != null && DateTime.now().difference(d) < const Duration(seconds: 30)) return;
    _scheduledReload = Timer(const Duration(seconds: 3), _reloadBaseMap);
  }

  void _reloadBaseMap() {
    _lastReload = DateTime.now();
    if (!_baseMapReload.isClosed) _baseMapReload.add(null);
  }

  /// Paquet affiché (compteur de chargements de l'AppProvider).
  int? _bundle;

  /// Cadrage sur l'emprise de la zone [minLon, minLat, maxLon, maxLat].
  static CameraFit? _fit(List<double>? e) => e == null
      ? null
      : CameraFit.bounds(
          bounds: LatLngBounds(LatLng(e[1], e[0]), LatLng(e[3], e[2])),
          padding: const EdgeInsets.all(32),
          maxZoom: 19,
        );

  /// Nouveau paquet : cadrage sur sa zone, fond par défaut de la zone (sauf fond Google choisi), sélection vidée,
  /// supports quittés oubliés.
  void _newBundle(AppProvider app) {
    if (_baseMap is! GoogleTiles) _baseMap = defaultBaseMap(app.bounds);
    _selection = null;
    _credit = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stopFlight();
      screenStack.forgetVisits();
      final c = _fit(context.read<AppProvider>().bounds);
      if (c != null) _mapController.fitCamera(c);
      _reload();
    });
  }

  /// Fournisseur de tuiles, recréé seulement quand l'option d'annulation ou le secours permis par le fond change
  /// (le TileLayer libère le courant).
  TileProvider _tiles(bool cancel) {
    final settings = (cancel, _baseMap.fallback);
    if (_tileProvider == null || _settings != settings) {
      final former = _tileProvider;
      if (former != null) WidgetsBinding.instance.addPostFrameCallback((_) => former.dispose());
      _tileProvider = tileProvider(cancelStale: cancel, fallback: _baseMap.fallback);
      _settings = settings;
    }
    return _tileProvider!;
  }

  Future<void> _updateAttribution() async {
    final baseMap = _baseMap;
    try {
      final c = _mapController.camera;
      final m = await baseMap.viewAttribution(c.visibleBounds, c.zoom.round());
      if (mounted && baseMap == _baseMap && m != _credit) setState(() => _credit = m);
    } catch (_) {
      // sans connexion : la mention précédente reste affichée
    }
  }

  Future<void> _selectBaseMap(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final apiKey = context.read<AppProvider>().googleKey;
    try {
      final baseMap = await openBaseMap(id, apiKey);
      if (!mounted) return;
      setState(() {
        _baseMap = baseMap;
        _credit = null;
      });
      _updateAttribution();
    } catch (e) {
      messenger.replaceSnackBar(SnackBar(content: Text(tr('Fond de plan indisponible : {0}', [e]))));
    }
  }

  @override
  void initState() {
    super.initState();
    _flightController = AnimationController(vsync: this)
      ..addListener(_fly)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _arrived();
      });
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    screenStack.addListener(_onScreens);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    screenStack.removeListener(_onScreens);
    _flightController.dispose();
    _pulse.dispose();
    _debounce?.cancel();
    _scheduledReload?.cancel();
    _baseMapReload.close();
    super.dispose();
  }

  /// Pile des écrans changée (après tout remplacement) : la sélection suit le support affiché (ouvert depuis la
  /// carte, atteint par un parcours, rouvert par le menu ⋮) ; revenue au premier plan, la carte repère la sélection
  /// si elle a changé entre-temps, ou si on l'a demandé (« Repérer sur la carte »). Différé : la pile change aussi
  /// pendant la construction des écrans.
  void _onScreens() {
    if (_screensScheduled) return;
    _screensScheduled = true;
    scheduleMicrotask(() {
      _screensScheduled = false;
      if (!mounted) return;
      final app = context.read<AppProvider>();
      final before = app.selectedSupport;
      final shown = screenStack.shown;
      if (shown != null) app.selectSupport(shown.id);
      // dialogues et panneaux de la carte : elle reste au premier plan
      final pages = screenStack.stack.where((r) => r is! PopupRoute);
      if (pages.isEmpty) return; // pile non suivie (essais sans observateur)
      if (pages.last != _route) {
        if (!_away) {
          _away = true;
          _leftWith = before;
          // repérage en cours (support ouvert pendant le vol) : achevé d'emblée, la carte l'attend au retour
          _finishFlight();
        }
        return;
      }
      if (!_away) return;
      _away = false;
      final requested = app.takeLocate();
      final id = app.selectedSupport;
      if (id != null && (id != _leftWith || requested != null)) _locateId(id);
    });
  }

  /// Repère le support [id], lu dans le dépôt.
  Future<void> _locateId(String id) async {
    final o = await context.read<AppProvider>().repo.object(id);
    if (mounted && o != null && !o.abandoned) _locate(o);
  }

  /// Repère [o] à la manière de « Repérer » de FibReady : vol de la vue jusqu'à lui (placement direct si l'animation
  /// est désactivée dans les paramètres, ou si le vol serait trop long), zoom d'arrivée borné par le rayon de
  /// repérage ([locateZoom]), puis trois pulsations de la sélection.
  void _locate(GeoObject o) {
    final p = o.point;
    if (p == null) return;
    final app = context.read<AppProvider>();
    _stopFlight();
    setState(() => _selection = o);
    final camera = _mapController.camera;
    final flight = Flight(camera, p, locateZoom(camera, p, app.locateRadius));
    if (!app.animateLocate || flight.duration == Duration.zero) {
      _mapController.move(flight.center, flight.zoom);
      _arrived();
      return;
    }
    _flight = flight;
    _flightController
      ..duration = flight.duration
      ..forward(from: 0);
  }

  void _fly() {
    final f = _flight;
    if (f == null) return;
    final (center, zoom) = f.at(Curves.ease.transform(_flightController.value));
    _mapController.move(center, zoom);
  }

  void _arrived() {
    _flight = null;
    _pulse.forward(from: 0);
    _reload();
  }

  /// Interrompt le vol (geste sur la carte, nouveau paquet) : la vue reste où elle est.
  void _stopFlight() {
    if (_flight == null) return;
    _flight = null;
    _flightController.stop();
    _reload();
  }

  /// Achève le vol d'emblée (la carte passe sous un autre écran) : la vue est à l'arrivée au retour.
  void _finishFlight() {
    final f = _flight;
    if (f == null) return;
    _flight = null;
    _flightController.stop();
    _mapController.move(f.center, f.zoom);
    _reload();
  }

  /// Amplitude de la pulsation à l'instant [t] (0 à 1) : trois battements qui s'amortissent.
  static double _wave(double t) => math.pow(math.sin(t * math.pi * 3), 2) * (1 - t);

  /// Recharge les objets dont l'emprise coupe la vue (jamais toute la zone d'un coup).
  void _reload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      if (!mounted) return;
      final app = context.read<AppProvider>();
      final b = _mapController.camera.visibleBounds;
      _zoom = _mapController.camera.zoom;
      _updateAttribution();
      final objects = await app.repo.objectsInBounds(
        [b.west, b.south, b.east, b.north],
        classes: {ObjectClass.noe, ObjectClass.lin, if (_layers.contains(MapLayer.administrative) && _zoom >= 16) ObjectClass.adr},
      );
      final statuses = <String, Completion?>{};
      for (final o in objects.where((o) => o.objectClass == ObjectClass.noe)) {
        final c = _statusCache[o.id];
        statuses[o.id] = c != null && identical(c.$1, o)
            ? c.$2
            : (_statusCache[o.id] = (o, await completionOf(o, app.referenceData, app.repo))).$2;
      }
      // un support supprimé (abandonné) quitte la sélection
      final id = app.selectedSupport;
      final sel = id == null ? null : await app.repo.object(id);
      if (!mounted) return;
      final gone = sel == null || sel.abandoned;
      if (gone && id != null && app.selectedSupport == id) app.selectSupport(null);
      setState(() {
        _inView = objects;
        _statuses = statuses;
        if (app.selectedSupport == null) {
          _selection = null;
        } else if (!gone && app.selectedSupport == sel.id) {
          _selection = sel;
        }
      });
    });
  }

  /// Sélection changée hors de la carte (support affiché, nouveau paquet) : l'objet est lu dans le dépôt.
  void _syncSelection(AppProvider app) {
    final id = app.selectedSupport;
    if (id == _selection?.id) return;
    _selection = null;
    if (id == null) return;
    app.repo.object(id).then((o) {
      if (mounted && app.selectedSupport == id && o != null && !o.abandoned) setState(() => _selection = o);
    });
  }

  /// Support choisi dans le bandeau de recherche : sélectionné et repéré.
  void _selectResult(GeoObject o) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.read<AppProvider>().selectSupport(o.id);
    _locate(o);
  }

  /// Panneau Couches : couches métier (œil) et fond de plan.
  void _openLayers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheetState) {
        final app = context.read<AppProvider>();
        final t = Theme.of(sheetContext).textTheme;
        // défilant : sur un petit téléphone ou en grands caractères, le panneau dépasse la hauteur de l'écran
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Couches'), style: t.titleMedium),
              for (final k in MapLayer.values)
                Builder(builder: (_) {
                  final visible = _layers.contains(k);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(color: k.color, borderRadius: BorderRadius.circular(3)),
                    ),
                    title: Text(tr(k.lib)),
                    subtitle: Text(tr(k.detail)),
                    trailing: Icon(
                      visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: visible ? Nge.slate : Nge.secondaryText,
                      semanticLabel: visible ? tr('affichée') : tr('masquée'),
                    ),
                    onTap: () {
                      setState(() => visible ? _layers.remove(k) : _layers.add(k));
                      setSheetState(() {});
                      _reload();
                    },
                  );
                }),
              const Divider(height: 24),
              Text(tr('Renseignement des supports'), style: t.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, children: [
                for (final r in Completion.values)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    SupportSymbol(family: 'POT', fill: r.color, size: 22),
                    const SizedBox(width: 6),
                    Text(tr(r.lib)),
                  ]),
              ]),
              const SizedBox(height: 4),
              Text(tr('Encre bleue : appui énergie. Pastille magenta : modifié.'), style: t.bodySmall),
              const Divider(height: 24),
              Text(tr('Fond de plan'), style: t.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (id, name) in availableBaseMaps(app.googleKey))
                  ChoiceChip(
                    label: Text(name),
                    selected: _baseMap.name == name,
                    onSelected: (_) async {
                      await _selectBaseMap(id);
                      if (sheetContext.mounted) setSheetState(() {});
                    },
                  ),
              ]),
              if (app.googleKey.isEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('Fonds Google : renseigner votre clé Map Tiles dans les Paramètres.'), style: t.bodySmall),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _reloadBaseMap();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Recharger le fond de plan')),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  bool _visible(GeoObject o, ReferenceData ref) {
    final k = MapLayer.of(o, ref);
    return k == null || _layers.contains(k);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    if (app.revision != _revision) {
      _revision = app.revision;
      _statusCache.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
    // premier paquet : cadrage initial de la carte ; suivants : recadrage
    if (_bundle != app.bundleCount) {
      if (_bundle != null) _newBundle(app);
      _bundle = app.bundleCount;
    }
    _syncSelection(app);
    final baseMap = _baseMap;
    if (baseMap is GoogleTiles && baseMap.apiKey != app.googleKey) {
      // clé Google retirée ou changée : retour au fond par défaut de la zone
      _baseMap = defaultBaseMap(app.bounds);
      _credit = null;
    }
    final e = app.bounds;
    final ref = app.referenceData;
    // le support sélectionné toujours dessiné, même si sa couche est masquée (repéré, il doit se voir)
    final sel = _selection;
    final displayed = _inView.where((o) => _visible(o, ref) || o.id == sel?.id).toList();
    final nodes = displayed.where((o) => o.objectClass != ObjectClass.lin).toList()
      ..sort((a, b) => a.objectClass.index.compareTo(b.objectClass.index) == 0 ? 0 : (a.objectClass == ObjectClass.adr ? -1 : 1));
    // le support sélectionné au-dessus des autres
    final iSel = sel == null ? -1 : nodes.indexWhere((n) => n.id == sel.id);
    if (iSel >= 0) nodes.add(nodes.removeAt(iSel));
    return Scaffold(
      // le clavier de la recherche recouvre le bas de la carte sans la rétrécir : le zoom d'un repérage est calculé
      // sur la carte entière
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: BottomBar(items: [
        BarItem(icon: Icons.layers_outlined, label: tr('Couches'), onPressed: _openLayers),
        // création d'un support sur la carte : à venir
        BarItem(icon: Icons.add_location_alt_outlined, label: tr('Créer')),
        BarItem(
          icon: Icons.outbox_outlined,
          label: tr('Retour'),
          badge: app.nbChanged,
          onPressed: app.nbChanged == 0 ? null : () => exportReturn(context),
        ),
        BarItem(
          icon: Icons.settings_outlined,
          label: tr('Paramètres'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ]),
      body: Column(children: [
        _Banner(zone: app.title, author: app.author, onSelected: _selectResult),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCameraFit: _fit(e),
                initialCenter: const LatLng(46.6, 2.4),
                initialZoom: 6,
                // au-delà du zoom natif des fonds, tuiles agrandies : un rayon de repérage de 10 m reste possible sur
                // une tablette
                maxZoom: 22,
                onMapReady: _reload,
                onMapEvent: (ev) {
                  // un geste sur la carte interrompt le vol de repérage
                  if (_flight != null && _gestures.contains(ev.source)) _stopFlight();
                  if (ev is MapEventMoveEnd || ev is MapEventFlingAnimationEnd || ev is MapEventDoubleTapZoomEnd ||
                      ev is MapEventScrollWheelZoom) {
                    _reload();
                  }
                },
                onTap: (tap, _) => _onTap(tap.relative),
              ),
              children: [
                TileLayer(
                  urlTemplate: _baseMap.urlTemplate,
                  maxNativeZoom: _baseMap.maxZoom,
                  userAgentPackageName: 'fr.nge.esplorer',
                  tileProvider: _tiles(app.cancelStaleTiles),
                  // tuile en échec : oubliée hors de la vue (redemandée au retour), fond rechargé ensuite
                  evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
                  errorTileCallback: (_, _, _) => _onTileError(),
                  reset: _baseMapReload.stream,
                ),
                PolylineLayer(polylines: [
                  for (final l in displayed.where((o) => o.objectClass == ObjectClass.lin)) _polyline(l, ref),
                ]),
                // petites échelles : supports dessinés en une seule couche (des centaines de widgets déplacés à
                // chaque image saccadent le déplacement de la carte) ; la sélection reste un marqueur
                if (_points)
                  PointLayer(
                    radius: _pointRadius,
                    stroke: _zoom < 14 ? 0.75 : 1,
                    points: [
                      for (final n in nodes)
                        if (n.objectClass == ObjectClass.noe && n.id != sel?.id) _point(n),
                    ],
                  ),
                MarkerLayer(markers: [
                  for (final n in nodes)
                    if (!_points || n.objectClass != ObjectClass.noe || n.id == sel?.id) _marker(n, ref),
                ]),
              ],
            ),
            // l'aperçu au-dessus de l'attribution, qui ne doit jamais être masquée ; carte large (paysage, tablette) :
            // carton compact dans le coin bas droit ([_Preview.compactFor], notes rep9)
            Positioned.fill(
              child: LayoutBuilder(builder: (context, c) {
                final compact = _Preview.compactFor(c.maxWidth);
                // en bas de la carte ; ailleurs, les touchers passent à la carte
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: compact ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      if (sel != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ConstrainedBox(
                            // borné à la carte (grands caractères sur un téléphone en paysage) : il défile au-delà
                            constraints: BoxConstraints(
                              maxWidth: compact ? _Preview.compactWidth : double.infinity,
                              maxHeight: math.max(0, c.maxHeight - 40),
                            ),
                            child: SingleChildScrollView(
                              child: _Preview(object: sel, referenceData: ref, status: _statuses[sel.id], compact: compact),
                            ),
                          ),
                        ),
                      _Attribution(logo: _baseMap.logo, credit: _credit ?? _baseMap.attribution),
                    ],
                  ),
                );
              }),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Gestes de l'utilisateur sur la carte.
  static const _gestures = {
    MapEventSource.tap,
    MapEventSource.doubleTap,
    MapEventSource.doubleTapHold,
    MapEventSource.dragStart,
    MapEventSource.multiFingerGestureStart,
    MapEventSource.scrollWheel,
    MapEventSource.keyboard,
    MapEventSource.cursorKeyboardRotation,
  };

  /// Petites échelles : supports en points.
  bool get _points => _zoom < symbolsZoom;

  /// Rayon des points (px) : fins de loin, pour que les supports ne se fondent pas en une masse.
  double get _pointRadius => _zoom < 13 ? 2.5 : (_zoom < 14 ? 3 : (_zoom < 15 ? 3.5 : 4.5));

  MapPoint _point(GeoObject n) => MapPoint(
        n.point!,
        fill: _statuses[n.id]?.color ?? SupportSymbol.paper,
        stroke: n.typeKey == 15 ? energyColor : Colors.black,
      );

  /// Toucher de la carte : support le plus proche (symbole ou étiquette), choix dans une liste quand plusieurs se
  /// valent ; ailleurs, la sélection est levée.
  Future<void> _onTap(Offset? screen) async {
    if (screen == null) return;
    final ref = context.read<AppProvider>().referenceData;
    final targets = <Target<GeoObject>>[];
    for (final o in _inView) {
      // la sélection est dessinée même si sa couche est masquée : elle se touche aussi
      if (o.objectClass != ObjectClass.noe || o.point == null || (!_visible(o, ref) && o.id != _selection?.id)) continue;
      final c = _mapController.camera.latLngToScreenOffset(o.point!);
      if ((c - screen).dx.abs() > 90 || (c - screen).dy.abs() > 70) continue;
      final (_, box, label) = _markerSize(o);
      Rect? rect;
      if (label) {
        final text = TextPainter(text: TextSpan(text: o.lib, style: _labelStyle), textDirection: TextDirection.ltr)
          ..layout(maxWidth: 120);
        final width = text.width + 10 + (_statuses[o.id] != null ? 12 : 0);
        text.dispose();
        rect = Rect.fromLTWH(c.dx - width / 2, c.dy + box / 2, width, 20);
      }
      targets.add(Target(o, c, label: rect, uncertain: o.props['GEOL_MOD_KEY'] == 8));
    }
    final hits = targetsAt(screen, targets, tolerance: _points ? 14 : 22);
    final choice = hits.length > 1 ? await _pickAmong(hits, ref) : hits.firstOrNull;
    if (!mounted || (choice == null && hits.isNotEmpty)) return;
    context.read<AppProvider>().selectSupport(choice?.id);
    setState(() => _selection = choice);
  }

  /// Supports qui se valent sous le doigt : l'utilisateur désigne le sien.
  Future<GeoObject?> _pickAmong(List<GeoObject> objects, ReferenceData ref) => showModalBottomSheet<GeoObject>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 8), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(tr('{0} supports à cet endroit', [objects.length]), style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final o in objects)
              ListTile(
                leading: SupportSymbol(
                  family: ref.familyCode(o.typeKey),
                  fill: _statuses[o.id]?.color,
                  energy: o.typeKey == 15,
                ),
                title: Text(o.lib ?? tr('Sans étiquette')),
                subtitle: Text([
                  ref.typeLabel(o.typeKey),
                  if (o.props['GEOL_MOD_KEY'] == 8) tr('position à relever'),
                ].join(' · ')),
                onTap: () => Navigator.pop(sheetContext, o),
              ),
          ]),
        ),
      );

  /// Taille du symbole, boîte (halo de sélection) et présence de l'étiquette d'un support.
  (double, double, bool) _markerSize(GeoObject n) {
    final selected = _selection?.id == n.id;
    final showSymbol = _zoom >= 16 || selected;
    final size = showSymbol ? (_zoom >= 17 || selected ? 24.0 : 20.0) : 10.0;
    return (size, size + 16, (_zoom >= 18 || selected) && n.lib != null);
  }

  static const _labelStyle =
      TextStyle(fontSize: 11, height: 1.5, fontWeight: FontWeight.w700, color: Nge.slateDark);

  Polyline _polyline(GeoObject l, ReferenceData ref) {
    final family = ref.familyCode(l.typeKey);
    final changed = l.status != null;
    final lineWidth = _zoom < 14 ? 1.2 : (_zoom < 16 ? 1.8 : 2.5);
    final color = switch (family) {
      'LIN-AER' => l.props['IMPL_KEY'] == 1 ? energyColor : telecomColor,
      'LIN-FAC' => facadeColor,
      'LIN-SOUT' => undergroundColor,
      _ => Colors.grey,
    };
    return Polyline(
      points: l.line,
      color: changed ? changedColor : color,
      strokeWidth: changed ? lineWidth + 1.5 : lineWidth,
      // tirets seulement aux grandes échelles (calculés à chaque image, invisibles de loin)
      pattern: family == 'LIN-AER' || _points ? const StrokePattern.solid() : StrokePattern.dashed(segments: const [8, 5]),
    );
  }

  /// Support : picto FibReady, carré intérieur à la couleur du statut de renseignement (FOA Explorer), encre bleue
  /// pour l'énergie, point aux petites échelles ; sélection : halo jaune cerclé de bleu ; modifié : pastille magenta ;
  /// étiquette à partir du zoom 18 (et toujours pour la sélection), marquée du statut. Adresse : point orange.
  /// Les touchers sont traités par la carte ([_onTap]), pas par les marqueurs.
  Marker _marker(GeoObject n, ReferenceData ref) {
    if (n.objectClass == ObjectClass.adr) {
      return Marker(
        point: n.point!,
        width: 14,
        height: 14,
        child: const Center(child: SupportPoint(fill: addressColor, ink: Colors.white, size: 8)),
      );
    }
    final family = ref.familyCode(n.typeKey);
    final selected = _selection?.id == n.id;
    final status = _statuses[n.id];
    final energy = n.typeKey == 15;
    final showSymbol = _zoom >= 16 || selected;
    final (size, box, label) = _markerSize(n);
    final margin = (box - size) / 2;
    // le symbole reste sur le point, l'étiquette dessous
    final height = box + (label ? 22 : 0);
    return Marker(
      point: n.point!,
      width: label ? 140 : box,
      height: height,
      alignment: label ? Alignment(0, 1 - box / height) : Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: box,
            height: box,
            // halo de la sélection : il pulse à l'arrivée d'un repérage, débordant du marqueur
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              if (selected)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, halo) => Transform.scale(
                      key: const ValueKey('halo'), scale: 1 + 1.1 * _wave(_pulse.value), child: halo),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Nge.yellow.withValues(alpha: 0.85),
                      border: Border.all(color: Nge.slate, width: 2.5),
                    ),
                  ),
                ),
              showSymbol
                  ? SupportSymbol(family: family, fill: status?.color, energy: energy, size: size)
                  : SupportPoint(
                      fill: status?.color ?? SupportSymbol.paper,
                      ink: energy ? energyColor : Colors.black,
                      size: size,
                    ),
              if (n.status != null && showSymbol)
                Positioned(
                  top: margin - 4,
                  right: margin - 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: changedColor,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ]),
          ),
          if (label)
            Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected ? Nge.yellow : Colors.white.withValues(alpha: 0.9),
                border: Border.all(
                  color: selected ? Nge.slate : (energy ? energyColor : Colors.black),
                  width: selected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (status != null) ...[
                  StatusSquare(color: status.color, side: 8, ink: energy ? energyColor : Colors.black),
                  const SizedBox(width: 4),
                ],
                Flexible(child: Text(n.lib!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _labelStyle)),
              ]),
            ),
        ]),
    );
  }
}

/// Couches métier du panneau Couches.
enum MapLayer {
  aerial('Aérien', 'Poteaux, portées, façades', telecomColor), // tr
  underground('Souterrain', 'Chambres, fourreaux', undergroundColor), // tr
  administrative('Administratif', 'Adresses, à partir du zoom 16', addressColor); // tr

  const MapLayer(this.lib, this.detail, this.color);
  final String lib;
  final String detail;
  final Color color;

  /// Couche d'un objet (null : toujours affiché).
  static MapLayer? of(GeoObject o, ReferenceData ref) {
    if (o.objectClass == ObjectClass.adr) return administrative;
    return switch (ref.familyCode(o.typeKey)) {
      'POT' || 'FAC' || 'LIN-AER' || 'LIN-FAC' => aerial,
      'CHB' || 'LIN-SOUT' => underground,
      _ => null,
    };
  }
}

/// Attribution du fond, en bas de la carte : logo éventuel à gauche (hauteur 18 dp, marges libres de 10 dp et 5 dp en
/// bas, règles Google Maps Platform), mention de copyright sur une ligne à droite.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.logo, required this.credit});

  final String? logo;
  final String credit;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (logo != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
          child: Semantics(label: 'Google Maps', image: true, child: Image.asset(logo!, height: 18)),
        ),
      const Spacer(),
      if (credit.isNotEmpty)
        Flexible(
          flex: 4,
          child: Container(
            color: Colors.white.withValues(alpha: 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(credit,
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
class _Banner extends StatelessWidget {
  const _Banner({required this.zone, required this.author, required this.onSelected});

  final String zone;
  final String author;
  final ValueChanged<GeoObject> onSelected;

  static const _round = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return Container(
      decoration: const BoxDecoration(
        color: Nge.slate,
        border: Border(bottom: BorderSide(color: Nge.yellow, width: Nge.ruleThickness)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Autocomplete<GeoObject>(
                  displayStringForOption: (o) => o.lib ?? '',
                  optionsBuilder: (v) => v.text.trim().isEmpty ? const <GeoObject>[] : app.repo.search(v.text),
                  onSelected: onSelected,
                  fieldViewBuilder: (context, ctl, focus, validate) => TextField(
                    controller: ctl,
                    focusNode: focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => validate(),
                    decoration: InputDecoration(
                      hintText: tr('Identification support'),
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, color: Nge.slateDark),
                      border: const OutlineInputBorder(borderRadius: _round),
                      enabledBorder: const OutlineInputBorder(borderRadius: _round, borderSide: BorderSide.none),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: _round,
                        borderSide: BorderSide(color: Nge.yellow, width: 2),
                      ),
                      suffixIcon: ListenableBuilder(
                        listenable: ctl,
                        builder: (context, _) => ctl.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: tr('Effacer'),
                                icon: const Icon(Icons.close, color: Nge.secondaryText),
                                onPressed: ctl.clear,
                              ),
                      ),
                    ),
                  ),
                  optionsViewBuilder: (context, choose, options) => Align(
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
                              subtitle: Text(app.referenceData.typeLabel(o.typeKey)),
                              onTap: () => choose(o),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: tr('Menu'),
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) {
                if (v == 'ouvrir') openBundle(context);
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text(tr('Zone : {0}', [zone]))),
                PopupMenuItem(enabled: false, child: Text(tr('Compte : {0}', [author]))),
                PopupMenuItem(value: 'ouvrir', child: Text(tr('Ouvrir un autre paquet'))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Aperçu du support sélectionné, avant d'ouvrir sa fiche. [compact] (carte large, où la carte borne le carton à
/// [compactWidth]) : boutons à leur taille naturelle, à droite ; sinon, boutons sur toute la largeur.
class _Preview extends StatelessWidget {
  const _Preview({required this.object, required this.referenceData, this.status, this.compact = false});

  final GeoObject object;
  final ReferenceData referenceData;
  final Completion? status;
  final bool compact;

  /// Largeur du carton compact : de l'ordre d'une colonne de téléphone.
  static const compactWidth = 360.0;

  /// Carton compact sur une carte d'au moins 600 dp de large (seuil Material entre fenêtres « compactes » et
  /// « moyennes ») : tablette et téléphone en paysage (640 dp et plus), où la rosace des portées passe en deux
  /// colonnes, fenêtre Windows assez large, et tablette en portrait, où toute la largeur étirerait aussi le carton.
  /// Téléphone en portrait (360 à 412 dp) : carton sur toute la largeur.
  static bool compactFor(double mapWidth) => mapWidth >= 600;

  /// Bouton à sa taille naturelle (carton compact : réduit seulement s'il n'y a pas la place, traduction longue ou
  /// grand texte) ou partageant la largeur du carton.
  Widget _fit(Widget button) => compact ? Flexible(child: button) : Expanded(child: button);

  @override
  Widget build(BuildContext context) {
    final family = referenceData.familyCode(object.typeKey);
    final t = Theme.of(context).textTheme;
    return Card(
      elevation: 4,
      shadowColor: Nge.slateDark.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(object.lib ?? tr('Sans étiquette'), style: t.titleMedium?.copyWith(fontSize: 18))),
            if (status != null)
              // rétrécie avec de grands caractères plutôt que de déborder du carton
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: status!.color,
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(tr(status!.lib),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nge.slateDark)),
                ),
              ),
          ]),
          Text(
            [
              referenceData.typeLabel(object.typeKey),
              if (object.status == 'C') tr('créé'),
              if (object.status == 'M') tr('modifié'),
              if (object.outOfZone) tr('hors zone'),
            ].join(' · '),
            style: t.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (family == 'POT' && object.point != null) ...[
              _fit(
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(settings: tabSettings(object, 'portees'), builder: (_) => RosetteScreen(pole: object))),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(tr('Portées')),
                ),
              ),
              const SizedBox(width: 10),
            ],
            _fit(
              FilledButton(
                onPressed: () => openSupport(context, object),
                child: Text(tr('Ouvrir')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
