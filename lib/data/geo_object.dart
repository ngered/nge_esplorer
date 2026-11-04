import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../lng.dart';

/// Classe d'un objet du paquet : nœud (Point), linéaire (LineString) ou adresse (Point).
enum ObjectClass {
  noe('NOE'),
  lin('LIN'),
  adr('ADR');

  const ObjectClass(this.code);
  final String code;

  static ObjectClass fromCode(String? code) =>
      values.firstWhere((c) => c.code == code, orElse: () => throw FormatException(tr('classe inconnue : {0}', [code])));
}

/// Objet GeoJSON du paquet (docs/paquet.md) : l'unité de stockage, de modification et de conflit.
///
/// Les propriétés restent sous forme de carte JSON : colonnes BE en majuscules, structure du format en
/// minuscules (`classe`, `statut`, `pot`, `chb`, `inf`, `fichiers`…). Les écrans des modules les lisent et les
/// écrivent par des accesseurs dédiés.
class GeoObject {
  GeoObject({required this.id, required this.objectClass, this.geometry, Map<String, dynamic>? props})
      : props = props ?? {'classe': objectClass.code};

  final String id;
  final ObjectClass objectClass;
  Map<String, dynamic>? geometry;
  final Map<String, dynamic> props;

  factory GeoObject.fromFeature(Map<String, dynamic> f) {
    final props = Map<String, dynamic>.from(f['properties'] as Map? ?? {});
    return GeoObject(
      id: f['id'] as String,
      objectClass: ObjectClass.fromCode(props['classe'] as String?),
      geometry: (f['geometry'] as Map?)?.cast<String, dynamic>(),
      props: props,
    );
  }

  Map<String, dynamic> toFeature() => {'type': 'Feature', 'id': id, 'geometry': geometry, 'properties': props};

  /// Copie profonde : un écran modifie une copie et ne l'enregistre qu'à la validation.
  GeoObject copy() => GeoObject.fromFeature(jsonDecode(jsonEncode(toFeature())) as Map<String, dynamic>);

  // -- noyau -----------------------------------------------------------------------------------

  int? get typeKey => props['TYPE_KEY'] as int?;
  String? get lib => (props['NOE_LIB'] ?? props['LIN_LIB']) as String?;
  String? get status => props['statut'] as String?;
  bool get abandoned => props['DATE_ABD'] != null;
  bool get outOfZone => props['hors_zone'] == true;
  String? get noe1 => props['NOE1_KEY'] as String?;
  String? get noe2 => props['NOE2_KEY'] as String?;

  /// Espace d'un module (`pot`, `chb`, `inf`), créé s'il est absent et [create] vaut vrai.
  Map<String, dynamic>? namespace(String key, {bool create = false}) {
    final e = props[key];
    if (e is Map<String, dynamic>) return e;
    if (e is Map) return props[key] = e.cast<String, dynamic>();
    if (!create) return null;
    return props[key] = <String, dynamic>{};
  }

  /// Affecte une valeur ; `null` ou chaîne vide retire la clé (valeur nulle omise dans le format).
  static void put(Map<String, dynamic> m, String key, Object? value) {
    if (value == null || (value is String && value.trim().isEmpty)) {
      m.remove(key);
    } else {
      m[key] = value;
    }
  }

  // -- géométrie -------------------------------------------------------------------------------

  LatLng? get point {
    final g = geometry;
    if (g == null || g['type'] != 'Point') return null;
    final c = g['coordinates'] as List;
    return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
  }

  List<LatLng> get line {
    final g = geometry;
    if (g == null || g['type'] != 'LineString') return const [];
    return [
      for (final c in g['coordinates'] as List) LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
  }

  static Map<String, dynamic> geoPoint(LatLng p) => {
        'type': 'Point',
        'coordinates': [_round(p.longitude), _round(p.latitude)],
      };

  static Map<String, dynamic> geoLine(List<LatLng> pts) => {
        'type': 'LineString',
        'coordinates': [
          for (final p in pts) [_round(p.longitude), _round(p.latitude)],
        ],
      };

  static double _round(double v) => (v * 1e7).roundToDouble() / 1e7;

  /// Emprise [minLon, minLat, maxLon, maxLat], pour l'index spatial du dépôt.
  List<double>? get bounds {
    final pts = objectClass == ObjectClass.lin ? line : [?point];
    if (pts.isEmpty) return null;
    var e = [pts.first.longitude, pts.first.latitude, pts.first.longitude, pts.first.latitude];
    for (final p in pts.skip(1)) {
      e = [
        p.longitude < e[0] ? p.longitude : e[0],
        p.latitude < e[1] ? p.latitude : e[1],
        p.longitude > e[2] ? p.longitude : e[2],
        p.latitude > e[3] ? p.latitude : e[3],
      ];
    }
    return e;
  }
}
