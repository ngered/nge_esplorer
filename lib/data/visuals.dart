import 'package:uuid/uuid.dart';

import '../lng.dart';
import 'geo_object.dart';
import 'bundle.dart';
import 'reference_data.dart';

/// Visuel d'un support : groupe de photos avec ses fonctions propres (docs/echanges.md §8). Visuel **attendu** :
/// vue du type (`DEF_VUE`, photos repérées par `VUE_CODE`, fonction `VUE_ACTION` : MASQUE pour la grille du masque
/// de chambre). Visuel **libre** : ajouté sur le terrain, titre saisi (photos repérées par `VIS_CODE`, titre
/// `VIS_LIB`) ; il existe tant qu'il a des photos.
class Visual {
  const Visual._(this.code, this.lib, {this.free = false, this.mandatory = false, this.ifMasked = false, this.action});

  factory Visual.expected(Map<String, dynamic> def) => Visual._(
        def['VUE_CODE'] as String,
        def['VUE_LIB'] as String? ?? def['VUE_CODE'] as String,
        mandatory: def['VUE_OBLIGATOIRE'] == 'OUI',
        ifMasked: def['VUE_OBLIGATOIRE'] == 'SI_MASQUE',
        action: def['VUE_ACTION'] as String?,
      );

  /// Nouveau visuel libre, sans photo jusqu'à la première prise.
  factory Visual.free(String lib, [String? code]) => Visual._(code ?? const Uuid().v4(), lib, free: true);

  final String code;
  final String lib;
  final bool free;
  final bool mandatory;

  /// Obligatoire si la face de chambre porte un masque.
  final bool ifMasked;
  final String? action;

  /// La photo [f] appartient à ce visuel.
  bool contains(Map<String, dynamic> f) => free ? f['VIS_CODE'] == code : f['VUE_CODE'] == code;

  /// Visuels de [o] : attendus pour son type et ses types parents (ordre de `VUE_ORDRE`), puis libres (ordre de
  /// création).
  static List<Visual> of(GeoObject o, ReferenceData ref) {
    final types = <int?>{o.typeKey};
    for (var t = ref.type(o.typeKey); t != null; t = ref.type(t['TYPE_PARENT_KEY'] as int?)) {
      if (!types.add(t['TYPE_PARENT_KEY'] as int?)) break;
    }
    final views = ref.table('noyau', 'DEF_VUE').where((v) => types.contains(v['TYPE_KEY'])).toList()
      ..sort((a, b) => (a['VUE_ORDRE'] as int).compareTo(b['VUE_ORDRE'] as int));
    final freeVisuals = <String, Visual>{};
    for (final f in o.files) {
      final code = f['VIS_CODE'] as String?;
      if (code != null && f['DATE_ABD'] == null) {
        freeVisuals.putIfAbsent(code, () => Visual.free(f['VIS_LIB'] as String? ?? tr('Visuel libre'), code));
      }
    }
    return [for (final v in views) Visual.expected(v), ...freeVisuals.values];
  }
}

/// Photos d'un objet (`fichiers`, PRJ_FICHIER) rangées par visuel. L'ordre de la galerie est `FIC_RANG` ; la
/// première photo est la photo de référence du visuel (`FIC_PRINCIPALE`). Une photo supprimée est abandonnée
/// (`DATE_ABD`, validée au contrôle du retour), sauf si elle a été prise sur le terminal et n'est pas encore
/// remontée : elle est alors retirée.
extension ObjectPhotos on GeoObject {
  /// Liste des fichiers de l'objet, normalisée une fois (mêmes cartes d'un appel à l'autre).
  List<Map<String, dynamic>> get files {
    final l = props['fichiers'];
    if (l is List<Map<String, dynamic>>) return l;
    final res = [for (final f in (l as List?) ?? const []) Map<String, dynamic>.from(f as Map)];
    if (l != null) props['fichiers'] = res;
    return res;
  }

  /// Photos du visuel [v] dans l'ordre de la galerie (abandonnées exclues).
  List<Map<String, dynamic>> photos(Visual v) {
    final l = files;
    final res = [
      for (final f in l)
        if (v.contains(f) && f['DATE_ABD'] == null) f,
    ];
    num rank(Map<String, dynamic> f) => f['FIC_RANG'] as num? ?? double.infinity;
    res.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      final p = ((b['FIC_PRINCIPALE'] as int?) ?? 0).compareTo((a['FIC_PRINCIPALE'] as int?) ?? 0);
      return p != 0 ? p : l.indexOf(a).compareTo(l.indexOf(b));
    });
    return res;
  }

  /// Fixe l'ordre de la galerie : rangs 1 à n, la première en photo de référence.
  void reorderPhotos(List<Map<String, dynamic>> order) {
    for (var i = 0; i < order.length; i++) {
      order[i]['FIC_RANG'] = i + 1;
      order[i]['FIC_PRINCIPALE'] = i == 0 ? 1 : 0;
    }
  }

  /// Ajoute une photo prise sur le terminal en fin de galerie du visuel [v] ; `fichier` donne son chemin dans le
  /// paquet de retour.
  Map<String, dynamic> addPhoto(Visual v, {required String name, required int size, required String author}) {
    final id = const Uuid().v4();
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
    final date = Bundle.timestamp();
    final f = <String, dynamic>{
      'ENTITE': 'PRJ_NOE',
      if (v.free) ...{'VIS_CODE': v.code, 'VIS_LIB': v.lib} else 'VUE_CODE': v.code,
      'FIC_CODE_EXT': id,
      'FIC_NOM': name,
      'FIC_TYPE': ?imageTypes[ext],
      'FIC_TAILLE': size,
      'DATE_PRISE': date,
      'DATE_CREA': date,
      'SRC_MODIF': author,
      'fichier': 'fichiers/$id.$ext',
    };
    final order = photos(v);
    props['fichiers'] = [...files, f];
    reorderPhotos([...order, f]);
    return f;
  }

  /// Supprime une photo du visuel [v] : retirée si [isNew], abandonnée sinon ; la galerie est renumérotée.
  void deletePhoto(Visual v, Map<String, dynamic> f, {required bool isNew, required String author}) {
    if (isNew) {
      files.remove(f);
    } else {
      f['DATE_ABD'] = Bundle.timestamp();
      f['SRC_ABD'] = author;
      f['FIC_PRINCIPALE'] = 0;
    }
    reorderPhotos(photos(v));
  }

  /// Change le titre d'un visuel libre (porté par chacune de ses photos).
  void renameVisual(Visual v, String lib) {
    assert(v.free);
    for (final f in files) {
      if (v.contains(f)) f['VIS_LIB'] = lib;
    }
  }
}

const imageTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
};
