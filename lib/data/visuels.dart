import 'package:uuid/uuid.dart';

import 'objet.dart';
import 'paquet.dart';
import 'referentiels.dart';

/// Visuel d'un support : groupe de photos avec ses fonctions propres (docs/echanges.md §8). Visuel **attendu** :
/// vue du type (`DEF_VUE`, photos repérées par `VUE_CODE`, fonction `VUE_ACTION` : MASQUE pour la grille du masque
/// de chambre). Visuel **libre** : ajouté sur le terrain, titre saisi (photos repérées par `VIS_CODE`, titre
/// `VIS_LIB`) ; il existe tant qu'il a des photos.
class Visuel {
  const Visuel._(this.code, this.lib, {this.libre = false, this.obligatoire = false, this.siMasque = false, this.action});

  factory Visuel.attendu(Map<String, dynamic> def) => Visuel._(
        def['VUE_CODE'] as String,
        def['VUE_LIB'] as String? ?? def['VUE_CODE'] as String,
        obligatoire: def['VUE_OBLIGATOIRE'] == 'OUI',
        siMasque: def['VUE_OBLIGATOIRE'] == 'SI_MASQUE',
        action: def['VUE_ACTION'] as String?,
      );

  /// Nouveau visuel libre, sans photo jusqu'à la première prise.
  factory Visuel.libre(String lib, [String? code]) => Visuel._(code ?? const Uuid().v4(), lib, libre: true);

  final String code;
  final String lib;
  final bool libre;
  final bool obligatoire;

  /// Obligatoire si la face de chambre porte un masque.
  final bool siMasque;
  final String? action;

  /// La photo [f] appartient à ce visuel.
  bool contient(Map<String, dynamic> f) => libre ? f['VIS_CODE'] == code : f['VUE_CODE'] == code;

  /// Visuels de [o] : attendus pour son type et ses types parents (ordre de `VUE_ORDRE`), puis libres (ordre de
  /// création).
  static List<Visuel> de(Objet o, Referentiels ref) {
    final types = <int?>{o.typeKey};
    for (var t = ref.type(o.typeKey); t != null; t = ref.type(t['TYPE_PARENT_KEY'] as int?)) {
      if (!types.add(t['TYPE_PARENT_KEY'] as int?)) break;
    }
    final vues = ref.table('noyau', 'DEF_VUE').where((v) => types.contains(v['TYPE_KEY'])).toList()
      ..sort((a, b) => (a['VUE_ORDRE'] as int).compareTo(b['VUE_ORDRE'] as int));
    final libres = <String, Visuel>{};
    for (final f in o.fichiers) {
      final code = f['VIS_CODE'] as String?;
      if (code != null && f['DATE_ABD'] == null) {
        libres.putIfAbsent(code, () => Visuel.libre(f['VIS_LIB'] as String? ?? 'Visuel libre', code));
      }
    }
    return [for (final v in vues) Visuel.attendu(v), ...libres.values];
  }
}

/// Photos d'un objet (`fichiers`, PRJ_FICHIER) rangées par visuel. L'ordre de la galerie est `FIC_RANG` ; la
/// première photo est la photo de référence du visuel (`FIC_PRINCIPALE`). Une photo supprimée est abandonnée
/// (`DATE_ABD`, validée au contrôle du retour), sauf si elle a été prise sur le terminal et n'est pas encore
/// remontée : elle est alors retirée.
extension PhotosObjet on Objet {
  /// Liste des fichiers de l'objet, normalisée une fois (mêmes cartes d'un appel à l'autre).
  List<Map<String, dynamic>> get fichiers {
    final l = props['fichiers'];
    if (l is List<Map<String, dynamic>>) return l;
    final res = [for (final f in (l as List?) ?? const []) Map<String, dynamic>.from(f as Map)];
    if (l != null) props['fichiers'] = res;
    return res;
  }

  /// Photos du visuel [v] dans l'ordre de la galerie (abandonnées exclues).
  List<Map<String, dynamic>> photos(Visuel v) {
    final l = fichiers;
    final res = [
      for (final f in l)
        if (v.contient(f) && f['DATE_ABD'] == null) f,
    ];
    num rang(Map<String, dynamic> f) => f['FIC_RANG'] as num? ?? double.infinity;
    res.sort((a, b) {
      final c = rang(a).compareTo(rang(b));
      if (c != 0) return c;
      final p = ((b['FIC_PRINCIPALE'] as int?) ?? 0).compareTo((a['FIC_PRINCIPALE'] as int?) ?? 0);
      return p != 0 ? p : l.indexOf(a).compareTo(l.indexOf(b));
    });
    return res;
  }

  /// Fixe l'ordre de la galerie : rangs 1 à n, la première en photo de référence.
  void ordonnerPhotos(List<Map<String, dynamic>> ordre) {
    for (var i = 0; i < ordre.length; i++) {
      ordre[i]['FIC_RANG'] = i + 1;
      ordre[i]['FIC_PRINCIPALE'] = i == 0 ? 1 : 0;
    }
  }

  /// Ajoute une photo prise sur le terminal en fin de galerie du visuel [v] ; `fichier` donne son chemin dans le
  /// paquet de retour.
  Map<String, dynamic> ajouterPhoto(Visuel v, {required String nom, required int taille, required String auteur}) {
    final id = const Uuid().v4();
    final ext = nom.contains('.') ? nom.split('.').last.toLowerCase() : 'jpg';
    final date = Paquet.horodatage();
    final f = <String, dynamic>{
      'ENTITE': 'PRJ_NOE',
      if (v.libre) ...{'VIS_CODE': v.code, 'VIS_LIB': v.lib} else 'VUE_CODE': v.code,
      'FIC_CODE_EXT': id,
      'FIC_NOM': nom,
      'FIC_TYPE': ?typesImage[ext],
      'FIC_TAILLE': taille,
      'DATE_PRISE': date,
      'DATE_CREA': date,
      'SRC_MODIF': auteur,
      'fichier': 'fichiers/$id.$ext',
    };
    final ordre = photos(v);
    props['fichiers'] = [...fichiers, f];
    ordonnerPhotos([...ordre, f]);
    return f;
  }

  /// Supprime une photo du visuel [v] : retirée si [nouvelle], abandonnée sinon ; la galerie est renumérotée.
  void supprimerPhoto(Visuel v, Map<String, dynamic> f, {required bool nouvelle, required String auteur}) {
    if (nouvelle) {
      fichiers.remove(f);
    } else {
      f['DATE_ABD'] = Paquet.horodatage();
      f['SRC_ABD'] = auteur;
      f['FIC_PRINCIPALE'] = 0;
    }
    ordonnerPhotos(photos(v));
  }

  /// Change le titre d'un visuel libre (porté par chacune de ses photos).
  void renommerVisuel(Visuel v, String lib) {
    assert(v.libre);
    for (final f in fichiers) {
      if (v.contient(f)) f['VIS_LIB'] = lib;
    }
  }
}

const typesImage = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
};
