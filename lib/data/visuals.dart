import 'package:uuid/uuid.dart';

import '../lng.dart';
import 'geo_object.dart';
import 'bundle.dart';
import 'reference_data.dart';

/// Visuel d'un support ou d'un de ses équipements : groupe de photos avec ses fonctions propres (docs/echanges.md
/// §8). Visuel **attendu** : vue du type du support ou vue des équipements (`DEF_VUE`, `VUE_ENTITE` `INF_EQUIPEMENT`
/// : boîtier fermé, ouvert, cassettes, mesures), photos repérées par `VUE_CODE`, fonction `VUE_ACTION` : MASQUE pour
/// la grille du masque de chambre. Visuel **libre** : ajouté sur le terrain, titre saisi (photos repérées par
/// `VIS_CODE`, titre `VIS_LIB`) ; il existe tant qu'il a des photos. Les photos d'un équipement sont portées par son
/// support (`ENTITE` `INF_EQUIPEMENT`, `EQU_KEY` : son `EQU_CODE_EXT`).
class Visual {
  const Visual._(this.code, this.lib,
      {this.free = false, this.mandatory = false, this.ifMasked = false, this.action, this.equipment});

  factory Visual.expected(Map<String, dynamic> def, {String? equipment}) => Visual._(
        def['VUE_CODE'] as String,
        def['VUE_LIB'] as String? ?? def['VUE_CODE'] as String,
        mandatory: def['VUE_OBLIGATOIRE'] == 'OUI',
        ifMasked: def['VUE_OBLIGATOIRE'] == 'SI_MASQUE',
        action: def['VUE_ACTION'] as String?,
        equipment: equipment,
      );

  /// Nouveau visuel libre, sans photo jusqu'à la première prise ; de l'équipement [equipment] s'il est donné.
  factory Visual.free(String lib, [String? code, String? equipment]) =>
      Visual._(code ?? const Uuid().v4(), lib, free: true, equipment: equipment);

  /// Entité des photos d'un équipement (`ENTITE` des fichiers, `VUE_ENTITE` de ses vues attendues).
  static const equipmentEntity = 'INF_EQUIPEMENT';

  final String code;
  final String lib;
  final bool free;
  final bool mandatory;

  /// Obligatoire si la face de chambre porte un masque.
  final bool ifMasked;
  final String? action;

  /// `EQU_CODE_EXT` de l'équipement dont c'est un visuel ; null : visuel du support.
  final String? equipment;

  /// Le même visuel libre sous le titre [lib].
  Visual renamed(String lib) => Visual.free(lib, code, equipment);

  /// Équipement de la photo [f] (`EQU_KEY` d'une photo d'`ENTITE` `INF_EQUIPEMENT`) ; null : photo du support. Une
  /// photo d'équipement d'un paquet antérieur au format 0.4.0, sans `EQU_KEY`, reste au support.
  static String? equipmentOf(Map<String, dynamic> f) =>
      f['ENTITE'] == equipmentEntity ? f['EQU_KEY'] as String? : null;

  /// La photo [f] appartient à ce visuel.
  bool contains(Map<String, dynamic> f) =>
      equipmentOf(f) == equipment && (free ? f['VIS_CODE'] == code : f['VUE_CODE'] == code);

  /// Visuels de [o] : attendus pour son type et ses types parents (ordre de `VUE_ORDRE`), puis libres (ordre de
  /// création). Sans les visuels de ses équipements ([ofEquipment]).
  static List<Visual> of(GeoObject o, ReferenceData ref) {
    final types = <int?>{o.typeKey};
    for (var t = ref.type(o.typeKey); t != null; t = ref.type(t['TYPE_PARENT_KEY'] as int?)) {
      if (!types.add(t['TYPE_PARENT_KEY'] as int?)) break;
    }
    return _visuals(
        o, ref, (v) => v['VUE_ENTITE'] == null && v['TYPE_KEY'] != null && types.contains(v['TYPE_KEY']), null);
  }

  /// Visuels de l'équipement [equipment] (`EQU_CODE_EXT`) du support [o] : vues des équipements, puis libres.
  static List<Visual> ofEquipment(GeoObject o, String equipment, ReferenceData ref) =>
      _visuals(o, ref, (v) => v['VUE_ENTITE'] == equipmentEntity, equipment);

  static List<Visual> _visuals(
      GeoObject o, ReferenceData ref, bool Function(Map<String, dynamic> v) expected, String? equipment) {
    final views = ref.table('noyau', 'DEF_VUE').where(expected).toList()
      ..sort((a, b) => (a['VUE_ORDRE'] as int).compareTo(b['VUE_ORDRE'] as int));
    final freeVisuals = <String, Visual>{};
    for (final f in o.files) {
      final code = f['VIS_CODE'] as String?;
      if (code != null && f['DATE_ABD'] == null && equipmentOf(f) == equipment) {
        freeVisuals.putIfAbsent(
            code, () => Visual.free(f['VIS_LIB'] as String? ?? tr('Visuel libre'), code, equipment));
      }
    }
    return [for (final v in views) Visual.expected(v, equipment: equipment), ...freeVisuals.values];
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
      if (v.equipment == null) 'ENTITE': 'PRJ_NOE' else ...{'ENTITE': Visual.equipmentEntity, 'EQU_KEY': v.equipment},
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
