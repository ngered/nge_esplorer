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

  /// Nœuds dont l'étiquette contient [text] (casse ignorée, abandonnés exclus), les plus courtes d'abord.
  Future<List<GeoObject>> search(String text, {int max = 20});

  /// Linéaires dont le nœud est une extrémité (abandonnés exclus).
  Future<List<GeoObject>> linearsOf(String nodeId);

  /// Adresses du paquet et créées sur le terminal (abandonnées exclues), avec ou sans position.
  Future<List<GeoObject>> addresses();

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
