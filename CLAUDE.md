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
  réelles par `tools/essai/charger_essai.py` (Heillecourt, Essonne, GraceTHD de test ; `--foa` pour un projet
  d'une seule base FOA, ex. Nancy) ; projet QGIS de
  consultation par `tools/essai/projet_qgis.py` (Python de QGIS : `python-qgis.bat`).
- **Paquet de zone** : [docs/paquet.md](docs/paquet.md) (ZIP : `paquet.json`, `objets.geojson`,
  `referentiels.json`, photos) ; publication et vérification par `tools/geojson/paquet.py` (référence côté BE).
- **Terminal** (`lib/`) : `data/` (objet GeoJSON, paquet, `DataRepository` + implémentation mémoire), `map/`
  (pictos des supports repris de FibReady, couleur du statut de renseignement façon FOA Explorer
  (`modules/completion.dart`) ; `TileSource` : Plan et photos IGN (fond par défaut en France), OSM (ailleurs, Maroc), Google Plan / Satellite /
  Hybride par la Map Tiles API avec la clé renseignée par l'utilisateur dans les paramètres, sous sa responsabilité,
  comme dans FibReady ; tuiles : serveur en usage courant, cache selon les en-têtes HTTP pour la fluidité, secours
  sans connexion sauf Google (règles de la Map Tiles API : ni usage hors connexion, logo et copyright de la vue
  obligatoires) ; calculs d'azimut en grades), `data/settings.dart` (paramètres conservés : Keystore sur Android), `theme.dart` (charte NGE de FibReady, thème clair imposé), `providers/` (`AppProvider`, provider + ChangeNotifier comme cruci),
  `screens/` (carte, visuels du support et galerie, saisie du support, adresse avec détection par géocodage inversé
  `data/geocoding.dart`), `modules/<module>/` (futurs paquets Dart : poteau avec la rosace, chambre avec l'aperçu
  et la grille des masques, infra avec les équipements) ; saisie, module et équipements sont des onglets du support
  (`openTab` de `widgets/support_bar.dart` : remplacés, non empilés).
  Tests : `flutter test` ; `PAQUET_REEL=<zip>` pour un vrai paquet.
- **Nommage du code** (comme FibReady) : identifiants et fichiers en anglais (types, méthodes, champs, paramètres,
  locales) ; commentaires et textes d'interface en français. Conservés : termes métier abrégés calqués sur les
  colonnes (`noe`, `lin`, `adr`, `chb`, `pot`, `cd`, `mat`, `equ`, `ctl`, `lib`) et préfixes `nb`, `col`, `txt` ;
  noms persistés (clés GeoJSON et `properties.<module>`, colonnes en majuscules, clés des réglages, codes de module,
  d'où les dossiers `modules/chambre` et `modules/poteau`).
- **Multilingue** (comme `CommonTools.Lng` de FibReady) : `tr('texte français', [args])` et
  `trn(n, singulier, pluriel)` de [lib/lng.dart](lib/lng.dart), le français servant de clé ; catalogues
  `assets/lang/{en,es,pt,de}.json` tenus à jour par `o:\flutter\sdk\flutter\bin\dart.bat run tools/lang/lng_extract.dart`
  (`--list-empty`, `--prune`) ; `test/lng_test.dart` échoue s'il manque une traduction. Textes constants
  (énumérations, tables `const`) marqués `// tr` et traduits à l'affichage. Restent en français : ce qui est écrit dans
  les données ou le paquet de retour, les libellés des référentiels (fournis par le BE), les noms propres. Langue
  choisie dans les Paramètres, appliquée sans redémarrage. Tout nouveau texte d'interface passe par `tr`, puis
  extraction et traduction des quatre catalogues.
- **Modules** : manifeste commun (BE, terminal, GeoJSON) ; côté BE, un fichier SQLite par module attaché au noyau
  (pas de clé étrangère entre bases, intégrité par l'application, journal non WAL) ; côté terminal, un paquet Dart
  et un espace `properties.<module>` par module.

## Environnement (poste actuel)

- Dépôt git : Azure DevOps `https://ngeInfranetSig@dev.azure.com/ngeInfranetSig/nge_esplorer/_git/nge_esplorer`
  (remote `origin`, branche `main`)
- Flutter hors PATH : `o:\flutter\sdk\flutter\bin\flutter.bat`
- Web : OK (`flutter build web`, `flutter run -d chrome`) ; cadre de terminal par l'adresse : `?terminal=smartphone` (360×800),
  `grand` (412×915), `tablette` (800×1280), `paysage` (1280×800) ou `390x844` ; photos non embarquées lues au
  serveur local `tools/essai/serveur_photos.py <projet>` par `&photos=8090` ou `--dart-define=SERVEUR_PHOTOS=8090` (lanceur « photos de Nancy » : pas de `&` dans les arguments, flutter.bat le prend pour un séparateur de commandes)
- Windows desktop : bloqué (Mode développeur désactivé) ; Android : pas de SDK, JDK 11 seulement
- Proxy Zscaler (inspection SSL) : pour Gradle, `systemProp.javax.net.ssl.trustStoreType=Windows-ROOT`
- VM Azure SRV0270 : demande d'évolution en cours (voir docs/echanges.md §9)

## Documents pour la DSI

- Rédigés en français, sans mentionner Claude ni l'assistance IA ; pas de titre « Questions à la DSI » (« Questions »).
- Marquage en pied de page selon la politique d'étiquettes NGE : `C3-CONFIDENTIEL : Propriété de NGE` (données
  NgeEsPlorer), `C2-LIMITÉ : Propriété de NGE` (infrastructure), centré, 10 pt.
- Copies dans [docs/dsi/](docs/dsi/).
