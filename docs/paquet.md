# Paquet de zone — format d'échange GeoJSON (version 0.2.0)

Norme interne d'échange entre le BE et les terminaux. La phase 1 l'échange à la main ; la phase 2 automatise le
transport par Azure, sans changer le format. Implémentation de référence :
[tools/geojson/paquet.py](../tools/geojson/paquet.py) (`publier`, `verifier`).

## Conteneur

Archive ZIP (`<projet>_<zone>_<date>.zip`) :

| Fichier | Contenu | Publication | Retour |
| --- | --- | --- | --- |
| `paquet.json` | En-tête | Oui | Oui |
| `objets.geojson` | `FeatureCollection` RFC 7946 : un objet par nœud, linéaire ou adresse | Oui | Objets modifiés seulement |
| `referentiels.json` | Tables `DEF_*` et `MAT_*` par module | Oui | Non |
| `fichiers/<FIC_CODE_EXT>.<ext>` | Photos | Sur option | Fichiers nouveaux |

Contenu d'une zone : ses nœuds et ses linéaires, les extrémités de ses linéaires situées dans une autre zone
(`hors_zone`), les adresses de ses nœuds et celles de son emprise (BAL à relever). Des fichiers, seules les photos
(`FIC_TYPE` `image/…`) sont publiées : le terminal n'affiche que des photos ; les autres pièces jointes (PDF,
tableurs, traces de mesure) restent au BE.

## En-tête `paquet.json`

```json
{
 "format": "nge-esplorer-paquet",
 "version": "0.2.0",
 "sens": "PUBLICATION",
 "date": "2026-11-04T09:32:26Z",
 "projet": {"code": "ESSAI", "lib": "Jeu d'essai chambres et poteaux", "modele": "0.3.0"},
 "zone": {"code": "GRACE", "lib": "Export GraceTHD de test (Auvergne)", "emprise": [2.888, 45.634, 2.923, 45.655]},
 "modules": {"noyau": "0.2.0", "infra": "0.1.0", "chambre": "0.3.0", "poteau": "0.2.0"},
 "effectifs": {"NOE": 229, "LIN": 228, "ADR": 0, "fichiers": 0}
}
```

Un paquet de **retour** (`"sens": "RETOUR"`) ajoute :
- `base` : la `date` du paquet de publication sur lequel le terminal a travaillé ;
- `intervention` : colonnes de `PRJ_INTERVENTION` (`INT_CODE_EXT`, `ACT_CODE`, `INT_COMMANDE`, `INT_AUTEUR`,
  `INT_TERMINAL`, `DATE_DEBUT`, `DATE_FIN`, `INT_COMMENT`).

`version` suit le versionnement sémantique : un changement de version majeure rend le paquet illisible par une
application plus ancienne. Le terminal refuse un paquet dont un module manque ou a une version majeure différente
de la sienne. Versions : 0.1.0, première version ; 0.2.0, journal des commentaires (`commentaires`) à la place des
champs libres `NOE_COMMENT`, `CHB_COMMENT` et `POT_COMMENT`, modules noyau, chambre et poteau et modèle du projet
(`projet.modele`, `SYS_PROJET.MODELE_VERSION`) en 0.2.0. Même version majeure : un terminal 0.x lit encore un
paquet 0.2.0.

Le changement d'un module ne change pas le format : le module chambre 0.3.0 (modèle du projet 0.3.0, format toujours
0.2.0) passe les masques en m (`FAC_LARG`, `FAC_HAUT` au lieu de `FAC_NB_COL`, `FAC_NB_LIG` ; voir
[Masques de chambre](#masques-de-chambre)). Le terminal refuse un paquet dont le module chambre est antérieur à
0.3.0 : ses positions sont dans l'ancien repère, en cellules FOA.

Modules publiés : ceux dont le format décrit l'espace (noyau, infra, chambre, poteau). Le terminal refuse un module
inconnu ; `publier` n'inscrit donc pas dans l'en-tête, et ne publie pas, les modules d'un projet que le format ne
décrit pas encore (optique et immeuble, modules 0.1.0 sans espace `opt` ni `imb`), et le signale. Leurs types et
leurs vues, enregistrés dans le noyau (`DEF_TYPE`, `DEF_VUE`), le sont avec lui : un immeuble (`IMM`) ou un SRO
(`SIT-SRO`) est publié comme un nœud de son type.

## Objets `objets.geojson`

```json
{"type": "Feature", "id": "GRA-CM91060454545452",
 "geometry": {"type": "LineString", "coordinates": [[2.9067428, 45.646524], [2.9066235, 45.6466619]]},
 "properties": {
  "classe": "LIN", "TYPE_KEY": 1002, "IMPL_KEY": 1,
  "NOE1_KEY": "GRA-ND91P60454545514", "NOE2_KEY": "GRA-ND91P60454545460", "ZONE_KEY": "GRACE",
  "LIN_LNG": 17.92, "DATE_CREA": "2026-10-31T02:44:33Z", "SRC_MODIF": "import",
  "inf": {"portee": {"PRT_ANG1": 365.37, "PRT_ANG2": 165.37, "PRT_LNG": 17.92,
          "cables": [{"PCB_RANG": 1, "MAT_KEY": 12, "PCB_NAPPE": 1, "PCB_TENSION": "STD_AGGLO"}]}}}}
```

Règles :
- **`id`** = `CODE_EXT` de l'objet, stable, jamais modifié. Un objet créé sur le terminal reçoit un UUID v4.
- **`geometry`** en WGS84 (RFC 7946), 7 décimales (environ 1 cm) ; Lambert 93 côté BE, conversion à l'export
  et à l'import.
- **`classe`** : `NOE` (Point, `PRJ_NOE`), `LIN` (LineString, `PRJ_LINEAIRE`), `ADR` (Point, `PRJ_ADRESSE`).
- **Clés en majuscules** = colonnes BE, telles qu'au schéma ([schema/](../schema/README.md)), sans la clé technique
  (`XXX_ID`) ni le lien vers le parent, porté par l'imbrication.
- **Références vers une entité** (`ZONE_KEY`, `ADR_KEY`, `NOE_KEY`, `NOE1_KEY`, `NOE2_KEY`, `LIN_KEY`, `CD_KEY`,
  `CD_PARENT_KEY`) : même nom de colonne, valeur = `CODE_EXT` de la cible. Les références aux référentiels
  (`TYPE_KEY`, `MAT_KEY`, `ETAT_KEY`…) gardent leur entier.
- **Valeurs nulles omises** : une clé absente vaut `null`.
- **Clés en minuscules** = structure du format :

| Clé | Où | Contenu |
| --- | --- | --- |
| `classe` | objet | `NOE`, `LIN`, `ADR` |
| `statut` | objet | Retour seulement : `C` créé, `M` modifié, `A` abandonné (`PRJ_INT_OBJET.IOB_ACTION`) |
| `hors_zone` | nœud | Extrémité d'un linéaire de la zone située dans une autre zone (consultation) |
| `chb` | nœud | `CHB_CHAMBRE`, avec `faces` (`CHB_FACE`, chacune avec ses `positions` : `CHB_POSITION`, en m, voir [Masques de chambre](#masques-de-chambre)) et `masques` (`CHB_MASQUE_LOGIQUE`) |
| `pot` | nœud | `POT_POTEAU`, avec `controles` (`POT_CONTROLE`) |
| `inf` | nœud | `equipements` (`INF_EQUIPEMENT`) et, dans une chambre, `conduites` sans destination connue (alvéole sans miroir : `INF_CONDUITE` rattachée par `NOE_KEY`, sans linéaire) |
| `inf` | linéaire | `conduites` (`INF_CONDUITE`, chacune avec ses `cables` : `INF_CD_CABLE`) et `portee` (`INF_PORTEE`, avec ses `cables` : `INF_PORTEE_CABLE`) |
| `fichiers` | objet | `PRJ_FICHIER` de l'objet et de ses éléments : `ENTITE` (table porteuse), `VUE_CODE` (visuel attendu) ou `VIS_CODE` / `VIS_LIB` (visuel libre), colonnes du fichier ; ordre de la galerie `FIC_RANG`, photo de référence `FIC_PRINCIPALE` ; `fichier` = chemin dans le paquet s'il y est inclus |
| `commentaires` | objet | Journal daté et signé de l'objet (`PRJ_COMMENTAIRE`), du plus ancien au plus récent : voir [Commentaires](#commentaires) |

Identification des éléments imbriqués : par leur `CODE_EXT` quand ils en ont un (conduite, équipement, fichier,
commentaire), sinon par leur clé naturelle dans le parent : face `FAC_CODE`, position `CD_KEY` dans la face,
masque logique `MLOG_NUM` (une position y renvoie par `MLOG_NUM`), câble de portée `PCB_RANG`, contrôle `DATE_CTL`.

Conventions métier rappelées :
- angles de portée `PRT_ANG1` / `PRT_ANG2` : azimut au nœud `NOE1_KEY` / `NOE2_KEY`, en grades, 0 = nord
  géographique, sens horaire (azimut géodésique ; le nord du quadrillage Lambert 93 s'en écarte de la convergence des
  méridiens, 2,3 grades à 5,9° E) ; `POT_ANG_CARTO` (axe du poteau) dans la même convention ;
- `CHB_ROTATION` : rotation FOA (attribut `ROTATION` du bloc AutoCAD `FT_Chambre` du PIT) convertie en grades : axe
  A-B de la chambre à 200 grades près, sans indiquer quel bout est A ;
- dates ISO 8601 UTC suffixées de `Z` (`2026-11-04T09:15:00Z`) ; une date de source sans fuseau (texte GraceTHD)
  est lue comme heure de Paris et convertie au chargement ; traçabilité GraceTHD : `DATE_CREA`, `DATE_MODIF`,
  `SRC_MODIF`, `DATE_ABD`, `SRC_ABD`.

## Masques de chambre

`chb.faces` porte les faces relevées de la chambre (`CHB_FACE`), chacune avec ses `positions` (`CHB_POSITION`), au
repère métrique du module chambre 0.3.0 (chambre de Nancy publiée après reprise, dates omises) :

```json
"chb": {"MAT_KEY": 36, "CHB_ROTATION": 123.22222222222223, "CHB_NIVEAU": 2, "SRC_MODIF": "import",
 "masques": [{"MLOG_NUM": 1}],
 "faces": [{"FAC_CODE": "B", "FAC_LARG": 0.567, "FAC_HAUT": 0.54,
   "positions": [
    {"CD_KEY": "NCY-CD36", "POS_X": 0.476595, "POS_Y": 0.12825, "MLOG_NUM": 1, "POS_MIROIR": 0, "SRC_MODIF": "import"},
    {"CD_KEY": "NCY-CD37", "POS_X": 0.347193, "POS_Y": 0.131535, "MLOG_NUM": 1, "POS_MIROIR": 0, "SRC_MODIF": "import"}]}]}
```

| Clé | Contenu |
| --- | --- |
| `FAC_CODE` | Face `A` à `D`, clé naturelle de la face dans la chambre. Convention Orange, dos à la voie : A à gauche, B à droite, C côté voie, D en face ; chambre le long de la voie : A et B sont les petits côtés |
| `FAC_LARG`, `FAC_HAUT` | Largeur et hauteur de la face, en m, strictement positives : largeur de la chambre pour A et B, longueur pour C et D ; hauteur (profondeur) de la chambre. Face relevée dans FOA Explorer : 0,567 × 0,54 m, sa fenêtre de dessin |
| `POS_X`, `POS_Y` | Centre de l'alvéole, en m depuis le bord gauche et depuis le bord haut de la face |
| `CD_KEY` | Conduite (`CD_CODE_EXT`), clé naturelle de la position dans la face ; son diamètre `CD_DIAM` (mm) donne la taille de l'alvéole |
| `MLOG_NUM` | Masque logique de la chambre (`masques`) |
| `POS_MIROIR` | 1 si la position a été créée en appliquant le miroir |

Règles :
- les alvéoles sont dessinées en vraie grandeur ; la grille du terminal (carrés de 5 cm) n'est qu'un repère
  d'affichage, pas une donnée ; le centre d'une alvéole est dans sa face, son disque peut en déborder ;
- dimensions d'une nouvelle face (relevées, sinon du catalogue `MAT_CHAMBRE`, sinon de la fenêtre FOA) et
  redimensionnement (agrandissement à la demande seulement, alvéoles recentrées puis bornées à la face) : voir
  [schema/README.md](../schema/README.md#masques-de-chambre) ;
- jusqu'au module chambre 0.2.0, faces (`FAC_NB_COL` × `FAC_NB_LIG`) et positions étaient en cellules de la fenêtre
  FOA (9 × 12 cellules de 6,3 × 4,5 cm). Le terminal refuse un tel paquet, avec un message demandant de le republier,
  et ne le convertit pas : son retour recopierait dans l'en-tête des versions de modules fausses pour des positions
  converties. Au BE, le projet est repris (`tools/schema/projet.py migrer`, conversion exacte : × 0,063 en largeur,
  × 0,045 en hauteur), puis le paquet republié ; `publier` refuse un projet non repris.

## Commentaires

`commentaires` porte, dans les propriétés d'un nœud, d'un linéaire ou d'une adresse, au même niveau que `fichiers`,
le journal daté et signé de l'objet (`PRJ_COMMENTAIRE`, voir [schema/README.md](../schema/README.md#commentaires)).
Depuis la 0.2.0, il remplace les champs libres du support `NOE_COMMENT`, `CHB_COMMENT` (`chb`) et `POT_COMMENT`
(`pot`) ; les autres colonnes `*_COMMENT` (`ADR_COMMENT`, `LIN_COMMENT`, `CD_COMMENT`…) restent.

```json
"commentaires": [
 {"COM_CODE_EXT": "aa4adf24-5a17-51c7-9eea-8d2f37de2000", "COM_TYPE": "standard", "COM_TEXTE": "verre poto 18m",
  "COM_AUTEUR": "FOA", "COM_ORIGINE": "FOA", "DATE_CREA": "2017-12-21T08:25:29Z"},
 {"COM_CODE_EXT": "9a3d2e61-5b7c-4f08-b1e2-7c4d8a9f0e15", "COM_TYPE": "alert", "COM_TEXTE": "Tampon fêlé, à remplacer",
  "COM_AUTEUR": "Paul Martin", "INT_CODE_EXT": "2b7f4c1a-93e5-4d0b-8a61-5c2e9f0d7b34",
  "DATE_CREA": "2026-11-04T09:15:00Z", "DATE_MODIF": "2026-11-04T09:20:00Z", "SRC_MODIF": "Paul Martin"}
]
```

| Clé | Contenu |
| --- | --- |
| `COM_CODE_EXT` | Identifiant stable, unique dans le paquet ; UUID v4 pour un commentaire saisi sur le terminal |
| `COM_TYPE` | Type repris de FibReady, par gravité décroissante : `alert` (Alerte), `minor` (Mineur), `standard` (type par défaut), `great` (Bon point) |
| `COM_TEXTE` | Texte, non vide |
| `COM_AUTEUR` | Nom de l'utilisateur ; `FOA` ou `BE` pour un texte repris |
| `COM_ORIGINE` | Absente pour une saisie ; `FOA`, `GRACE` ou `BE` pour un texte repris d'un import FOA Explorer, d'un import GraceTHD ou du BE ; `CTRL_n` pour un contrôle |
| `INT_CODE_EXT` | Intervention terrain qui l'a saisi (`INT_KEY` du BE, traduit à la publication en `INT_CODE_EXT` de `PRJ_INTERVENTION`) ; absente pour un commentaire du BE ou repris |
| `DATE_CREA` | Date de saisie ; pour un texte repris, la date que porte son nœud (`DATE_MODIF`, à défaut `DATE_CREA`), à défaut la date de la reprise |
| `DATE_MODIF`, `SRC_MODIF` | Dernière modification et son auteur |

Règles :
- ordre du plus ancien au plus récent (`DATE_CREA`, puis `COM_ID` au BE) ; clé absente s'il n'y en a pas ; valeurs
  nulles omises ; pas de clé `ENTITE`, l'objet porteur suffit ;
- un commentaire abandonné au BE (`DATE_ABD`, `SRC_ABD`) n'est pas publié : au BE, un commentaire se retire par
  abandon ;
- seul le journal d'un nœud, d'un linéaire ou d'une adresse a sa place dans le paquet : `publier` n'écrit pas une
  entrée rattachée à une autre table (zone, chambre…) et le signale (nombre par table, sur la sortie d'erreur) ;
- un commentaire n'est modifiable ou supprimable que par son auteur, et seulement tant que le paquet de retour qui le
  contient n'a pas été exporté ; il est ensuite figé. Ceux des autres auteurs et ceux venus du BE sont en lecture
  seule ;
- sur le terminal, un commentaire saisi reçoit un UUID v4, `COM_AUTEUR` = l'utilisateur (`INT_AUTEUR` du retour),
  `INT_CODE_EXT` = l'intervention en cours et `DATE_CREA` ; une modification pose `DATE_MODIF` et `SRC_MODIF` ; retiré
  avant l'export, il disparaît, n'ayant jamais quitté le terminal. Ajouter, modifier ou retirer un commentaire modifie
  l'objet qui le porte ;
- le retour porte l'objet complet, donc tous ses commentaires : ceux de l'intervention du retour (`INT_CODE_EXT` =
  `intervention.INT_CODE_EXT` de l'en-tête) sont les nouveaux ou modifiés, signés `COM_AUTEUR` =
  `intervention.INT_AUTEUR` ; les autres doivent être identiques à leur état publié (contrôles à l'intégration,
  étapes 2 et 3 ci-dessous) ;
- le terminal n'affiche aujourd'hui que le journal des supports (nœuds) : celui d'un linéaire ou d'une adresse est
  conservé et renvoyé tel quel avec l'objet.

## Modification sur le terminal

- L'**objet** (nœud, linéaire ou adresse avec tout ce qu'il porte) est l'unité de modification, de stockage
  (une ligne par objet en base chiffrée) et de conflit.
- Toute modification remplace l'objet entier, met à jour `DATE_MODIF` et `SRC_MODIF` (compte abonné) et pose
  `statut` (`C` si l'objet a été créé sur le terminal, sinon `M`).
- **Pas de suppression** : l'abandon pose `DATE_ABD` / `SRC_ABD` et `statut` = `A`.
- Créer une portée vers une destination nouvelle crée deux objets : le nœud de destination (`C`) et le linéaire
  (`C`).
- Commentaires : journal de l'objet, avec sa propre règle de modification (voir [Commentaires](#commentaires)).

## Intégration d'un retour (sas de contrôle)

Contrôles d'abord, sans aucune écriture : au premier contrôle en échec, le retour est refusé ou mis en arbitrage,
et la base reste inchangée.

1. Structure (`verifier`, ci-dessous) et versions des modules.
2. Conflits, à arbitrer manuellement, pour chaque objet du retour :
   - l'objet a été modifié au BE après `base` (`DATE_MODIF` BE > `base`) ;
   - un commentaire de son journal a, au BE, un `DATE_MODIF` ou un `DATE_ABD` postérieur à `base` : modifié ou
     abandonné au BE depuis la publication, sans que le `DATE_MODIF` de l'objet ait bougé.
3. Règles du journal, pour chaque objet du retour :
   - un commentaire de l'intervention du retour (`INT_CODE_EXT` = `intervention.INT_CODE_EXT`, signé
     `intervention.INT_AUTEUR`) inconnu du BE est à ajouter ; s'il a déjà été intégré par un retour précédent de la
     même intervention, l'export de ce retour l'a figé : il doit être identique à l'entrée intégrée ;
   - tout autre commentaire du retour est comparé à son état publié, celui du paquet `base` : il doit lui être
     identique (même `COM_CODE_EXT`, mêmes clés et valeurs). Sans conflit à l'étape 2, cet état publié est l'état
     actuel de l'entrée au BE ;
   - sinon le retour est refusé. Un retour ne retire ni n'abandonne aucun commentaire : une entrée du BE absente du
     retour reste au journal.

Écritures ensuite, en une seule transaction, dans l'ordre où chaque clé peut être résolue :

4. Intervention : `PRJ_INTERVENTION`, dont l'`INT_ID` est l'`INT_KEY` des commentaires qu'elle a saisis.
5. Objets : résolution des `CODE_EXT` en `XXX_ID`, création des objets nouveaux (`C`), aplatissement dans les
   tables, remplacement des éléments imbriqués de chaque objet modifié ; objets de l'intervention (`PRJ_INT_OBJET`).
6. Journal : ajout des commentaires nouveaux de l'intervention, rattachés à leur objet (`ENT_KEY`, `OBJ_KEY`, résolus
   à l'étape 5, objets nouveaux compris) et à l'intervention (`INT_KEY`, étape 4). Le journal est complété, jamais
   remplacé.

## Contrôles de `verifier`

`python -I tools/geojson/paquet.py verifier <paquet.zip>` affiche `conforme` (code de sortie 0) ou une anomalie par
ligne (code 1) ; la commande `publier` vérifie le paquet qu'elle vient d'écrire, et refuse d'abord un projet dont un
module est en retard sur son schéma (projet à reprendre par `tools/schema/projet.py migrer`).
- Conteneur : `paquet.json` et `objets.geojson`, plus `referentiels.json` pour une publication.
- En-tête : `format` = `nge-esplorer-paquet` ; `sens` = `PUBLICATION` ou `RETOUR` ; un retour porte `base` et une
  `intervention` avec `INT_CODE_EXT`, `ACT_CODE`, `INT_AUTEUR` et `DATE_DEBUT`.
- Objets : `FeatureCollection` ; `id` présent et unique ; `classe` `NOE`, `LIN` ou `ADR`, géométrie du type attendu
  (Point, LineString, Point) ; `statut` absent d'une publication, `C`, `M` ou `A` dans un retour ; chaque `fichier`
  cité est dans l'archive.
- Commentaires, en publication comme en retour : `commentaires` est une liste ; `COM_CODE_EXT` présent et unique
  dans le paquet ; `COM_TEXTE` non vide ; `COM_TYPE` parmi `alert`, `minor`, `standard`, `great` ; `COM_AUTEUR` non
  vide ; `DATE_CREA` présente ; dans un retour, un commentaire de l'intervention (`INT_CODE_EXT` =
  `intervention.INT_CODE_EXT`) est signé `intervention.INT_AUTEUR`.
- Masques, en publication comme en retour : module `chambre` de l'en-tête en 0.3.0 au moins, présent dès qu'un objet
  a des faces ; chaque face a `FAC_LARG` et `FAC_HAUT` numériques strictement positifs, sans `FAC_NB_COL` ni
  `FAC_NB_LIG` ; chaque position non abandonnée a `POS_X` et `POS_Y` numériques et son centre dans la face à 1 mm
  près (−0,001 ≤ `POS_X` ≤ `FAC_LARG` + 0,001, de même pour `POS_Y` et `FAC_HAUT`). Tolérance : le centre est borné
  à la face puis arrondi, au micromètre au BE (conversions exactes), au millimètre au plus sur le terminal, soit
  0,5 mm de débord au plus ; au-delà, la position est dans un autre repère (cellules) ou sa face a été réduite sans
  recentrage. Bien moindre qu'un demi-diamètre (14 mm pour la plus petite alvéole normalisée, 28 mm), elle garantit
  qu'une alvéole acceptée recouvre sa face ; le disque, lui, peut déborder (206 alvéoles des relevés FOA de Nancy
  débordent de la fenêtre FOA, aucune n'en a le centre dehors). Une position abandonnée (`DATE_ABD`), qui n'est plus
  dessinée, n'est pas bornée.
- Publication seulement (un retour ne porte que les objets modifiés, ses références peuvent viser des objets du
  BE) : extrémités `NOE1_KEY` / `NOE2_KEY` de chaque linéaire et adresse `ADR_KEY` présentes dans le paquet ;
  conduite de chaque position de chambre présente ; référentiels de chaque module de l'en-tête présents.

Le contrôle des commentaires par rapport au BE (conflits, identité à l'état publié) relève de l'intégration
(étapes 2 et 3), qui dispose de la base.

## `referentiels.json`

```json
{"noyau": {"DEF_TYPE": [{"TYPE_ID": 13, "TYPE_CODE": "POT", "TYPE_LIB": "Poteau", "...": "..."}]},
 "infra": {"MAT_CABLE": [{"MAT_ID": 1, "MAT_LIB": "5/9", "CAB_TYPE": "Telecom", "CAB_USAGE": "BRANCHEMENT"}]},
 "chambre": {"MAT_CHAMBRE": []}, "poteau": {"MAT_POTEAU": []}}
```

Toutes les tables `DEF_*` et `MAT_*` des manifestes des modules du paquet, valeurs nulles omises. Les
référentiels ne sont gérés qu'au BE.

## Points ouverts

- Chiffrement du paquet par la clé de zone (phase 2, principe NGE Es'tore) : le ZIP devient la charge chiffrée.
- Paquet de fonds de plan (MBTiles / PMTiles), distinct de ce paquet de données : IGN en France, tuiles générées
  à partir des données OSM ailleurs (Maroc) ; jamais de tuiles Google (voir echanges.md §4).
- Paquets différentiels (seuls les objets modifiés depuis une publication) quand les zones grossiront.
- Retour d'un terminal antérieur à la 0.2.0 : il peut encore porter `NOE_COMMENT`, `chb.CHB_COMMENT` ou
  `pot.POT_COMMENT`, retirés du schéma, à reprendre dans le journal (signés `INT_AUTEUR`) ou à refuser à
  l'intégration.
- Terminal antérieur au module chambre 0.3.0 : même version majeure, il lirait un paquet 0.3.0 mais placerait ses
  alvéoles en cellules. `verifier` refuse les positions qui sortent alors de la face et les clés `FAC_NB_COL`,
  `FAC_NB_LIG` d'une face qu'il crée, pas une position en cellules qui tombe dans la face (moins de 0,567 colonne,
  0,54 ligne) : un tel terminal ne doit plus servir.
