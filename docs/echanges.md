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

Couverture (1er novembre 2026) : l'IGN ne couvre que la France ; hors de France (Maroc notamment), le fond livré
dans le paquet est généré en interne à partir des données OSM (extraits Geofabrik, licence ODbL), jamais aspiré du
serveur public ; imagerie hors de France : source à trouver. Google (Map Tiles API) n'est jamais livré dans un
paquet : ses règles interdisent le préchargement et l'usage hors connexion, avec ou sans clé. Comme dans FibReady,
l'utilisateur renseigne lui-même sa clé Google dans les paramètres de l'application, sous sa responsabilité
(facturation au-delà de la franchise) ; les fonds Google n'apparaissent qu'avec une clé.

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

Jeu d'essai chambres : base `c:\NoDrive\Documents\data\FOA\FTTH_OR_HEILLECOURT\FOA_HEILLECOURT.db` (version de
schéma antérieure à `c:\NoDrive\Documents\Etudes\essonne\09_DOU_12-13_FOA_EXP.db`, qui ajoute l'occupation par
câbles, les liaisons entre chambres et les poteaux) : 1 277 chambres importées du PIT, 51 relevées, 477 alvéoles
(458 avec destination), 232 photos référencées (203 retrouvées sous `Chambres\ID<n>\Photos\`, les chemins en base
pointent vers l'ancien profil), Lambert 93. Les miroirs y sont des **copies** d'alvéoles étiquetées
`MIROIR_<chambre>_<face>`, parfois en chaîne (`MIROIR_17455_MIROIR_18426_A`) : c'est ce que le modèle à conduite
partagée évite.

### Ordre de réalisation des domaines (31 octobre 2026)

1. **Chambres et poteaux** (domaines noyau, infra, chambre, poteau ; activités relevé chambres et relevé poteaux) :
   valider le système complet sur un domaine connu. Étapes : (1) schéma BE — **fait le 31 octobre 2026**, voir
   [schema/](../schema/README.md) ; (2) jeu d'essai sur données réelles — **fait le 31 octobre 2026**,
   `tools/essai/charger_essai.py` → `docs/essai/projet_essai/` (non versionné), consultable dans QGIS par
   `projet_essai.qgs` (généré par `tools/essai/projet_qgis.py`) ; (3) format GeoJSON et paquet de
   zone — **fait le 31 octobre 2026**, [paquet.md](paquet.md), `tools/geojson/paquet.py` (paquets d'essai dans
   `docs/essai/paquets/`, non versionnés) ; (4) terminal Flutter (web d'abord) — **premier incrément le
   31 octobre 2026**, voir §8.

Jeu d'essai (3 zones, aucun orphelin) :

| Zone | Contenu chargé |
| --- | --- |
| HEI — Heillecourt (FOA) | 1 277 chambres (51 relevées), 99 faces, 221 conduites dont 29 vues des deux côtés, 250 positions, 203 photos (29 introuvables) |
| ESS — Essonne DOU 12-13 (FOA) | 140 chambres, 36 destinations (poteaux, façades, BAL, immeubles), 208 conduites dont 56 vues des deux côtés, 264 positions, 216 occupations par câbles |
| GRACE — export GraceTHD de test | 200 appuis, 26 chambres, 197 portées (angles calculés depuis la géométrie), 188 câbles portés, 31 conduites |

Constats sur les sources :
- `FOA_HEILLECOURT.db` déclare EPSG:2154 mais ses coordonnées sont en Lambert II étendu (27572) ; la base de
  l'Essonne est déclarée et réellement en 27572 ;
- dans FOA, les destinations « autres » (poteau, façade, BAL, immeuble) n'ont pas de géométrie : reprises comme
  nœuds à 1 m de la chambre, position à relever ;
- 227 copies « MIROIR » de Heillecourt non reprises (face d'accueil inconnue) : 199 conduites restent vues d'un
  seul côté, à compléter par la fonction miroir ;
- angles des portées GraceTHD : azimut en grades, 0 = nord, sens horaire — convention retenue pour la rosace du
  terminal, orientée au nord (voir « Hirondelle » plus bas).

Paquet réel de Nancy (3 novembre 2026), FOA Explorer FTTH Orange `FTTH_OR_NANCY` (2016-2017, 27572 déclaré et
réel) : projet à part par `charger_essai.py … --foa <base> NCY "Nancy (FOA Explorer)" <dossier Chambres>` →
`docs/essai/projet_nancy/` (6 Go avec les photos), paquet `docs/essai/paquets/NANCY_NCY.zip` (0,9 Mo, sans les
photos), non versionnés. Contenu : 8 061 chambres (1 189 relevées), 2 268 faces, 7 851 conduites dont 2 563 vues
des deux côtés, 10 414 positions, 1 544 masques logiques, 6 452 photos (15 introuvables), emprise 20 km², aucun
orphelin. À reprendre : 2 431 copies « MIROIR » non reprises (2 043 conduites vues d'un seul côté entre deux
chambres), 3 241 alvéoles sans destination (autorisées : conduite rattachée à sa chambre, sans linéaire ni nœud
« à localiser » sur la carte), 18 positions dont les deux alvéoles FOA
appariées ont des destinations incohérentes, adresses quasi absentes (5). Photos sur le web sans les embarquer :
le paquet donne le chemin de chaque photo dans le projet (`FIC_CHEMIN`), lue à la demande au serveur local
`tools/essai/serveur_photos.py docs/essai/projet_nancy` (dossier `photos/` seul, boucle locale, CORS) quand
l'application est ouverte avec `?photos=8090` ou compilée avec `--dart-define=SERVEUR_PHOTOS=8090` (un `&` dans les arguments du lanceur coupe la commande de flutter.bat) ; lanceur VS Code « photos de Nancy » (tâche du serveur comprise).
Sur Android, les photos seront dans le stockage du terminal (paquet avec photos).
Repris le 4 novembre 2026 par `projet.py migrer` (journal de 14 commentaires FOA, puis masques métriques : 2 268 faces
de 0,567 × 0,54 m, 10 414 positions converties, aucune hors de sa face ; module chambre et modèle en 0.3.0) et
republié ; contrôles indépendants conformes (bases et paquet comparés ligne à ligne, QGIS). Sauvegardes des états
0.1.0 et 0.2.0, bases et paquet, dans `docs/essai/sauvegardes/`.
2. **Optique**, puis **retour fin de travaux** : (1) schéma BE — **première version le 4 novembre 2026**, modules
   optique et immeuble 0.1.0 calqués sur GraceTHD v2.0.1, voir [schema/](../schema/README.md) ; (2) jeu d'essai DOE
   sur données réelles — **fait le 4 novembre 2026**, ci-dessous ; (3) espaces `opt` et `imb` du paquet ; (4) écrans du
   terminal (liens fibres d'une boîte d'épissure, route optique, retour fin de travaux).
3. Immeubles / BAL (schéma 0.1.0 posé avec le jeu d'essai DOE), électrique : ensuite.

Jeu d'essai DOE Evicom (4 novembre 2026) : DOE du SRO-2-02HG (Hussigny-Godbrange, Meurthe-et-Moselle, réseau EVICOM
2000), matériau de `docs/essai/evicom_data/in/` chargé par `tools/essai/charger_doe.py` → `docs/essai/projet_evicom/`
(625 Mo avec photos et documents ; projet QGIS `projet_evicom.qgs`), paquet `docs/essai/paquets/EVICOM_SRO-2-02HG.zip`
(0,16 Mo sans les photos, conforme, lu par les tests du terminal), non versionnés. Sources : export GraceTHD v2.0.1
du pré-DOE (16 septembre 2026), référence du chargement ; relevé d'infrastructure FibReady (type d'appui, matière) ;
études COMAC de l'APD (juillet 2025) ; photos, plans de boîte, mesures, conventions d'immeuble.

| Domaine | Contenu chargé |
| --- | --- |
| Supports | 65 appuis (40 BT Enedis, 25 télécom ; 60 avec leur étude COMAC, 40 avec leur référence `MAT_POTEAU`, 15 études concluant à un appui insuffisant, en alerte au journal), 30 chambres (L1T à L4T), 36 façades, SRO, NRO, 15 immeubles |
| Parcours | 146 linéaires (79 portées aériennes, 23 parcours en façade, 44 souterrains) ; 102 portées orientées, 116 câbles portés ; 78 conduites, 147 occupations |
| Matériel | 99 boîtiers (95 PBO dont 19 à poser en immeuble, 4 BPE), baie et 6 tiroirs du SRO ; catalogues `MAT_EQUIP` et `MAT_CABLE` complétés de 11 et 13 références |
| Optique | 99 câbles (7,2 km ; 95 au parcours complet, 183 passages ; 4 câbles de colonne), 195 lovages, 6 000 fibres, 286 cassettes, 8 583 positions (700 épissures, 2 717 passages, 4 434 attentes, 732 connecteurs), 884 routes, 438 réflectométries à 1 550 nm rattachées à leur route (1 hors seuils) |
| BAL et immeubles | 339 adresses (436 logements, 15 locaux professionnels ; 322 pavillons, 15 immeubles), 464 locaux rattachés à leur PBO, 12 conventions d'immeuble |
| Fichiers | 1 158 photos (182 Mo : images extraites des rapports PDF des boîtes et du tirage, appuis, SRO, photométrie, études COMAC, infrastructure tierce Evicom) ; 879 documents non publiés (rapports PDF, plans de boîte, synthèses et traces de mesure, DT-DICT, conventions) |

Constats :
- angles des portées : `charger_essai.py` les calculait dans le quadrillage Lambert 93 ; à 5,9° E, la convergence
  des méridiens les écarte de 2,3 grades du nord géographique de la rosace du terminal (le test du paquet réel l'a
  relevé ; rien de visible pour la zone GRACE, à 2,9° E, près du méridien central). Calcul désormais géodésique, en
  WGS84, dans les deux chargeurs ; rosaces du projet QGIS tournées de la convergence ;
- des rues ont deux études COMAC (Rue Carnot et Rue Carnot 1, Rue du Réservoir et Rue du Réservoir 1) et un appui
  d'angle figure dans celles de deux rues, son nom suffixé de -IN (insuffisant) dans l'une seulement : un appui reçoit
  toutes les études d'un même support ;
- la capacité d'un boîtier posé (`bp_typephy`, B012) diffère de celle de son modèle (« PBO 48 fo ») : capacité du
  modèle au catalogue, capacité utile dans `OPT_EQUIPEMENT` ;
- l'appareil de mesure nomme la fibre par son rang au départ du SRO et le câble par la boîte d'extrémité :
  CDI-2-02HG-1015 fibre 55 = route partant de la fibre 55 du CDI-2-02HG-1005 (288 FO) ;
- non repris : la base FibReady (l'export GraceTHD en est tiré) et ses câbles de raccordement (non posés au DOE) ; le
  rapport de réserves (`reserves/rapport_distribution-SRO-08LG.xls`) porte sur un autre SRO, le SRO-1-08LG
  (168 non-conformités : point technique, criticité, thème, contrôle, statut, retour NGE) : modèle pour la levée de
  réserves du retour fin de travaux ;
- paquet : modules optique et immeuble non publiés (format 0.2.0) ; adresses de l'emprise de la zone et photos seules
  publiées.

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

Premier incrément du terminal (31 octobre 2026), web :
- **paquet** : ouverture d'un paquet de zone (ZIP) et export du paquet de retour (objets modifiés, intervention),
  conformes à [paquet.md](paquet.md) et vérifiés par l'implémentation de référence ;
- **dépôt** `DataRepository` en mémoire (une entrée par objet, index d'emprise et des linéaires par nœud) ;
  `TileSource` : Plan IGN et photographies aériennes de la Géoplateforme ;
- **carte** (`flutter_map`) : objets de la vue seulement, poteaux, chambres, façades, adresses, portées et
  parcours ; bandeau « Identification support » ;
- **fiche** : identification, poteau (référence du catalogue, nature, structure, implantation, hauteur, effort),
  contrôles du jour (FOA Explorer), visuels attendus et photos embarquées, linéaires rattachés ; chambre en
  lecture seule ;
- **rosace** (reprise d'Hirondelle, orientée au nord) : une aiguille par portée, orientée en la faisant glisser
  (pas de 0,1 grade), angle prérempli par la géométrie, destination existante (nœuds à moins de 150 m) ou
  nouvelle (position provisoire qui suit l'aiguille, à relever), longueur, câbles portés (catalogue, nappe,
  tension, flèche et température), flèches selon la légende Hirondelle ;
- **tests** : `flutter test` (paquet synthétique) ; `PAQUET_REEL=<paquet.zip>` ajoute la rosace de tous les poteaux
  d'un vrai paquet (GRACE : 200 poteaux, 390 portées, angles BE et terminal concordants à moins d'un grade).

Compléments (1er et 2 novembre 2026) : fonds Plan et photos IGN (défaut en France), OpenStreetMap (défaut ailleurs),
Google Plan / Satellite / Hybride avec la clé de l'utilisateur (paramètres) ; tuiles par le serveur en usage
courant, cache pour la fluidité et en secours sans connexion (sauf Google) ; cadrage sur l'emprise de la zone à
chaque paquet chargé.

**Protocole des modifications non exportées** (validé le 2 novembre 2026, à maintenir sur Android) : un paquet
chargé remplace le précédent ; tant que des modifications n'ont pas été exportées depuis la dernière écriture,
ouvrir un autre paquet demande confirmation (exporter le retour, abandonner les modifications ou annuler) et
quitter l'application est signalé (web : avertissement du navigateur) ; un export annulé ne compte pas comme
exporté.

**Retour à la carte** (2 novembre 2026) : depuis tout écran plein (fiche, rosace, paramètres) dont la carte n'est pas
l'écran précédent, un bouton « Revenir à la carte » ferme les écrans un par un, comme des retours arrière : chaque
saisie non enregistrée demande confirmation et le retour s'arrête si l'utilisateur reste ; pas de raccourci dans les
dialogues et feuilles modales, qui se ferment d'abord ; le retour arrière garde son sens (écran précédent).

**Écrans de saisie** (2 novembre 2026, `widgets/entry_screen.dart`) : bouton flottant « Enregistrer » en bas à droite,
visible seulement s'il y a quelque chose à enregistrer ; après l'enregistrement, on reste sur l'écran (message
« Enregistré ») ; quitter avec une saisie en cours demande « Quitter sans enregistrer ? » (Rester / Quitter). Les
interrupteurs des paramètres s'appliquent immédiatement.

**Rapprochement de la maquette Figma et de la charte NGE** (2 novembre 2026 ; captures du prototype dans
`docs/captures/figma/`) : parcours et organisation des écrans repris du Figma, couleurs de la charte NGE de FibReady
(`Megatools/NgeCharte/ClsCharte.cs`) au lieu du fond bleu nuit du prototype, peu lisible en plein soleil :
- **thème clair imposé** (pas de thème sombre automatique), texte de base en 16, cibles tactiles de 48 dp et plus ;
  bleu nuit `#022A78` réservé à l'écran de démarrage (support de marque) ; barres en bleu d'interface `#1C3C73`
  soulignées d'un filet jaune ; action principale (Enregistrer, Ouvrir) en jaune `#FAC100`, texte `#153166` ;
  rouge réservé aux suppressions et aux défauts ;
- **carte** : bandeau haut « Identification support » (recherche d'un support par son étiquette) ; barre basse
  Couches · Créer · Retour (compteur) · Paramètres ; panneau Couches (Aérien, Souterrain, Administratif avec l'œil)
  et fonds de plan ; étiquettes des supports encadrées à la couleur du métier ; sélection en jaune cerclé de bleu,
  avec un aperçu (Portées, Ouvrir) avant la fiche ;
- **démarrage** : bleu nuit, grand logo NGE sur cartouche blanc, compte, bouton jaune d'ouverture de la zone ;
- **couleurs de la carte** : celles de l'application (GraceTHD), appui énergie en bleu, façade en orange pointillé ;
- **symboles des supports** : pictos de FibReady, jeu par défaut des paramètres
  (`C:\outils\fibready_parametres\fibready_parametres_default\Pictures\noe\svg` : `NOE_POT`, `NOE_CHB`,
  `NOE_FAC`, copiés dans `assets/fibready/noe`), affichés en 24 px (points au-dessous du zoom 16, comme FibReady
  au-delà du 1/10 000) ; le remplissage « papier » prend la couleur du **statut de renseignement**, sur le principe
  de FOA Explorer (NOE_STATUT) : à renseigner cyan `#00FFFF`, partiel orange `#FF8C00`, complet vert `#00FF7F`,
  défaut rouge `#FF0000` (poteau déclaré inutilisable au dernier contrôle) ; même couleur au fond de l'étiquette ;
  encre bleue pour l'appui énergie (même picto que le télécom dans FibReady) ; pastille magenta : modifié ;
  sélection : halo jaune cerclé de bleu ; règles de complétude par module (champ `completude` des manifestes),
  calculées en direct par la carte et posées dans `POT_NIVEAU` / `CHB_NIVEAU` à l'enregistrement, comme FOA
  Explorer à l'enregistrement de la fiche ;
- **paramètres FibReady** (2 novembre 2026) : coquille corrigée dans `fibready_parametres_default` —
  `param_arbo_noe_pictures.csv`, la ligne poteau portait les poses de chambre (`POT,CHB-EX,CHB-AC,CHB-FT`, reste
  de « CHB-FTPOH ») et donnait le picto poteau aux chambres CHB-EX, CHB-AC et CHB-FT ; ramenée à `POT` ; correction
  ajoutée à `_recensement/merge_default.py` (`ARBO_FIX`) ; la coquille reste dans le paramétrage livré
  (`Desktop/Demo/Parametrage`, `Sources/bin/.../Parametrage`) et les affaires orne et unifiber ;
- **visuel et photo** : un **visuel** (vue attendue, `DEF_VUE`) regroupe **plusieurs photos** et porte ses
  fonctions propres (`VUE_ACTION` : visuel masque → bouton masque) ; toucher un visuel ouvre la **galerie** de ses
  photos, que l'on organise : la première (en haut à gauche) est la **photo de référence** du visuel (`FIC_RANG` 1,
  `FIC_PRINCIPALE`), affichée sur la carte du visuel ; la corbeille d'une photo est dans la galerie ;
- **visuel libre** : « Ajouter » (barre basse du support) crée un visuel hors des vues attendues : titre saisi,
  puis première photo ; il existe tant qu'il a des photos, qui portent son identifiant et son titre
  (`PRJ_FICHIER.VIS_CODE`, `VIS_LIB`, `VUE_KEY` nul) ; renommable dans sa galerie ; affiché après les visuels
  attendus ; un support sans vue attendue s'ouvre aussi sur ses visuels, pour pouvoir en ajouter ;
- un **visuel attendu** est un visuel libre **précréé et branché sur un module** (`DEF_VUE` : titre, ordre,
  obligation, fonction propre) : même nature, même galerie ; il est affiché vide, « à renseigner », dès
  l'ouverture du support (retenu le 2 novembre 2026, plutôt qu'une liste à activer par « Ajouter ») ;
- **support** : écran d'arrivée « visuels » (une carte par visuel : photo de référence, nombre de photos ou
  « Manquante », prendre une photo, fonction propre du visuel) ; le **crayon** de l'en-tête (depuis le 4 novembre
  2026, « Saisie du support » du menu ⋮) ouvre la saisie générale de l'entité (identification, commentaire,
  caractéristiques, contrôles, données propres au module), pas les photos ni leur titre ; barre basse commune module (Portées pour le poteau, Masques et conduites pour la chambre) ·
  **Équipements** (icône dessinée « boîtier sur câble », `assets/icons/equipment.svg`, valable pour les télécoms et
  l'électricité, retenue parmi sept propositions ; remplace « Connecteurs » le 4 novembre 2026 : une boîte d'épissure y propose ses liens fibres,
  écrans `support_saisie_optique` / `support_route_optique`) · Carte (globe, remplace « Revenir à la carte ») ·
  Ajouter (visuel libre) ;
- **onglets du support** (4 novembre 2026) : écrans séparés plutôt qu'un long formulaire ; saisie (crayon des
  visuels, puis « Saisie du support » du menu ⋮), module (portées, masques) et équipements sont des onglets : passer
  de l'un à l'autre remplace l'écran au lieu de l'empiler (saisie enregistrée avant ; grille ou rosace modifiée :
  confirmation, et l'on peut rester), le retour ramène aux visuels du support s'ils sont dessous (support ouvert par
  « Ouvrir » de la carte), puis à la carte ; depuis la grille d'une face, Masques ramène à l'aperçu ;
  chaque donnée n'a qu'un écran : les équipements ne sont plus dans la saisie (poteau et chambre), le nombre
  d'équipements reste affiché sur le bouton de la barre basse ; un nouveau message remplace les précédents (pas de
  file de confirmations) ; « Visuels du support » (d'abord un picto en haut à droite, puis une entrée du menu ⋮)
  ramène aux visuels depuis les écrans de saisie (saisie, portées, masques, grille d'une face, équipements), saisie
  enregistrée avant ; grille ou rosace modifiée : confirmation ;
- **parcours suivi** (4 novembre 2026) : depuis une portée, un parcours ou une conduite, le support d'en face
  s'ouvre sur le même linéaire, comme on chemine sur le terrain, sur le même écran des parcours, avec le carton du
  retour (notes rep5, `follow(route: true)`) : portées du poteau (portée commune ouverte, vue de son côté, ou
  parcours sélectionné), aperçu des masques de la chambre (parcours sélectionné), saisie des autres supports
  (ancrage façade… : liste « Portées et parcours », linéaire sélectionné). Dans ces trois écrans, toucher un
  parcours le sélectionne et montre son carton « Naviguer vers … » (au-dessus de la barre basse ; dans la rosace, en
  haut du panneau, pour qu'elle garde sa taille quand il paraît) ; la saisie en cours est enregistrée avant ; l'icône
  « ouvrir » des portées est retirée. Dans la grille, le « Vers … » du panneau de l'alvéole mène d'une touche à la
  grille de la chambre d'en face (notes rep7 : ni carton ni infobulle), sur l'alvéole de la même conduite si elle y
  est placée (`follow(cd:)`, base du futur miroir), sinon sur la face où le parcours arrive (ou la première), rien de
  choisi à sa place ; ce lien est un bouton sur sa ligne, avec le pictogramme du support d'en face (celui de la carte),
  son étiquette en gras et son type (notes rep10, `SupportLink`). Le même pictogramme précède chaque parcours de la
  liste et l'étiquette du bouton « Naviguer vers … » du carton. Le bouton « Ouvrir » de l'aperçu sur la carte mène toujours aux visuels. « Face non relevée »
  devient « Face vide » ;
- **un seul support ouvert à la fois** (4 novembre 2026, notes rep8 : « fiabiliser la pile de la navigation ») :
  d'abord empilé sur l'écran courant (le retour ramenait au support précédent), le support d'en face remplace
  désormais le support affiché (`openAt`, pile suivie par `screenStack`). La pile est la carte puis un seul support :
  ouvert depuis la carte, ses visuels, un onglet et ses écrans propres ; atteint par un parcours ou rouvert par le menu
  ⋮, directement son écran d'arrivée (ses visuels seulement s'ils sont l'arrivée), comme ses portées ouvertes par
  « Portées » de l'aperçu de la carte. Le retour mène donc à la carte (aux visuels d'abord pour un support ouvert par
  « Ouvrir »), et « Carte » n'a jamais plus de quelques écrans à
  fermer. Deux relectures avaient montré que l'empilement laissait sous l'écran courant des sessions de saisie aux
  copies périmées des linéaires communs (portées, conduites), qu'un enregistrement au retour aurait écrasées : pertes de
  données confirmées sur la rosace et les masques. Le support quitté est fermé comme par autant de retours arrière
  (saisie enregistrée avant, ou question habituelle, et l'on peut rester). Une relecture suivante a écarté les autres
  copies périmées : visuels relus après toute écriture, galerie dont chaque geste part du support enregistré (« Annuler »
  ne rétablit que la photo), session de masques qui repart de la chambre du dépôt ; une portée supprimée puis
  enregistrée ne laisse plus l'écran « modifié ». Un support supprimé n'est plus atteint par un parcours (« Naviguer
  vers », « Vers … ») ni proposé par le menu ⋮, et le dépôt le garde abandonné même réécrit depuis une copie qui
  l'ignorait ;
- **menu ⋮** des écrans d'un support (visuels, saisie, portées, aperçu des masques, grille, équipements, galerie),
  seul bouton de leur barre de titre (notes rep8 : il remplace les pictos), pour la navigation fine qui remplace la
  pile : actions propres à l'écran (grille : photos et dimensions de la face ; galerie : prendre une photo, renommer
  un visuel libre), écrans du support (« Visuels du support », « Saisie du support » : la saisie générale aussi
  depuis les masques et les portées), puis les supports quittés récemment, du plus récent au plus ancien (cinq au
  plus ; le premier « Revenir à … », intitulé à jour), chacun rouvert à la place du support affiché sur l'écran où on
  l'a laissé (face, alvéole, parcours ou portée choisis, notés par l'écran), et « Repérer sur la carte » (« Rester »
  sur une saisie non enregistrée retire la demande) ;
- **repérage d'un support** (4 novembre 2026, notes rep7) : la sélection de la carte suit le support affiché (ouvert
  depuis la carte, atteint par un parcours, rouvert par le menu ⋮) ; revenue au premier plan, la carte repère la
  sélection si elle a changé entre-temps, ou à la demande (« Repérer sur la carte ») ; la recherche repère le support
  trouvé. Repérage calqué sur « Repérer » de FibReady (`PlugCarto/sources/web/carte.js` : `locateZoom`,
  `locateFlight`, `pulser`) : vol de la vue (`flyTo` de MapLibre d'après van Wijk et Nuij, courbure 1,6, vitesse 1,1,
  saut direct au-delà de 4 s ; un geste sur la carte l'interrompt ; ouvrir le support pendant le vol l'achève
  d'emblée), zoom d'arrivée qui montre au plus le rayon de repérage autour du support (`OPT_CARTO_ZOOM_RAYON` de
  FibReady, 50 m par défaut : de plus loin, la carte zoome jusque-là ; de plus près, elle garde le zoom ; supports en
  pictos au moins ; zoom de la carte porté à 22, tuiles agrandies, pour 10 m sur une tablette ; calculé sur la carte
  entière, le clavier de la recherche la recouvrant sans la rétrécir), puis trois pulsations amorties du halo de la
  sélection (1,8 s), dessinée même si sa couche est masquée. Paramètres : « Repérage animé » (désactivé : placement
  direct) et « Rayon de repérage (m) » (10 à 500 m) ;
- **écrans larges** (4 novembre 2026, notes rep6, rep8 et rep9 : tablette, paysage, Windows) : à gauche les noms des
  faces au-dessus de la grille des masques, à droite une colonne pour la légende et l'alvéole choisie (480 dp au plus,
  40 % de la largeur ; légende en grand, un état par ligne, dès 420 dp de hauteur ; état et diamètre de l'alvéole en
  grandes cases, libellés entiers, les diamètres sur deux rangées de quatre, dès 560 dp, présentation compacte
  en deçà, tablette 1024 × 600 ou téléphone en paysage ; « Retirer du masque » et « Enregistrer » toujours visibles,
  épinglés en bas de la colonne quand le panneau défile) ; la création d'une alvéole
  se déplie depuis la droite sur cette colonne (volet modal, grandes cases), la grille restant visible, au lieu de
  la feuille du bas du portrait. Aperçu du support sur la carte en carton compact de 360 dp dans le coin bas droit
  (carte de 600 dp et plus), au-dessus de l'attribution. Visuels : même carte partout (titre et état, photo de
  référence au format 4:3, jamais étirée en bandeau, commandes en icônes à sa droite), en tuiles de 340 dp au moins :
  une colonne sur un téléphone en portrait, deux sur une tablette en portrait ou un téléphone en paysage, trois sur
  une tablette en paysage, davantage sur un écran très large. Galerie d'un visuel (notes rep10), sur le même principe :
  chaque photo entière (au format 4:3, sur fond sombre, une photo prise en hauteur n'étant pas rognée), en tuiles ;
  toucher une photo l'affiche en plein écran, agrandie au pincement ou à la molette ; un appui long la dépose sur une
  autre tuile, qui prend sa place (« Définir comme référence » demeure). Aperçu des masques en paysage (notes rep10) :
  les faces à gauche, en tuiles avec la miniature de leur masque (contour aux proportions réelles, cellules de 5 cm,
  alvéoles à leur place et à l'échelle, à la couleur de l'état de leur conduite), les conduites à droite ;
- **saisie de la chambre** (4 novembre 2026) : cartes dépliables Général (date, type, numéro, référence,
  implantation, adresse), Dimensions (une ligne par dimension : référence du catalogue, dimension relevée),
  Commentaires (journal daté et signé, voir « commentaires datés et signés » plus bas) ;
  masques et conduites ne sont plus dans la saisie : le bouton Masques de la barre basse ouvre leur aperçu (une
  ligne par face : alvéoles, grille, chaque face ouvrant sa grille ; puis les conduites : parcours vers les autres
  supports, conduites sans destination connue) ; dimension de référence en petit dans le cadre de chaque champ de
  dimension, en bas à gauche sous la valeur (libellé toujours sur la bordure, pour ne pas la chevaucher) ;
- **saisie du poteau** (4 novembre 2026), sur les principes de la chambre : cartes dépliables Général (date, type,
  numéro, référence du catalogue, nature, structure, caractéristique, implantation, hauteur, effort, adresse),
  Contrôles (contrôle du jour, sans champ libre : les commentaires sont réunis dans le journal, `CTL_COMMENT` n'est
  plus saisi), Commentaires ; les linéaires ne sont plus dans la saisie : l'écran des Portées (barre basse) les
  reprend, comme l'aperçu des masques reprend les conduites de la chambre : carte Portées (chaque portée s'ouvre
  pour la modifier, ou se suit jusqu'au support d'en face, voir « parcours suivi » : les portées modifiées sont
  d'abord enregistrées), puis carte Autres parcours (parcours souterrain…), seulement s'il y
  en a ; dans l'interface,
  « parcours » plutôt que « linéaire », terme du modèle (`PRJ_LINEAIRE`) : la carte des linéaires des autres
  supports (ancrage façade…) s'intitule Portées et parcours ;
- **adresse d'un support** (4 novembre 2026) : toucher l'adresse ouvre son écran, calqué sur « Adresse édition »
  de FibReady : sélection commune, voie, adresse parmi celles du paquet (ou nouvelle adresse), détail (numéro,
  complément, code postal, commentaire), Détacher / Annuler / Valider ; l'adresse est enregistrée avec le support.
  Bouton « Détection automatique » : géocodage inversé de la position du support comme l'adresse auto de FibReady
  (`GeoCodage.GetBestAdr` : Géoplateforme en France, Photon en repli ou ailleurs), rapproché des adresses du paquet
  (casse et accents ignorés) ; nouvelle adresse sinon, avec l'identifiant BAN. Demande une connexion. Entrée, type de
  bâtiment et niveaux de FibReady non repris (absents de `PRJ_ADRESSE`) ;
- **commentaires datés et signés** (4 novembre 2026) : un journal par objet remplace les champs libres du support
  (`NOE_COMMENT`, `CHB_COMMENT`, `POT_COMMENT`, retirés du schéma) : table noyau `PRJ_COMMENTAIRE` (rattachée à l'objet
  comme `PRJ_FICHIER`, intervention, auteur, dates, abandon au BE), clé `commentaires` du paquet (format 0.2.0, modules
  noyau, chambre et poteau en 0.2.0) ; types de FibReady (Alerte, Mineur, Standard, Bon point : pastille de couleur) ;
  carte « Commentaires » commune aux supports (auteur, date et heure, texte ; ajout). Un commentaire ne se modifie ou ne
  se retire (après confirmation) que par son auteur, tant que le paquet de retour qui le contient n'est pas exporté ;
  ensuite il est figé, comme ceux des autres auteurs et du BE ; sur le web, le téléchargement du retour vaut export.
  Textes existants repris comme premières entrées (auteur « FOA » ou « BE », origine déduite de la zone, datés du
  nœud) par `tools/schema/projet.py migrer` (alias `migrer-commentaires`) pour un projet déjà construit (idempotente, annulée si une
  base de module manque, statistiques SpatiaLite recalculées pour QGIS, modèle du projet en 0.2.0), et par le
  chargeur d'essai (mêmes codes, auteurs, origines et dates) ; dates GraceTHD lues en heure de Paris et écrites en
  UTC (Z) ; la base refuse un texte ou un auteur blanc. Le terminal
  n'affiche pour l'instant que le journal des supports (ceux des linéaires et des adresses sont conservés et renvoyés) ;
  l'intervention en cours et les commentaires exportés, gardés en mémoire, seront à conserver avec le dépôt Android ;
- **masques aux proportions réelles** (4 novembre 2026). Conventions retrouvées dans le code de FOA Explorer
  (`O:\c#\InfraExplorer`) : chaque face est une fenêtre fixe de 9 × 12 cellules de 6,3 × 4,5 unités, 1 unité = 1 cm (les
  alvéoles y sont en vraie grandeur), soit 56,7 × 54 cm quelles que soient les dimensions de la chambre ; `ALV_X` / `ALV_Y`
  = centre de l'alvéole, origine en bas à gauche ; le miroir FOA fait X' = 56,7 − X. Convention Orange
  (`docs/Besoins_KIZEO.xlsx`) : A à gauche dos à la voie, B à droite, C côté voie, D face à la voie ; chambre le long de la
  voie : A et B petits côtés (ils portent 88 % des alvéoles de Nancy). Dimensions souvent absentes (54 % des chambres
  relevées de Nancy en OHN, aucune dimension relevée dans FOA). Décisions : repère métrique (positions et dimensions de
  face en m, depuis la gauche et le haut ; grille dessinée en cellules carrées de 5 cm, alvéoles en vraie grandeur) ;
  faces A et B à la largeur de la chambre, C et D à la longueur, hauteur = profondeur ; nouvelle face aux dimensions de la
  chambre (relevées, sinon catalogue, sinon fenêtre FOA 0,567 × 0,54 m), modifiables en centimètres ; une face déjà
  relevée n'est agrandie qu'à la demande, alvéoles centrées. Module chambre 0.3.0 (`FAC_LARG`, `FAC_HAUT` au lieu de
  `FAC_NB_COL`, `FAC_NB_LIG`) ; données converties exactement (cellule FOA × 0,063 / 0,045 m) ; le terminal refuse un
  paquet de masques à l'ancien repère. `CHB_ROTATION` est l'axe A-B du symbole PIT à 200 grades près, pas la face A ;
- **suppression au plus près de l'élément** (au lieu de la coche de sélection et de la corbeille de la barre basse du
  Figma) : corbeille sur chaque photo de la galerie avec « Annuler » dans le message qui suit, « Supprimer ce câble » dans le
  détail d'un câble porté, « Supprimer le support » en bas de la saisie du support, avec confirmation ; le message
  « … · ANNULER » (`UndoMessage`, `widgets/messages.dart`) disparaît seul au bout de 6 s, se ferme quand on quitte
  l'écran et dès qu'une autre modification le rend caduc (4 novembre 2026 : il restait affiché d'écran en écran, et
  son « Annuler » aurait réenregistré l'objet d'avant par-dessus les modifications suivantes) ;
- l'action du module n'est pas répétée sur chaque vue, sauf la **grille du masque de chambre**, propre à la vue
  catégorisée (masque A, B…) ;
- **portées** : rosace en haut, câbles portés en accordéon dessous (un seul ouvert, saisie sur place : type,
  longueur, nappe, pose, flèche et température si relevée, « Supprimer ce câble » avec « Annuler ») ; barre commune
  du support, Portées active, « Direction » ajoute une portée ; l'enregistrement recalcule le niveau du poteau
  (`POT_NIVEAU`), l'orientation des portées comptant dans son renseignement.

Mise en œuvre (2 novembre 2026) : thème `lib/theme.dart`, démarrage, carte, visuels, galerie et saisie du
support. Les gestes sur les photos (prise, ordre, suppression) sont enregistrés aussitôt, sans bouton Enregistrer ;
une photo prise sur le terminal remonte dans le paquet de retour (`fichiers/<FIC_CODE_EXT>.<ext>`) tant qu'elle
reste rattachée ; sur le web, « prendre une photo » choisit une image (appareil photo sur Android, à venir).
L'action `ROSACE` de la vue tête de poteau n'est pas affichée (Portées dans la barre basse).

Masques de chambre (2 novembre 2026, `lib/modules/chambre/`) : entrée « Masques » de la barre du support et
bouton grille des visuels A à D ; une face en plein écran (A à D), grille (repère métrique depuis le 4 novembre : voir
« masques aux proportions réelles ») de `FAC_NB_COL` × `FAC_NB_LIG` cellules
(9 × 12 par défaut, réglable pour les grandes faces) parcourue par déplacement et zoom ; une alvéole par position,
disque à la couleur de l'état (`DEF_CD_ETAT`), taille selon le diamètre, numéro de la conduite. Toucher la grille
place une alvéole (parcours souterrain de la chambre, diamètre normalisé, état ; derniers choix repris pour la
saisie en série) ; toucher une alvéole la sélectionne (état, diamètre, retrait) ; l'appui long la déplace. La
position est écrite dans la chambre (`chb.faces[].positions`), l'état et le diamètre dans la conduite du linéaire
(`inf.conduites`) ; retirer une position venue du BE l'abandonne (`DATE_ABD`), une alvéole créée dans la session
disparaît. Le niveau de renseignement est recalculé à l'enregistrement (positions abandonnées ignorées).

Fiche de la chambre (crayon), reprise de la fiche « Chambre - édition des informations » de FOA Explorer : type
(chambre, chambre FT, chambre SAT : `TYPE_KEY`), numéro (`NOE_LIB`), adresse rattachée (lecture seule ; choix de
l'adresse à venir), référence du catalogue (`MAT_KEY`, `MAT_CHAMBRE`), implantation (`IMPS_KEY`), équipements
(`inf.equipements`, catalogue `MAT_EQUIP`, communs aux supports : aussi sur le poteau), commentaire, dimensions de
référence (catalogue, intérieur) et dimensions relevées si elles diffèrent (`CHB_LARG`, `CHB_LNG`, `CHB_HAUT`) ;
puis les quatre faces, chacune ouvrant sa grille. La date de la fiche FOA correspond ici à la date de modification.
Réorganisée le 4 novembre 2026 (cartes dépliables, adresse modifiable, faces et conduites dans l'aperçu des
masques) : voir « saisie de la chambre » et « adresse d'un support » plus haut.

Suites prévues : appareil photo sur Android, miroir (report d'une alvéole dans la chambre voisine), masques
logiques et câbles des conduites, persistance locale (Drift ; SQLCipher sur Android), boussole pour orienter la
rosace, connexion par jeton abonné.

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

## 11. Modèle de données et relevé de chambres

Décisions (30 octobre 2026) :
- **Base BE** : SpatiaLite d'abord, bascule possible sur PostGIS (même schéma).
- **Schéma commun** `PRJ_NOE` (objets ponctuels) / `PRJ_LINEAIRE` (objets linéaires, reliés à leurs nœuds), autour
  duquel se greffent les schémas métiers (chambres, poteaux, immeubles…). FOA Explorer était une base métier
  chambres + poteaux ; NgeEsPlorer généralise.
- **Échange et stockage terminal en GeoJSON** (Flutter ne lit pas SpatiaLite sur Android).
- **Hors périmètre de NgeEsPlorer** : préparation des données, génération des FOA et autres sorties. Elles sont
  déléguées à une application BE en C# : FibReady, une extension de FibReady ou une application dédiée sur les
  mêmes bibliothèques (CommonTools, DataTools, CartoTools : EPPlus 8, PDFsharp, NetTopologySuite avec SpatiaLite et
  shapefile, System.Data.SQLite).
- **InfraExplorer** : pas de reprise du code ; on s'inspire du mode opératoire du relevé de chambres (manuel
  `o:\C#\Installs\InfraExp\2024_remastered\Annexe\INFRA_EXPLORER_MANUEL.chm`).

Mode opératoire hérité du relevé de chambres :
1. Préparation BE : import des chambres du PIT Orange (shapefile), référentiel adresses FANTOIR par code INSEE,
   fonds de plan découpés sur l'emprise, une base par zone copiée sur la tablette.
2. Terrain : sélection sur la carte → fiche (n°, type, adresse, date, opérateur, commande) → masques A à D en
   grille → alvéoles et sous-tubages glissés (diamètres normalisés) → statut (R réservée, X occupée, M mauvaise) →
   destination (chambre voisine ou autre : poteau, façade, abonné) → câbles (taux d'occupation, grille FT) →
   miroir (report des alvéoles de la chambre A vers la chambre B qu'elles desservent).
3. Photos : une par masque, dessus, environnement (positions des masques A à D placées sur la photo), mesures.
4. Niveau de renseignement en trois couleurs : non relevée, partielle, complète (1 masque renseigné = 1 photo,
   photos d'environnement, de mesure et de dessus présentes).
5. Sorties : fiche FOA Excel par chambre (masques + photos, synthèse d'occupation), lot ZIP filtré par période.
   Exemple : `c:\NoDrive\Documents\Etudes\essonne\CHA_597.xlsx` (deux onglets ; photos nommées
   `CHA_597_A_1`, `CHA_597_DESSUS_1`, `CHA_597_ENV_1`…).

Relevé de chambres dans NgeEsPlorer :
- **Quatre faces seulement** à la saisie. Les très grandes faces se parcourent par déplacement (« pan ») sur une
  grille plus large que l'écran. L'export FOA transpose en masques E, F, G… sur plusieurs feuilles, comme les FOA
  Orange des grandes chambres.
- On garde l'esprit du miroir, des couleurs et du niveau de renseignement, mais l'interface dépend du support :
  smartphone en vertical (interface repensée), tablette en horizontal (proche de FOA Explorer).
- **Photos prises en direct**, fonction du socle commun à tous les modules (voir la maquette Figma) ; plusieurs
  photos par masque, dont une photo principale désignée.

Stockage et échange (proposition) :
- **Terminal** : SQLite chiffrée (SQLCipher), une ligne par objet ; colonnes d'index (UUID, classe, zone, statut,
  date de modification, emprise xmin/ymin/xmax/ymax) et une colonne contenant l'objet GeoJSON complet. Aucune
  géométrie SpatiaLite sur le terminal.
- **Objets** : deux sortes d'objets GeoJSON, selon le modèle GraceTHD ci-dessous. Un nœud (Point) porte ses
  entités métier, ses positions de masque et ses photos ; un linéaire (LineString) porte ses conduites (alvéoles,
  sous-tubes, occupation). Chaque élément imbriqué a son UUID ; les références entre objets se font par UUID.
- **BE** : le GeoJSON n'est que le format d'échange. À l'import, l'application BE aplatit chaque objet dans les
  tables relationnelles (`PRJ_NOE`, `PRJ_LINEAIRE`, tables métier) avec de vraies géométries SpatiaLite ou PostGIS.

Inspiration GraceTHD (exemple : `c:\NoDrive\Documents\Etudes\Auvergne\projets\test_grace\data\Export\GraceTHD\
test_grace_EXP_GRACETHD.sqlite`, tables `patch201` → version 2.0.1) : les entités métier sont séparées de leur
expression géométrique.

| Couche | GraceTHD | NgeEsPlorer |
| --- | --- | --- |
| Géométrie ponctuelle | `t_noeud` (PT, ST, SF) | `PRJ_NOE` |
| Géométrie linéaire entre deux nœuds | `t_cheminement` (`cm_ndcode1`, `cm_ndcode2`) | `PRJ_LINEAIRE` |
| Métier porté par un nœud | `t_ptech` (chambre, poteau, façade), `t_ebp` (porté par le ptech), `t_sitetech`, `t_suf` | Tables métier (chambre, poteau, immeuble, support électrique…) |
| Métier porté par un linéaire | `t_conduite` via `t_cond_chem` (sous-tubage : `cd_cd_code`) ; `t_cable` via `t_cab_cond` | Conduites (alvéoles), câbles |
| Position dans une chambre | `t_masque` (nœud, face, colonne, ligne, conduite) | Positions de masque |
| Traçabilité | `_creadat`, `_majdate`, `_majsrc`, `_abddate`, `_abdsrc`, `_geolqlt`, `_geolmod`, `_geolsrc` | Idem : abandon daté plutôt que suppression |

Conséquences pour le relevé de chambres :
- une alvéole est une **conduite** portée par le linéaire qui relie la chambre à sa destination ; renseigner la
  destination revient à choisir ou créer le nœud d'arrivée (chambre, poteau, façade, abonné) et le linéaire ;
- le **miroir** devient naturel : la même conduite apparaît dans le masque de chaque extrémité ; « appliquer le
  miroir » crée seulement la position de masque côté B, sans recopier de données ;
- les colonnes et lignes de masque ne sont pas bornées, ce qui convient aux grandes faces parcourues par
  déplacement ;
- l'application BE dispose déjà d'import et d'export GraceTHD dans FibReady (`PlugImpShpGrace`, `PlugExpGrace`).

Le motif nœud / linéaire / métier rattaché s'étend à l'électricité ; seules les tables métier diffèrent.

GraceTHD v3 : aucune base SpatiaLite publiée (GitHub `GraceTHD-community` s'arrête à la v2.0.1 ; standard CNIG
v3.0 au stade de projet). Base vide reconstituée depuis les gabarits de l'export FibReady
(`PlugExpGrace\...\Data\shapes_v3`) : `docs/gracethd/gracethd_v3.sqlite`, script et règles dans
[tools/gracethd/](../tools/gracethd/README.md). Ces gabarits sont une variante de donneur d'ordre.
Différences structurantes avec la v2 :
- `t_noeud` réduit au code et aux dates ; le support physique géolocalisé devient `t_pointaccueil` (chambre,
  appui, ancrage façade…), et `t_tranchee` relie deux points d'accueil ;
- `t_sitetech` / `t_ltech` / `t_suf` → `t_site` / `t_local` ;
- **plus de `t_conduite`, `t_cond_chem` ni `t_masque`** : le câble emprunte directement les cheminements
  (`t_cab_chem`).

Conséquence : les masques, alvéoles et sous-tubages du relevé de chambres n'ont pas d'équivalent en v3. Ils
forment une extension métier propre à NgeEsPlorer, à exporter en v2 (`t_conduite`, `t_masque`) ou dans les FOA.

**Décision (30 octobre 2026)** : modèle mixte, au plus près de **GraceTHD v2** (la version la plus utilisée) et de
**FOA Explorer**. De GraceTHD v2 : la séparation entre géométrie (nœuds, linéaires) et entités métier. De FOA
Explorer : la convention d'identifiants (`XXX_ID` en clé, `XXX_KEY` en référence) et les tables de matériel
détaillées (`MAT_CHAMBRE` avec dimensions, `MAT_POTEAU`, `MAT_CABLE` avec COMAC, `MAT_EQUIP`, fabricants).

Modèle mixte (proposition) :

| Couche | Tables | Origine |
| --- | --- | --- |
| Géométrie | `PRJ_NOE` (Point), `PRJ_LINEAIRE` (LineString, `NOE1_KEY` / `NOE2_KEY`) | GraceTHD `t_noeud`, `t_cheminement` |
| Métier sur nœud | `PRJ_CHB`, `PRJ_POT`, équipements, immeubles… (`NOE_KEY`, `MAT_KEY`) | FOA `PRJ_CHB_NOE`, `PRJ_POT_NOE` sans géométrie ; GraceTHD `t_ptech`, `t_ebp` |
| Métier sur linéaire | `PRJ_CONDUITE` (`LIN_KEY`, `PARENT_KEY` pour le sous-tubage, état R/X/M), occupation par câbles, `PRJ_CABLE` | GraceTHD `t_conduite`, `t_cable` ; FOA `PRJ_CHB_ALVEOLE`, `PRJ_CHB_ALVCAB` |
| Relevé de chambre | `PRJ_MASQUE` (`NOE_KEY`, face, colonne, ligne, `CD_KEY`, masque logique) | GraceTHD `t_masque` ; FOA masques logiques |
| Photos et pièces jointes | `PRJ_ATTACH_FILE` (entité, rôle, rang, principale) | FOA |
| Référentiels | `DEF_TYPE` (arborescence des types), `MAT_*`, `DEF_FABRICANTS`, `DEF_FIB_*` ; correspondance vers les listes GraceTHD pour l'export | FOA `DEF_ALLTYPES` / `DEF_CLASSTYPE` |

Points d'attention :
- **Nommage** : suffixe `_ID` = clé primaire, suffixe `_KEY` = clé étrangère, préfixé par l'entité visée
  (`NOE_KEY`, `LIN_KEY`, `MAT_KEY`) ; un rôle distingue plusieurs références vers la même table (`NOE1_KEY` /
  `NOE2_KEY`, `TAMPON_MAT_KEY`, `PARENT_KEY`).
- **Identifiants** (décision du 30 octobre 2026) — trois notions distinctes :

  | Champ | Nature | Unicité | Attribué par |
  | --- | --- | --- | --- |
  | `XXX_ID` | Entier long auto-incrémenté, clé technique | Dans une base | La base BE |
  | `XXX_CODE_EXT` | Chaîne, identifiant stable de l'entité | Dans le projet | Le BE ou le terminal qui crée l'entité |
  | `XXX_LIB` | Libellé lu par l'humain (ex. n° de chambre Orange « 1476 ») | Aucune | Saisie |

  Le GeoJSON et la synchronisation n'utilisent que `CODE_EXT`, y compris pour les références entre entités ;
  l'import BE le résout en `XXX_ID`. Les référentiels (`MAT_*`, `DEF_*`), gérés par le BE seul, gardent leurs
  entiers partout. Une entité créée hors ligne reçoit son `CODE_EXT` sur le terminal : le format doit garantir
  l'unicité sans coordination (UUID, ou préfixe propre au terminal + séquence).
- **À ne pas reprendre de FOA** : géométrie répétée dans chaque table métier (`PRJ_CHB_NOE`, `PRJ_POT_NOE`),
  clé composée (`NOE_ID`, `TYPE_KEY`) et références polymorphes (`ALV_DEST_KEY` + `ALV_DEST_TYPE_KEY`) — un seul
  `PRJ_NOE` les rend inutiles ; types de voies mélangés à `DEF_ALLTYPES` ; dates en entier Unix (préférer
  l'ISO 8601).
- **À reprendre de GraceTHD** : traçabilité (création, mise à jour, abandon et leurs sources ; qualité et mode de
  géolocalisation).

### Modules : noyau et greffons

Chaque module (chambre, poteau, immeuble, optique…) a son univers : tables métier, référentiels (`MAT_*`), code,
contrôles et sorties. Le module est une seule notion, déclinée à trois endroits et décrite par un **manifeste**
commun (nom, version, dépendances, tables BE, espace GeoJSON, référentiels, correspondance GraceTHD).

| | Desktop BE | Terminal | Échange GeoJSON |
| --- | --- | --- | --- |
| Schéma | Un fichier SQLite par module, attaché à la base noyau (`ATTACH`) ; un schéma par module dans PostGIS | Pas de tables métier : une ligne par objet GeoJSON | Un espace de nommage versionné par module (`properties.chb`, `properties.pot`…) |
| Code | Une bibliothèque C# par module | Un paquet Dart par module | — |
| Référentiels | Dans le fichier du module | Un fichier de référentiels par module, téléchargé avec lui | Codes `MAT_KEY` / `TYPE_KEY` |
| Activation | Le projet attache ses modules | L'abonnement liste les modules autorisés | Un paquet de zone ne contient que les modules souscrits |

Toutes les géométries restent dans le noyau (`PRJ_NOE`, `PRJ_LINEAIRE`) : les modules ne contiennent que des tables
attributaires, ce qui évite les limites de SpatiaLite sur les bases attachées.

Contraintes SQLite entre bases attachées (vérifiées par essai le 30 octobre 2026, sauf le mode WAL tiré de la
documentation) :

| Mécanisme | Résultat |
| --- | --- |
| Clé étrangère d'un module vers le noyau | Impossible : la référence est cherchée dans le module lui-même |
| Trigger ou vue enregistrés qui croisent deux bases | Refusés |
| Trigger ou vue `TEMP` (recréés à chaque connexion) | Fonctionnent : un orphelin est bien refusé |
| Transaction sur plusieurs bases en mode WAL | Atomique base par base, pas sur l'ensemble |

Règles qui en découlent :
1. pas de clé étrangère déclarée entre bases : les `_KEY` sont des colonnes indexées ;
2. intégrité assurée par l'application : triggers et vues `TEMP` à l'ouverture du projet, recherche d'orphelins
   dans le sas de contrôle ; l'abandon daté limite les suppressions en cascade ;
3. journal `DELETE` ou `TRUNCATE`, pas WAL : un relevé écrit à la fois dans le noyau et dans un module ;
4. dépendances explicites dans le manifeste ; un module ne référence que les modules qu'il déclare.

Graphe de dépendances des domaines (à préciser) :

```
noyau (PRJ_NOE, PRJ_LINEAIRE, DEF_TYPE, adresses, interventions)
 ├─ infra (parcours souterrain : conduites, sous-tubage ; parcours aérien : portées)
 │   ├─ chambre (PRJ_CHB, masques, MAT_CHAMBRE)
 │   ├─ poteau (PRJ_POT, MAT_POTEAU, COMAC)
 │   └─ optique (câbles, boîtiers, MAT_CABLE…) — dépend aussi de chambre et poteau
 ├─ adresse / immeuble / BAL
 └─ électrique (à définir)
```

### Maquette Figma (analysée le 31 octobre 2026)

[infraExp](https://www.figma.com/design/RyUPQF7cUKdUyqV9J6kpcZ/infraExp) (copie locale `docs/infraExp.fig`) :
46 écrans en 360 × 800 (smartphone vertical ; pas encore d'écran tablette). Exemples sur Limours.

| Écran | Contenu |
| --- | --- |
| `Login`, `Logged out` | Connexion (compte NGE) |
| `Map_00` et variantes | Carte : poteaux `P…` (carrés verts), chambres `C…` (carrés violets pointillés), adresses `A…` (orange) ; couches Aérien / Souterrain / Administratif ; bandeau « Identification support » |
| `support_sout_main`, `support_aer_main` | **Visuels** du support : une photo par vue (chambre : Boîtier optique, Environnement, Vue A à D ; poteau : Boîtier optique, Vue d'ensemble, Vue tête de poteau), chacune avec trois actions : validée, action propre au module (grille de masque pour la chambre, rosace pour le poteau), ajout de photo |
| `support_sout_saisie`, `support_saisie_caracteristiques` | Caractéristiques. Chambre : identifiant, coordonnées, date, adresse, type (P3T), largeur, longueur, hauteur, implantation, équipements, commentaire. Poteau : identifiant, coordonnées, date, adresse, type (BS7), nature (bois), hauteur, implantation, référence (« Bois BS7 Bois simple »), structure (couplé), matériel sur appui, commentaire |
| `support_sout_saisie_grid` | Masque d'une face en plein écran : grille plus grande que l'écran (déplacement), alvéoles X / M / XR |
| `support_saisie_rosace_01` / `_02` | **Rosace des portées** : rapporteur gradué en grades (0–400), une flèche par destination — appuis télécom (vert), façade (vert pointillé), appui BT (orange) ; liste des câbles portés : destination [longueur], type de câble (5/9, 98-14-6, L1092-1-A), pose ; détail : type de câble, longueur, appui de destination, nappe, hauteur de flèche, température de relevé |
| `support_*photos*`, `*mesure*` | Prise et détail des photos, photos de mesure |
| `support_saisie_optique*`, `support_route_optique*` | Optique : boîtier (BPE / PBO), cassettes, routage (domaine ultérieur) |
| `admin_*` | Adresses / immeubles : vue d'ensemble, parcours et colonne en photos (domaine ultérieur) |

Enseignements :
- **socle commun « visuels »** identique pour tous les supports : liste de vues photographiées, validation,
  action propre au module, ajout de photo ;
- **poteau** : la rosace décrit les **portées** (linéaires aériens vers les destinations, angle en grades au
  poteau) et les **câbles portés** (type de câble du catalogue, nappe, flèche, température : données COMAC) — pendant
  aérien de l'occupation des alvéoles ; les couleurs correspondent aux types d'implantation GraceTHD (aérien
  télécom, aérien énergie, façade) ;
- **chambre** : grille de masque en plein écran avec déplacement, conforme à la décision sur les grandes faces.

Décisions poteau (31 octobre 2026) :
- **contrôles à prévoir** (absents de la maquette) : ceux de FOA Explorer — visuel, percussion, secousse, pointe
  carrée, tête de poteau, environnement (surplomb, élagage, nacelle, bitume), sécurité (voisinage ERDF, flambement,
  verticalité, étiquette, utilisable) ;
- **destination d'une portée** = un nœud du modèle ; le numéro d'appui Orange (ex. 437991) en est l'étiquette.

Précisions (guide Enedis-MOP-RES_010E, avril 2024, études mécaniques COMAC) :
- **nappe** = câbles d'une même traverse sur une portée (3 traverses télécom au plus par appui Enedis, espacées
  de 0,10 m au moins) → numéro de traverse ;
- **standard** = tension de pose standard selon la zone (Agglomération ou Écart), sans relevé de flèche ; pour
  une portée molle, flèche réelle relevée avec la température ambiante (COMAC en déduit le paramètre à 40 °C).

Implantations des supports validées : chaussée, trottoir, accotement, terre-plein, domaine privé, façade, autre.
Table COMAC des câbles optiques : à compléter plus tard. Question ouverte : la longueur se rapporte-t-elle au
câble ou à la portée (deux câbles vers 437991 : 31 m et 32 m) ?

### Hirondelle : rosace de l'application Excel (2014–2016)

Hirondelle (`FOA/FTTH_OR_HEILLECOURT/Hirondelle/install/model.xlsm`) est une macro VBA appelée depuis la « Fiche
de relevés d'appui FT » (modèles `FICHE FT.xltm`, `Fiche BT.xltm`). Le formulaire « Saisie des portées » est
dessiné avec le contrôle ActiveX VeCAD. Son interface a donné satisfaction : elle sert de **référence pour la
rosace du terminal**.

Interaction :
- **rosace plein cadre** : rapporteur en grades (un trait par grade, un trait long tous les 2, une valeur tous
  les 10), deux couronnes de chiffres (extérieure en sens horaire, intérieure en sens inverse) ;
- **poteau au centre** : symbole selon le type (simple, jumelé, haubané, EDF, CF), orientable en le faisant
  glisser (axe) ;
- **une aiguille par direction** (« Ajout angle ») : talon contre le poteau, poignée, pointe sur le bord ; elle
  tourne en suivant le pointeur, avec la valeur affichée en direct (« Angle : 221,9 ») ;
- **étiquette de destination** sur chaque aiguille (« DEST. » par défaut) : déplaçable, modifiée par double-clic
  (n° d'appui FT, façade, ERDF…) ;
- **types de portée** : l'aiguille sélectionnée ouvre un menu latéral de quatre boutons-bascules. Chaque type
  donne au plus une flèche, placée à côté des autres le long de l'aiguille. Le menu propose aussi « Suppr
  angle ». Sens des types d'après la légende du modèle `Fiche BT.xltm` :

  | Code | Flèche | Câbles |
  | --- | --- | --- |
  | 1 | bleu tireté | branchement ERDF ou éclairage public |
  | 2 | bleu plein | réseau ERDF (T70, T150, cuivre nu) |
  | 3 | vert tireté | branchement FT (5/9, 5/10) |
  | 4 | vert plein | réseau FT (98-14-6, 98-28-6…) |

  La couleur donne le réseau (bleu = électrique, vert = télécom) et le trait l'usage (plein = réseau,
  tireté = branchement). Le tireté ne désigne pas une façade. La même légende donne la forme du poteau sur la
  rosace : rectangle pour un poteau béton rectangulaire, rond pour un poteau rond (béton, bois, métal) ;
- **manipulation directe** : on sélectionne en touchant, on déplace en faisant glisser et on désélectionne en
  touchant ailleurs, sans aucune boîte de dialogue. Ce fonctionnement se transpose tel quel au tactile ;
- **Valider** : rendu épuré (flèches fines en éventail autour de chaque aiguille), image insérée dans la fiche
  (zone `ZONE_ROSACE`) ; un clic sur l'image rouvre la saisie.

Données : `POTEAUX` (axe, type), `ANGLES` (aiguille, angle, destination, position de l'étiquette, angle en
grades), `PORTEES` (aiguille, type 1 à 4). La rosace ne porte que la géométrie. Les câbles sont décrits dans le
tableau de la fiche : type (liste de 38 références, de 5/9 à L1092), longueur, nappe (sur réhausse, standard,
basse), nombre de câbles de branchement, appui de destination.

**Convention d'angle** (lue dans le code) : grades, 0 à droite de la rosace, sens horaire (100 en bas, 300 en
haut). Sur le terrain, la rosace était orientée au nord, haut du dessin vers le nord. Le nord se lit donc 300, et
l'azimut d'une valeur Hirondelle vaut (angle + 100) mod 400. La colonne `ROTATION_ROSACE` des fiches est
une constante de dessin (90°), pas une orientation relevée.

À ne pas reproduire : l'axe du poteau est affiché et enregistré en degrés alors que les angles sont en grades ; un
pointeur exactement horizontal donne 360 (calcul par arc tangente sans `atan2`).

Pour le terminal, l'interaction Hirondelle est reprise et complétée par la maquette Figma et le modèle :
- la destination est un nœud du modèle (voisin proposé sur la carte, ou nœud créé « à relever ») ; quand sa
  position est connue, l'angle est prérempli par l'azimut de la géométrie ;
- **la rosace est orientée au nord** (nord en haut, aidé par la boussole du terminal) et l'angle enregistré est
  l'azimut : grades, 0 = nord, sens horaire. C'est la convention des angles calculés depuis GraceTHD
  (`PRT_ANG1`, `PRT_ANG2`) ; la couronne affiche 0 en haut ;
- les câbles portés se saisissent sous chaque portée (la maquette Figma les liste par destination) ;
- les types de flèche ne sont pas une donnée à saisir. Un même linéaire d'infra porte plusieurs câbles, de
  réseaux éventuellement différents (`INF_PORTEE_CABLE`), et chaque câble porté donne une flèche :
  - couleur = réseau, déduit du catalogue (`MAT_CABLE.CAB_TYPE` : N et I = BT, Telecom, FO et Fibre = télécom) ;
  - trait = usage (réseau ou branchement), donné à titre indicatif par `MAT_CABLE.CAB_USAGE` (rempli à
    l'import d'après la légende Hirondelle ; non renseigné pour les câbles optiques).

  La maquette Figma, qui colore selon l'implantation de la destination (façade en vert pointillé, appui BT en
  orange), est à aligner sur la légende Hirondelle.

### Domaines et activités (31 octobre 2026)

Deux axes distincts :
- **domaine** = ce qui est décrit (données) : noyau, infra, chambre, poteau, adresse / immeuble / BAL, optique,
  électrique. Côté BE, un fichier attaché par domaine ; côté terminal, un espace `properties.<domaine>`.
- **activité** = ce que fait le technicien : écrans, enchaînement, règles de complétude côté terminal ; contrôles
  et sorties côté BE. L'abonnement dit ce que le technicien peut faire (activités) et où (zones).

| Activité | Domaines modifiés | Domaines lus |
| --- | --- | --- |
| Relevé chambres | chambre, infra (parcours souterrain) | noyau, poteau (destinations) |
| Relevé poteaux | poteau, infra (parcours aérien : portées) | noyau, chambre |
| Relevé BAL | adresse / immeuble / BAL | noyau |
| Relevé immeubles | adresse / immeuble / BAL | noyau |
| Retour fin de travaux | infra, chambre, poteau, optique, immeuble… | tous |
| Maintenance optique | optique | infra, chambre, poteau |
| Travaux réseaux électriques | électrique (à définir) | noyau, infra |

Les activités dialoguent par les données, sans appel direct de l'une à l'autre :
1. **le noyau partagé** : chambres et poteaux sont des nœuds du même `PRJ_NOE`, reliés par des linéaires (ex.
   remontée aéro-souterraine) ;
2. **la carte du socle** : dans une mission combinant plusieurs activités (ex. relevé chambres + poteaux + autres
   supports), toucher un nœud ouvre l'écran de l'activité correspondant à son type ;
3. **les tâches transmises** : une destination vers un poteau inexistant crée le nœud, marqué « à relever » pour
   l'activité poteaux.

Ajouts au modèle :
- **intervention** dans le noyau : qui, quand, mission (commande), objets touchés. Nécessaire au retour de fin de
  travaux (prévu / réalisé, avancement et statut GraceTHD), à la maintenance et au sas de contrôle, qui valide une
  intervention plutôt que des objets isolés ;
- **deux manifestes** : domaine (tables, référentiels, correspondance GraceTHD) et activité (domaines lus et
  modifiés, écrans, complétude, sorties).

### Applications desktop

La logique qui relie les schémas est écrite une seule fois, dans des bibliothèques C# communes (lignée
CommonTools / DataTools) :
- **bibliothèque noyau** : ouverture d'un projet et attachement des modules selon leurs manifestes, contrôle des
  dépendances, intégrité entre bases, résolution des `CODE_EXT` en `XXX_ID` à l'import, abandon daté ;
- **une bibliothèque par module** : tables, contrôles, écrans BE, sorties (FOA, C3A, export GraceTHD…).

Les applications assemblent ces bibliothèques selon leur rôle :

| Rôle | Nature | Contenu |
| --- | --- | --- |
| Préparation et publication | Interactive (BE) | Import PIT / GraceTHD, découpage en zones, publication des paquets chiffrés |
| Sas de contrôle et d'intégration | Interactive pour la validation, automatique pour le transport | Réception des retours, contrôles par module, arbitrage des conflits, intégration au référentiel |
| Exploitation et sorties | Interactive (BE) | FOA, C3A, synoptiques, exports GraceTHD |

Préparation et sorties peuvent vivre dans une seule application à modules, comme FibReady et ses plugins
(import, export, panneau, moteur) : extension de FibReady ou application sœur sur les mêmes bibliothèques. Une
application séparée ne se justifie que pour un fonctionnement à part : la tâche planifiée Azure ↔ PostGIS de la
phase 2, sous forme de service sans interface. Objectif : le BE et le terminal appliquent les mêmes définitions,
sans règles divergentes d'une application à l'autre.

## 12. Points ouverts

- Réponses de la DSI : synthèse + complément NgeEsPlorer, évolution de la VM.
- Note de vision d'ensemble (finalité, mode de fonctionnement, choix techniques) — à venir.
- Format du paquet (version 0.1.0, [paquet.md](paquet.md)) : chiffrement par la clé de zone, paquet de fonds de
  plan, paquets différentiels ; intégration d'un retour dans le sas (implémentation de référence à écrire).
- Terminaux des sous-traitants : mobiles NGE gérés (Intune / MDM ?) → effacement à distance possible.
- Catalogue des câbles : usage (réseau ou branchement) des câbles optiques, non renseigné.
- Références existantes dans `docs/` : `Besoins_KIZEO.xlsx`, `exemple_fiche_KIZEO.zip`, maquette `infraExp.fig`.
