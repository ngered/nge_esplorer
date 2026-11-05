import 'dart:async';
import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:http_parser/http_parser.dart';

import '../lng.dart';

/// Délai par tentative au-delà duquel le serveur de tuiles est considéré injoignable (le cache prend alors le relais).
const tileTimeout = Duration(seconds: 8);

/// Client réseau des tuiles : délai par tentative et nouvelles tentatives sur erreur réseau, délai dépassé, 429 et
/// 5xx (la Géoplateforme limite le débit), avant de déclarer la tuile en échec (trou dans le fond de plan).
/// [delay] : délai avant la tentative n (par défaut 0,5 s puis × 1,5).
http.Client tileNetworkClient({http.Client? inner, Duration Function(int)? delay}) => RetryClient(
      _TimeoutClient(inner ?? http.Client()),
      retries: 2,
      when: (r) => r.statusCode == 429 || r.statusCode >= 500,
      whenError: (e, _) => e is TimeoutException || (e is http.ClientException && e is! http.RequestAbortedException),
      delay: delay ?? (n) => const Duration(milliseconds: 500) * (n == 0 ? 1 : 1.5 * n),
    );

/// Applique [tileTimeout] à chaque tentative.
class _TimeoutClient extends http.BaseClient {
  _TimeoutClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request).timeout(tileTimeout);

  @override
  void close() => _inner.close();
}

/// Tuiles HTTP : le serveur en usage courant (le terminal est le plus souvent connecté), selon la fraîcheur annoncée
/// par ses en-têtes ; le cache rend fluides les tuiles encore fraîches. Cache sur Android et Windows ; sur le web,
/// celui du navigateur. [fallback] : sans connexion, afficher la tuile du cache même périmée (une tuile jamais
/// téléchargée reste transparente) ; à refuser pour les fonds dont la licence interdit l'usage hors connexion.
/// [cancelStale] : annuler le téléchargement des tuiles qui ne seront plus affichées (désactivé par défaut ; sur
/// le web, chaque annulation met en outre le débogueur en pause).
TileProvider tileProvider({bool cancelStale = false, bool fallback = true}) {
  final storage = BuiltInMapCachingProvider.getOrCreateInstance();
  final client = fallback ? FallbackTileClient(storage) : tileNetworkClient();
  return _CachedTileProvider(client, storage, cancelStale);
}

/// NetworkTileProvider qui ferme son client (fourni de l'extérieur, il ne le ferait pas).
class _CachedTileProvider extends NetworkTileProvider {
  _CachedTileProvider(this._client, MapCachingProvider storage, bool cancelStale)
      : super(
          httpClient: _client,
          cachingProvider: storage,
          abortObsoleteRequests: cancelStale,
          // échec signalé, pas masqué : une tuile transparente passerait pour chargée, ni oubliée hors de la vue ni
          // redemandée au rechargement du fond (zone grise jusqu'à ce qu'elle sorte de la carte)
          silenceExceptions: false,
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
class FallbackTileClient extends http.BaseClient {
  FallbackTileClient(this._storage, [http.Client? network]) : _network = network ?? tileNetworkClient();

  final MapCachingProvider _storage;
  final http.Client _network;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _network.send(request);
    } on http.RequestAbortedException {
      rethrow;
    } on Object catch (e) {
      if (e is! http.ClientException && e is! TimeoutException) rethrow;
      final tile = _storage.isSupported ? await _storage.getTile('${request.url}') : null;
      if (tile == null) rethrow;
      final m = tile.metadata;
      return http.StreamedResponse(const Stream.empty(), 304, request: request, headers: {
        'cache-control': 'max-age=0',
        'age': '0',
        if (m.etag != null) 'etag': m.etag!,
        if (m.lastModified != null) 'last-modified': formatHttpDate(m.lastModified!),
      });
    }
  }

  @override
  void close() => _network.close();
}

/// Source des fonds de plan. Web (provisoire) : tuiles HTTP ; Android (cible) : MBTiles / PMTiles locales.
abstract class TileSource {
  String get name;
  String get attribution;
  String get urlTemplate;
  int get maxZoom;

  /// La licence permet d'afficher sans connexion une tuile périmée du cache.
  bool get fallback => true;

  /// Logo d'attribution (image du dossier assets), le cas échéant.
  String? get logo => null;

  /// Mention de copyright de la vue affichée ; par défaut, la mention fixe.
  Future<String> viewAttribution(LatLngBounds view, int zoom) async => attribution;
}

/// Plan IGN v2 de la Géoplateforme (licence ouverte), en WMTS « PM » (Web Mercator).
class IgnPlan extends TileSource {
  IgnPlan();

  @override
  String get name => tr('Plan IGN');

  @override
  String get attribution => '© IGN — Géoplateforme';

  @override
  String get urlTemplate => 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
      '&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM&FORMAT=image/png'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

  @override
  int get maxZoom => 19;
}

/// Orthophotographies IGN (licence ouverte).
class IgnOrtho extends TileSource {
  IgnOrtho();

  @override
  String get name => tr('Photographies aériennes IGN');

  @override
  String get attribution => '© IGN — Géoplateforme';

  @override
  String get urlTemplate => 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
      '&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM&FORMAT=image/jpeg'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

  @override
  int get maxZoom => 20;
}

/// OpenStreetMap (ODbL) : serveur communautaire, usage modéré, pas de téléchargement en masse.
class Osm extends TileSource {
  Osm();

  @override
  String get name => 'OpenStreetMap';

  @override
  String get attribution => tr('© contributeurs OpenStreetMap');

  @override
  String get urlTemplate => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  int get maxZoom => 19;
}

/// Fond par défaut d'une zone ([minLon, minLat, maxLon, maxLat]) : OpenStreetMap partout, moins chargé que le Plan
/// IGN et plus lisible sous un réseau dense (retour du 5 novembre 2026) ; les fonds IGN restent au choix en France.
TileSource defaultBaseMap(List<double>? bounds) => Osm();

/// Fonds proposés (identifiant, nom), le fond par défaut d'abord : les fonds Google seulement avec une clé
/// renseignée. Les identifiants des fonds Google sont préfixés (« plan » est le Plan IGN, pas Google Plan).
List<(String, String)> availableBaseMaps(String googleKey) => [
      ('osm', 'OpenStreetMap'),
      ('plan', tr('Plan IGN')),
      ('ortho', tr('Photographies aériennes IGN')),
      if (googleKey.isNotEmpty)
        for (final g in GoogleMapType.values) ('google-${g.name}', tr(g.label)),
    ];

/// Ouvre le fond [id] de [availableBaseMaps] (session Map Tiles pour un fond Google).
Future<TileSource> openBaseMap(String id, String googleKey) async {
  final google = GoogleMapType.values.where((g) => 'google-${g.name}' == id).firstOrNull;
  return switch (id) {
    _ when google != null => await GoogleTiles.open(google, googleKey),
    'ortho' => IgnOrtho(),
    'osm' => Osm(),
    _ => IgnPlan(),
  };
}

enum GoogleMapType {
  roadmap('Google Plan', {'mapType': 'roadmap'}, 'assets/google/google_maps_contour_clair.png'), // tr
  satellite('Google Satellite', {'mapType': 'satellite'}, 'assets/google/google_maps_contour_sombre.png'), // tr
  hybrid('Google Hybride', { // tr
    'mapType': 'satellite',
    'layerTypes': ['layerRoadmap'],
  }, 'assets/google/google_maps_contour_sombre.png');

  const GoogleMapType(this.label, this.params, this.logo);
  final String label;
  final Map<String, Object> params;
  final String logo;
}

/// Google Maps par la Map Tiles API (2D). La clé est renseignée par l'utilisateur dans les paramètres de
/// l'application, sous sa responsabilité (comme dans FibReady) ; session ouverte à la sélection. Règles de l'API
/// (developers.google.com/maps/documentation/tile/policies) : cache selon les en-têtes `Cache-Control` et `ETag`
/// (cache de flutter_map), aucun usage hors connexion (pas de secours), logo Google Maps (officiel, non modifié, 16 à
/// 19 dp) et mention de copyright de la vue (requête viewport) affichés en bas de la carte.
class GoogleTiles extends TileSource {
  GoogleTiles._(this.type, this.apiKey, this._session);

  static final _sessions = <(GoogleMapType, String), (String, DateTime)>{};

  /// Ouvre (ou réutilise tant qu'elle est valide) une session de tuiles du type demandé ; une clé refusée lève une
  /// [http.ClientException] portant la réponse de Google.
  /// Message d'une réponse d'erreur Google (`error.message`), sinon le corps de la réponse.
  static String _pattern(String body) {
    try {
      return ((jsonDecode(body) as Map)['error'] as Map)['message'] as String;
    } catch (_) {
      return body;
    }
  }

  static Future<GoogleTiles> open(GoogleMapType type, String apiKey) async {
    final s = _sessions[(type, apiKey)];
    if (s != null && s.$2.isAfter(DateTime.now().add(const Duration(hours: 1)))) {
      return GoogleTiles._(type, apiKey, s.$1);
    }
    final rep = await http.post(
      Uri.https('tile.googleapis.com', '/v1/createSession', {'key': apiKey}),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({...type.params, 'language': 'fr-FR', 'region': 'FR'}),
    );
    if (rep.statusCode != 200) throw http.ClientException('Google Map Tiles ${rep.statusCode} : ${_pattern(rep.body)}');
    final j = jsonDecode(rep.body) as Map<String, dynamic>;
    final session = j['session'] as String;
    final expiration = DateTime.fromMillisecondsSinceEpoch(int.parse('${j['expiry']}') * 1000);
    _sessions[(type, apiKey)] = (session, expiration);
    return GoogleTiles._(type, apiKey, session);
  }

  final GoogleMapType type;
  final String apiKey;
  final String _session;

  @override
  String get name => tr(type.label);

  @override
  String get attribution => '';

  @override
  String get urlTemplate => 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=$_session&key=$apiKey';

  @override
  int get maxZoom => 21;

  @override
  bool get fallback => false;

  @override
  bool operator ==(Object other) => other is GoogleTiles && other.type == type && other.apiKey == apiKey;

  @override
  int get hashCode => Object.hash(type, apiKey);

  @override
  String get logo => type.logo;

  @override
  Future<String> viewAttribution(LatLngBounds view, int zoom) async {
    double lat(double v) => v.clamp(-89.999999, 89.999999);
    double lon(double v) => v.clamp(-179.999999, 179.999999);
    final rep = await http.get(Uri.https('tile.googleapis.com', '/tile/v1/viewport', {
      'session': _session,
      'key': apiKey,
      'zoom': '${zoom.clamp(0, maxZoom)}',
      'north': '${lat(view.north)}',
      'south': '${lat(view.south)}',
      'east': '${lon(view.east)}',
      'west': '${lon(view.west)}',
    }));
    if (rep.statusCode != 200) throw http.ClientException('Google Map Tiles (viewport) : ${rep.statusCode}');
    return (jsonDecode(rep.body) as Map<String, dynamic>)['copyright'] as String? ?? '';
  }
}
