# NgeEsPlorer — contexte projet

Application Android terrain multi-métiers (télécoms et électricité) de NGE-ES : SIG, photos, formulaires pilotés,
modules métiers combinables, travail hors ligne en zone blanche. Synthèse complète des échanges de conception :
[docs/echanges.md](docs/echanges.md). Note de vision d'ensemble : à venir.

## Stack et cibles

- **Flutter** 3.41+ / Dart 3.11+ — package `nge_esplorer`, identifiant Android `fr.nge.esplorer`
- **Cibles** : Android (production), web (développement en attendant Android), Windows (possible)
- Maquette : Figma [infraExp](https://www.figma.com/design/RyUPQF7cUKdUyqV9J6kpcZ/infraExp) (fileKey
  `RyUPQF7cUKdUyqV9J6kpcZ`, lisible par le connecteur Figma ; analyse dans docs/echanges.md §11)
- Carte : `flutter_map` ou `maplibre_gl` ; géométries `geobase` ; projections `proj4dart` ;
  base locale chiffrée Drift + `sqlcipher_flutter_libs` (Android)

## Principes d'architecture

- **Interfaces + implémentations par plateforme** (comme `WordRepository` dans `o:\flutter\cruci`) :
  `DataRepository`, `TileSource`, `KeyStore` — web provisoire, Android cible.
- **Fonds de plan** (MBTiles/PMTiles) séparés des **données** (GeoJSON, une ligne par objet en SQLite, colonnes
  d'emprise indexées). Protection selon la sensibilité : fonds publics en clair, fonds métier et données chiffrés
  par zone.
- **Sécurité** : principe NGE Es'tore (`o:\C#\FibReady_net.10\Megatools\Deploiement\sources\README.md`) — jeton
  abonné, liste des comptes signée, clé par zone remise aux abonnés, SAS Azure commun ; la révocation passe par
  le changement de clé de zone. Clés dans l'Android Keystore, jamais dans le code.
- **Phase 1** : import / export GeoJSON (UUID stable, date de modification, statut, WGS84, version du format).
- **Phase 2** : PostGIS interne jamais exposée aux terminaux ; échange par paquets chiffrés via Azure ; **tous les
  retours passent par validation dans le sas de contrôle et de synchronisation** avant intégration.
- Sur le web : données de test uniquement (pas de chiffrement local dans le navigateur).
- **Périmètre** : saisie terrain uniquement. Préparation des données et sorties (FOA, C3A…) dans une application BE
  en C# (famille FibReady) ; base BE SpatiaLite puis PostGIS, schéma commun `PRJ_NOE` / `PRJ_LINEAIRE` + schémas
  métiers ; modèle mixte GraceTHD v2 (séparation géométrie / métier) et FOA Explorer (`XXX_ID` / `XXX_KEY`, tables
  `MAT_*`). Terminal : SQLite chiffrée, une ligne par objet GeoJSON complet (voir docs/echanges.md §11).
- **Schéma BE** : [schema/](schema/README.md) (un dossier par domaine : manifeste + SQL) ; construction et essai
  par `tools/schema/projet.py` (implémentation de référence de la bibliothèque noyau C#) ; jeu d'essai sur données
  réelles par `tools/essai/charger_essai.py` (Heillecourt, Essonne, GraceTHD de test) ; projet QGIS de
  consultation par `tools/essai/projet_qgis.py` (Python de QGIS : `python-qgis.bat`).
- **Paquet de zone** : [docs/paquet.md](docs/paquet.md) (ZIP : `paquet.json`, `objets.geojson`,
  `referentiels.json`, photos) ; publication et vérification par `tools/geojson/paquet.py` (référence côté BE).
- **Terminal** (`lib/`) : `data/` (objet GeoJSON, paquet, `DataRepository` + implémentation mémoire), `carte/`
  (`TileSource` : Plan et photos IGN (fond par défaut en France), OSM (ailleurs, Maroc), Google Plan / Satellite /
  Hybride par la Map Tiles API avec la clé renseignée par l'utilisateur dans les paramètres, sous sa responsabilité,
  comme dans FibReady ; tuiles : serveur en usage courant, cache selon les en-têtes HTTP pour la fluidité, secours
  sans connexion sauf Google (règles de la Map Tiles API : ni usage hors connexion, logo et copyright de la vue
  obligatoires) ; calculs d'azimut en grades), `data/reglages.dart` (paramètres conservés : Keystore sur Android), `providers/` (`AppProvider`, provider + ChangeNotifier comme cruci),
  `screens/` (carte, fiche), `modules/<module>/` (futurs paquets Dart : poteau avec la rosace, chambre, infra).
  Tests : `flutter test` ; `PAQUET_REEL=<zip>` pour un vrai paquet.
- **Modules** : manifeste commun (BE, terminal, GeoJSON) ; côté BE, un fichier SQLite par module attaché au noyau
  (pas de clé étrangère entre bases, intégrité par l'application, journal non WAL) ; côté terminal, un paquet Dart
  et un espace `properties.<module>` par module.

## Environnement (poste actuel)

- Dépôt git : Azure DevOps `https://ngeInfranetSig@dev.azure.com/ngeInfranetSig/nge_esplorer/_git/nge_esplorer`
  (remote `origin`, branche `main`)
- Flutter hors PATH : `o:\flutter\sdk\flutter\bin\flutter.bat`
- Web : OK (`flutter build web`, `flutter run -d chrome`)
- Windows desktop : bloqué (Mode développeur désactivé) ; Android : pas de SDK, JDK 11 seulement
- Proxy Zscaler (inspection SSL) : pour Gradle, `systemProp.javax.net.ssl.trustStoreType=Windows-ROOT`
- VM Azure SRV0270 : demande d'évolution en cours (voir docs/echanges.md §9)

## Documents pour la DSI

- Rédigés en français, sans mentionner Claude ni l'assistance IA ; pas de titre « Questions à la DSI » (« Questions »).
- Marquage en pied de page selon la politique d'étiquettes NGE : `C3-CONFIDENTIEL : Propriété de NGE` (données
  NgeEsPlorer), `C2-LIMITÉ : Propriété de NGE` (infrastructure), centré, 10 pt.
- Copies dans [docs/dsi/](docs/dsi/).
