# Paquet de zone — format d'échange GeoJSON (version 0.5.0)

Norme interne d'échange entre le BE et les terminaux. La phase 1 l'échange à la main ; la phase 2 automatise le
transport par Azure, sans changer le format. Implémentation de référence :
[tools/geojson/paquet.py](../tools/geojson/paquet.py) (`publier`, `verifier`).

## Conteneur

Archive ZIP (`<projet>_<zone>_<date>.zip`) :

| Fichier | Contenu | Publication | Retour |
| --- | --- | --- | --- |
| `paquet.json` | En-tête | Oui | Oui |
| `objets.geojson` | `FeatureCollection` RFC 7946 : un objet par nœud, linéaire, adresse ou câble optique | Oui | Objets modifiés seulement |
| `referentiels.json` | Tables `DEF_*` et `MAT_*` par module | Oui | Non |
| `fichiers/<FIC_CODE_EXT>.<ext>` | Photos | Sur option | Fichiers nouveaux |

Contenu d'une zone : ses nœuds et ses linéaires, les extrémités de ses linéaires situées dans une autre zone
(`hors_zone`), les adresses de ses nœuds et celles de son emprise (BAL à relever), ses câbles optiques (voir
[Optique](#optique)) et leurs extrémités situées ailleurs (`hors_zone`). Des fichiers, seules les photos
(`FIC_TYPE` `image/…`) sont publiées : le terminal n'affiche que des photos ; les autres pièces jointes (PDF,
tableurs, traces de mesure) restent au BE.

## En-tête `paquet.json`

```json
{
 "format": "nge-esplorer-paquet",
 "version": "0.5.0",
 "sens": "PUBLICATION",
 "date": "2026-11-05T17:10:12Z",
 "projet": {"code": "EVICOM", "lib": "DOE Evicom SRO-2-02HG (Hussigny-Godbrange)", "modele": "0.6.0"},
 "zone": {"code": "SRO-2-02HG", "lib": "SRO-2-02HG Hussigny-Godbrange (DOE Evicom)",
          "emprise": [5.8713665, 49.48833, 5.8871179, 49.4947209]},
 "modules": {"noyau": "0.3.0", "infra": "0.2.0", "chambre": "0.4.0", "immeuble": "0.2.0", "optique": "0.3.0",
             "poteau": "0.3.0"},
 "effectifs": {"NOE": 148, "LIN": 146, "ADR": 339, "CAB": 462, "fichiers": 0}
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
(`projet.modele`, `SYS_PROJET.MODELE_VERSION`) en 0.2.0 ; 0.3.0, modules optique et immeuble : classe `CAB` des
câbles, espaces `opt` des nœuds et `imb` des adresses (voir [Optique](#optique) et
[Immeubles et locaux](#immeubles-et-locaux)) ; 0.4.0, galerie des équipements (modèle du projet 0.5.0 : noyau 0.3.0,
optique 0.2.0, chambre 0.4.0, poteau 0.3.0, immeuble 0.2.0) : une photo d'équipement désigne son équipement
(`EQU_KEY`), les vues attendues d'un équipement sont publiées dans `DEF_VUE` (`VUE_ENTITE`) et la vue « Boîtier
optique » (`BOITIER`) des supports disparaît (voir [Fichiers et visuels](#fichiers-et-visuels)) ; 0.5.0, câbles
de raccordement (modèle du projet 0.6.0 : optique 0.3.0) : un câble de raccordement final mène du PBO à l'adresse
desservie (`ADR2_KEY`, sans `NOE2_KEY`) et porte son tracé propre en géométrie `LineString` (voir
[Câbles de raccordement](#câbles-de-raccordement)). Même version majeure : un terminal 0.x lit encore un paquet 0.2.0
ou 0.1.0 ; un terminal 0.2.0 refuse un paquet 0.3.0 qui porte les modules optique ou immeuble (module inconnu) ; un
terminal 0.3.0 lit un paquet 0.4.0 mais range les photos d'équipement parmi celles du support, sans leurs vues ; un
terminal 0.4.0 lit un paquet 0.5.0 mais ignore le tracé des câbles de raccordement, qu'il ne voit qu'au PBO.

Le changement d'un module ne change pas le format : le module chambre 0.3.0 (modèle du projet 0.3.0, format toujours
0.2.0) passe les masques en m (`FAC_LARG`, `FAC_HAUT` au lieu de `FAC_NB_COL`, `FAC_NB_LIG` ; voir
[Masques de chambre](#masques-de-chambre)). Le terminal refuse un paquet dont le module chambre est antérieur à
0.3.0 : ses positions sont dans l'ancien repère, en cellules FOA. Le module infra 0.2.0 (modèle du projet 0.4.0,
format toujours 0.2.0) ajoute l'occupation des conduites : état `XM`, référentiel des diamètres `DEF_CD_DIAM`, rang
`CDC_RANG` et nature `CDC_NATURE` des câbles de conduite, taux `CD_OCCUP` calculé (voir
[Conduites et occupation](#conduites-et-occupation)). Le terminal refuse un paquet dont le module infra est antérieur à
0.2.0 : ses câbles de conduite n'ont pas de clé naturelle (`CDC_RANG`). Le BE refuse de même ces paquets et leurs
retours (`verifier`), et `publier` refuse un projet non repris : le projet est repris (`tools/schema/projet.py
migrer`), puis le paquet republié.

Modules publiés : ceux dont le format décrit l'espace (noyau, infra, chambre, poteau, optique, immeuble). Le
terminal refuse un module inconnu ; `publier` n'inscrit donc pas dans l'en-tête, et ne publie pas, le module d'un
projet que le format ne décrirait pas encore, et le signale. Les types et les vues des modules, enregistrés dans le
noyau (`DEF_TYPE`, `DEF_VUE`), sont publiés avec lui : un immeuble (`IMM`) ou un SRO (`SIT-SRO`) est un nœud de son
type. Un projet sans module optique ou immeuble n'a ni câbles, ni espace `opt`, ni espace `imb`.

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
- **`classe`** : `NOE` (Point, `PRJ_NOE`), `LIN` (LineString, `PRJ_LINEAIRE`), `ADR` (Point, `PRJ_ADRESSE`), `CAB`
  (câble optique `OPT_CABLE`, géométrie `null` : son tracé est celui des linéaires de son parcours ; LineString pour
  un câble de raccordement, qui porte son tracé propre).
- **Clés en majuscules** = colonnes BE, telles qu'au schéma ([schema/](../schema/README.md)), sans la clé technique
  (`XXX_ID`) ni le lien vers le parent, porté par l'imbrication.
- **Références vers une entité** (`ZONE_KEY`, `ADR_KEY`, `ADR2_KEY`, `NOE_KEY`, `NOE1_KEY`, `NOE2_KEY`, `LIN_KEY`, `CD_KEY`,
  `CD_PARENT_KEY`, `EQU_KEY`, `EQU1_KEY`, `EQU2_KEY`, `CAB_KEY`) : même nom de colonne, valeur = `CODE_EXT` de la
  cible (`EQU_CODE_EXT` d'un équipement de `inf.equipements`, `CAB_CODE_EXT` d'un câble). Une fibre, sans
  `CODE_EXT`, est désignée par son câble et son rang : `FIB1_KEY` devient `CAB1_KEY` + `FIB1_NUM` (de même `FIB2_KEY`,
  et `FIB_KEY` d'une mesure : `CAB_KEY` + `FIB_NUM`). Les références aux référentiels (`TYPE_KEY`, `MAT_KEY`,
  `ETAT_KEY`…) gardent leur entier.
- **Valeurs nulles omises** : une clé absente vaut `null`.
- **Clés en minuscules** = structure du format :

| Clé | Où | Contenu |
| --- | --- | --- |
| `classe` | objet | `NOE`, `LIN`, `ADR`, `CAB` |
| `statut` | objet | Retour seulement : `C` créé, `M` modifié, `A` abandonné (`PRJ_INT_OBJET.IOB_ACTION`) |
| `hors_zone` | nœud | Extrémité d'un linéaire ou d'un câble de la zone située dans une autre zone (consultation), publiée sans son espace `opt` |
| `opt` | nœud | `equipements` : contenu optique des équipements du nœud (`OPT_EQUIPEMENT`), chacun avec ses `cassettes` (`OPT_CASSETTE`, chacune avec ses `positions` : `OPT_POSITION`) et ses `mesures` (`OPT_MESURE`) : voir [Optique](#optique) |
| `passages`, `lovages`, `fibres` | câble | Parcours (`OPT_PASSAGE`), réserves (`OPT_LOVE`) et fibres (`OPT_FIBRE`) du câble : voir [Optique](#optique) |
| `imb` | adresse | `IMB_ADRESSE` (immeuble, logements, convention), avec ses `locaux` (`IMB_LOCAL`) : voir [Immeubles et locaux](#immeubles-et-locaux) |
| `chb` | nœud | `CHB_CHAMBRE`, avec `faces` (`CHB_FACE`, chacune avec ses `positions` : `CHB_POSITION`, en m, voir [Masques de chambre](#masques-de-chambre)) et `masques` (`CHB_MASQUE_LOGIQUE`) |
| `pot` | nœud | `POT_POTEAU`, avec `controles` (`POT_CONTROLE`) |
| `inf` | nœud | `equipements` (`INF_EQUIPEMENT`) et, dans une chambre, `conduites` sans destination connue (alvéole sans miroir : `INF_CONDUITE` rattachée par `NOE_KEY`, sans linéaire, chacune avec ses `cables`) |
| `inf` | linéaire | `conduites` (`INF_CONDUITE`, chacune avec ses `cables` : `INF_CD_CABLE`, voir [Conduites et occupation](#conduites-et-occupation)) et `portee` (`INF_PORTEE`, avec ses `cables` : `INF_PORTEE_CABLE`) |
| `fichiers` | objet | `PRJ_FICHIER` de l'objet et de ses éléments : `ENTITE` (table porteuse), `EQU_KEY` (`EQU_CODE_EXT` de l'équipement, photo de sa galerie : `ENTITE` `INF_EQUIPEMENT`), `VUE_CODE` (visuel attendu) ou `VIS_CODE` / `VIS_LIB` (visuel libre), colonnes du fichier ; ordre de la galerie `FIC_RANG`, photo de référence `FIC_PRINCIPALE` ; `fichier` = chemin dans le paquet s'il y est inclus (voir [Fichiers et visuels](#fichiers-et-visuels)) |
| `commentaires` | objet | Journal daté et signé de l'objet (`PRJ_COMMENTAIRE`), du plus ancien au plus récent : voir [Commentaires](#commentaires) |

Identification des éléments imbriqués : par leur `CODE_EXT` quand ils en ont un (conduite, équipement, fichier,
commentaire, mesure, local), sinon par leur clé naturelle dans le parent : face `FAC_CODE`, position `CD_KEY` dans la
face, masque logique `MLOG_NUM` (une position y renvoie par `MLOG_NUM`), câble de portée `PCB_RANG`, câble de
conduite `CDC_RANG` dans sa conduite, contrôle `DATE_CTL`, contenu optique `EQU_KEY` dans le nœud, cassette
`CAS_NUM` dans l'équipement, position de cassette par ses fibres (`POS_NUM` se répète dans la cassette 0 : deux
attentes en vis-à-vis), passage `LIN_KEY` et lovage `NOE_KEY` dans le câble, fibre `FIB_NUM` dans le câble.

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
- une conduite a au plus une position (non abandonnée) par chambre, toutes faces confondues : une à chaque bout du
  fourreau, dans deux chambres ;
- miroir : un fourreau vu des deux chambres est une seule conduite (`CD_KEY`), avec une position dans chacune ;
  appliquer le miroir sur le terminal crée la position d'en face (`POS_MIROIR` = 1), sans copier la conduite ni ses
  câbles. Position proposée, calculée par le terminal depuis la position de l'autre bout (face de largeur `W`,
  position `X`, `Y`) vers une face de largeur `W'` et de hauteur `H'` : `X' = W' × (1 − X / W)` (vue de l'autre côté,
  la gauche devient la droite, à la même proportion de la largeur), `Y' = Y` (même profondeur depuis le haut), puis
  bornée à la face (0 ≤ `X'` ≤ `W'`, 0 ≤ `Y'` ≤ `H'`). Rien d'autre n'est enregistré ;
- dimensions d'une nouvelle face (relevées, sinon du catalogue `MAT_CHAMBRE`, sinon de la fenêtre FOA) et
  redimensionnement (agrandissement à la demande seulement, alvéoles recentrées puis bornées à la face) : voir
  [schema/README.md](../schema/README.md#masques-de-chambre) ;
- jusqu'au module chambre 0.2.0, faces (`FAC_NB_COL` × `FAC_NB_LIG`) et positions étaient en cellules de la fenêtre
  FOA (9 × 12 cellules de 6,3 × 4,5 cm). Le terminal refuse un tel paquet, avec un message demandant de le republier,
  et ne le convertit pas : son retour recopierait dans l'en-tête des versions de modules fausses pour des positions
  converties. Au BE, le projet est repris (`tools/schema/projet.py migrer`, conversion exacte : × 0,063 en largeur,
  × 0,045 en hauteur), puis le paquet republié ; `publier` refuse un projet non repris.

## Conduites et occupation

`inf.conduites` porte les conduites d'un linéaire (alvéoles ou tubes du fourreau) ou, dans une chambre, celles sans
destination connue ; chacune porte ses `cables`, les câbles constatés dans la conduite (`INF_CD_CABLE`), depuis le
module infra 0.2.0 (dates omises ; alvéole sous-tubée de Nancy publiée après reprise du projet, alvéole de l'Essonne
publiée après un chargement neuf par `tools/essai/charger_essai.py`, qui reprend la nature `CAB_TYPE` de FOA ; la reprise
d'un projet chargé avant le module infra 0.2.0 donne les mêmes câbles et le même taux, nature inconnue faute de
référence `MAT_KEY`) :

```json
"inf": {"conduites": [
 {"CD_CODE_EXT": "NCY-CD22399", "CD_NUM": 2, "CD_DIAM": 80.0, "ETAT_KEY": 2, "CD_OCCUP": 0.0},
 {"CD_CODE_EXT": "NCY-CD22400", "CD_PARENT_KEY": "NCY-CD22399", "CD_NUM": 1, "CD_DIAM": 28.0, "ETAT_KEY": 0,
  "CD_OCCUP": 0.0}]}
```

```json
{"CD_CODE_EXT": "ESS-CD4010", "CD_NUM": 2, "CD_DIAM": 60.0, "ETAT_KEY": 2, "CD_OCCUP": 14.8,
 "cables": [{"CDC_RANG": 1, "CDC_NB": 1, "CDC_DIAM": 12.0, "CDC_NATURE": "CU", "SRC_MODIF": "import"},
            {"CDC_RANG": 2, "CDC_NB": 1, "CDC_DIAM": 15.0, "CDC_NATURE": "CU", "SRC_MODIF": "import"}]}
```

| Clé | Contenu |
| --- | --- |
| `CD_DIAM` | Diamètre nominal (mm) ; diamètres normalisés et leur diamètre intérieur : référentiel `DEF_CD_DIAM` (`DIAM_NOMINAL`, `DIAM_INT`, `DIAM_SOUS_TUBE` = 1 pour ceux proposés au sous-tubage : 20, 24, 28, 33) |
| `ETAT_KEY` | État (`DEF_CD_ETAT`) : 0 `V` vide, 1 `R` réservée, 2 `X` occupée, 3 `XR` occupée et réservée, 4 `M` mauvaise, 5 `XM` occupée et mauvaise |
| `CD_OCCUP` | Taux d'occupation (%), calculé (voir ci-dessous) |
| `CD_PARENT_KEY` | Sous-tube : `CD_CODE_EXT` de l'alvéole qui le contient |
| `CD_NUM` | Numéro de l'alvéole ; pour un sous-tube, son rang dans son parent (1, 2… ; affiché `N.k`, `N` numéro du parent) |
| `cables` | Câbles constatés, une ligne pour `CDC_NB` câbles de même diamètre et de même nature |
| `cables[].CDC_RANG` | Rang de la ligne dans sa conduite, entier, clé naturelle de la ligne dans la conduite (comme `PCB_RANG` d'un câble porté) |
| `cables[].CDC_NB` | Nombre de câbles de la ligne, entier, au moins 1 |
| `cables[].CDC_DIAM` | Diamètre constaté (mm) |
| `cables[].CDC_NATURE` | `FO` fibre optique ou `CU` cuivre (FOA `CAB_TYPE` 0 / 1) ; absente si inconnue |
| `cables[].MAT_KEY` | Référence du câble (`MAT_CABLE`), facultative : le terminal constate un diamètre et une nature ; l'identification du câble relève du module optique |

Règles :
- **état automatique** (règle de FOA Explorer) : dès qu'une conduite porte un câble ou un sous-tube, elle est
  occupée : `V` → `X`, `R` → `XR`, `M` → `XM` ;
- **taux d'occupation** `CD_OCCUP`, formule des sections : Σ `CDC_NB` × (`CDC_DIAM` / Ø intérieur)² × 100 sur les
  câbles de la conduite, Ø intérieur = `DIAM_INT` du diamètre nominal `CD_DIAM` dans `DEF_CD_DIAM`, arrondi au
  dixième ; sans câble : 100 pour une conduite `M` ou `XM`, 0 sinon ; absent quand il n'est pas calculable (`CD_DIAM`
  hors de `DEF_CD_DIAM`, câble sans diamètre). Il peut dépasser 100. Les sous-tubes ne comptent pas dans le taux de leur
  parent, comme dans FOA. Le terminal le recalcule et l'écrit à chaque modification des câbles ou de l'état ; le BE le
  recalcule de même (`recalculer_occupation` de `tools/schema/projet.py`) ;
- **sous-tubage** : un sous-tube est une conduite de la même liste `conduites` que son parent (même porteur : même
  linéaire `LIN_KEY`, ou même chambre `NOE_KEY` pour une alvéole sans destination), dont il hérite la destination ;
  un seul niveau (le parent n'est pas lui-même un sous-tube) ; il a sa propre position (`chb.faces[].positions`),
  dans la même face que son parent ;
- **miroir** : la conduite étant commune aux deux chambres, ses câbles et son état ne sont saisis qu'une fois ; rien
  n'est recopié d'un bout à l'autre.

## Optique

Depuis la 0.3.0 (module optique 0.1.0, modèle GraceTHD v2, voir [schema/README.md](../schema/README.md#optique)), le
contenu optique est publié en deux parties : les câbles, objets de la classe `CAB`, et le contenu optique des
équipements, dans l'espace `opt` du nœud qui les porte. PBO d'une chambre du DOE Evicom (positions abrégées, dates
omises) :

```json
"inf": {"equipements": [{"EQU_CODE_EXT": "EVI-BP000000000516", "MAT_KEY": 1022, "EQU_QTE": 1}]},
"opt": {"equipements": [
 {"EQU_KEY": "EVI-BP000000000516", "EQO_LIB": "PBO-2-02HG-1015", "OTYP_KEY": 2, "EQO_CAPA": 36, "AVCT_KEY": 1,
  "PROPRIO_KEY": 10,
  "cassettes": [
   {"CAS_NUM": 0, "CTYP_KEY": 1, "CAS_CAPA": 12, "positions": [
    {"POS_NUM": 1, "CAB1_KEY": "EVI-CB000000000030", "FIB1_NUM": 1, "CAB2_KEY": "EVI-CB000000000031", "FIB2_NUM": 1,
     "PFON_KEY": 2, "POS_AFFECT": "PASSAGE"}]},
   {"CAS_NUM": 1, "CTYP_KEY": 2, "CAS_CAPA": 12, "positions": [
    {"POS_NUM": 1, "CAB1_KEY": "EVI-CB000000000030", "FIB1_NUM": 13, "PFON_KEY": 3, "POS_AFFECT": "ABONNE"}]},
   {"CAS_NUM": 2, "CTYP_KEY": 2, "CAS_CAPA": 12, "positions": [
    {"POS_NUM": 1, "CAB1_KEY": "EVI-CB000000000030", "FIB1_NUM": 19, "CAB2_KEY": "EVI-CB000000000010", "FIB2_NUM": 1,
     "PFON_KEY": 1, "POS_CONNECTEUR": "SFU"}]}],
  "mesures": [
   {"MES_CODE_EXT": "EVI-M-CDI-2-02HG-1015_MSB-55-1550-OE", "MMET_KEY": 1, "CAB_KEY": "EVI-CB000000000088",
    "FIB_NUM": 55, "MES_CABLE": "CDI-2-02HG-1015_MSB", "MES_FIBRE": 55, "MES_ORIGINE": "SRO", "MES_EXTREMITE": "PBO",
    "MES_LAMBDA": 1550, "MES_SENS": "OE", "MES_LNG": 1168.112, "MES_PERTE": 0.572, "MES_EVT_MAX": 0.109,
    "MES_PENTE_MAX": 0.188, "MES_ORL": 41.14, "MES_CONFORME": 1, "MES_APPAREIL": "MTS 4000 V2",
    "MES_DATE": "2026-04-06T10:39:45Z"}]}]}
```

```json
{"type": "Feature", "id": "EVI-CB000000000002", "geometry": null,
 "properties": {
  "classe": "CAB", "CAB_LIB": "CDI-2-02HG-2060", "MAT_KEY": 326, "CFON_KEY": 7, "CAB_CAPA": 48, "CAB_MODULO": 12,
  "NOE1_KEY": "EVI-ND000000000377", "NOE2_KEY": "EVI-ND000000000373", "EQU1_KEY": "EVI-BP000000000480",
  "EQU2_KEY": "EVI-BP000000000476", "CAB_LNG": 69.29, "AVCT_KEY": 1, "PROPRIO_KEY": 10,
  "passages": [{"LIN_KEY": "EVI-CM000000000142", "CD_KEY": "EVI-CD000000000171", "CDC_RANG": 1, "PAS_RANG": 1},
               {"LIN_KEY": "EVI-CM000000000141", "CD_KEY": "EVI-CD000000000170", "CDC_RANG": 1, "PAS_RANG": 2}],
  "lovages": [{"NOE_KEY": "EVI-ND000000000373", "LOV_LNG": 3.0}, {"NOE_KEY": "EVI-ND000000000377", "LOV_LNG": 2.0}],
  "fibres": [{"FIB_NUM": 1, "FIB_TUBE": 1, "FIB_NUM_TUBE": 1, "COUL_KEY": 1, "TUBE_COUL_KEY": 1, "FIB_TYPE": "G657"},
             {"FIB_NUM": 2, "FIB_TUBE": 1, "FIB_NUM_TUBE": 2, "COUL_KEY": 2, "TUBE_COUL_KEY": 1, "FIB_TYPE": "G657"}]}}
```

| Clé | Contenu |
| --- | --- |
| `opt.equipements[].EQU_KEY` | Équipement du nœud (`EQU_CODE_EXT` de `inf.equipements`) dont l'entrée décrit le contenu optique ; une entrée au plus par équipement |
| `EQO_LIB`, `OTYP_KEY`, `EQO_CAPA` | Étiquette terrain, fonction (`DEF_OPT_EQUIP_TYPE` : BPE, PBO, PTO, DTI, baie, tiroir), capacité en fibres |
| `EQO_PARENT_KEY` | Baie d'un tiroir : `EQU_CODE_EXT` de l'équipement de la baie, dans le même nœud |
| `cassettes[].CAS_NUM` | Numéro de la cassette dans l'équipement ; la cassette 0 regroupe les fibres en passage hors platines |
| `positions[]` | Fibre entrante (`CAB1_KEY`, `FIB1_NUM`) et fibre sortante (`CAB2_KEY`, `FIB2_NUM`) : deux pour une épissure ou un passage, une pour une attente ou un connecteur ; fonction `PFON_KEY` (`DEF_POS_FONCTION`), connecteur `POS_CONNECTEUR`, affectation `POS_AFFECT` (`ABONNE`, `DEPART`, `PASSAGE`, `RESERVE`, `MORTE`…) |
| `mesures[]` | Mesures prises à l'équipement (`EQU_KEY` de `OPT_MESURE`) : fibre mesurée (`CAB_KEY`, `FIB_NUM`, première fibre de la route), fibre telle que nommée par l'appareil (`MES_CABLE`, `MES_FIBRE`), longueur d'onde, sens, longueur, perte, conformité aux seuils |
| `CAB` : `NOE1_KEY`, `NOE2_KEY` | Extrémités amont et aval ; `EQU1_KEY`, `EQU2_KEY` : équipements qui les raccordent, parmi ceux de ces nœuds ; câble de raccordement : `ADR2_KEY` (adresse desservie) au lieu de `NOE2_KEY` |
| `passages[]` | Linéaire du parcours (`LIN_KEY`), rang depuis `NOE1_KEY` (`PAS_RANG`) et ligne de l'infra qui porte le câble : câble porté `PCB_RANG` de la portée, ou câble de conduite `CD_KEY` + `CDC_RANG`, pas les deux |
| `lovages[]` | Réserve laissée au nœud `NOE_KEY`, longueur `LOV_LNG` (m) |
| `fibres[]` | Rang `FIB_NUM`, tube `FIB_TUBE` et rang dans le tube `FIB_NUM_TUBE`, couleurs de la fibre et du tube (`COUL_KEY`, `TUBE_COUL_KEY`, code `DEF_FO_COULEUR`) ; au-delà de 12 tubes, la couleur du tube revient avec (`FIB_TUBE` − 1) / 12 bagues noires |

Règles :
- **câbles d'une zone** : ceux qui ont une extrémité ou un passage dans la zone, ou une fibre dans une position ou une
  mesure d'un équipement de la zone, et les câbles de raccordement des adresses de la zone (le raccordement suit
  aussi son PBO, `NOE1_KEY`) ; leurs extrémités situées ailleurs sont publiées `hors_zone`, l'adresse desservie par un
  câble publié est publiée. Un passage ou un
  lovage peut viser un linéaire ou un nœud d'une autre zone, absent du paquet (parcours hors zone) ;
- **nœud hors zone** : publié sans son espace `opt`, qui relève de sa zone (sans quoi ses positions appelleraient les
  câbles de proche en proche jusqu'au réseau entier) ;
- **routes** : les routes optiques (`OPT_ROUTE`, suite des fibres du tiroir de départ au PBO) restent au BE ; la
  route d'une mesure (`RTE_KEY`) n'est pas publiée. Le terminal retrouve le chemin d'une fibre de proche en proche par
  les positions ;
- **fichiers** : la photo d'un équipement suit le nœud (`ENTITE` `INF_EQUIPEMENT`, `EQU_KEY`, galerie de
  l'équipement : voir [Fichiers et visuels](#fichiers-et-visuels)), celle d'un câble le câble (`OPT_CABLE`) ; les traces de mesure (`.sor`) et les plans de boîte (PDF, tableurs) restent au BE ;
- **terminal** : contenu optique en lecture (liens fibres d'un équipement, câbles raccordés, mesures, locaux
  desservis) ; l'objet retourné porte son `opt` et un câble ses éléments tels que publiés. La saisie sur le terrain
  (constat d'un câble tiré, d'une épissure) reste à définir.

### Câbles de raccordement

Depuis la 0.5.0 (module optique 0.3.0), un câble de raccordement final (fonction `RA` de `DEF_CAB_FONCTION`) mène du
PBO à la boîte aux lettres de l'adresse desservie. La BAL est portée par l'adresse, pas par un nœud : son extrémité
aval est l'adresse (`ADR2_KEY`), sans `NOE2_KEY`. Il ne suit pas les linéaires du réseau (portées, conduites) : il
porte son **tracé propre**, seule exception aux câbles sans géométrie, orienté du PBO vers l'adresse, sans passages.
Câble du DOE Evicom (tracé de la base FibReady, à poser) :

```json
{"type": "Feature", "id": "EVI-FBT-RAC-232",
 "geometry": {"type": "LineString", "coordinates": [[5.8717896, 49.4911965], [5.871807, 49.4909642]]},
 "properties": {
  "classe": "CAB", "CAB_LIB": "RAC-2-02HG-1015-01", "CFON_KEY": 8, "CAB_CAPA": 1, "CAB_MODULO": 2,
  "NOE1_KEY": "EVI-ND000000000407", "EQU1_KEY": "EVI-BP000000000516", "ADR2_KEY": "EVI-AD000000000133",
  "CAB_LNG": 31.16, "AVCT_KEY": 2, "CAB_COMMENT": "Raccordement FibReady, pose en fourreau"}}
```

Les locaux desservis par un PBO (`imb.locaux[].EQU_KEY`) restent l'affectation de la zone de desserte du PBO ; le
câble de raccordement en est le tracé physique, quand il est connu (363 au DOE Evicom, du PBO à 337 adresses).

## Fichiers et visuels

Une photo appartient à un **visuel** : vue attendue (`VUE_CODE`, référentiel `DEF_VUE` du noyau) ou visuel libre
créé sur le terrain (`VIS_CODE`, titre `VIS_LIB`), jamais les deux. Depuis la 0.4.0, deux galeries :
- **galerie du support** : photos du nœud et de ses éléments autres que les équipements (`ENTITE` `PRJ_NOE`,
  `CHB_CHAMBRE`, `POT_CONTROLE`…) ; vues attendues de son type et de ses types parents (`DEF_VUE.TYPE_KEY`) ;
- **galerie d'un équipement** : photos d'`ENTITE` `INF_EQUIPEMENT`, portées par le nœud de l'équipement et
  désignant l'équipement par `EQU_KEY` (`EQU_CODE_EXT`, présent dans `inf.equipements` du nœud) ; vues attendues
  `DEF_VUE.VUE_ENTITE` = `INF_EQUIPEMENT` (module optique 0.2.0 : boîtier fermé `FERME`, boîtier ouvert `OUVERT`,
  `CASSETTES`, mesures photométriques `MESURES`, aucune obligatoire : un équipement préexistant n'a pas à être
  renseigné en détail).

```json
{"ENTITE": "INF_EQUIPEMENT", "EQU_KEY": "EVI-BP000000000467", "VUE_CODE": "OUVERT",
 "FIC_CODE_EXT": "EVI-6f9b0dc2-20cb-5979-95ae-175f9419efaa", "FIC_RANG": 1, "FIC_PRINCIPALE": 1,
 "FIC_NOM": "SRO-2-02HG_PBO-2-02HG-2100__1_04.jpg", "FIC_TYPE": "image/jpeg", "...": "..."}
```

Une photo nouvelle d'un équipement, sur le terminal, porte `ENTITE` `INF_EQUIPEMENT` et `EQU_KEY`, y compris pour
un équipement ajouté pendant la même intervention (créé dans `inf.equipements` de l'objet retourné). Jusqu'au noyau
0.2.0, les supports avaient une vue « Boîtier optique » (`BOITIER`) ; un support peut porter plusieurs équipements :
la reprise du projet (`tools/schema/projet.py migrer`, étape 0.5.0) range ses photos dans le visuel libre « Boîtier
optique » de leur équipement s'il en est déjà le porteur ou si le nœud n'en porte qu'un, sinon dans celui du
support.

## Immeubles et locaux

Depuis la 0.3.0 (module immeuble 0.1.0), l'espace `imb` d'une adresse porte les colonnes de `IMB_ADRESSE` (immeuble,
logements, convention) et ses `locaux` (`IMB_LOCAL`), chacun desservi par son PBO (adresse du DOE Evicom, dates
omises) :

```json
"imb": {"HAB_KEY": 2, "IETAT_KEY": 1, "IAD_NB_LOG": 7, "IAD_NB_PRO": 0, "IAD_NB_PRISE_LOG": 7, "IAD_NB_PRISE_PRO": 0,
 "IAD_NEUF": 0, "IAD_BATCODE": "AD5420001007249", "IMPL_KEY": 7, "GEST_KEY": 1, "IAD_ACCORD_GEST": 0,
 "locaux": [{"LOC_CODE_EXT": "EVI-SF000000000013", "LTYP_KEY": 1, "RACCO_KEY": 1, "LOC_ESCALIER": "1",
             "LOC_ETAGE": "2", "LOC_LIB": "1", "EQU_KEY": "EVI-BP000000000518", "LOC_COMMENT": "COL-HAB"}]}
```

| Clé | Contenu |
| --- | --- |
| `HAB_KEY`, `IETAT_KEY` | Habitat (`DEF_IMB_HABITAT` : pavillon, immeuble), état (`DEF_IMB_ETAT` : cible, signé, en cours de déploiement, déployé, abandonné) |
| `IAD_NB_LOG`, `IAD_NB_PRO` | Logements et locaux professionnels ; prises `IAD_NB_PRISE_LOG`, `IAD_NB_PRISE_PRO` |
| `GEST_KEY`, `IAD_CONV_DATE`, `IAD_ACCORD_GEST` | Gestionnaire (`DEF_ORGANISME`), signature de la convention, accord du gestionnaire |
| `locaux[].LOC_CODE_EXT` | Identifiant du local, unique dans le paquet |
| `locaux[].LTYP_KEY`, `RACCO_KEY` | Type (`DEF_LOC_TYPE`) et état de raccordement (`DEF_LOC_RACCO`) |
| `locaux[].EQU_KEY` | PBO qui dessert le local (`EQU_CODE_EXT`) ; peut viser un équipement d'une autre zone, absent du paquet |

Règles : `imb` est absent d'une adresse sans immeuble ni local ; sur le terminal, il est en lecture (carte « Immeuble
et BAL » de l'adresse, locaux desservis d'un PBO) et renvoyé tel quel avec l'adresse. Le relevé BAL sur le terrain
reste à définir avec l'activité correspondante.

## Commentaires

`commentaires` porte, dans les propriétés d'un nœud, d'un linéaire, d'une adresse ou d'un câble, au même niveau que `fichiers`,
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
- seul le journal d'un nœud, d'un linéaire, d'une adresse ou d'un câble a sa place dans le paquet : `publier`
  n'écrit pas une entrée rattachée à une autre table (zone, chambre…) et le signale (nombre par table, sur la sortie
  d'erreur) ;
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
- le terminal n'affiche aujourd'hui que le journal des supports (nœuds) : celui d'un linéaire, d'une adresse ou d'un
  câble est conservé et renvoyé tel quel avec l'objet.

## Modification sur le terminal

- L'**objet** (nœud, linéaire, adresse ou câble avec tout ce qu'il porte) est l'unité de modification, de stockage
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
- Objets : `FeatureCollection` ; `id` présent et unique ; `classe` `NOE`, `LIN`, `ADR` ou `CAB`, géométrie du type
  attendu (Point, LineString, Point ; pour un câble `null` ou LineString, son tracé propre) ; `statut` absent d'une publication, `C`, `M` ou `A` dans
  un retour ; chaque `fichier` cité est dans l'archive.
- Fichiers, en publication comme en retour : une photo d'équipement (`ENTITE` `INF_EQUIPEMENT`) est portée par un
  nœud et désigne par `EQU_KEY` un équipement de son `inf.equipements` ; `EQU_KEY` est absente des autres photos ;
  `VUE_CODE` est une vue de son porteur (du support ou de l'équipement : `DEF_VUE` du paquet, d'après les manifestes
  du schéma pour un retour, qui n'a pas de référentiels), jamais avec un `VIS_CODE`.
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
  dessinée, n'est pas bornée. Une conduite a au plus une position non abandonnée dans la chambre, toutes faces
  confondues (aucun écart dans les données existantes : 10 414 positions à Nancy, 514 dans le jeu d'essai).
- Conduites, en publication comme en retour (l'objet porte toutes ses conduites) : module `infra` de l'en-tête en
  0.2.0 au moins, présent dès qu'un objet a des conduites ; chaque ligne de `cables` d'une
  conduite a un `CDC_RANG` entier, unique dans la conduite, et un `CDC_NB` entier d'au moins 1 ; `CDC_NATURE` est
  absente ou vaut `FO` ou `CU` ; un `CD_PARENT_KEY` désigne une autre conduite de la même liste `conduites` (même
  porteur), qui n'a pas elle-même de `CD_PARENT_KEY` (un seul niveau).
- Optique, en publication comme en retour : modules `optique` et `immeuble` dans l'en-tête dès qu'un objet porte
  leurs données (câble, `opt`, `imb`) ; chaque entrée de `opt.equipements` désigne par `EQU_KEY` un équipement de
  `inf.equipements` du même nœud, une seule fois ; `CAS_NUM` entier unique dans l'équipement ; chaque position porte au
  moins une fibre, chaque fibre (position, mesure) un câble et un rang entier ensemble ; une mesure a son
  `MES_CODE_EXT`. Câble : `NOE1_KEY`, et `NOE2_KEY` ou l'adresse desservie `ADR2_KEY` ; passages à `LIN_KEY` unique, `PAS_RANG` entier ou absent, câble
  porté (`PCB_RANG` entier) ou câble de conduite (`CD_KEY` et `CDC_RANG` entier ensemble), pas les deux ; lovages à
  `NOE_KEY` unique ; `FIB_NUM` entier unique. Locaux : `LOC_CODE_EXT` présent et unique dans le paquet.
- Publication seulement (un retour ne porte que les objets modifiés, ses références peuvent viser des objets du
  BE) : extrémités `NOE1_KEY` / `NOE2_KEY` de chaque linéaire et de chaque câble (sauf `NOE2_KEY` d'un câble de
  raccordement) et adresses `ADR_KEY`, `ADR2_KEY` présentes dans le paquet ; conduite de chaque position de chambre présente ; équipements `EQU1_KEY` / `EQU2_KEY` d'un câble parmi
  ceux de son nœud `NOE1_KEY` / `NOE2_KEY` ; passage sur un linéaire du paquet : câble porté (`PCB_RANG`) parmi ceux
  de sa portée, câble de conduite (`CD_KEY`, `CDC_RANG`) parmi ceux d'une conduite du linéaire ; fibre de chaque
  position et de chaque mesure : câble du paquet, rang parmi ses `fibres` ; référentiels de chaque module de
  l'en-tête présents.

Le contrôle des commentaires par rapport au BE (conflits, identité à l'état publié) relève de l'intégration
(étapes 2 et 3), qui dispose de la base.

## `referentiels.json`

```json
{"noyau": {"DEF_TYPE": [{"TYPE_ID": 13, "TYPE_CODE": "POT", "TYPE_LIB": "Poteau", "...": "..."}]},
 "infra": {"MAT_CABLE": [{"MAT_ID": 1, "MAT_LIB": "5/9", "CAB_TYPE": "Telecom", "CAB_USAGE": "BRANCHEMENT"}]},
 "chambre": {"MAT_CHAMBRE": []}, "poteau": {"MAT_POTEAU": []}}
```

Toutes les tables `DEF_*` et `MAT_*` des manifestes des modules du paquet, valeurs nulles omises, dont, pour le noyau,
les vues attendues (`DEF_VUE` : d'un type de support, `TYPE_KEY`, ou d'un équipement, `VUE_ENTITE`), pour l'infra,
les états des conduites (`DEF_CD_ETAT`) et les diamètres normalisés (`DEF_CD_DIAM`, depuis le module infra 0.2.0), pour
l'optique le code couleur des fibres (`DEF_FO_COULEUR`, `COUL_RGB` en `#RRGGBB`) et les fonctions des positions
(`DEF_POS_FONCTION`), pour l'immeuble les types et états de raccordement des locaux. Les référentiels ne sont gérés
qu'au BE.

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
- Terminal antérieur au module infra 0.2.0 : il refuse un paquet 0.2.0 s'il contrôle la version du module ; sinon il
  recopierait les `cables` tels quels, sans `CDC_RANG` pour un câble ajouté, sans recalculer l'état ni `CD_OCCUP`.
  `verifier` refuse un retour dont l'en-tête porte un module infra antérieur à 0.2.0 et tout câble sans `CDC_RANG`
  entier ; un tel terminal ne doit plus servir. Le terminal 0.2.0 refuse les paquets 0.1.0 encore en circulation
  (`docs/essai/paquets`), à republier depuis un projet repris.
- Diamètres intérieurs de 20 et 24 mm (`DEF_CD_DIAM` : 16 et 20 mm) : à confirmer, absents de l'abaque de FOA.
- Saisie optique et BAL sur le terminal (constat d'un câble tiré dans une portée ou une conduite, épissure réalisée,
  relevé des boîtes aux lettres) : objet modifié, règles d'intégration du sas et contrôle des positions à définir avec
  les activités retour fin de travaux et relevé BAL ; jusque-là, `opt`, `imb` et les câbles sont renvoyés tels que
  publiés.
- Taille : le paquet Evicom (1 SRO, 99 câbles, 6 000 fibres, 8 583 positions) fait 3,9 Mo de GeoJSON, 0,3 Mo
  compressé ; les fibres, déductibles de la capacité et du modulo dans le cas courant, pourraient n'être publiées
  qu'en écart au code couleur si les zones grossissent.
