# GraceTHD v3 — base SpatiaLite reconstituée

Aucune base SpatiaLite GraceTHD v3 n'est publiée : les dépôts `GraceTHD-community` sur GitHub s'arrêtent à la
v2.0.1 (et 2.0.2-rc1), et le standard CNIG v3.0 (juin 2020) n'est qu'un projet. `build_gracethd_v3.py`
reconstitue une base vide à partir des gabarits v3 utilisés par l'export GraceTHD de FibReady.

## Construction

```powershell
$data = "o:\C#\FibReady_net.10\FibReady\Plugins\Export\PlugExpGrace\Sources\bin\Debug\Data"
python -I tools\gracethd\build_gracethd_v3.py "$data\shapes_v3" "$data\gracethd_v2.0.1.sqlite" `
    docs\gracethd\gracethd_v3.sqlite "C:\Program Files\QGIS 3.44.7\bin"
```

Prérequis : Python 3 et le `mod_spatialite` de QGIS. La base produite (`docs/gracethd/`) n'est pas versionnée.

## Sources des définitions

| Élément | Source |
| --- | --- |
| Tables et colonnes (ordre compris) | Gabarits v3 : en-têtes CSV, champs DBF des shapefiles |
| Types, NOT NULL, clés primaires, références | Base v2.0.1, y compris sous un autre préfixe : `t_ltech` (`lt_`) → `t_local` (`lc_`), `t_sitetech` → `t_site`, `t_ptech` (`pt_`) → `t_pointaccueil` (`pa_`), `t_cheminement` (`cm_`) → `t_tranchee` (`tr_`), `t_cab_cond` → `t_cab_chem` |
| Colonnes propres à la v3 | Règles explicites du script (`NEW_COLUMNS`, suffixes `_perirec`, `_abandon`, `_codtemp`), sinon types `t_adresse` pour les champs d'adresse, sinon champ DBF |
| Listes `l_*` | Gabarits v3 ; les listes vides en v3 sont complétées par la liste v2 équivalente |
| Géométries | EPSG:2154 ; zones et empreintes en MULTIPOLYGON comme en v2 ; index spatiaux |

## Limites

- Les gabarits sont ceux d'un donneur d'ordre : le code FibReady signale des variantes (« version engelvin »,
  « version axione », champs `tr_pa` / `tr_pacoex1`). Ce n'est pas la v3 CNIG officielle.
- Les références des colonnes nouvelles (`cb_bp1`, `bp_lc_code`, `tr_pa1`, `cc_cm_code`…) sont déduites de leur
  nom ; la clé de `t_cab_chem` est (`cc_cb_code`, `cc_cm_code`).
- `l_position_usetype` reste vide (absente de la v2).
- Références v2 abandonnées faute de cible en v3 : `l_immeuble_type`, `t_document`.
- Pas de vues (la v2 en avait 33, à redéfinir si besoin).
