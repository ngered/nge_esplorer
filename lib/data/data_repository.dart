import 'dart:typed_data';

import 'objet.dart';
import 'paquet.dart';
import 'referentiels.dart';

/// Données d'un paquet de zone sur le terminal : une ligne par objet GeoJSON (docs/paquet.md).
///
/// Web (provisoire) : mémoire, données de test uniquement. Android (cible) : SQLite chiffrée (SQLCipher), colonnes
/// d'index (id, classe, statut, date de modification, emprise) et objet GeoJSON complet.
abstract class DataRepository {
  bool get ouvert;

  /// En-tête du paquet de publication chargé (projet, zone, modules, date).
  Map<String, dynamic>? get entete;

  Referentiels get referentiels;

  /// Remplace les données locales par celles d'un paquet de publication.
  Future<void> charger(Paquet paquet);

  Future<void> fermer();

  /// Objets dont l'emprise coupe le rectangle [minLon, minLat, maxLon, maxLat] (abandonnés exclus).
  Future<List<Objet>> objetsDansEmprise(List<double> emprise, {Set<Classe> classes = const {Classe.noe, Classe.lin}});

  Future<Objet?> objet(String id);

  /// Nœuds dont l'étiquette contient [texte] (casse ignorée, abandonnés exclus), les plus courtes d'abord.
  Future<List<Objet>> rechercher(String texte, {int max = 20});

  /// Linéaires dont le nœud est une extrémité (abandonnés exclus).
  Future<List<Objet>> lineairesDe(String noeudId);

  /// Enregistre une copie modifiée : pose `statut`, `DATE_MODIF` et `SRC_MODIF` (ou `DATE_ABD` si [abandon]).
  Future<void> enregistrer(Objet objet, {required String auteur, bool abandon = false});

  /// Objets modifiés depuis le chargement, pour le paquet de retour.
  Future<List<Objet>> modifies();

  /// Fichier joint au paquet ou pris sur le terminal (photo), par son chemin dans le paquet.
  Uint8List? fichier(String chemin);

  /// Conserve un fichier pris sur le terminal (photo), à remonter avec le paquet de retour.
  Future<void> ajouterFichier(String chemin, Uint8List octets);

  /// Fichiers pris sur le terminal depuis le chargement du paquet, par chemin.
  Map<String, Uint8List> get fichiersNouveaux;
}
