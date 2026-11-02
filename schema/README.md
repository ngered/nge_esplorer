# Schéma BE NgeEsPlorer

Modèle mixte GraceTHD v2 (séparation géométrie / métier) et FOA Explorer (identifiants, catalogues `MAT_*`).
Un dossier par domaine : `manifest.json` + scripts SQL. Décisions et contexte : [docs/echanges.md](../docs/echanges.md) §11.

| Domaine | Fichier | Contenu |
| --- | --- | --- |
| [noyau](noyau/) | `noyau.sqlite` (SpatiaLite, EPSG:2154) | Projet, modules, types, référentiels communs, zones, adresses, nœuds, linéaires, interventions, fichiers, vues photographiées |
| [infra](infra/) | `infra.sqlite` | Conduites et sous-tubage, occupation par câbles, portées et câbles portés, matériel sur support ; catalogues câbles, COMAC, équipements |
| [chambre](chambre/) | `chambre.sqlite` | Chambres, faces, masques logiques, positions des conduites (miroir) ; catalogue `MAT_CHAMBRE` |
| [poteau](poteau/) | `poteau.sqlite` | Poteaux, contrôles ; catalogue `MAT_POTEAU` (dont codes GESPOT) |

## Conventions

- `XXX_ID` clé primaire (entier long auto-incrémenté), `XXX_KEY` clé étrangère préfixée par l'entité visée
  (`NOE_KEY`, `LIN_KEY`, `MAT_KEY`), rôle en préfixe quand il y a plusieurs références (`NOE1_KEY`, `PROPRIO_KEY`).
- `XXX_CODE_EXT` : identifiant stable, unique dans le projet, seul identifiant échangé (GeoJSON, synchronisation).
- `XXX_LIB` : libellé terrain (n° de chambre, n° d'appui Orange) ; aucune unicité.
- Traçabilité : `DATE_CREA`, `DATE_MODIF`, `SRC_MODIF`, `DATE_ABD`, `SRC_ABD` (abandon daté plutôt que suppression) ;
  géolocalisation : `GEOL_QLT`, `GEOL_MOD_KEY`, `GEOL_CLASSE_KEY`, `GEOL_SRC`. Dates ISO 8601 UTC.
- Toutes les géométries sont dans le noyau (`GEOMETRY`) ; les modules ne contiennent que des tables attributaires.
- Les types (`DEF_TYPE`) reprennent les identifiants FOA quand ils existent (13 poteau, 16 chambre, 30 façade…) ;
  les vues d'un type valent pour ses sous-types.

## Modules et intégrité

Le noyau attache chaque module sous son code (`ATTACH … AS chambre`). SQLite ne contrôle pas les clés étrangères
entre bases : les références vers une autre base sont déclarées dans `references` du manifeste, et l'ouverture du
projet crée pour chacune des triggers `TEMP` (refus d'une valeur inconnue à l'insertion ou à la mise à jour, refus
de supprimer une cible référencée). Les références internes à un fichier sont de vraies clés étrangères. Journal
`DELETE` imposé (pas de WAL) pour que les transactions sur plusieurs fichiers restent atomiques.

Le manifeste déclare aussi les dépendances, les types, les entités (porteuses de fichiers et d'interventions), les
vues photographiées, l'espace GeoJSON et la correspondance GraceTHD.

## Construction et essai

```powershell
python -I tools\schema\projet.py construire docs\essai\projet_vide `
    c:\NoDrive\Documents\Etudes\essonne\09_DOU_12-13_FOA_EXP.db "C:\Program Files\QGIS 3.44.7\bin" --essai
```

[tools/schema/projet.py](../tools/schema/projet.py) est l'implémentation de référence de la future bibliothèque
noyau C# : construction, ouverture (attachement, dépendances, triggers d'intégrité), recherche d'orphelins, et un
scénario d'essai (deux chambres reliées par une conduite vue des deux côtés, deux poteaux et leur portée, une
façade, photo, intervention, refus attendus), annulé à la fin.

Corrections à l'import des catalogues FOA :
- `MAT_CABLE` : 132 câbles sans `MAT_ID` reçoivent un identifiant ; le lien COMAC n'est posé que par le nom
  (68 câbles) ; les 64 clés COMAC FOA sans équivalent (câbles optiques L1092…, L1047…) restent dans `COMAC_FOA` ;
  `CAB_USAGE` (réseau ou branchement, indicatif, pour le trait des flèches de la rosace) est déduit de la
  légende Hirondelle : branchement pour 5/9, 5/10 et les torsadés BT 2 ou 4 conducteurs, réseau pour le cuivre
  FT 97 / 98 / 99 et les autres câbles BT, non renseigné pour les optiques ;
- `MAT_POTEAU` : deux mâts lorrains sans libellé reçoivent leur code (`MLX`, `MLJ`) ;
- fabricants 14 à 18 cités par les catalogues mais absents de `DEF_FABRICANTS` : créés « à compléter » ;
  fabricant 0 → vide.

Câbles portés (`INF_PORTEE_CABLE`), d'après le guide Enedis-MOP-RES_010E (avril 2024) : la **nappe** est
l'ensemble des câbles d'une même traverse sur la portée (3 traverses télécom au plus sur un appui Enedis) →
`PCB_NAPPE` = n° de traverse ; la **tension** est standard selon la zone (`STD_AGGLO`, `STD_ECART`, colonnes
`TENSION_CONS_RIGIDE_AGGLO` / `_ECART` de `MAT_CAB_COMAC`) ou déduite d'une flèche réelle relevée avec la
température ambiante (`RELEVE` + `PCB_FLECHE`, `PCB_TEMP`).

## Points ouverts

- Câbles portés : longueur par câble ou par portée.
- Table COMAC complète pour les câbles optiques (clés `COMAC_FOA`) : fournie plus tard.
- Règle de complétude du poteau.
