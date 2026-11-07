import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../data/data_repository.dart';
import '../data/geo_object.dart';
import '../data/bundle.dart';
import '../data/reference_data.dart';
import '../data/settings.dart';
import '../modules/optique/fibready_chart.dart';
import '../data/visuals.dart';
import '../lng.dart';
import '../modules/completion.dart';
import 'page_exit.dart' if (dart.library.js_interop) 'page_exit_web.dart';

/// Paquet à ouvrir au démarrage (web, développement), demandé par l'adresse de la page, `?paquet=8091` (port du
/// serveur local, paquet à `/paquet.zip`) ou l'adresse complète du paquet, sinon à la compilation,
/// `--dart-define=PAQUET=8091` (lanceurs VS Code), servi par l'option `--paquet` de `tools/essai/serveur_photos.py`.
/// Null sinon, et toujours hors du web : un terminal ouvre ses paquets lui-même.
Uri? devBundleUrl(Uri pageUrl, {bool web = kIsWeb, String compile = const String.fromEnvironment('PAQUET')}) {
  if (!web) return null;
  final v = (pageUrl.queryParameters['paquet'] ?? compile).trim();
  if (v.isEmpty) return null;
  return Uri.parse(int.tryParse(v) != null ? 'http://localhost:$v/paquet.zip' : v);
}

/// État de la session terrain : paquet chargé, compte, intervention en cours.
class AppProvider extends ChangeNotifier {
  AppProvider(this.repo, {this.settings});

  final DataRepository repo;

  /// Paramètres conservés sur le terminal (absents dans les tests).
  final Settings? settings;

  /// Compte abonné (provisoire : saisi tant que la connexion par jeton n'existe pas).
  String author = 'terrain';
  String? error;
  bool loading = false;

  /// Option : annuler le téléchargement des tuiles qui ne seront plus affichées (désactivée par défaut).
  bool cancelStaleTiles = false;

  /// Clé Google Map Tiles renseignée par l'utilisateur, sous sa responsabilité (vide : pas de fonds Google).
  String googleKey = '';

  /// Serveur des photos demandé par l'adresse de la page (`?photos=`), prioritaire sur le paramètre.
  String? urlPhotoServer;

  /// Paramètre (web) : photos non embarquées lues au serveur local `tools/essai/serveur_photos.py`.
  bool useLocalPhotoServer = false;
  static const localPhotoServer = 'http://localhost:8090/';

  /// Serveur des photos non embarquées dans le paquet (web, développement), null sinon.
  String? get photoServer => urlPhotoServer ?? (useLocalPhotoServer ? localPhotoServer : null);

  /// Repérage d'un support sur la carte (recherche, retour d'un autre support, « Repérer sur la carte »), comme
  /// « Repérer » de FibReady : vol animé de la vue ([animateLocate], sinon placement direct) ; la vue d'arrivée montre
  /// au plus [locateRadius] m autour du support (de plus loin, la carte zoome jusque-là ; de plus près, elle garde le
  /// zoom).
  bool animateLocate = true;
  double locateRadius = defaultLocateRadius;

  /// Liens fibres (écran Optique, route optique) à la charte FibReady (`FibreRow`), sinon affichage simplifié
  /// (`LinkChip`, notes equipements rep4 : version précédente conservée).
  LinkDisplay linkDisplay = LinkDisplay.fibReady;

  /// Liens en ligne de cellules ou de pastilles (charte FibReady et sa variante), plutôt qu'en affichage simplifié.
  bool get fibReadyChart => linkDisplay != LinkDisplay.simple;
  static const defaultLocateRadius = 50.0;

  /// Rayons de repérage proposés dans les paramètres (m).
  static const locateRadii = [10.0, 20.0, 50.0, 100.0, 200.0, 500.0];

  /// Support sélectionné sur la carte (identifiant) : touché ou trouvé par la recherche, puis le support affiché
  /// (ouvert depuis la carte, atteint par un parcours, rouvert par le menu ⋮) ; null : aucun.
  String? selectedSupport;

  /// Support à repérer (« Repérer sur la carte ») quand la carte reviendra au premier plan ([takeLocate]).
  String? _locateTarget;

  void selectSupport(String? id) {
    if (id == selectedSupport) return;
    selectedSupport = id;
    notifyListeners();
  }

  /// Sélectionne le support [id] et demande à la carte de le repérer à son retour au premier plan.
  void locate(String id) {
    selectedSupport = id;
    _locateTarget = id;
    notifyListeners();
  }

  /// Renonce au repérage demandé (on est resté sur l'écran du support).
  void cancelLocate() => _locateTarget = null;

  /// Repérage demandé, retiré : la carte le traite une fois.
  String? takeLocate() {
    final id = _locateTarget;
    _locateTarget = null;
    return id;
  }

  int nbChanged = 0;

  /// Le retour a été exporté depuis la dernière modification.
  bool _exported = false;

  /// Modifications qui seraient perdues sans export (web : données en mémoire seulement).
  bool get toExport => nbChanged > 0 && !_exported;

  /// Incrémenté à chaque écriture : la carte recharge les objets visibles.
  int revision = 0;

  /// Incrémenté à chaque paquet chargé : la carte se cadre sur l'emprise de la zone.
  int bundleCount = 0;

  String? _intervention;
  String? _start;

  /// Commentaires de l'intervention (`COM_CODE_EXT`) contenus dans le dernier paquet de retour préparé
  /// ([returnBundle]), versés dans [_exportedComments] quand ce retour est exporté ([markExported]).
  Set<String> _returnedComments = const {};

  /// Commentaires de l'intervention contenus dans un paquet de retour exporté : figés ([canEditComment]). Remis à
  /// zéro au chargement d'un paquet, comme l'intervention. L'intervention en cours et cet ensemble devront être
  /// conservés avec le dépôt persistant prévu sur Android (aujourd'hui en mémoire, comme les données du web).
  final _exportedComments = <String>{};

  bool get isOpen => repo.isOpen;
  Map<String, dynamic>? get header => repo.header;
  ReferenceData get referenceData => repo.referenceData;

  String get title {
    final e = header;
    if (e == null) return 'NgeEsPlorer';
    return '${(e['zone'] as Map?)?['lib'] ?? (e['zone'] as Map?)?['code']}';
  }

  /// Emprise de la zone [minLon, minLat, maxLon, maxLat].
  List<double>? get bounds =>
      ((header?['zone'] as Map?)?['emprise'] as List?)?.map((v) => (v as num).toDouble()).toList();

  /// Ouvre le paquet servi à [url] (web, développement : [devBundleUrl]) ; une erreur s'affiche sur l'écran de
  /// démarrage, d'où l'on peut ouvrir un autre paquet.
  Future<void> loadBundleFrom(Uri url, {http.Client? client}) async {
    loading = true;
    error = null;
    notifyListeners();
    final c = client ?? http.Client();
    try {
      final r = await c.get(url);
      if (r.statusCode == 200) return await loadBundle(r.bodyBytes);
      error = tr('Paquet introuvable à {0} (HTTP {1})', [url, r.statusCode]);
    } catch (e) {
      error = tr('Paquet introuvable à {0} : {1}', [url, e]);
    } finally {
      if (client == null) c.close();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadBundle(Uint8List zip) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await repo.load(Bundle.read(zip));
      _intervention = null;
      _start = null;
      _returnedComments = const {};
      _exportedComments.clear();
      selectedSupport = null;
      _locateTarget = null;
      nbChanged = 0;
      _exported = false;
      warnBeforeLeaving(toExport);
      revision++;
      bundleCount++;
    } on FormatException catch (e) {
      error = tr('Paquet illisible : {0}', [e.message]);
    } catch (e) {
      error = tr('Paquet illisible : {0}', [e]);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setAuthor(String name) {
    author = name.trim().isEmpty ? 'terrain' : name.trim();
    notifyListeners();
  }

  Future<void> loadSettings() async {
    final r = settings;
    if (r == null) return;
    googleKey = await r.read(Settings.googleKey) ?? '';
    cancelStaleTiles = await r.read(Settings.cancelStaleTiles) == 'oui';
    useLocalPhotoServer = await r.read(Settings.useLocalPhotoServer) == 'oui';
    animateLocate = await r.read(Settings.animateLocate) != 'non';
    linkDisplay = LinkDisplay.of(await r.read(Settings.linkChart));
    final radius = double.tryParse(await r.read(Settings.locateRadius) ?? '');
    locateRadius = radius != null && radius > 0 ? radius : defaultLocateRadius;
    final language = await r.read(Settings.language);
    if (language != null && language != Lng.language) {
      await Lng.load(language);
      Lng.rebuildAll();
    }
    notifyListeners();
  }

  /// Langue de l'interface (code ISO, `Lng.languages`), appliquée tout de suite à tous les écrans.
  String get language => Lng.language;

  Future<void> setLanguage(String code) async {
    await Lng.load(code);
    settings?.write(Settings.language, Lng.language == Lng.sourceLanguage ? null : Lng.language);
    notifyListeners();
    Lng.rebuildAll();
  }

  void setUseLocalPhotoServer(bool enabled) {
    useLocalPhotoServer = enabled;
    settings?.write(Settings.useLocalPhotoServer, enabled ? 'oui' : null);
    notifyListeners();
  }

  void setFibReadyChart(bool fibReady) => setLinkDisplay(fibReady ? LinkDisplay.fibReady : LinkDisplay.simple);

  void setLinkDisplay(LinkDisplay display) {
    linkDisplay = display;
    settings?.write(Settings.linkChart, display.stored);
    notifyListeners();
  }

  void setAnimateLocate(bool animated) {
    animateLocate = animated;
    settings?.write(Settings.animateLocate, animated ? null : 'non');
    notifyListeners();
  }

  void setLocateRadius(double meters) {
    locateRadius = meters;
    settings?.write(Settings.locateRadius, meters == defaultLocateRadius ? null : '${meters.round()}');
    notifyListeners();
  }

  void setCancelStaleTiles(bool active) {
    cancelStaleTiles = active;
    settings?.write(Settings.cancelStaleTiles, active ? 'oui' : null);
    notifyListeners();
  }

  void setGoogleKey(String apiKey) {
    googleKey = apiKey.trim();
    settings?.write(Settings.googleKey, googleKey);
    notifyListeners();
  }

  void _begin() {
    _intervention ??= const Uuid().v4();
    _start ??= Bundle.timestamp();
  }

  /// Intervention en cours (`INT_CODE_EXT`), commencée à la première écriture ou au premier commentaire.
  String get intervention {
    _begin();
    return _intervention!;
  }

  /// Règle du journal : un commentaire ne se modifie ou ne se retire que par son auteur, pendant l'intervention qui
  /// l'a saisi et tant qu'aucun paquet de retour exporté ne le contient ; ensuite il est figé. Ceux des autres
  /// auteurs et ceux venus du BE sont en lecture seule. Les commentaires exportés sont retenus par leur code
  /// ([_exportedComments]), pas par leur date de saisie, qu'un recalage de l'horloge du terminal fausserait.
  bool canEditComment(Map<String, dynamic> c) =>
      _intervention != null &&
      c['INT_CODE_EXT'] == _intervention &&
      c['COM_AUTEUR'] == author &&
      !_exportedComments.contains(c['COM_CODE_EXT']);

  /// À appeler après toute écriture dans le dépôt (l'intervention commence à la première).
  Future<void> afterWrite() async {
    _begin();
    nbChanged = (await repo.modifies()).length;
    _exported = false;
    warnBeforeLeaving(toExport);
    revision++;
    notifyListeners();
  }

  /// À appeler une fois le paquet de retour enregistré : les commentaires qu'il contient sont figés.
  void markExported() {
    _exported = true;
    _exportedComments.addAll(_returnedComments);
    warnBeforeLeaving(toExport);
    notifyListeners();
  }

  Future<void> save(GeoObject o, {bool abandon = false}) async {
    if (!abandon) await saveLevel(o, referenceData, repo);
    await repo.save(o, author: author, abandon: abandon);
    await afterWrite();
  }

  /// Ajoute une photo prise sur le terminal au visuel [v] de [o] (copie de travail) et enregistre l'objet.
  Future<void> addPhoto(GeoObject o, Visual v, {required String name, required Uint8List bytes}) async {
    final f = o.addPhoto(v, name: name, size: bytes.length, author: author);
    await repo.addFile(f['fichier'] as String, bytes);
    await save(o);
  }

  /// Paquet de retour (objets modifiés, intervention, photos prises sur le terminal) et son nom de fichier.
  Future<(String, Uint8List)> returnBundle() async {
    final e = header!;
    final objects = await repo.modifies();
    final activities = <String>{
      for (final o in objects) ...[
        if (o.props.containsKey('pot') || o.namespace('inf')?['portee'] != null) 'RELEVE_POT',
        if (o.props.containsKey('chb') || o.namespace('inf')?['conduites'] != null) 'RELEVE_CHB',
      ],
    };
    // commentaires de l'intervention contenus dans ce retour : figés s'il est exporté
    _returnedComments = {
      if (_intervention != null)
        for (final o in objects)
          for (final c in o.comments)
            if (c['INT_CODE_EXT'] == _intervention && c['COM_CODE_EXT'] is String) c['COM_CODE_EXT'] as String,
    };
    final date = Bundle.timestamp();
    final intervention = {
      'INT_CODE_EXT': _intervention ?? const Uuid().v4(),
      'ACT_CODE': activities.isEmpty ? 'RELEVE' : (activities.toList()..sort()).join(','),
      'INT_AUTEUR': author,
      'INT_TERMINAL': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'DATE_DEBUT': _start ?? date,
      'DATE_FIN': date,
    };
    // photos prises sur le terminal et toujours rattachées à un objet du retour
    final references = {
      for (final o in objects)
        for (final f in o.files)
          if (f['DATE_ABD'] == null) f['fichier'],
    };
    final files = {
      for (final f in repo.newFiles.entries)
        if (references.contains(f.key)) f.key: f.value,
    };
    final zip = Bundle.writeReturn(base: e, intervention: intervention, objects: objects, files: files);
    final name =
        '${(e['projet'] as Map?)?['code']}_${(e['zone'] as Map?)?['code']}_RETOUR_'
        '${date.replaceAll(RegExp(r'[-:]'), '').substring(0, 13)}.zip';
    return (name, zip);
  }
}
