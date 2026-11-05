# Schéma BE NgeEsPlorer

Modèle mixte GraceTHD v2 (séparation géométrie / métier) et FOA Explorer (identifiants, catalogues `MAT_*`).
Un dossier par domaine : `manifest.json` + scripts SQL. Décisions et contexte : [docs/echanges.md](../docs/echanges.md) §11.

| Domaine | Fichier | Contenu |
| --- | --- | --- |
| [noyau](noyau/) | `noyau.sqlite` (SpatiaLite, EPSG:2154) | Projet, modules, types, référentiels communs, zones, adresses, nœuds, linéaires, interventions, fichiers, commentaires, vues photographiées |
| [infra](infra/) | `infra.sqlite` | Conduites et sous-tubage, occupation par câbles (état, taux), portées et câbles portés, matériel sur support ; diamètres normalisés des alvéoles ; catalogues câbles, COMAC, équipements |
| [chambre](chambre/) | `chambre.sqlite` | Chambres, faces et positions des conduites en m (miroir), masques logiques ; catalogue `MAT_CHAMBRE` |
| [poteau](poteau/) | `poteau.sqlite` | Poteaux, contrôles ; catalogue `MAT_POTEAU` (dont codes GESPOT) |
| [optique](optique/) | `optique.sqlite` (SpatiaLite depuis 0.3.0) | Contenu optique du matériel posé, câbles identifiés et leurs passages, câbles de raccordement des adresses (tracé propre), lovages, fibres, cassettes et positions, routes optiques, mesures ; sites techniques (NRO, SRO) |
| [immeuble](immeuble/) | `immeuble.sqlite` | Attributs BAL des adresses (logements, habitat, convention), locaux desservis et leur PBO ; immeubles (type `IMM`) |

## Conventions

- `XXX_ID` clé primaire (entier long auto-incrémenté), `XXX_KEY` clé étrangère préfixée par l'entité visée
  (`NOE_KEY`, `LIN_KEY`, `MAT_KEY`), rôle en préfixe quand il y a plusieurs références (`NOE1_KEY`, `PROPRIO_KEY`).
- `XXX_CODE_EXT` : identifiant stable, unique dans le projet, seul identifiant échangé (GeoJSON, synchronisation).
- `XXX_LIB` : libellé terrain (n° de chambre, n° d'appui Orange) ; aucune unicité.
- Traçabilité : `DATE_CREA`, `DATE_MODIF`, `SRC_MODIF`, `DATE_ABD`, `SRC_ABD` (abandon daté plutôt que suppression) ;
  géolocalisation : `GEOL_QLT`, `GEOL_MOD_KEY`, `GEOL_CLASSE_KEY`, `GEOL_SRC`. Dates ISO 8601 UTC.
- Les géométries sont dans le noyau (`GEOMETRY`) ; les modules ne contiennent que des tables attributaires, sauf le
  tracé propre d'un câble de raccordement (`OPT_CABLE.GEOMETRY`, optique 0.3.0), qui ne suit pas les linéaires.
- Les types (`DEF_TYPE`) reprennent les identifiants FOA quand ils existent (13 poteau, 16 chambre, 30 façade…) ;
  les vues d'un type valent pour ses sous-types.
- Vues photographiées (`DEF_VUE`, noyau 0.3.0) : d'un type de support (`TYPE_KEY`, galerie du support) ou des éléments
  d'une table porteuse (`VUE_ENTITE`, l'un ou l'autre : `INF_EQUIPEMENT` pour la galerie d'un équipement, vues du
  module optique) ; une photo (`PRJ_FICHIER`) est rangée dans une vue attendue (`VUE_KEY`) ou dans un visuel libre
  (`VIS_CODE`, `VIS_LIB`) de son porteur (`ENT_KEY`, `OBJ_KEY`). Manifeste : une vue porte `type` ou `entite`.

## Modules et intégrité

Le noyau attache chaque module sous son code (`ATTACH … AS chambre`) ; l'ouverture du projet refuse un fichier de
module absent, qu'`ATTACH` créerait vide. SQLite ne contrôle pas les clés étrangères entre bases : les références
vers une autre base sont déclarées dans `references` du manifeste, et l'ouverture du projet crée pour chacune des
triggers `TEMP` (refus d'une valeur inconnue à l'insertion ou à la mise à jour, refus de supprimer une cible
référencée). Les références internes à un fichier sont de vraies clés étrangères. Journal `DELETE` imposé (pas de
WAL) pour que les transactions sur plusieurs fichiers restent atomiques.

Le manifeste déclare aussi les dépendances, les types, les entités (porteuses de fichiers et d'interventions), les
vues photographiées, l'espace GeoJSON et la correspondance GraceTHD.

## Commentaires

`PRJ_COMMENTAIRE` (noyau, depuis la 0.2.0) est le journal daté et signé des commentaires d'un objet (`PRJ_NOE`,
`PRJ_LINEAIRE`, `PRJ_ADRESSE`), rattaché comme `PRJ_FICHIER` (`ENT_KEY`, `OBJ_KEY`). Chaque entrée porte son auteur
(`COM_AUTEUR`), sa date (`DATE_CREA`), l'intervention terrain qui l'a saisie (`INT_KEY`) et son type, repris de
FibReady : par gravité décroissante `alert` (Alerte), `minor` (Mineur), `standard` (par défaut), `great` (Bon
point). `COM_ORIGINE` est vide pour une saisie, vaut `FOA`, `GRACE` ou `BE` pour un texte repris, `CTRL_n` pour un
contrôle. Texte et auteur ne peuvent être blancs (contraintes `CHECK`, comme le contrôle du paquet). Une entrée n'est
modifiable ou supprimable que par son auteur, tant que le paquet de retour qui la contient
n'a pas été exporté ; elle est ensuite figée, et celles des autres auteurs ou du BE sont en lecture seule. Au BE, une
entrée se retire par abandon (`DATE_ABD`, `SRC_ABD`). Échange : liste `commentaires` de l'objet dans le paquet
([docs/paquet.md](../docs/paquet.md)).

Le journal remplace les champs libres du support `NOE_COMMENT` (noyau), `CHB_COMMENT` (chambre) et `POT_COMMENT`
(poteau), retirés en 0.2.0 ; les autres colonnes `*_COMMENT` restent. Reprise d'un projet construit avant : étape
0.2.0 de [la reprise](#reprise-dun-projet-existant).

## Masques de chambre

Repère métrique depuis le module chambre 0.3.0 (modèle du projet 0.3.0) :
- **face** (`CHB_FACE`) : paroi `FAC_CODE` A à D de `FAC_LARG` × `FAC_HAUT` m (`NOT NULL`, contraintes `CHECK` > 0).
  Convention Orange ([docs/Besoins_KIZEO.xlsx](../docs/Besoins_KIZEO.xlsx)), dos à la voie : A à gauche
  (« gauche dos route »), B à droite (« droite dos route »), C côté voie (« dos route »), D en face (« face route ») ;
  chambre le long de la voie : A et B sont les petits côtés. Faces A et B à la largeur de la chambre, C et D à sa
  longueur ; hauteur de face = hauteur (profondeur) de la chambre ;
- **position** (`CHB_POSITION`) : centre de l'alvéole, `POS_X` depuis le bord gauche et `POS_Y` depuis le bord haut
  de la face, en m ; les alvéoles sont dessinées en vraie grandeur (diamètre de la conduite) ;
- la grille du terminal (carrés de 5 cm) n'est qu'un repère d'affichage, pas une donnée ;
- **nouvelle face** : dimensions de la chambre selon la face, relevées (`CHB_LARG`, `CHB_LNG`, `CHB_HAUT` > 0),
  sinon celles du catalogue (`MAT_CHAMBRE` : `CHB_LARG_INT`, `CHB_LNG_INT`, `CHB_HAUT_INT` > 0), sinon celles de la
  fenêtre FOA (0,567 m de large, 0,54 m de haut), par exemple pour une chambre OHN ;
- **redimensionnement** : une face qui a des alvéoles n'est agrandie qu'à la demande ; ses alvéoles restent
  centrées (`POS_X` += (nouvelle largeur − ancienne) / 2, `POS_Y` += (nouvelle hauteur − ancienne) / 2), puis
  bornées à la face. Même règle pour tout redimensionnement ;
- **FOA Explorer** dessine chaque face dans une fenêtre fixe de 9 × 12 cellules de 6,3 × 4,5 unités, 1 unité = 1 cm
  (alvéoles en vraie grandeur : rayon = `ALV_DIAM` / 20 unités), soit 56,7 × 54 cm quelles que soient les dimensions
  de la chambre ; `ALV_X` / `ALV_Y` = centre de l'alvéole, origine en bas à gauche, y vers le haut. Chargement
  ([tools/essai/charger_essai.py](../tools/essai/charger_essai.py)) : face de 0,567 × 0,54 m, `POS_X` = `ALV_X` / 100,
  `POS_Y` = (54 − `ALV_Y`) / 100 ;
- `CHB_ROTATION` : rotation FOA (attribut `ROTATION` du bloc AutoCAD `FT_Chambre` du PIT) convertie en grades : axe
  A-B de la chambre à 200 grades près, sans indiquer quel bout est A.

Jusqu'au module chambre 0.2.0, faces (`FAC_NB_COL` × `FAC_NB_LIG`) et positions étaient en cellules de la fenêtre FOA,
dessinées carrées sur le terminal : les masques FOA y étaient étirés de 1,4 fois en hauteur. Reprise : étape 0.3.0
ci-dessous.

Une conduite a au plus une position par chambre (une à chaque bout du fourreau). Miroir : la position d'en face est
proposée par le terminal, `X' = W' × (1 − X / W)` et `Y' = Y` (même profondeur), bornée à la face, `POS_MIROIR` = 1 ;
rien d'autre n'est enregistré, la conduite étant commune aux deux chambres.

## Conduites et occupation

Module infra 0.2.0 (modèle du projet 0.4.0), repris d'Infra Explorer (FOA Explorer) :
- **états** (`DEF_CD_ETAT`) : V, R, X, XR, M et XM (occupée et mauvaise, FOA 32). Règle de FOA : une conduite qui
  porte un câble ou un sous-tube est occupée, V → X, R → XR, M → XM ;
- **diamètres normalisés** (`DEF_CD_DIAM`) : diamètre nominal (`CD_DIAM`) → diamètre intérieur, 20 à 150 mm ; 20 à
  33 mm proposés au sous-tubage (`DIAM_SOUS_TUBE`). Diamètres intérieurs de 28 à 150 mm : ceux qu'encode l'abaque
  d'occupation de FOA (`cab_occupation.csv`) ; 20 → 16 et 24 → 20 mm à confirmer ;
- **câbles constatés** (`INF_CD_CABLE`) : une ligne pour `CDC_NB` câbles (au moins 1) de même diamètre `CDC_DIAM` et
  de même nature `CDC_NATURE` (`FO` fibre, `CU` cuivre ; FOA `CAB_TYPE` 0 / 1), rang `CDC_RANG` unique dans la conduite
  (clé naturelle dans le paquet), référence `MAT_KEY` facultative (le câble identifié relève du module optique) ;
- **taux d'occupation** `CD_OCCUP` (%) : Σ `CDC_NB` × (`CDC_DIAM` / `DIAM_INT`)² × 100, arrondi au dixième ; sans
  câble, 100 pour M et XM, 0 sinon ; vide s'il n'est pas calculable (diamètre nominal hors référentiel, câble sans
  diamètre). Écrit par le terminal, recalculé au BE par `recalculer_occupation` de
  [tools/schema/projet.py](../tools/schema/projet.py) (reprise, chargements) ; les sous-tubes ne comptent pas dans le
  taux de leur parent ;
- **sous-tube** : `CD_PARENT_KEY` vers une conduite du même porteur (même `LIN_KEY`, ou même `NOE_KEY` sans
  destination), dont il hérite la destination ; un seul niveau ; `CD_NUM` = rang dans le parent (affiché N.k) ;
  position propre dans la même face que le parent. Chargement FOA : le sous-tube prend le porteur de son alvéole, et
  la suit quand elle passe sur le linéaire.

Échange : [docs/paquet.md](../docs/paquet.md#conduites-et-occupation) ; contrôles de `verifier` (rang, nombre et nature
des câbles, parent du même porteur et d'un seul niveau, une position par conduite et par chambre).

## Optique

Module 0.1.0 (novembre 2026), calqué sur GraceTHD v2.0.1 et établi sur le DOE Evicom du SRO-2-02HG
([tools/essai/charger_doe.py](../tools/essai/charger_doe.py)) :
- le matériel reste dans l'infra (`INF_EQUIPEMENT`, catalogue `MAT_EQUIP`, capacité du modèle) ; `OPT_EQUIPEMENT` en
  décrit le contenu optique : étiquette terrain (`EQO_LIB`), fonction (BPE, PBO, PTO, DTI, baie, tiroir), capacité
  utile du boîtier posé (`EQO_CAPA`), emplacement dans un local technique, avancement (posé, à créer), propriétaire ;
  un tiroir a pour parent sa baie ;
- câble (`OPT_CABLE`) d'un nœud à l'autre, raccordé à ses extrémités dans un équipement, sans géométrie : son tracé
  est celui des linéaires de ses passages (`OPT_PASSAGE`, rangés depuis `NOE1`), chacun relié à la ligne de l'infra
  qui le porte : câble porté (`INF_PORTEE_CABLE`, aérien et façade) ou occupation de la conduite (`INF_CD_CABLE`,
  souterrain). Un câble de colonne a ses deux extrémités dans l'immeuble et aucun passage ;
- câble de raccordement final (module 0.3.0, fonction `RA`) : du PBO (`NOE1_KEY`, `EQU1_KEY`) à l'adresse desservie
  (`ADR2_KEY`, sans `NOE2_KEY` : la boîte aux lettres est portée par l'adresse), avec son tracé propre
  (`GEOMETRY`, ligne en Lambert 93, orientée du PBO vers l'adresse), sans passages ; `NOE2_KEY` ou `ADR2_KEY`
  obligatoire (contrôle de la table). La base du module devient SpatiaLite (Lambert 93 seul déclaré). DOE Evicom :
  363 câbles de la base FibReady (aériens 214, en fourreau 127, en immeuble 22), à poser, du PBO à 337 adresses ;
- lovages (`OPT_LOVE`) ; fibres (`OPT_FIBRE` : rang dans le câble, tube et rang dans le tube, couleurs du code
  Orange `DEF_FO_COULEUR` ; au-delà de 12 tubes, la couleur revient avec des bagues noires) ;
- cassettes d'un boîtier ou d'un tiroir (`OPT_CASSETTE` ; cassette 0 : fibres en passage hors platines) et positions
  (`OPT_POSITION` : fibre entrante `FIB1`, fibre sortante `FIB2`, rôle épissure, passage, attente ou connecteur,
  affectation reprise de l'étude : ABONNE, DEPART, PASSAGE, RESERVE, MORTE, SURCAPA) ;
- route optique (`OPT_ROUTE`, `OPT_ROUTE_FIBRE`) : fibres du tiroir de départ au PBO, dans l'ordre ;
- mesure (`OPT_MESURE`) d'une fibre à une longueur d'onde et dans un sens : réflectométrie, photométrie ou perte
  d'insertion ; route, fibre d'origine et équipement d'extrémité ; longueur, perte totale, plus forte atténuation
  d'événement, plus forte pente, ORL, conformité aux seuils de la mesure ; trace (`.sor`) dans `PRJ_FICHIER`,
  rattachée à la mesure ;
- types de nœud : site technique `SIT` (NRO `SIT-NRO`, SRO `SIT-SRO`) et ses vues (armoire fermée, ouverte,
  étiquettes, tiroirs, arrivée des fourreaux, mise à la terre) ;
- galerie d'un équipement (module 0.2.0) : vues `VUE_ENTITE` = `INF_EQUIPEMENT` (boîtier fermé `FERME`, boîtier
  ouvert `OUVERT`, `CASSETTES`, mesures photométriques `MESURES`, aucune obligatoire : un équipement préexistant n'a
  pas à être renseigné en détail) et visuels libres, photos `PRJ_FICHIER` d'`ENT_KEY` `INF_EQUIPEMENT`. Un support
  pouvant porter plusieurs équipements, la vue « Boîtier optique » (`BOITIER`) des chambres, poteaux et immeubles est
  retirée (chambre 0.4.0, poteau 0.3.0, immeuble 0.2.0).

Échange depuis le format 0.3.0 ([docs/paquet.md](../docs/paquet.md#optique)) : câbles en objets de la classe `CAB`
(parcours, lovages, fibres), contenu optique des équipements dans l'espace `opt` de leur nœud (cassettes, positions,
mesures) ; fibre désignée par son câble et son rang ; routes au BE seulement. Depuis le format 0.4.0, une photo
d'équipement désigne son équipement (`EQU_KEY`, [docs/paquet.md](../docs/paquet.md#fichiers-et-visuels)) ; depuis
le format 0.5.0, un câble de raccordement mène à son adresse (`ADR2_KEY`) et porte son tracé en géométrie
([docs/paquet.md](../docs/paquet.md#câbles-de-raccordement)). Le terminal les lit (liens fibres d'un équipement)
sans les modifier.

## Immeubles et BAL

Module 0.1.0 (novembre 2026), d'après GraceTHD v2.0.1 (`t_adresse`, `t_suf`, `t_sitetech` de type BAT) :
- immeuble = nœud du noyau de type `IMM` (identifiant FOA 12) à son adresse, avec ses vues (vue d'ensemble, boîtes
  aux lettres, colonne montante ; le boîtier optique a la galerie de son équipement) ; son local technique héberge le matériel (emplacement dans
  `OPT_EQUIPEMENT`) ;
- `IMB_ADRESSE`, ce que l'adresse dessert, relevé au BAL : logements, locaux professionnels, prises à construire,
  habitat (pavillon, immeuble), état (cible, signé, en cours de déploiement, déployé, abandonné), immeuble neuf, code
  du bâtiment chez l'opérateur, raccordement prévu (`DEF_IMPLANTATION`), gestionnaire, signature de la convention,
  accord du gestionnaire ;
- `IMB_LOCAL`, local desservi (site utilisateur final) : type (résidentiel, professionnel, opérateur, technique),
  raccordement (programmé … abonné), bâtiment, escalier, étage, PBO qui le dessert (zone du PBO).

Échange depuis le format 0.3.0 ([docs/paquet.md](../docs/paquet.md#immeubles-et-locaux)) : espace `imb` de
l'adresse (colonnes de `IMB_ADRESSE` et ses `locaux`), lu par le terminal (immeuble et BAL de l'adresse, locaux
desservis d'un PBO).

## Reprise d'un projet existant

```powershell
python -I tools\schema\projet.py migrer <dossier projet> "C:\Program Files\QGIS 3.44.7\bin"
```

Applique dans l'ordre les étapes en attente, en une seule transaction sur le noyau et les modules ;
`migrer-commentaires`, ancien nom de la commande, en est un simple alias. Chaque étape porte à sa version les
modules qu'elle a mis au niveau (`SYS_MODULE`) et le modèle du projet (`SYS_PROJET.MODELE_VERSION`). Annulent toute
la reprise : un module inscrit dont le fichier manque (refusé dès l'ouverture du projet, avant toute écriture), une
table absente du fichier d'un module, une anomalie propre à une étape. Un module non inscrit au projet est ignoré.
Idempotente : une étape déjà faite n'est pas rejouée, une seconde exécution ne change rien.

**Étape 0.2.0, journal des commentaires** :
- création de `PRJ_COMMENTAIRE` si elle manque (instructions lues dans `noyau/schema.sql`) ;
- une entrée `standard` par texte non vide, rattachée au nœud (`PRJ_NOE`), sans intervention, datée du nœud (sa
  `DATE_MODIF`, à défaut sa `DATE_CREA`, à défaut la date de la reprise) en UTC : une date sans fuseau, comme les
  dates GraceTHD d'un projet chargé avant la 0.2.0, est lue comme heure de Paris ;
- origine d'après la base : une ligne encore marquée `SRC_MODIF = 'import'` vient de
  [tools/essai/charger_essai.py](../tools/essai/charger_essai.py), seul chargement à ce jour, qui charge chaque source
  dans sa zone : GraceTHD dans la zone `GRACE` du jeu d'essai, FOA Explorer ailleurs (en mode `--foa`, l'unique zone
  porte le code du projet et vient de FOA Explorer, même si ce code est `GRACE`) ; toute autre ligne est rapportée au
  BE. Auteur `FOA` pour un texte venu de FOA Explorer, `BE` sinon. Code, auteur et date suivent les règles de
  `charger_essai.py` (`code_reprise`, `auteur_reprise` et `date_reprise` de `projet.py`) ;
- retrait des colonnes, avec recalcul des statistiques SpatiaLite de `PRJ_NOE` (`InvalidateLayerStatistics` puis
  `UpdateLayerStatistics`, qui seul ne recalcule rien après un retrait de colonne) : sans lui, QGIS montre encore
  `NOE_COMMENT` et l'ajout d'un nœud échoue ;
- modules noyau, chambre et poteau portés à 0.2.0, seulement ceux dont la table ne porte plus la colonne ; modèle
  porté à 0.2.0 ;
- annulent la reprise : un texte porté par une ligne sans nœud ; déjà faite : une colonne déjà retirée (statistiques
  recalculées si elles la citent encore), et chaque entrée reprise a un `COM_CODE_EXT` déterministe (UUID v5 du
  projet, du nœud et de la colonne).

**Étape 0.3.0, masques métriques** (à faire tant que `CHB_FACE` porte `FAC_NB_COL` et `FAC_NB_LIG`) :
- conversion exacte des cellules FOA en m, arrondie au micromètre (exacte pour une position au millième de
  cellule) : `FAC_LARG` = `FAC_NB_COL` × 0,063, `FAC_HAUT` = `FAC_NB_LIG` × 0,045 (une face 9 × 12 devient
  0,567 × 0,54 m ; une dimension vide, grille par défaut 9 × 12 avant la 0.3.0, devient celle de la fenêtre FOA),
  `POS_X` × 0,063, `POS_Y` × 0,045 ;
- tables `CHB_CHAMBRE`, `CHB_FACE`, `CHB_MASQUE_LOGIQUE` et `CHB_POSITION` reconstruites d'après
  `chambre/schema.sql` (copie temporaire, suppression puis création, clés étrangères actives) : lignes, identifiants,
  séquences `AUTOINCREMENT` et index gardés, texte du schéma identique à celui d'un projet neuf (commentaire de
  `CHB_ROTATION` compris) ;
- annulent la reprise : une dimension de face nulle, négative ou non numérique, une position non numérique, une
  référence interne au module sans cible, une colonne inattendue que la reconstruction perdrait ;
- rapport : faces et positions converties, positions dont le centre sort de leur face (aucune attendue) ;
- module chambre et modèle portés à 0.3.0.

**Étape 0.4.0, occupation des conduites** (module infra 0.2.0) :
- `DEF_CD_DIAM` créée si elle manque, lignes du référentiel ajoutées ; état XM ajouté à `DEF_CD_ETAT` (lignes lues dans
  `infra/referentiels.sql`, ajoutées sans écraser l'existant) ;
- câbles recopiés en miroir retirés : le chargement FOA d'avant le module infra 0.2.0 reprenait dans la conduite
  commune les câbles des deux alvéoles d'un miroir, que FOA recopie d'un côté à l'autre (taux doublés). Pour une
  conduite placée dans deux chambres, dont toutes les lignes viennent d'un chargement (`SRC_MODIF = 'import'`) et dont
  la liste, dans l'ordre des `CDC_ID`, est faite de deux moitiés identiques (`CDC_NB`, `CDC_DIAM`, `MAT_KEY`,
  `CDC_COMMENT`), la seconde moitié est supprimée, sauf si un passage optique (`OPT_PASSAGE.CDC_KEY`) y renvoie
  (conduite gardée et signalée). Une liste d'au moins deux lignes qui ne se scinde pas ainsi est signalée, à contrôler
  sur la base FOA (relevé divergent des deux côtés, ou câbles réellement différents). Jeu d'essai : 40 lignes retirées
  sur 23 conduites, `ESS-CD4332` signalée (27 mm d'un côté, 4 mm de l'autre ; un chargement neuf ne garde que le 27 mm) ;
- `INF_CD_CABLE` reconstruite d'après `infra/schema.sql` (comme à l'étape 0.3.0 : lignes, identifiants, séquence et
  index gardés, les références `OPT_PASSAGE.CDC_KEY` du module optique restent valides) : `CDC_RANG` = rang de la
  ligne dans sa conduite, dans l'ordre des `CDC_ID` ; `CDC_NATURE` = `FO` pour un câble dont la référence `MAT_KEY`
  désigne un câble à fibres du catalogue (`MAT_CABLE.CAB_NB_FIB` > 0, comme un chargement DOE neuf), vide sinon (nature
  inconnue : la nature FOA `CAB_TYPE` n'était pas reprise) ; le rapport compte les lignes FO et de nature inconnue ;
- sous-tubes renumérotés dans leur parent (`CD_NUM` = 1, 2…, dans l'ordre de l'ancien numéro, numéro FOA de l'alvéole
  dans la chambre) ;
- état et taux d'occupation recalculés (`recalculer_occupation`) ;
- annulent la reprise : une table absente, un câble de conduite sans conduite, un `CDC_NB` non entier ou inférieur à
  1, une ligne du référentiel déjà prise par une autre valeur ; déjà faite : `INF_CD_CABLE` porte `CDC_RANG` et
  `CDC_NATURE` (retrait des recopies compris ; numérotation et recalcul, idempotents, sont repassés) ;
- module infra porté à 0.2.0, modèle à 0.4.0. Les tables `DEF_CD_ETAT` et `INF_CONDUITE` ne sont pas reconstruites :
  leur texte est resté celui du module 0.1.0.

**Étape 0.5.0, visuels des équipements** (noyau 0.3.0, optique 0.2.0, chambre 0.4.0, poteau 0.3.0, immeuble 0.2.0) :
- `DEF_VUE` reconstruite d'après `noyau/schema.sql` (`VUE_ENTITE` vide, `TYPE_KEY` facultatif, mêmes `VUE_ID` :
  `PRJ_FICHIER.VUE_KEY` reste valide ; contrôle des clés étrangères différé à la fin de la transaction) ;
- vues de la galerie d'un équipement ajoutées d'après le manifeste optique, si le module est inscrit ;
- vue `BOITIER` des supports retirée ; ses photos, abandonnées comprises, passent dans le visuel libre « Boîtier
  optique » (`VUE_KEY` vide, `VIS_CODE` déterministe : UUID v5 du projet, du porteur et de la vue) de leur équipement
  s'il en est déjà le porteur (`ENT_KEY` `INF_EQUIPEMENT`) ou si leur nœud porte exactement un équipement non
  abandonné, sinon de leur nœud ; rangs renumérotés par visuel, la première en photo de référence. Une photo portée
  par une autre table que `PRJ_NOE`, `CHB_CHAMBRE`, `POT_POTEAU` ou `INF_EQUIPEMENT` annule la reprise ;
- ordres des vues des supports alignés sur les manifestes ; déjà faite : `DEF_VUE` porte `VUE_ENTITE`, aucune vue
  `BOITIER` de support ne reste ;
- Evicom (copie, avant rechargement) : 68 photos reprises dans 53 visuels d'équipement, aucune de support ; Nancy :
  aucune photo `BOITIER`, deux vues retirées.

**Étape 0.6.0, câbles de raccordement** (optique 0.3.0) :
- `OPT_CABLE` reconstruite d'après `optique/schema.sql` (`NOE2_KEY` facultatif, `ADR2_KEY` vide, contrôle
  « `NOE2_KEY` ou `ADR2_KEY` », index ; mêmes `CAB_ID` et séquence), colonne `GEOMETRY` ajoutée vide ; les tables qui
  la référencent (passages, lovages, fibres, et par elles positions, routes et mesures) restent intactes : clés
  étrangères différées le temps de la reconstruction, puis contrôlées ; déjà faite : `OPT_CABLE` porte `ADR2_KEY` ;
- après la transaction, la base du module est déclarée à SpatiaLite (métadonnées, Lambert 93,
  `RecoverGeometryColumn` de `OPT_CABLE.GEOMETRY`) : SpatiaLite ne déclare une colonne que dans la base principale
  d'une connexion, pas dans une base attachée ;
- Evicom (copie, avant rechargement) : 99 câbles, 183 passages, 195 lovages et 6 000 fibres gardés ; Nancy : pas de
  module optique, modèle porté à 0.6.0.

Un projet construit avant la dernière étape n'est pas publié tant qu'il n'est pas repris : `paquet.py publier`
refuse un projet dont un module est en retard sur son schéma.

## Construction et essai

```powershell
python -I tools\schema\projet.py construire docs\essai\projet_vide `
    c:\NoDrive\Documents\Etudes\essonne\09_DOU_12-13_FOA_EXP.db "C:\Program Files\QGIS 3.44.7\bin" --essai
```

[tools/schema/projet.py](../tools/schema/projet.py) est l'implémentation de référence de la future bibliothèque
noyau C# : construction, ouverture (attachement, dépendances, triggers d'intégrité), recherche d'orphelins, reprise
d'un projet existant, et un scénario d'essai (deux chambres reliées par une conduite vue des deux côtés, sous-tubée et
occupée par des câbles cuivre et fibre, état et taux recalculés, faces aux dimensions du catalogue et positions en m,
une alvéole mauvaise sans destination, deux poteaux et leur portée, une
façade, photo, vues des supports et d'un équipement, intervention, journal de commentaires, un PBO et le câble tiré sur la portée avec ses fibres, une
cassette, une route et sa mesure, une adresse de deux logements desservis par le PBO et raccordée par un câble au
tracé propre, refus attendus), annulé à la
fin. La recherche d'orphelins ne porte que sur les modules attachés : un projet construit avant les modules optique
et immeuble reste contrôlable.

Corrections à l'import des catalogues FOA :
- `MAT_CABLE` : 132 câbles sans `MAT_ID` reçoivent un identifiant ; le lien COMAC n'est posé que par le nom
  (68 câbles) ; les 64 clés COMAC FOA sans équivalent (câbles optiques L1092…, L1047…) restent dans `COMAC_FOA` ;
  `CAB_USAGE` (réseau ou branchement, indicatif, pour le trait des flèches de la rosace) est déduit de la
  légende Hirondelle : branchement pour 5/9, 5/10 et les torsadés BT 2 ou 4 conducteurs, réseau pour le cuivre
  FT 97 / 98 / 99 et les autres câbles BT, non renseigné pour les optiques ;
- `MAT_POTEAU` : deux mâts lorrains sans libellé reçoivent leur code (`MLX`, `MLJ`) ;
- fabricants 14 à 18 cités par les catalogues mais absents de `DEF_FABRICANTS` : créés « à compléter » ;
  fabricant 0 → vide.

Angles des portées (`PRT_ANG1`, `PRT_ANG2`) et axe du poteau : azimut géographique, calculé en WGS84 (azimut
géodésique) et non dans le quadrillage Lambert 93, dont le nord s'en écarte de la convergence des méridiens
(2,3 grades à Hussigny-Godbrange, 5,9° E ; presque rien près du méridien central, 3° E, comme pour la zone GRACE).

Câbles portés (`INF_PORTEE_CABLE`), d'après le guide Enedis-MOP-RES_010E (avril 2024) : la **nappe** est
l'ensemble des câbles d'une même traverse sur la portée (3 traverses télécom au plus sur un appui Enedis) →
`PCB_NAPPE` = n° de traverse ; la **tension** est standard selon la zone (`STD_AGGLO`, `STD_ECART`, colonnes
`TENSION_CONS_RIGIDE_AGGLO` / `_ECART` de `MAT_CAB_COMAC`) ou déduite d'une flèche réelle relevée avec la
température ambiante (`RELEVE` + `PCB_FLECHE`, `PCB_TEMP`).

## Points ouverts

- Export GraceTHD `t_masque` (`mq_col`, `mq_ligne`) : colonne et ligne à déduire des positions en m, grille à définir.
- Câbles portés : longueur par câble ou par portée.
- Table COMAC complète pour les câbles optiques (clés `COMAC_FOA`) : fournie plus tard.
- Règle de complétude du poteau.
- Rattachement `ENT_KEY` / `OBJ_KEY` (`PRJ_FICHIER`, `PRJ_COMMENTAIRE`, `PRJ_INT_OBJET`) : `ENT_KEY` est une vraie
  clé étrangère, mais l'existence de l'objet visé n'est contrôlée ni par trigger ni par la recherche d'orphelins.
- Optique et immeuble : saisie sur le terminal (câble tiré constaté, épissure, relevé BAL) et son intégration ;
  complétude des activités retour fin de travaux, relevé BAL et relevé immeubles.
- Étiquette d'un équipement : portée par `OPT_EQUIPEMENT` (matériel optique) ; à remonter dans `INF_EQUIPEMENT` si le
  matériel électrique en a besoin.
- Orientation des appuis tirée des études COMAC (`POT_ANG_CARTO`) : reprise telle quelle, repère de l'étude à
  confirmer (nord géographique ou du quadrillage).
- Occupation : diamètres intérieurs des sous-tubes de 20 et 24 mm à confirmer ; place des sous-tubes dans le taux de
  leur parent (aujourd'hui ignorés, comme dans FOA) ; diamètres GraceTHD hors palette FOA (DOE Evicom : 40 et 63 mm,
  pas de taux) ; export GraceTHD (`cd_occup` = `CD_OCCUP`, `cd_nbcable` = Σ `CDC_NB`).
- DOE FibReady : `cd_dia_int` et `cd_dia_ext` exportés inversés (40 / 33 pour un PEHD 40) ; le chargement prend le
  plus grand comme diamètre nominal.
