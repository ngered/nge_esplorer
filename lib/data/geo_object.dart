import 'dart:convert';
import 'dart:ui' show Color;

import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../lng.dart';
import 'bundle.dart';

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

/// Type d'un commentaire (`COM_TYPE`, repris de la table COMMENTS de FibReady) : code, libellé, couleur de la
/// pastille. L'ordre est celui de la gravité, de l'alerte au bon point ; Standard par défaut.
enum CommentType {
  alert('alert', 'Alerte', Color(0xFFE53935)), // tr
  minor('minor', 'Mineur', Color(0xFFFB8C00)), // tr
  standard('standard', 'Standard', Color(0xFF4FC3F7)), // tr
  great('great', 'Bon point', Color(0xFF43A047)); // tr

  const CommentType(this.code, this.lib, this.color);
  final String code;
  final String lib;
  final Color color;

  /// Type du commentaire [c] ; un code absent ou inconnu vaut Standard.
  static CommentType of(Map<String, dynamic> c) => values.firstWhere((t) => t.code == c['COM_TYPE'], orElse: () => standard);
}

/// Objet GeoJSON du paquet (docs/paquet.md) : l'unité de stockage, de modification et de conflit.
///
/// Les propriétés restent sous forme de carte JSON : colonnes BE en majuscules, structure du format en
/// minuscules (`classe`, `statut`, `pot`, `chb`, `inf`, `fichiers`, `commentaires`…). Les écrans des modules les
/// lisent et les écrivent par des accesseurs dédiés.
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

  // -- commentaires ----------------------------------------------------------------------------
  // Journal daté et signé de l'objet (`commentaires`, PRJ_COMMENTAIRE). Seul un commentaire saisi pendant
  // l'intervention en cours et pas encore exporté se modifie ou se retire (règle tenue par AppProvider) : retiré, il
  // disparaît, n'ayant jamais quitté le terminal. Au BE, un commentaire se retire par abandon (`DATE_ABD`).

  /// Liste des commentaires, normalisée une fois (mêmes cartes d'un appel à l'autre).
  List<Map<String, dynamic>> get _commentList {
    final l = props['commentaires'];
    if (l is List<Map<String, dynamic>>) return l;
    final res = [for (final c in (l as List?) ?? const []) Map<String, dynamic>.from(c as Map)];
    if (l != null) props['commentaires'] = res;
    return res;
  }

  /// Commentaires du plus ancien au plus récent (`DATE_CREA`, puis ordre du paquet), abandonnés exclus.
  List<Map<String, dynamic>> get comments {
    final l = _commentList;
    return [
      for (final c in l)
        if (c['DATE_ABD'] == null) c,
    ]..sort((a, b) {
        final d = '${a['DATE_CREA'] ?? ''}'.compareTo('${b['DATE_CREA'] ?? ''}');
        return d != 0 ? d : l.indexOf(a).compareTo(l.indexOf(b));
      });
  }

  /// Ajoute un commentaire signé de [author], saisi pendant l'intervention [intervention] (`INT_CODE_EXT`).
  Map<String, dynamic> addComment({
    required String text,
    required String author,
    required String intervention,
    CommentType type = CommentType.standard,
  }) {
    final c = <String, dynamic>{
      'COM_CODE_EXT': const Uuid().v4(),
      'COM_TYPE': type.code,
      'COM_TEXTE': text.trim(),
      'COM_AUTEUR': author,
      'INT_CODE_EXT': intervention,
      'DATE_CREA': Bundle.timestamp(),
    };
    props['commentaires'] = [..._commentList, c];
    return c;
  }

  /// Modifie le texte et le type du commentaire [c] ; pose la date et l'auteur de la modification.
  void editComment(Map<String, dynamic> c, {required String text, required CommentType type, required String author}) {
    c['COM_TEXTE'] = text.trim();
    c['COM_TYPE'] = type.code;
    c['DATE_MODIF'] = Bundle.timestamp();
    c['SRC_MODIF'] = author;
  }

  /// Retire le commentaire [c] (la clé `commentaires` part avec le dernier).
  void removeComment(Map<String, dynamic> c) {
    final l = _commentList;
    final i = l.indexWhere((e) => e['COM_CODE_EXT'] == c['COM_CODE_EXT']);
    if (i >= 0) l.removeAt(i);
    if (l.isEmpty) props.remove('commentaires');
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
