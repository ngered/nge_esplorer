import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Adresse trouvée par géocodage inversé, aux colonnes de PRJ_ADRESSE ; [point] : position de l'adresse.
typedef FoundAddress = ({
  int? numero,
  String? rep,
  String? voie,
  String? cp,
  String? insee,
  String? commune,
  String? banId,
  LatLng? point,
});

/// Géocodage inversé d'une position (adresse automatique de FibReady, `GeoCodage.GetBestAdr`) : Géoplateforme
/// (Base Adresse Nationale) en France, complétée par Photon (OpenStreetMap, mondial) si l'adresse est incomplète
/// (score < 80) ou hors de France. Demande une connexion : rien hors ligne.
class Geocoder {
  Geocoder({http.Client? client, this.timeout = const Duration(seconds: 10)}) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static final _geoplateforme = Uri.parse('https://data.geopf.fr/geocodage/reverse');
  static final _photon = Uri.parse('https://photon.komoot.io/reverse');

  /// Emprises de la Base Adresse Nationale (latMin, latMax, lonMin, lonMax), larges comme dans FibReady : un faux
  /// positif ne coûte qu'un appel vide, rattrapé par Photon.
  static const _franceBoxes = [
    [41.30, 51.15, -5.15, 9.60], // métropole et Corse
    [15.80, 16.55, -61.85, -60.95], // Guadeloupe
    [14.35, 14.92, -61.25, -60.75], // Martinique
    [2.10, 5.80, -54.65, -51.60], // Guyane
    [-21.42, -20.85, 55.20, 55.85], // La Réunion
    [-13.05, -12.60, 45.00, 45.32], // Mayotte
    [17.80, 18.20, -63.20, -62.75], // Saint-Martin et Saint-Barthélemy
    [46.73, 47.15, -56.45, -56.10], // Saint-Pierre-et-Miquelon
  ];

  static bool inFrance(LatLng p) => _franceBoxes
      .any((b) => p.latitude >= b[0] && p.latitude <= b[1] && p.longitude >= b[2] && p.longitude <= b[3]);

  /// Complétude d'une adresse (FibReady `GetAdrScore`, sans le complément) : 95 pour une adresse complète.
  static int score(FoundAddress a) {
    bool empty(Object? v) => v == null || (v is String && v.isEmpty);
    return 100 -
        (empty(a.insee) ? 35 : 0) -
        (empty(a.commune) ? 25 : 0) -
        (empty(a.voie) ? 20 : 0) -
        (a.numero == null ? 15 : 0) -
        5;
  }

  /// Meilleure adresse au voisinage de [p], null si aucune ; erreur réseau ou délai dépassé : exception.
  Future<FoundAddress?> reverse(LatLng p) async {
    final ban = inFrance(p) ? await _reverseBan(p) : null;
    if (ban != null && score(ban) >= 80) return ban;
    FoundAddress? osm;
    try {
      osm = await _reversePhoton(p);
    } catch (_) {
      if (ban == null) rethrow;
    }
    if (osm == null) return ban;
    if (ban == null) return osm;
    // le repli complète la BAN champ par champ (comme FibReady `MergeAdr`)
    return (
      numero: osm.numero ?? ban.numero,
      rep: osm.numero != null ? osm.rep : ban.rep,
      voie: osm.voie ?? ban.voie,
      cp: ban.cp ?? osm.cp,
      insee: ban.insee,
      commune: osm.commune ?? ban.commune,
      banId: ban.banId,
      point: ban.point ?? osm.point,
    );
  }

  Future<List<Map<String, dynamic>>> _features(Uri uri) async {
    final r = await _client.get(uri).timeout(timeout);
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}', uri);
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return [for (final f in (json['features'] as List?) ?? const []) (f as Map).cast<String, dynamic>()];
  }

  static LatLng? _point(Map<String, dynamic> f) {
    final c = (f['geometry'] as Map?)?['coordinates'] as List?;
    return c == null ? null : LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
  }

  static String? _text(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v'.trim();

  /// Numéro et indice de répétition d'un numéro de voie (« 12 », « 12bis », « 12 B »).
  static (int?, String?) splitNumber(String? s) {
    final m = RegExp(r'^\s*(\d+)\s*(.*?)\s*$').firstMatch(s ?? '');
    if (m == null) return (null, null);
    return (int.parse(m[1]!), _text(m[2]));
  }

  Future<FoundAddress?> _reverseBan(LatLng p) async {
    final features = await _features(_geoplateforme.replace(queryParameters: {
      'lon': '${p.longitude}',
      'lat': '${p.latitude}',
      'limit': '5',
    }));
    FoundAddress? best;
    for (final f in features) {
      final q = (f['properties'] as Map).cast<String, dynamic>();
      if (q['city'] == null) continue;
      final voie = _text(q['street']) ?? _text(q['locality'])?.split(',').first;
      final (numero, rep) = voie == null ? (null, null) : splitNumber(_text(q['housenumber']));
      final a = (
        numero: numero,
        rep: rep,
        voie: voie,
        cp: _text(q['postcode']),
        insee: _text(q['citycode']),
        commune: _text(q['city']),
        banId: _text(q['banId']) ?? _text(q['id']),
        point: _point(f),
      );
      if (best == null || score(a) > score(best)) best = a;
    }
    return best;
  }

  Future<FoundAddress?> _reversePhoton(LatLng p) async {
    final features = await _features(_photon.replace(queryParameters: {
      'lon': '${p.longitude}',
      'lat': '${p.latitude}',
      'lang': 'fr',
    }));
    if (features.isEmpty) return null;
    final f = features.first;
    final q = (f['properties'] as Map).cast<String, dynamic>();
    final voie = _text(q['street']) ?? (q['type'] == 'street' ? _text(q['name']) : null);
    final (numero, rep) = voie == null ? (null, null) : splitNumber(_text(q['housenumber']));
    return (
      numero: numero,
      rep: rep,
      voie: voie,
      cp: _text(q['postcode']),
      insee: null,
      commune: _text(q['city']) ?? _text(q['locality']) ?? _text(q['district']),
      banId: null,
      point: _point(f),
    );
  }
}
