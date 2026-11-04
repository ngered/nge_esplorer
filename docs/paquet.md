# Paquet de zone — format d'échange GeoJSON (version 0.1.0)

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
| `fichiers/<FIC_CODE_EXT>.<ext>` | Photos et pièces jointes | Sur option | Fichiers nouveaux |

## En-tête `paquet.json`

```json
{
 "format": "nge-esplorer-paquet",
 "version": "0.1.0",
 "sens": "PUBLICATION",
 "date": "2026-10-31T02:46:39Z",
 "projet": {"code": "ESSAI", "lib": "Jeu d'essai chambres et poteaux", "modele": "0.1.0"},
 "zone": {"code": "GRACE", "lib": "Export GraceTHD de test", "emprise": [2.888, 45.634, 2.923, 45.655]},
 "modules": {"noyau": "0.1.0", "infra": "0.1.0", "chambre": "0.1.0", "poteau": "0.1.0"},
 "effectifs": {"NOE": 229, "LIN": 228, "ADR": 0, "fichiers": 0}
}
```

Un paquet de **retour** (`"sens": "RETOUR"`) ajoute :
- `base` : la `date` du paquet de publication sur lequel le terminal a travaillé ;
- `intervention` : colonnes de `PRJ_INTERVENTION` (`INT_CODE_EXT`, `ACT_CODE`, `INT_COMMANDE`, `INT_AUTEUR`,
  `INT_TERMINAL`, `DATE_DEBUT`, `DATE_FIN`, `INT_COMMENT`).

`version` suit le versionnement sémantique : un changement de version majeure rend le paquet illisible par une
application plus ancienne. Le terminal refuse un paquet dont un module manque ou a une version majeure différente
de la sienne.

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
| `chb` | nœud | `CHB_CHAMBRE`, avec `faces` (`CHB_FACE`, chacune avec ses `positions`) et `masques` (`CHB_MASQUE_LOGIQUE`) |
| `pot` | nœud | `POT_POTEAU`, avec `controles` (`POT_CONTROLE`) |
| `inf` | nœud | `equipements` (`INF_EQUIPEMENT`) et, dans une chambre, `conduites` sans destination connue (alvéole sans miroir : `INF_CONDUITE` rattachée par `NOE_KEY`, sans linéaire) |
| `inf` | linéaire | `conduites` (`INF_CONDUITE`, chacune avec ses `cables` : `INF_CD_CABLE`) et `portee` (`INF_PORTEE`, avec ses `cables` : `INF_PORTEE_CABLE`) |
| `fichiers` | objet | `PRJ_FICHIER` de l'objet et de ses éléments : `ENTITE` (table porteuse), `VUE_CODE` (visuel attendu) ou `VIS_CODE` / `VIS_LIB` (visuel libre), colonnes du fichier ; ordre de la galerie `FIC_RANG`, photo de référence `FIC_PRINCIPALE` ; `fichier` = chemin dans le paquet s'il y est inclus |

Identification des éléments imbriqués : par leur `CODE_EXT` quand ils en ont un (conduite, équipement, fichier),
sinon par leur clé naturelle dans le parent : face `FAC_CODE`, position `CD_KEY` dans la face, masque logique
`MLOG_NUM` (une position y renvoie par `MLOG_NUM`), câble de portée `PCB_RANG`, contrôle `DATE_CTL`.

Conventions métier rappelées :
- angles de portée `PRT_ANG1` / `PRT_ANG2` : azimut au nœud `NOE1_KEY` / `NOE2_KEY`, en grades, 0 = nord, sens
  horaire ; `POT_ANG_CARTO` (axe du poteau) dans la même convention ;
- dates ISO 8601 UTC ; traçabilité GraceTHD : `DATE_CREA`, `DATE_MODIF`, `SRC_MODIF`, `DATE_ABD`, `SRC_ABD`.

## Modification sur le terminal

- L'**objet** (nœud, linéaire ou adresse avec tout ce qu'il porte) est l'unité de modification, de stockage
  (une ligne par objet en base chiffrée) et de conflit.
- Toute modification remplace l'objet entier, met à jour `DATE_MODIF` et `SRC_MODIF` (compte abonné) et pose
  `statut` (`C` si l'objet a été créé sur le terminal, sinon `M`).
- **Pas de suppression** : l'abandon pose `DATE_ABD` / `SRC_ABD` et `statut` = `A`.
- Créer une portée vers une destination nouvelle crée deux objets : le nœud de destination (`C`) et le linéaire
  (`C`).

## Intégration d'un retour (sas de contrôle)

1. Contrôle de structure (`verifier`) et des versions de modules.
2. Conflit si un objet du retour a été modifié au BE après `base` (`DATE_MODIF` BE > `base`) : arbitrage
   manuel.
3. Résolution des `CODE_EXT` en `XXX_ID`, aplatissement dans les tables, remplacement des éléments imbriqués de
   chaque objet modifié.
4. Enregistrement de l'intervention et de ses objets (`PRJ_INTERVENTION`, `PRJ_INT_OBJET`).

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
