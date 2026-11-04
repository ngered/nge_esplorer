import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/data_repository.dart';
import '../data/geo_object.dart';
import '../data/bundle.dart';
import '../data/reference_data.dart';
import '../data/settings.dart';
import '../data/visuals.dart';
import '../lng.dart';
import '../modules/completion.dart';
import 'page_exit.dart' if (dart.library.js_interop) 'page_exit_web.dart';

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

  Future<void> loadBundle(Uint8List zip) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await repo.load(Bundle.read(zip));
      _intervention = null;
      _start = null;
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

  /// À appeler après toute écriture dans le dépôt (l'intervention commence à la première).
  Future<void> afterWrite() async {
    _intervention ??= const Uuid().v4();
    _start ??= Bundle.timestamp();
    nbChanged = (await repo.modifies()).length;
    _exported = false;
    warnBeforeLeaving(toExport);
    revision++;
    notifyListeners();
  }

  /// À appeler une fois le paquet de retour enregistré.
  void markExported() {
    _exported = true;
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
    final name = '${(e['projet'] as Map?)?['code']}_${(e['zone'] as Map?)?['code']}_RETOUR_'
        '${date.replaceAll(RegExp(r'[-:]'), '').substring(0, 13)}.zip';
    return (name, zip);
  }
}
