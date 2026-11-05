import 'dart:typed_data';

import 'geo_object.dart';
import 'bundle.dart';
import 'reference_data.dart';

/// Données d'un paquet de zone sur le terminal : une ligne par objet GeoJSON (docs/paquet.md).
///
/// Web (provisoire) : mémoire, données de test uniquement. Android (cible) : SQLite chiffrée (SQLCipher), colonnes
/// d'index (id, classe, statut, date de modification, emprise) et objet GeoJSON complet.
abstract class DataRepository {
  bool get isOpen;

  /// En-tête du paquet de publication chargé (projet, zone, modules, date).
  Map<String, dynamic>? get header;

  ReferenceData get referenceData;

  /// Remplace les données locales par celles d'un paquet de publication.
  Future<void> load(Bundle bundle);

  Future<void> close();

  /// Objets dont l'emprise coupe le rectangle [minLon, minLat, maxLon, maxLat] (abandonnés exclus).
  Future<List<GeoObject>> objectsInBounds(List<double> bounds, {Set<ObjectClass> classes = const {ObjectClass.noe, ObjectClass.lin}});

  Future<GeoObject?> object(String id);

  /// Supports trouvés par [text] (casse et espaces superflus ignorés, abandonnés exclus) dans leur étiquette et dans
  /// les entités qui leur sont associées ([SearchMatch]) ; textes trouvés les plus courts d'abord.
  Future<List<SearchHit>> search(String text, {int max = 20});

  /// Linéaires dont le nœud est une extrémité (abandonnés exclus).
  Future<List<GeoObject>> linearsOf(String nodeId);

  /// Adresses du paquet et créées sur le terminal (abandonnées exclues), avec ou sans position.
  Future<List<GeoObject>> addresses();

  /// Câbles optiques dont le nœud est une extrémité (`NOE1_KEY`, `NOE2_KEY` ; abandonnés exclus).
  Future<List<GeoObject>> cablesOf(String nodeId);

  /// Câbles optiques tirés sur chacun des linéaires [linearIds] (`passages[].LIN_KEY` de leur parcours ; abandonnés
  /// exclus) : couche Tirage de la carte. Un linéaire sans câble est absent du résultat.
  Future<Map<String, List<GeoObject>>> cablesOnLinears(Iterable<String> linearIds);

  /// Nœud qui porte l'équipement [equipmentId] (`EQU_CODE_EXT` de `inf.equipements`).
  Future<GeoObject?> nodeOfEquipment(String equipmentId);

  /// Adresses dont un local est desservi par l'équipement [equipmentId] (`imb.locaux[].EQU_KEY` ; abandonnées
  /// exclues).
  Future<List<GeoObject>> addressesServedBy(String equipmentId);

  /// Enregistre une copie modifiée : pose `statut`, `DATE_MODIF` et `SRC_MODIF` (ou `DATE_ABD` si [abandon]).
  Future<void> save(GeoObject object, {required String author, bool abandon = false});

  /// Objets modifiés depuis le chargement, pour le paquet de retour.
  Future<List<GeoObject>> modifies();

  /// Fichier joint au paquet ou pris sur le terminal (photo), par son chemin dans le paquet.
  Uint8List? file(String path);

  /// Conserve un fichier pris sur le terminal (photo), à remonter avec le paquet de retour.
  Future<void> addFile(String path, Uint8List bytes);

  /// Fichiers pris sur le terminal depuis le chargement du paquet, par chemin.
  Map<String, Uint8List> get newFiles;
}

/// Ce qui a mené au support dans une recherche.
enum SearchMatch {
  /// Étiquette du support (`NOE_LIB`).
  support,

  /// Étiquette d'un équipement optique présent dans le support (`opt.equipements[].EQO_LIB`).
  equipment,

  /// Étiquette d'un câble optique dont le support est une extrémité (`CAB_LIB`).
  cable,

  /// Adresse du support (`ADR_KEY`).
  address,

  /// Adresse dont un local est desservi par un équipement du support (`imb.locaux[].EQU_KEY`).
  servedAddress,
}

/// Résultat d'une recherche : le support à repérer, ce qui y a mené et le texte trouvé ; [equipment] : équipement en
/// cause (`EQU_CODE_EXT`), pour un équipement ou une adresse desservie.
class SearchHit {
  const SearchHit(this.support, this.match, this.text, {this.equipment});

  final GeoObject support;
  final SearchMatch match;
  final String text;
  final String? equipment;
}
