# NgeEsPlorer — synthèse des échanges (octobre 2026)

Décisions, recommandations et points ouverts issus des échanges de conception (22 au 30 octobre 2026).
La note de vision d'ensemble (finalité, mode de fonctionnement, choix techniques) viendra compléter ce document.

## 1. Objet

Application Android (APK) multi-métiers (télécoms et électricité), en Flutter + Dart.

- Socle commun : SIG, gestion des photos, formulaires pilotés.
- Modules métiers indépendants et combinables : optique, parcours d'infrastructures, immeubles, administratif
  (adresses), réseau électrique.
- Diffusion par store ou téléchargement de l'APK ; accès à l'application et aux données par jeton abonné ;
  abonnements par zone ; jetons révocables par l'administration.
- Données abonnés = GeoJSON + fonds de plan, téléchargés depuis Azure (SAS), chiffrés, lisibles par l'application
  seule ; synchronisation à la demande ; travail en zone blanche.

Source : [dsi/description.md](dsi/description.md).

## 2. APK plutôt que PWA

| Critère | APK (retenu) | PWA |
| --- | --- | --- |
| Fonds de plan embarqués | Sur le terminal, sans quota ni purge | Stockage du navigateur limité, purgeable |
| Gros volumes GeoJSON | Lecture native, rapide | Plus lent |
| Zone blanche | Fonctionnement complet | Dépend de ce que le navigateur a conservé |
| Maîtrise des données | Stockage chiffré, application seule | Stockage géré par le navigateur |

La PWA garde l'avantage de la diffusion (une URL) et des mises à jour immédiates, mais pas pour du hors ligne
lourd. Flutter permet une version web ou Windows ultérieure avec le même code.

## 3. Flutter et données spatiales

Dart n'a pas de pile SIG complète (ni GDAL, ni SpatiaLite, ni JTS, ni GeoPackage clé en main). Ce qui fonctionne :

| Besoin | Solution |
| --- | --- |
| Fonds de plan hors ligne (raster ou vectoriel) | MBTiles / PMTiles via `flutter_map` (+ extensions) ou `maplibre_gl` |
| Géométries | `geobase` (GeoJSON, WKT, WKB) |
| Projections (Lambert 93 ↔ WGS84) | `proj4dart` |
| Base locale chiffrée | `sqlcipher_flutter_libs` avec Drift |
| SIG complet (payant) | ArcGIS Maps SDK for Flutter |

Recommandation : le SIG lourd reste côté serveur (GDAL / ogr2ogr, tippecanoe). Sur le terminal :
- GeoJSON en base SQLite chiffrée, **une ligne par objet**, colonnes d'emprise (xmin, ymin, xmax, ymax) indexées
  (R-tree si disponible) — jamais un gros fichier GeoJSON chargé en entier ;
- affichage par `flutter_map` ou MapLibre.

Si l'application doit faire de l'analyse spatiale sur le terrain (pas seulement consultation et saisie), Flutter
atteint ses limites : ArcGIS SDK ou code natif.

## 4. Fonds de plan séparés des données

La protection dépend de la sensibilité de la donnée, pas de sa forme : « le public est partagé, le sensible est
chiffré et cloisonné ».

| Catégorie | Exemples | Format | Chiffrement | Diffusion | Mise à jour |
| --- | --- | --- | --- | --- | --- |
| Fonds de plan publics | IGN, OSM | MBTiles | Non | Tous les abonnés d'une zone | Rare, par paquet versionné |
| Fonds de plan métier | Réseaux existants, plans de récolement | MBTiles | Oui, clé de zone | Abonnés de la zone | Par paquet |
| Données éditables | Objets métier, formulaires, photos | GeoJSON en base locale | Oui, clé de zone | Abonnés de la zone | Synchronisation à la demande, deux sens |

Licences : pas de téléchargement massif des tuiles OSM publiques ; préférer la Géoplateforme IGN (licence ouverte)
ou des tuiles générées en interne.

## 5. Sécurité et révocation — principe de NGE Es'tore

Réutilisation du modèle NGE Es'tore (`o:\C#\FibReady_net.10\Megatools\Deploiement\`, voir `sources/README.md`) :
SAS commun à tous (stratégie d'accès stockée), révocation portée par les clés.

| Niveau | Action de l'administration | Effet |
| --- | --- | --- |
| 1. Compte | Abonnement retiré, compte suspendu ou nouveau jeton (liste signée des comptes) | Connexion et synchronisation refusées |
| 2. Clé de zone | Nouvelle clé pour chaque zone du compte retiré, remise aux seuls abonnés restants | Données publiées ensuite illisibles pour le compte retiré |
| 3. SAS | Nouvelle stratégie d'accès stockée, révocation de l'ancienne | Plus de téléchargement, même chiffré |

- Conteneur `demandes` en **création seule** : chacun dépose, personne ne lit ni ne supprime les dépôts des autres.
- Catalogue et liste des comptes signés (ECDSA P-256 dans NGE Es'tore) ; chiffrement AES-256-GCM, clé de projet
  (ici : de zone) chiffrée par une clé dérivée du secret du jeton.

Limites assumées :
- un terminal hors ligne n'est révoqué qu'à sa reconnexion → durée maximale sans synchronisation, au-delà de
  laquelle l'application refuse d'ouvrir les données locales ;
- les données déjà téléchargées restent déchiffrables par qui contourne l'application → effacement local à la
  reconnexion d'un compte révoqué, clés dans l'Android Keystore (jamais dans le code) ;
- changer la clé d'une zone impose de rechiffrer ses données (fait à la publication).

Pistes écartées ou en réserve : authentification Entra ID + SAS courts générés par un service (plus lourd, peu
adapté aux prestataires hors domaine) ; Managed Google Play / Intune (pertinent si les terminaux sont gérés NGE).

## 6. Données sensibles — périmètre vis-à-vis de la DSI

La demande NGE Es'tore du 13 octobre 2026 précisait « aucune donnée métier ». NgeEsPlorer stockera des données
métier sensibles sur Azure : changement de périmètre signalé à la DSI dans le complément du 22 octobre
(chiffrement par zone, cloisonnement, prestataires abonnés).

Questions posées : même compte de stockage ou compte dédié ; remise de données métier chiffrées à des
prestataires ; durée maximale hors ligne ; exigences de journalisation.

## 7. Phases de développement

### Phase 1 — import / export GeoJSON

Conçue comme la future méthode d'échange avec PostGIS, pas comme une solution jetable. Format à fixer comme une
norme interne :
- identifiant stable par objet (UUID), jamais modifié ;
- date de modification et statut (créé, modifié, supprimé), comme `status` / `date_modif` dans cruci ;
- coordonnées WGS84 (RFC 7946), conversion Lambert 93 à l'import / export ;
- numéro de version du format dans le fichier.

### Phase 2 — base PostGIS interne

PostGIS n'est **jamais exposée** aux terminaux (ni identifiants de base sur les mobiles, ni ouverture réseau ;
une partie des utilisateurs sont des sous-traitants, sur mobiles NGE). Échange par fichiers, automatisé :

1. PostGIS → Azure : tâche planifiée côté NGE, export par zone en paquets GeoJSON chiffrés ;
2. Mobiles ↔ Azure : téléchargement des paquets, dépôt des saisies (conteneur en création seule) ;
3. Azure → PostGIS : tâche côté NGE, chargement dans des tables d'attente.

**Décision** : tous les retours (sous-traitants comme internes) passent par validation dans un **sas de contrôle
et de synchronisation** avant intégration au référentiel. Outils : `ogr2ogr` (GeoJSON → PostGIS),
`ST_AsGeoJSON` (PostGIS → GeoJSON).

La phase 1 est la version manuelle de la phase 2 : mêmes fichiers, même format ; seul le transport s'automatise.

## 8. Développer en attendant Android

La compilation **web** fonctionne sur le poste actuel (vérifié le 30/10/2026 : `flutter build web` en 43 s ;
l'avertissement « wasm dry run » est sans conséquence). Windows desktop et Android sont bloqués (voir §9).

Organisation : interfaces + implémentations par plateforme, comme `WordRepository` dans cruci :

| Interface | Web (provisoire) | Android (cible) |
| --- | --- | --- |
| `DataRepository` | Mémoire / téléchargement direct | SQLite chiffrée (SQLCipher) |
| `TileSource` | Tuiles HTTP (PMTiles, serveur) | MBTiles locales |
| `KeyStore` | Factice | Android Keystore |

Précautions : uniquement des **données de test** sur le web (pas de chiffrement local dans le navigateur) ; tester
sur Android dès que possible (volumes, permissions GPS / appareil photo).

## 9. Environnement de développement

### Poste actuel (sans droits administrateur)

- Flutter 3.41.7 dans `o:\flutter\sdk\flutter`, **absent du PATH** → `o:\flutter\sdk\flutter\bin\flutter.bat`.
- Windows desktop : bloqué par le **Mode développeur** désactivé (liens symboliques des plugins).
- Android : pas de SDK Android, JDK 11 seulement (il faut le JDK 17).
- Réseau : tous les dépôts (Gradle, Maven, Google, pub.dev) accessibles, mais **inspection SSL Zscaler** : Java ne
  connaît pas le certificat Zscaler → `systemProp.javax.net.ssl.trustStoreType=Windows-ROOT` dans
  `%USERPROFILE%\.gradle\gradle.properties`, ou import du certificat dans le `cacerts` du JDK 17.
- Visual Studio 2022 / 2026 avec C++ et Windows SDK : présents.

### VM Azure SRV0270 (droits administrateur, accès Internet)

État actuel : B2s (2 vCPU, 4 Go), Windows Server 2019, disque système seul, sans arrêt automatique. VS Code plante
au démarrage, certains outils refusent de s'installer → inutilisable en l'état.

Demande d'évolution envoyée (version 32 Go) : D8s_v5 recommandé / D4s_v5 minimum ; Windows 11 si licences, sinon
Windows Server 2025 (winget intégré) ; disque de données SSD Premium 128 Go ; arrêt automatique ; ouverture du port
SSH par un accès sécurisé (VPN, Bastion ou règle réseau). Usage prévu : VS Code Remote-SSH depuis le poste,
compilation sur la VM, APK rapatrié et installé par adb sur le téléphone branché au poste.

Ne rien installer de lourd avant la réponse : un passage à Windows 11 implique de recréer la VM.

## 10. Documents produits

| Document | Destinataire | Fichier | En ligne |
| --- | --- | --- | --- |
| Synthèse NgeEsPlorer (sécurité, souplesse, APK vs PWA) | DSI | [dsi/NgeEsPlorer.pdf](dsi/NgeEsPlorer.pdf), [version texte](dsi/NgeEsPlorer%20-%20C3-CONFIDENTIEL.txt) | [lien](https://claude.ai/artifact/KMknMowqLeBgc1JCMPW8gd) |
| Complément : révocation et données sensibles | DSI | [dsi/NgeEsPlorer - Complément - C3-CONFIDENTIEL.pdf](dsi/NgeEsPlorer%20-%20Complément%20-%20C3-CONFIDENTIEL.pdf) | [lien](https://claude.ai/artifact/KEy5R2bdjG49vDjVc27mVS) |
| Demande d'évolution de la VM SRV0270 | DSI / admins Azure | [dsi/Demande évolution VM SRV0270 - C2-LIMITE.pdf](dsi/Demande%20évolution%20VM%20SRV0270%20-%20C2-LIMITE.pdf) | [lien](https://claude.ai/artifact/RybMkNjepK2b99o3Czk7mQ) |

Marquage : C3-CONFIDENTIEL pour NgeEsPlorer, C2-LIMITÉ pour la VM (libellés de la politique d'étiquettes Office
NGE : « Cx : Propriété de NGE », pied de page centré, 10 pt).

## 11. Points ouverts

- Réponses de la DSI : synthèse + complément NgeEsPlorer, évolution de la VM.
- Note de vision d'ensemble (finalité, mode de fonctionnement, choix techniques) — à venir.
- Spécification du format GeoJSON de la phase 1 (propriétés communes, identifiants, statuts, versions, exemple par
  module).
- Terminaux des sous-traitants : mobiles NGE gérés (Intune / MDM ?) → effacement à distance possible.
- Références existantes dans `docs/` : `Besoins_KIZEO.xlsx`, `exemple_fiche_KIZEO.zip`, maquette `infraExp.fig`.
