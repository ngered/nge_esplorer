import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Classe d'un objet du paquet : nœud (Point), linéaire (LineString) ou adresse (Point).
enum Classe {
  noe('NOE'),
  lin('LIN'),
  adr('ADR');

  const Classe(this.code);
  final String code;

  static Classe depuis(String? code) =>
      values.firstWhere((c) => c.code == code, orElse: () => throw FormatException('classe inconnue : $code'));
}

/// Objet GeoJSON du paquet (docs/paquet.md) : l'unité de stockage, de modification et de conflit.
///
/// Les propriétés restent sous forme de carte JSON : colonnes BE en majuscules, structure du format en
/// minuscules (`classe`, `statut`, `pot`, `chb`, `inf`, `fichiers`…). Les écrans des modules les lisent et les
/// écrivent par des accesseurs dédiés.
class Objet {
  Objet({required this.id, required this.classe, this.geometry, Map<String, dynamic>? props})
      : props = props ?? {'classe': classe.code};

  final String id;
  final Classe classe;
  Map<String, dynamic>? geometry;
  final Map<String, dynamic> props;

  factory Objet.depuisFeature(Map<String, dynamic> f) {
    final props = Map<String, dynamic>.from(f['properties'] as Map? ?? {});
    return Objet(
      id: f['id'] as String,
      classe: Classe.depuis(props['classe'] as String?),
      geometry: (f['geometry'] as Map?)?.cast<String, dynamic>(),
      props: props,
    );
  }

  Map<String, dynamic> versFeature() => {'type': 'Feature', 'id': id, 'geometry': geometry, 'properties': props};

  /// Copie profonde : un écran modifie une copie et ne l'enregistre qu'à la validation.
  Objet copie() => Objet.depuisFeature(jsonDecode(jsonEncode(versFeature())) as Map<String, dynamic>);

  // -- noyau -----------------------------------------------------------------------------------

  int? get typeKey => props['TYPE_KEY'] as int?;
  String? get lib => (props['NOE_LIB'] ?? props['LIN_LIB']) as String?;
  String? get statut => props['statut'] as String?;
  bool get abandonne => props['DATE_ABD'] != null;
  bool get horsZone => props['hors_zone'] == true;
  String? get noe1 => props['NOE1_KEY'] as String?;
  String? get noe2 => props['NOE2_KEY'] as String?;

  /// Espace d'un module (`pot`, `chb`, `inf`), créé s'il est absent et [creer] vaut vrai.
  Map<String, dynamic>? espace(String cle, {bool creer = false}) {
    final e = props[cle];
    if (e is Map<String, dynamic>) return e;
    if (e is Map) return props[cle] = e.cast<String, dynamic>();
    if (!creer) return null;
    return props[cle] = <String, dynamic>{};
  }

  /// Affecte une valeur ; `null` ou chaîne vide retire la clé (valeur nulle omise dans le format).
  static void poser(Map<String, dynamic> m, String cle, Object? valeur) {
    if (valeur == null || (valeur is String && valeur.trim().isEmpty)) {
      m.remove(cle);
    } else {
      m[cle] = valeur;
    }
  }

  // -- géométrie -------------------------------------------------------------------------------

  LatLng? get point {
    final g = geometry;
    if (g == null || g['type'] != 'Point') return null;
    final c = g['coordinates'] as List;
    return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
  }

  List<LatLng> get ligne {
    final g = geometry;
    if (g == null || g['type'] != 'LineString') return const [];
    return [
      for (final c in g['coordinates'] as List) LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
  }

  static Map<String, dynamic> geoPoint(LatLng p) => {
        'type': 'Point',
        'coordinates': [_arrondi(p.longitude), _arrondi(p.latitude)],
      };

  static Map<String, dynamic> geoLigne(List<LatLng> pts) => {
        'type': 'LineString',
        'coordinates': [
          for (final p in pts) [_arrondi(p.longitude), _arrondi(p.latitude)],
        ],
      };

  static double _arrondi(double v) => (v * 1e7).roundToDouble() / 1e7;

  /// Emprise [minLon, minLat, maxLon, maxLat], pour l'index spatial du dépôt.
  List<double>? get emprise {
    final pts = classe == Classe.lin ? ligne : [?point];
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
