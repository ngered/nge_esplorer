import 'dart:async';
import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:http_parser/http_parser.dart';

/// Délai par tentative au-delà duquel le serveur de tuiles est considéré injoignable (le cache prend alors le relais).
const delaiTuiles = Duration(seconds: 8);

/// Client réseau des tuiles : délai par tentative et nouvelles tentatives sur erreur réseau, délai dépassé, 429 et
/// 5xx (la Géoplateforme limite le débit), avant de déclarer la tuile en échec (trou dans le fond de plan).
/// [attente] : délai avant la tentative n (par défaut 0,5 s puis × 1,5).
http.Client clientReseauTuiles({http.Client? interne, Duration Function(int)? attente}) => RetryClient(
      _ClientDelai(interne ?? http.Client()),
      retries: 2,
      when: (r) => r.statusCode == 429 || r.statusCode >= 500,
      whenError: (e, _) => e is TimeoutException || (e is http.ClientException && e is! http.RequestAbortedException),
      delay: attente ?? (n) => const Duration(milliseconds: 500) * (n == 0 ? 1 : 1.5 * n),
    );

/// Applique [delaiTuiles] à chaque tentative.
class _ClientDelai extends http.BaseClient {
  _ClientDelai(this._interne);

  final http.Client _interne;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _interne.send(request).timeout(delaiTuiles);

  @override
  void close() => _interne.close();
}

/// Tuiles HTTP : le serveur en usage courant (le terminal est le plus souvent connecté), selon la fraîcheur annoncée
/// par ses en-têtes ; le cache rend fluides les tuiles encore fraîches. Cache sur Android et Windows ; sur le web,
/// celui du navigateur. [secours] : sans connexion, afficher la tuile du cache même périmée (une tuile jamais
/// téléchargée reste transparente) ; à refuser pour les fonds dont la licence interdit l'usage hors connexion.
/// [annulerObsoletes] : annuler le téléchargement des tuiles qui ne seront plus affichées (désactivé par défaut ; sur
/// le web, chaque annulation met en outre le débogueur en pause).
TileProvider fournisseurTuiles({bool annulerObsoletes = false, bool secours = true}) {
  final stockage = BuiltInMapCachingProvider.getOrCreateInstance();
  final client = secours ? ClientTuilesSecours(stockage) : clientReseauTuiles();
  return _Fournisseur(client, stockage, annulerObsoletes);
}

/// NetworkTileProvider qui ferme son client (fourni de l'extérieur, il ne le ferait pas).
class _Fournisseur extends NetworkTileProvider {
  _Fournisseur(this._client, MapCachingProvider stockage, bool annulerObsoletes)
      : super(
          httpClient: _client,
          cachingProvider: stockage,
          abortObsoleteRequests: annulerObsoletes,
          silenceExceptions: true,
        );

  final http.Client _client;

  @override
  Future<void> dispose() async {
    _client.close();
    return super.dispose();
  }
}

/// Client des tuiles : sans réponse du serveur, une tuile présente dans le cache (même périmée) est déclarée « non
/// modifiée » (304), et flutter_map l'affiche depuis le cache ; elle reste périmée pour que le serveur soit de
/// nouveau interrogé à la tuile suivante.
class ClientTuilesSecours extends http.BaseClient {
  ClientTuilesSecours(this._stockage, [http.Client? reseau]) : _reseau = reseau ?? clientReseauTuiles();

  final MapCachingProvider _stockage;
  final http.Client _reseau;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _reseau.send(request);
    } on http.RequestAbortedException {
      rethrow;
    } on Object catch (e) {
      if (e is! http.ClientException && e is! TimeoutException) rethrow;
      final tuile = _stockage.isSupported ? await _stockage.getTile('${request.url}') : null;
      if (tuile == null) rethrow;
      final m = tuile.metadata;
      return http.StreamedResponse(const Stream.empty(), 304, request: request, headers: {
        'cache-control': 'max-age=0',
        'age': '0',
        if (m.etag != null) 'etag': m.etag!,
        if (m.lastModified != null) 'last-modified': formatHttpDate(m.lastModified!),
      });
    }
  }

  @override
  void close() => _reseau.close();
}

/// Source des fonds de plan. Web (provisoire) : tuiles HTTP ; Android (cible) : MBTiles / PMTiles locales.
abstract class TileSource {
  String get nom;
  String get attribution;
  String get urlTemplate;
  int get zoomMax;

  /// La licence permet d'afficher sans connexion une tuile périmée du cache.
  bool get secours => true;

  /// Logo d'attribution (image du dossier assets), le cas échéant.
  String? get logo => null;

  /// Mention de copyright de la vue affichée ; par défaut, la mention fixe.
  Future<String> attributionVue(LatLngBounds vue, int zoom) async => attribution;
}

/// Plan IGN v2 de la Géoplateforme (licence ouverte), en WMTS « PM » (Web Mercator).
class PlanIgn extends TileSource {
  PlanIgn();

  @override
  String get nom => 'Plan IGN';

  @override
  String get attribution => '© IGN — Géoplateforme';

  @override
  String get urlTemplate => 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
      '&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM&FORMAT=image/png'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

  @override
  int get zoomMax => 19;
}

/// Orthophotographies IGN (licence ouverte).
class OrthoIgn extends TileSource {
  OrthoIgn();

  @override
  String get nom => 'Photographies aériennes IGN';

  @override
  String get attribution => '© IGN — Géoplateforme';

  @override
  String get urlTemplate => 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
      '&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM&FORMAT=image/jpeg'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

  @override
  int get zoomMax => 20;
}

/// OpenStreetMap (ODbL) : serveur communautaire, usage modéré, pas de téléchargement en masse.
class Osm extends TileSource {
  Osm();

  @override
  String get nom => 'OpenStreetMap';

  @override
  String get attribution => '© contributeurs OpenStreetMap';

  @override
  String get urlTemplate => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  int get zoomMax => 19;
}

/// Fond par défaut d'une zone ([minLon, minLat, maxLon, maxLat]) : l'IGN en France métropolitaine, OpenStreetMap
/// ailleurs (Maroc…), l'IGN ne couvrant que la France.
TileSource fondParDefaut(List<double>? emprise) {
  if (emprise == null) return PlanIgn();
  final lon = (emprise[0] + emprise[2]) / 2;
  final lat = (emprise[1] + emprise[3]) / 2;
  final france = lon > -5.5 && lon < 10 && lat > 41 && lat < 51.5;
  return france ? PlanIgn() : Osm();
}

/// Fonds proposés (identifiant, nom) : les fonds Google seulement avec une clé renseignée. Les identifiants des
/// fonds Google sont préfixés (« plan » est le Plan IGN, pas Google Plan).
List<(String, String)> fondsProposes(String cleGoogle) => [
      ('plan', 'Plan IGN'),
      ('ortho', 'Photographies aériennes IGN'),
      ('osm', 'OpenStreetMap'),
      if (cleGoogle.isNotEmpty)
        for (final g in TypeGoogle.values) ('google-${g.name}', g.nom),
    ];

/// Ouvre le fond [id] de [fondsProposes] (session Map Tiles pour un fond Google).
Future<TileSource> ouvrirFond(String id, String cleGoogle) async {
  final google = TypeGoogle.values.where((g) => 'google-${g.name}' == id).firstOrNull;
  return switch (id) {
    _ when google != null => await GoogleTiles.ouvrir(google, cleGoogle),
    'ortho' => OrthoIgn(),
    'osm' => Osm(),
    _ => PlanIgn(),
  };
}

enum TypeGoogle {
  plan('Google Plan', {'mapType': 'roadmap'}, 'assets/google/google_maps_contour_clair.png'),
  satellite('Google Satellite', {'mapType': 'satellite'}, 'assets/google/google_maps_contour_sombre.png'),
  hybride('Google Hybride', {
    'mapType': 'satellite',
    'layerTypes': ['layerRoadmap'],
  }, 'assets/google/google_maps_contour_sombre.png');

  const TypeGoogle(this.nom, this.parametres, this.logo);
  final String nom;
  final Map<String, Object> parametres;
  final String logo;
}

/// Google Maps par la Map Tiles API (2D). La clé est renseignée par l'utilisateur dans les paramètres de
/// l'application, sous sa responsabilité (comme dans FibReady) ; session ouverte à la sélection. Règles de l'API
/// (developers.google.com/maps/documentation/tile/policies) : cache selon les en-têtes `Cache-Control` et `ETag`
/// (cache de flutter_map), aucun usage hors connexion (pas de secours), logo Google Maps (officiel, non modifié, 16 à
/// 19 dp) et mention de copyright de la vue (requête viewport) affichés en bas de la carte.
class GoogleTiles extends TileSource {
  GoogleTiles._(this.type, this.cle, this._session);

  static final _sessions = <(TypeGoogle, String), (String, DateTime)>{};

  /// Ouvre (ou réutilise tant qu'elle est valide) une session de tuiles du type demandé ; une clé refusée lève une
  /// [http.ClientException] portant la réponse de Google.
  /// Message d'une réponse d'erreur Google (`error.message`), sinon le corps de la réponse.
  static String _motif(String corps) {
    try {
      return ((jsonDecode(corps) as Map)['error'] as Map)['message'] as String;
    } catch (_) {
      return corps;
    }
  }

  static Future<GoogleTiles> ouvrir(TypeGoogle type, String cle) async {
    final s = _sessions[(type, cle)];
    if (s != null && s.$2.isAfter(DateTime.now().add(const Duration(hours: 1)))) {
      return GoogleTiles._(type, cle, s.$1);
    }
    final rep = await http.post(
      Uri.https('tile.googleapis.com', '/v1/createSession', {'key': cle}),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({...type.parametres, 'language': 'fr-FR', 'region': 'FR'}),
    );
    if (rep.statusCode != 200) throw http.ClientException('Google Map Tiles ${rep.statusCode} : ${_motif(rep.body)}');
    final j = jsonDecode(rep.body) as Map<String, dynamic>;
    final session = j['session'] as String;
    final expiration = DateTime.fromMillisecondsSinceEpoch(int.parse('${j['expiry']}') * 1000);
    _sessions[(type, cle)] = (session, expiration);
    return GoogleTiles._(type, cle, session);
  }

  final TypeGoogle type;
  final String cle;
  final String _session;

  @override
  String get nom => type.nom;

  @override
  String get attribution => '';

  @override
  String get urlTemplate => 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=$_session&key=$cle';

  @override
  int get zoomMax => 21;

  @override
  bool get secours => false;

  @override
  bool operator ==(Object other) => other is GoogleTiles && other.type == type && other.cle == cle;

  @override
  int get hashCode => Object.hash(type, cle);

  @override
  String get logo => type.logo;

  @override
  Future<String> attributionVue(LatLngBounds vue, int zoom) async {
    double lat(double v) => v.clamp(-89.999999, 89.999999);
    double lon(double v) => v.clamp(-179.999999, 179.999999);
    final rep = await http.get(Uri.https('tile.googleapis.com', '/tile/v1/viewport', {
      'session': _session,
      'key': cle,
      'zoom': '${zoom.clamp(0, zoomMax)}',
      'north': '${lat(vue.north)}',
      'south': '${lat(vue.south)}',
      'east': '${lon(vue.east)}',
      'west': '${lon(vue.west)}',
    }));
    if (rep.statusCode != 200) throw http.ClientException('Google Map Tiles (viewport) : ${rep.statusCode}');
    return (jsonDecode(rep.body) as Map<String, dynamic>)['copyright'] as String? ?? '';
  }
}
