"""Construction, ouverture et contrôle d'un projet NgeEsPlorer côté BE (noyau SpatiaLite + modules attachés).

Implémentation de référence de la future bibliothèque noyau C# :
- construire : crée noyau.sqlite et un fichier par module à partir de schema/<module>/ (manifeste + SQL),
  importe les référentiels FOA Explorer, enregistre types, entités et vues des modules dans le noyau ;
- ouvrir : attache les modules (nom de schéma = code du module) en refusant un fichier absent, contrôle les
  dépendances, impose le journal DELETE, crée les triggers TEMP d'intégrité entre bases à partir des références
  des manifestes ;
- orphelins : liste les références entre bases sans cible ;
- migrer : reprise d'un projet construit avec un modèle antérieur, étapes en attente appliquées dans l'ordre, en
  une seule transaction : 0.2.0, journal des commentaires (champs libres NOE_COMMENT, CHB_COMMENT et POT_COMMENT
  repris dans PRJ_COMMENTAIRE, colonnes retirées) ; 0.3.0, masques métriques (faces et positions des chambres
  converties des cellules FOA en m). migrer-commentaires, ancien nom de la commande, en est un simple alias.

Usage :
  python -I tools/schema/projet.py construire <dossier> <base FOA> <dossier QGIS bin> [--essai]
  python -I tools/schema/projet.py migrer <dossier projet> <dossier QGIS bin>
"""
import json, os, re, sqlite3, sys, uuid
from collections import Counter
from datetime import datetime, timedelta, timezone

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')
RACINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCHEMA = os.path.join(RACINE, 'schema')
MODELE_VERSION = '0.3.0'        # 0.2.0 : journal des commentaires (PRJ_COMMENTAIRE) ; 0.3.0 : masques métriques
FORMAT_DATE = '%Y-%m-%dT%H:%M:%SZ'

# Fenêtre de dessin d'une face dans FOA Explorer : 9 x 12 cellules de 6,3 x 4,5 unités, 1 unité = 1 cm, soit
# 0,567 x 0,54 m quelles que soient les dimensions de la chambre. Repère des masques jusqu'au module chambre 0.2.0
# (positions en cellules) ; dimensions d'une face relevée dans FOA Explorer.
GRILLE_FOA = (9, 12)                # colonnes, lignes
CELLULE_FOA = (0.063, 0.045)        # largeur, hauteur d'une cellule (m)
FENETRE_FOA = (0.567, 0.54)         # largeur, hauteur de la fenêtre (m)
DECIMALES_MASQUE = 6                # dimensions des faces et positions en m, arrondies au micromètre


def manifestes():
    """Manifestes triés selon leurs dépendances (noyau d'abord)."""
    tous = {}
    for nom in os.listdir(SCHEMA):
        chemin = os.path.join(SCHEMA, nom, 'manifest.json')
        if os.path.isfile(chemin):
            m = json.load(open(chemin, encoding='utf-8'))
            m['dossier'] = os.path.join(SCHEMA, nom)
            tous[m['code']] = m
    ordre, vus = [], set()

    def visiter(code, pile=()):
        if code in vus:
            return
        if code in pile:
            raise ValueError(f'dépendance circulaire : {" → ".join(pile + (code,))}')
        if code not in tous:
            raise ValueError(f'module inconnu : {code}')
        for d in tous[code]['dependances']:
            visiter(d, pile + (code,))
        vus.add(code)
        ordre.append(tous[code])

    for code in sorted(tous):
        visiter(code)
    return ordre


def connecter(chemin, qgis_bin=None, spatial=False):
    con = sqlite3.connect(chemin, isolation_level=None)
    con.text_factory = lambda b: b.decode('utf-8', 'replace')
    if spatial:
        os.add_dll_directory(qgis_bin)
        os.environ['PATH'] = qgis_bin + os.pathsep + os.environ['PATH']
        os.environ.setdefault('PROJ_DATA', os.path.join(os.path.dirname(qgis_bin), 'share', 'proj'))
        con.enable_load_extension(True)
        con.load_extension('mod_spatialite')
    con.execute('PRAGMA journal_mode = DELETE')
    con.execute('PRAGMA foreign_keys = ON')
    return con


def executer_script(con, chemin):
    con.executescript(open(chemin, encoding='utf-8').read())


# Import des référentiels FOA Explorer ----------------------------------------------------------

def texte_foa(b):
    try:
        return b.decode('utf-8')
    except UnicodeDecodeError:
        return b.decode('cp1252')


def importer_foa(con, foa, ref, rapport):
    cols_cible = [r[1] for r in con.execute(f'PRAGMA table_info({ref["cible"]})')]
    cols_source = {r[1] for r in foa.execute(f'PRAGMA table_info({ref["source"]})')} | {'rowid'}
    corresp = {c: c for c in cols_cible if c in cols_source}
    corresp.update(ref.get('colonnes', {}))
    cibles = list(corresp)
    lignes = []
    for row in foa.execute(f'SELECT {", ".join(corresp[c] for c in cibles)} FROM {ref["source"]}'):
        lignes.append([v.strip() if isinstance(v, str) else v for v in row])
    if ref['cible'] == 'MAT_CABLE':
        lignes = corriger_mat_cable(con, cibles, lignes, rapport)
    if ref['cible'] == 'MAT_POTEAU':
        lignes = corriger_mat_poteau(cibles, lignes, rapport)
    con.executemany(f'INSERT INTO {ref["cible"]} ({", ".join(cibles)}) VALUES ({", ".join("?" * len(cibles))})',
                    lignes)
    rapport.append(f'{ref["cible"]} ← FOA {ref["source"]} : {len(lignes)}')
    if ref['cible'] == 'MAT_CABLE':
        usage_mat_cable(con, rapport)


def corriger_mat_cable(con, cibles, lignes, rapport):
    """FOA : 132 câbles sans MAT_ID ; COMAC_KEY ne correspond pas aux lignes de MAT_CAB_COMAC → lien posé
    uniquement par le nom du câble, la clé d'origine reste dans COMAC_FOA."""
    i_id, i_lib = cibles.index('MAT_ID'), cibles.index('MAT_LIB')
    i_comac, i_foa = cibles.index('COMAC_KEY'), cibles.index('COMAC_FOA')
    comac = {nom: cid for cid, nom in con.execute('SELECT COMAC_ID, COMAC_NOM FROM MAT_CAB_COMAC')}
    suivant = max((l[i_id] for l in lignes if l[i_id] is not None), default=0) + 1
    ids = lies = sans = 0
    for l in lignes:
        if l[i_id] is None:
            l[i_id], suivant, ids = suivant, suivant + 1, ids + 1
        l[i_comac] = comac.get(l[i_lib])
        lies += l[i_comac] is not None
        sans += l[i_comac] is None and l[i_foa] is not None
    rapport.append(f'MAT_CABLE : {ids} identifiants attribués ; COMAC rapproché par le nom pour {lies} câbles, '
                   f'{sans} câbles avec une clé COMAC FOA sans équivalent (conservée dans COMAC_FOA)')
    return lignes


def usage_mat_cable(con, rapport):
    """CAB_USAGE indicatif, d'après la légende de la rosace Hirondelle : branchement pour 5/9, 5/10 et les
    torsadés BT à 2 ou 4 conducteurs ; réseau pour le cuivre FT 97 / 98 / 99, le BT nu et les autres torsadés BT ;
    les autres câbles (optiques notamment) restent non renseignés."""
    con.execute("UPDATE MAT_CABLE SET CAB_USAGE = 'BRANCHEMENT' "
                "WHERE MAT_LIB IN ('5/9', '5/10') OR (CAB_TYPE = 'I' AND MAT_LIB GLOB 'BT [24][*]*')")
    con.execute("UPDATE MAT_CABLE SET CAB_USAGE = 'RESEAU' WHERE CAB_USAGE IS NULL "
                "AND ((CAB_TYPE = 'Telecom' AND MAT_LIB GLOB '9[789]-*') OR CAB_TYPE IN ('N', 'I'))")
    n = dict(con.execute('SELECT CAB_USAGE, COUNT(*) FROM MAT_CABLE GROUP BY CAB_USAGE').fetchall())
    rapport.append(f'MAT_CABLE : usage indicatif réseau {n.get("RESEAU", 0)}, branchement '
                   f'{n.get("BRANCHEMENT", 0)}, non renseigné {n.get(None, 0)}')


def completer_fabricants(dossier, qgis_bin, rapport):
    """Fabricants cités par les catalogues FOA mais absents de DEF_FABRICANTS : 0 = inconnu → NULL ;
    les autres identifiants sont créés « à compléter » pour ne pas perdre l'information."""
    con = ouvrir(dossier, qgis_bin, integrite=False)
    con.execute('BEGIN')
    for m in manifestes():
        for ref in m['references']:
            if ref['cible'] != 'noyau.DEF_FABRICANT.FAB_ID':
                continue
            s, t, c = schema_de(m['code']), ref['table'], ref['colonne']
            con.execute(f'UPDATE {s}.{t} SET {c} = NULL WHERE {c} = 0')
            for (fab,) in con.execute(f'SELECT DISTINCT {c} FROM {s}.{t} WHERE {c} IS NOT NULL AND {c} NOT IN '
                                      f'(SELECT FAB_ID FROM DEF_FABRICANT)').fetchall():
                con.execute('INSERT INTO DEF_FABRICANT (FAB_ID, FAB_LIB) VALUES (?, ?)',
                            (fab, f'À compléter (fabricant FOA n° {fab})'))
                rapport.append(f'DEF_FABRICANT : fabricant {fab} cité par {m["code"]}.{t} créé « à compléter »')
    con.execute('COMMIT')
    con.close()


def corriger_mat_poteau(cibles, lignes, rapport):
    """FOA : deux mâts lorrains sans MAT_LIB → code CAPFT_LIB, à défaut la description."""
    i_lib, i_cap, i_desc = cibles.index('MAT_LIB'), cibles.index('CAPFT_LIB'), cibles.index('MAT_DESC')
    corriges = []
    for l in lignes:
        if not l[i_lib]:
            l[i_lib] = l[i_cap] or l[i_desc]
            corriges.append(l[i_lib])
    if corriges:
        rapport.append(f'MAT_POTEAU : libellé repris du code pour {corriges}')
    return lignes


# Construction ----------------------------------------------------------------------------------

def construire(dossier, foa_chemin, qgis_bin, code_projet='ESSAI', lib_projet='Projet d\'essai'):
    os.makedirs(dossier, exist_ok=True)
    mods = manifestes()
    foa = sqlite3.connect(foa_chemin)
    foa.text_factory = texte_foa
    rapport = []
    for m in mods:
        chemin = os.path.join(dossier, m['fichier'])
        if os.path.exists(chemin):
            os.remove(chemin)
        con = connecter(chemin, qgis_bin, m['spatial'])
        for s in m['scripts']:
            executer_script(con, os.path.join(m['dossier'], s))
        con.execute('BEGIN')
        for ref in m.get('referentiels_foa', []):
            importer_foa(con, foa, ref, rapport)
        con.execute('COMMIT')
        con.close()

    noyau = connecter(os.path.join(dossier, 'noyau.sqlite'), qgis_bin, True)
    noyau.execute('BEGIN')
    noyau.execute('INSERT INTO SYS_PROJET (PRJ_CODE_EXT, PRJ_LIB, MODELE_VERSION) VALUES (?, ?, ?)',
                  (code_projet, lib_projet, MODELE_VERSION))
    for m in mods:
        noyau.execute('INSERT INTO SYS_MODULE (MOD_CODE, MOD_VERSION, MOD_FICHIER) VALUES (?, ?, ?)',
                      (m['code'], m['version'], m['fichier']))
        for t in m['types']:
            noyau.execute('INSERT INTO DEF_TYPE (TYPE_ID, TYPE_CODE, TYPE_LIB, TYPE_PARENT_KEY, TYPE_GEOM, MOD_CODE, '
                          'GRACE_CODE) VALUES (?, ?, ?, ?, ?, ?, ?)',
                          (t['id'], t['code'], t['lib'], t.get('parent'), t['geom'], m['code'], t.get('grace')))
        for e in m['entites']:
            noyau.execute('INSERT INTO DEF_ENTITE (ENT_TABLE, MOD_CODE, ENT_LIB) VALUES (?, ?, ?)',
                          (e['table'], m['code'], e['lib']))
        for v in m['vues']:
            type_id = noyau.execute('SELECT TYPE_ID FROM DEF_TYPE WHERE TYPE_CODE = ?', (v['type'],)).fetchone()[0]
            noyau.execute('INSERT INTO DEF_VUE (TYPE_KEY, VUE_CODE, VUE_LIB, VUE_ORDRE, VUE_OBLIGATOIRE, VUE_ACTION, '
                          'MOD_CODE) VALUES (?, ?, ?, ?, ?, ?, ?)',
                          (type_id, v['code'], v['lib'], v['ordre'], v['obligatoire'], v.get('action'), m['code']))
    noyau.execute('COMMIT')
    noyau.close()
    completer_fabricants(dossier, qgis_bin, rapport)
    return rapport


# Ouverture ---------------------------------------------------------------------------------------

def schema_de(code):
    return 'main' if code == 'noyau' else code


def ouvrir(dossier, qgis_bin, integrite=True):
    """Projet existant : un fichier absent est refusé, SQLite créerait sinon une base vide à sa place."""
    noyau = os.path.join(dossier, 'noyau.sqlite')
    if not os.path.isfile(noyau):
        raise RuntimeError(f'{noyau} absent : pas de projet dans ce dossier')
    con = connecter(noyau, qgis_bin, True)
    mods = {m['code']: m for m in manifestes()}
    attaches = {'noyau'}
    for code, fichier in con.execute("SELECT MOD_CODE, MOD_FICHIER FROM SYS_MODULE WHERE MOD_CODE <> 'noyau' "
                                     "ORDER BY MOD_ID").fetchall():
        manquantes = set(mods[code]['dependances']) - attaches
        if manquantes:
            raise RuntimeError(f'module {code} : dépendances non attachées {sorted(manquantes)}')
        chemin = os.path.join(dossier, fichier)
        if not os.path.isfile(chemin):
            con.close()
            raise RuntimeError(f'module {code} : fichier {fichier} absent du projet')
        con.execute('ATTACH DATABASE ? AS ' + code, (chemin,))
        con.execute(f'PRAGMA {code}.journal_mode = DELETE')
        attaches.add(code)
    if integrite:
        for code in attaches:
            for ref in mods[code]['references']:
                creer_triggers(con, code, ref)
    return con


def cible(ref):
    mod, table, col = ref['cible'].split('.')
    return schema_de(mod), table, col


def creer_triggers(con, code, ref):
    s, t, c = schema_de(code), ref['table'], ref['colonne']
    cs, ct, cc = cible(ref)
    nom = f'{code}_{t}_{c}'.lower()
    absente = f'NOT EXISTS (SELECT 1 FROM {cs}.{ct} WHERE {cc} = NEW.{c})'
    message = f'{t}.{c} : {ct} inconnu'
    for quand in ('INSERT', f'UPDATE OF {c}'):
        suffixe = 'ins' if quand == 'INSERT' else 'upd'
        con.execute(f'CREATE TEMP TRIGGER ref_{nom}_{suffixe} BEFORE {quand} ON {s}.{t} '
                    f'WHEN NEW.{c} IS NOT NULL AND {absente} '
                    f"BEGIN SELECT RAISE(ABORT, '{message}'); END")
    con.execute(f'CREATE TEMP TRIGGER ref_{nom}_del BEFORE DELETE ON {cs}.{ct} '
                f'WHEN EXISTS (SELECT 1 FROM {s}.{t} WHERE {c} = OLD.{cc}) '
                f"BEGIN SELECT RAISE(ABORT, '{ct} référencé par {code}.{t}.{c}'); END")


def orphelins(con):
    """Références sans cible des modules attachés : un module absent du projet (construit avant lui) est ignoré."""
    attaches = {r[1] for r in con.execute('PRAGMA database_list')}
    resultat = []
    for m in manifestes():
        if schema_de(m['code']) not in attaches:
            continue
        for ref in m['references']:
            s, t, c = schema_de(m['code']), ref['table'], ref['colonne']
            cs, ct, cc = cible(ref)
            n = con.execute(f'SELECT COUNT(*) FROM {s}.{t} x WHERE x.{c} IS NOT NULL AND NOT EXISTS '
                            f'(SELECT 1 FROM {cs}.{ct} y WHERE y.{cc} = x.{c})').fetchone()[0]
            resultat.append((f'{m["code"]}.{t}.{c} → {ref["cible"]}', n))
    return resultat


# Reprise d'un projet construit avec un modèle antérieur (migrer) ------------------------------------

# Étape 0.2.0 : champs libres du support remplacés par le journal : module, table, colonne, colonne du nœud porteur.
COMMENTAIRES_REPRIS = (('noyau', 'PRJ_NOE', 'NOE_COMMENT', 'NOE_ID'),
                       ('chambre', 'CHB_CHAMBRE', 'CHB_COMMENT', 'NOE_KEY'),
                       ('poteau', 'POT_POTEAU', 'POT_COMMENT', 'NOE_KEY'))
VERSION_JOURNAL = '0.2.0'           # version du modèle et des modules noyau, chambre et poteau qui introduit le journal
ZONE_GRACE = 'GRACE'                # zone de l'export GraceTHD du jeu d'essai (tools/essai/charger_essai.py)
# Étape 0.3.0 : masques métriques ; tables du module chambre reconstruites d'après son schéma, des parents aux enfants.
VERSION_MASQUES = '0.3.0'           # version du modèle et du module chambre qui passe les masques en m
TABLES_MASQUES = ('CHB_CHAMBRE', 'CHB_FACE', 'CHB_MASQUE_LOGIQUE', 'CHB_POSITION')


def version(v):
    return tuple(int(x) for x in v.split('.'))


def code_reprise(code_projet, code_noe, colonne):
    """COM_CODE_EXT d'une entrée reprise d'un ancien champ libre (colonne : NOE_COMMENT, CHB_COMMENT ou POT_COMMENT) :
    UUID v5 du projet, du nœud et de la colonne, le même pour la reprise d'un projet antérieur (reprendre_commentaires)
    et pour un chargement (tools/essai/charger_essai.py)."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f'urn:nge-esplorer:{code_projet}:{code_noe}:{colonne}'))


def auteur_reprise(origine):
    """Auteur d'une entrée reprise : « FOA » pour un texte venu de FOA Explorer, « BE » sinon."""
    return 'FOA' if origine == 'FOA' else 'BE'


def dernier_dimanche(annee, mois):
    fin = datetime(annee, mois + 1, 1) - timedelta(days=1)
    return fin - timedelta(days=(fin.weekday() + 1) % 7)


def heure_de_paris(locale):
    """Heure légale de Paris sans fuseau (datetime naïf) → UTC (datetime naïf), sans la base des fuseaux (tzdata) :
    règle européenne de l'heure d'été, en vigueur depuis 1996, UTC+2 du dernier dimanche de mars au dernier dimanche
    d'octobre à 1 h UTC, UTC+1 sinon. Heure sautée au printemps : lue en heure d'hiver ; heure répétée à l'automne :
    la première (heure d'été)."""
    ete = locale - timedelta(hours=2)
    debut = dernier_dimanche(locale.year, 3).replace(hour=1)
    fin = dernier_dimanche(locale.year, 10).replace(hour=1)
    return ete if debut <= ete < fin else locale - timedelta(hours=1)


def utc(date):
    """Date en ISO 8601 UTC suffixée de Z, forme des dates du projet et du paquet. date : date Unix (FOA Explorer) ou
    texte ISO 8601 ; un texte sans fuseau (GraceTHD : « 2026-06-23 08:50:27 ») est une heure de Paris. Un texte
    illisible est rendu tel quel."""
    if isinstance(date, (int, float)):
        return datetime.fromtimestamp(date, timezone.utc).strftime(FORMAT_DATE)
    texte = str(date).strip()
    try:
        d = datetime.fromisoformat(texte)
    except ValueError:
        return texte
    if d.tzinfo is None:
        return heure_de_paris(d).strftime(FORMAT_DATE)
    return d.astimezone(timezone.utc).strftime(FORMAT_DATE)


def date_reprise(date_modif, date_crea):
    """Date d'une entrée reprise : celle que porte le nœud (PRJ_NOE), sa DATE_MODIF, à défaut sa DATE_CREA, à défaut
    l'instant de la reprise ; en UTC (utc). Même règle pour reprendre_commentaires et tools/essai/charger_essai.py."""
    for date in (date_modif, date_crea):
        if date is not None and str(date).strip():
            return utc(date)
    return datetime.now(timezone.utc).strftime(FORMAT_DATE)


def instructions(module, table):
    """Instructions des scripts d'un module qui créent une table non spatiale et ses index : mise à niveau d'un
    projet existant à partir du schéma, sans le recopier. Seuls les commentaires qui précèdent l'instruction sont
    retirés : ceux de son corps restent, comme dans le texte que SQLite conserve pour un projet neuf."""
    m = next(m for m in manifestes() if m['code'] == module)
    trouvees, courante = [], ''
    for script in m['scripts']:
        for ligne in open(os.path.join(m['dossier'], script), encoding='utf-8'):
            courante += ligne
            if sqlite3.complete_statement(courante):
                lignes = courante.splitlines()
                while lignes and (not lignes[0].strip() or lignes[0].lstrip().startswith('--')):
                    lignes.pop(0)
                sql = '\n'.join(lignes).strip()
                if re.match(rf'CREATE (UNIQUE )?(TABLE|INDEX \w+ ON) {table}\b', sql):
                    trouvees.append(sql)
                courante = ''
    return trouvees


def qualifier(sql, schema):
    """Instruction CREATE TABLE ou CREATE INDEX du schéma (instructions) à exécuter dans la base attachée schema ;
    SQLite retire ce préfixe du texte qu'il conserve, qui reste celui d'un projet neuf."""
    return re.sub(r'^CREATE (UNIQUE )?(TABLE|INDEX) (\w+)', lambda m: f'CREATE {m[1] or ""}{m[2]} {schema}.{m[3]}',
                  sql, count=1)


def champ_perime(con, table, colonne):
    """Colonne retirée de la table mais encore listée dans les statistiques SpatiaLite de la couche."""
    return con.execute('SELECT 1 FROM geometry_columns_field_infos WHERE lower(f_table_name) = lower(?) '
                       'AND upper(column_name) = upper(?)', (table, colonne)).fetchone() is not None


def recalculer_statistiques(con, table):
    """Statistiques SpatiaLite d'une couche du noyau (geometry_columns_field_infos… : champs que QGIS lit), à
    recalculer après un retrait de colonne : sinon QGIS montre encore la colonne et l'ajout d'une entité échoue.
    UpdateLayerStatistics seul ne recalcule rien, geometry_columns_time ne voyant aucune écriture depuis le dernier
    calcul (un retrait de colonne n'y touche pas) : InvalidateLayerStatistics d'abord."""
    for f in ('InvalidateLayerStatistics', 'UpdateLayerStatistics'):
        if con.execute(f"SELECT {f}(?, 'GEOMETRY')", (table,)).fetchone()[0] != 1:
            raise RuntimeError(f'{table} : {f} en échec, reprise annulée')


def origine_reprise(src_modif, zone, code_projet):
    """Origine d'un texte repris : 'FOA', 'GRACE' ou 'BE', d'après la zone du nœud (zone : ZONE_CODE_EXT). Seul
    chargement à ce jour, tools/essai/charger_essai.py marque ses lignes SRC_MODIF = 'import' et charge chaque source
    dans sa zone : l'export GraceTHD du jeu d'essai dans la zone GRACE (ZONE_GRACE), FOA Explorer dans les autres ; en
    mode --foa, l'unique zone porte le code du projet et tous ses nœuds viennent de FOA Explorer, même si ce code est
    GRACE. Une ligne modifiée depuis l'import, ou créée au BE, est rapportée au BE."""
    if src_modif != 'import':
        return 'BE'
    return 'GRACE' if zone == ZONE_GRACE and zone != code_projet else 'FOA'


def reprendre_commentaires(con, inscrits, rapport):
    """Étape 0.2.0, journal des commentaires : reprend NOE_COMMENT, CHB_COMMENT et POT_COMMENT dans le journal
    PRJ_COMMENTAIRE (créé s'il manque), puis retire les colonnes (statistiques SpatiaLite de PRJ_NOE recalculées pour
    QGIS). Chaque texte non vide devient une entrée standard rattachée au nœud, sans intervention, datée du nœud
    (date_reprise), signée « FOA » pour un texte venu de FOA Explorer, « BE » sinon (origine_reprise,
    auteur_reprise). Une table absente du fichier d'un module ou un texte porté par une ligne sans nœud annulent la
    reprise ; une colonne déjà retirée est une reprise déjà faite. Idempotente : colonnes retirées et COM_CODE_EXT
    déterministe (code_reprise). Rend les modules dont la table ne porte plus la colonne (seuls à passer en 0.2.0)."""
    if not con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'PRJ_COMMENTAIRE'").fetchone():
        for sql in instructions('noyau', 'PRJ_COMMENTAIRE'):
            con.execute(sql)
        rapport.append('PRJ_COMMENTAIRE : table et index créés')
    code_projet = con.execute('SELECT PRJ_CODE_EXT FROM SYS_PROJET').fetchone()[0]
    ent_noe = con.execute("SELECT ENT_ID FROM DEF_ENTITE WHERE ENT_TABLE = 'PRJ_NOE'").fetchone()[0]
    zones = dict(con.execute('SELECT ZONE_ID, ZONE_CODE_EXT FROM PRJ_ZONE'))
    sans_champ = set()          # modules dont la table ne porte plus le champ libre (retiré ici ou avant)
    for module, table, colonne, noe_col in COMMENTAIRES_REPRIS:
        if module not in inscrits:
            rapport.append(f'{table}.{colonne} : module {module} non inscrit au projet, rien à reprendre')
            continue
        s = schema_de(module)
        colonnes = {r[1] for r in con.execute(f'PRAGMA {s}.table_info({table})')}
        if not colonnes:
            raise RuntimeError(f'{module}.{table} absente (base du module incomplète), reprise annulée')
        sans_champ.add(module)
        if colonne not in colonnes:
            if s == 'main' and champ_perime(con, table, colonne):      # reprise faite sans recalcul
                recalculer_statistiques(con, table)
                rapport.append(f'{table}.{colonne} : colonne déjà retirée, statistiques SpatiaLite périmées '
                               f'recalculées')
            else:
                rapport.append(f'{table}.{colonne} : colonne déjà retirée (reprise faite), rien à reprendre')
            continue
        textes = [l for l in con.execute(
            f'SELECT n.NOE_ID, n.NOE_CODE_EXT, n.ZONE_KEY, n.DATE_MODIF, n.DATE_CREA, x.{colonne}, x.SRC_MODIF '
            f'FROM {s}.{table} x LEFT JOIN PRJ_NOE n ON n.NOE_ID = x.{noe_col} WHERE x.{colonne} IS NOT NULL '
            f'ORDER BY x.{noe_col}').fetchall() if str(l[5]).strip()]
        sans_noeud = sum(1 for l in textes if l[0] is None)
        if sans_noeud:
            raise RuntimeError(f'{table}.{colonne} : texte sur une ligne sans nœud ({sans_noeud}), reprise annulée')
        repris, deja = Counter(), 0
        for noe, code_noe, zone, modif, crea, texte, src_modif in textes:
            code = code_reprise(code_projet, code_noe, colonne)
            if con.execute('SELECT 1 FROM PRJ_COMMENTAIRE WHERE COM_CODE_EXT = ?', (code,)).fetchone():
                deja += 1
                continue
            origine = origine_reprise(src_modif, zones.get(zone), code_projet)
            con.execute('INSERT INTO PRJ_COMMENTAIRE (COM_CODE_EXT, ENT_KEY, OBJ_KEY, COM_TEXTE, COM_AUTEUR, '
                        'COM_ORIGINE, DATE_CREA) VALUES (?, ?, ?, ?, ?, ?, ?)',
                        (code, ent_noe, noe, str(texte).strip(), auteur_reprise(origine), origine,
                         date_reprise(modif, crea)))
            repris[origine] += 1
        con.execute(f'ALTER TABLE {s}.{table} DROP COLUMN {colonne}')
        stats = ''
        if s == 'main':                 # couche SpatiaLite du noyau (les modules sont des tables simples)
            recalculer_statistiques(con, table)
            stats = ', statistiques SpatiaLite recalculées'
        total = sum(repris.values())
        detail = [f'{k} {v}' for k, v in sorted(repris.items())] + ([f'déjà repris {deja}'] if deja else [])
        suite = f' ({", ".join(detail)})' if detail else ''
        rapport.append(f'{table}.{colonne} : {total} texte{"s" * (total > 1)} repris{suite}, colonne retirée{stats}')
    return sans_champ


def reconstruire(con, module, tables, valeurs, retirees):
    """Reconstruit des tables d'un module d'après ses scripts (instructions), lignes, identifiants, séquences
    AUTOINCREMENT et index gardés : copie temporaire, suppression des enfants aux parents, création et recopie des
    parents aux enfants, clés étrangères actives (contrôlées à chaque ligne recopiée). Le texte des tables est alors
    celui d'un projet neuf. tables : des parents aux enfants ; valeurs : {(table, colonne) : expression SQL sur
    l'ancienne ligne}, pour une colonne nouvelle ou convertie ; retirees : {table : colonnes que le schéma ne porte
    plus}, seules à pouvoir se perdre. Une autre colonne perdue, une colonne nouvelle sans valeur ou un effectif
    changé annulent la reprise. Rend les effectifs par table."""
    s = schema_de(module)
    sequences = dict(con.execute(f'SELECT name, seq FROM {s}.sqlite_sequence').fetchall())
    for t in tables:
        con.execute(f'CREATE TEMP TABLE reprise_{t} AS SELECT * FROM {s}.{t}')
    for t in reversed(tables):
        con.execute(f'DROP TABLE {s}.{t}')
    effectifs = {}
    for t in tables:
        for sql in instructions(module, t):
            con.execute(qualifier(sql, s))
        anciennes = [r[1] for r in con.execute(f'PRAGMA temp.table_info(reprise_{t})')]
        nouvelles = [r[1] for r in con.execute(f'PRAGMA {s}.table_info({t})')]
        perdues = sorted(set(anciennes) - set(nouvelles) - set(retirees.get(t, ())))
        sans_valeur = [c for c in nouvelles if c not in anciennes and (t, c) not in valeurs]
        if perdues or sans_valeur:
            raise RuntimeError(f'{module}.{t} : ' + ' ; '.join(
                ([f'colonnes inattendues, perdues par la reconstruction {perdues}'] if perdues else [])
                + ([f'colonnes nouvelles sans valeur {sans_valeur}'] if sans_valeur else [])) + ', reprise annulée')
        cols = [c for c in nouvelles if c in anciennes or (t, c) in valeurs]
        con.execute(f'INSERT INTO {s}.{t} ({", ".join(cols)}) '
                    f'SELECT {", ".join(valeurs.get((t, c), c) for c in cols)} FROM temp.reprise_{t}')
        avant = con.execute(f'SELECT COUNT(*) FROM temp.reprise_{t}').fetchone()[0]
        effectifs[t] = con.execute(f'SELECT COUNT(*) FROM {s}.{t}').fetchone()[0]
        if effectifs[t] != avant:
            raise RuntimeError(f'{module}.{t} : {effectifs[t]} lignes recopiées sur {avant}, reprise annulée')
        con.execute(f'DROP TABLE temp.reprise_{t}')
        # séquence d'origine : un identifiant déjà attribué, même supprimé depuis, ne revient pas
        if t in sequences and not con.execute(f'UPDATE {s}.sqlite_sequence SET seq = MAX(seq, ?) WHERE name = ?',
                                              (sequences[t], t)).rowcount:
            con.execute(f'INSERT INTO {s}.sqlite_sequence (name, seq) VALUES (?, ?)', (t, sequences[t]))
    return effectifs


def positions_hors_face(con):
    """Positions de chambre dont le centre sort de sa face (repère métrique, module chambre 0.3.0) : aucune
    attendue."""
    return con.execute('SELECT COUNT(*) FROM chambre.CHB_POSITION p JOIN chambre.CHB_FACE f ON f.FAC_ID = p.FAC_KEY '
                       'WHERE p.POS_X < 0 OR p.POS_X > f.FAC_LARG OR p.POS_Y < 0 OR p.POS_Y > f.FAC_HAUT').fetchone()[0]


def reprendre_masques(con, inscrits, rapport):
    """Étape 0.3.0, masques métriques : jusqu'au module chambre 0.2.0, faces (FAC_NB_COL x FAC_NB_LIG) et positions
    (POS_X colonne depuis la gauche, POS_Y ligne depuis le haut) sont en cellules de la fenêtre FOA (CELLULE_FOA) ;
    elles passent en m (FAC_LARG x FAC_HAUT ; centre de l'alvéole depuis la gauche et le haut de la face) par une
    conversion exacte arrondie au micromètre : une face 9 x 12 devient 0,567 x 0,54 m. Une dimension vide prend celle
    de la fenêtre FOA, grille par défaut avant la 0.3.0. Les tables CHB_* sont reconstruites d'après
    schema/chambre/schema.sql (reconstruire). Annulent la reprise : une table absente, une dimension nulle, négative
    ou non numérique, une position non numérique, une référence interne sans cible. Faite quand CHB_FACE porte
    FAC_LARG et FAC_HAUT. Rend {'chambre'} quand le module est au niveau, maintenant ou avant."""
    if 'chambre' not in inscrits:
        rapport.append('CHB_FACE : module chambre non inscrit au projet, rien à reprendre')
        return set()
    absentes = [t for t in TABLES_MASQUES if not con.execute(f'PRAGMA chambre.table_info({t})').fetchall()]
    if absentes:
        raise RuntimeError(f'chambre.{", chambre.".join(absentes)} : absente{"s" * (len(absentes) > 1)} (base du '
                           f'module incomplète), reprise annulée')
    colonnes = {r[1] for r in con.execute('PRAGMA chambre.table_info(CHB_FACE)')}
    metres, cellules = {'FAC_LARG', 'FAC_HAUT'}, {'FAC_NB_COL', 'FAC_NB_LIG'}
    if metres <= colonnes and not cellules & colonnes:
        rapport.append('CHB_FACE : faces et positions déjà en m (reprise faite), rien à convertir')
        return {'chambre'}
    if not cellules <= colonnes or metres & colonnes:
        raise RuntimeError(f'CHB_FACE : ni en cellules ni en m ({", ".join(sorted((metres | cellules) & colonnes))}), '
                           f'reprise annulée')
    nombre = lambda c: f"typeof({c}) IN ('integer', 'real')"
    n = con.execute(f'SELECT COUNT(*) FROM chambre.CHB_FACE WHERE '
                    f'(FAC_NB_COL IS NOT NULL AND NOT ({nombre("FAC_NB_COL")} AND FAC_NB_COL > 0)) OR '
                    f'(FAC_NB_LIG IS NOT NULL AND NOT ({nombre("FAC_NB_LIG")} AND FAC_NB_LIG > 0))').fetchone()[0]
    if n:
        raise RuntimeError(f'CHB_FACE : {n} face{"s" * (n > 1)} de dimension nulle, négative ou non numérique, '
                           f'reprise annulée')
    n = con.execute(f'SELECT COUNT(*) FROM chambre.CHB_POSITION WHERE NOT ({nombre("POS_X")} AND {nombre("POS_Y")})'
                    ).fetchone()[0]
    if n:
        raise RuntimeError(f'CHB_POSITION : {n} position{"s" * (n > 1)} non numérique{"s" * (n > 1)}, reprise annulée')
    orphelines = Counter(f'{t} → {parent}' for t, _, parent, _ in con.execute('PRAGMA chambre.foreign_key_check'))
    if orphelines:
        detail = ', '.join(f'{k} {v}' for k, v in sorted(orphelines.items()))
        raise RuntimeError(f'chambre : références internes sans cible ({detail}), reprise annulée')
    grilles = con.execute('SELECT FAC_NB_COL, FAC_NB_LIG, COUNT(*) FROM chambre.CHB_FACE GROUP BY 1, 2 '
                          'ORDER BY 3 DESC').fetchall()
    (cl, ch), (gc, gl), d = CELLULE_FOA, GRILLE_FOA, DECIMALES_MASQUE
    effectifs = reconstruire(con, 'chambre', TABLES_MASQUES, {
        ('CHB_FACE', 'FAC_LARG'): f'ROUND(COALESCE(FAC_NB_COL, {gc}) * {cl}, {d})',
        ('CHB_FACE', 'FAC_HAUT'): f'ROUND(COALESCE(FAC_NB_LIG, {gl}) * {ch}, {d})',
        ('CHB_POSITION', 'POS_X'): f'ROUND(POS_X * {cl}, {d})',
        ('CHB_POSITION', 'POS_Y'): f'ROUND(POS_Y * {ch}, {d})'}, {'CHB_FACE': cellules})
    cellules_vides = lambda v, defaut: f'{defaut} (vide)' if v is None else v
    grille = [f'{cellules_vides(c, gc)} x {cellules_vides(l, gl)} → '
              f'{round((c or gc) * cl, d):g} x {round((l or gl) * ch, d):g} m : {n}' for c, l, n in grilles]
    rapport.append(f'CHB_FACE : {effectifs["CHB_FACE"]} faces converties des cellules FOA en m'
                   + (f' ({", ".join(grille)})' if grille else ''))
    rapport.append(f'CHB_POSITION : {effectifs["CHB_POSITION"]} positions converties en m (POS_X x {cl}, '
                   f'POS_Y x {ch}), {positions_hors_face(con)} hors de leur face')
    rapport.append('chambre : tables reconstruites d\'après schema/chambre/schema.sql, identifiants, séquences et '
                   'index gardés (' + ', '.join(f'{t} {n}' for t, n in effectifs.items()) + ')')
    return {'chambre'}


# Étapes de la reprise, dans l'ordre des versions du modèle : (version, libellé, étape). Une étape (con, modules
# inscrits, rapport) est idempotente et rend les modules mis à son niveau, maintenant ou avant.
ETAPES = ((VERSION_JOURNAL, 'journal des commentaires', reprendre_commentaires),
          (VERSION_MASQUES, 'masques métriques', reprendre_masques))


def migrer(dossier, qgis_bin):
    """Reprise d'un projet construit avec un modèle antérieur : applique dans l'ordre les étapes en attente (ETAPES)
    en une seule transaction sur le noyau et les modules. Un module inscrit dont le fichier manque est refusé par
    ouvrir, avant toute écriture ; une table absente ou une anomalie propre à une étape annulent toute la reprise. Les
    modules rendus par une étape passent à sa version dans SYS_MODULE, le modèle du projet
    (SYS_PROJET.MODELE_VERSION) à celle de chaque étape passée ; un module non inscrit est ignoré. Idempotente : une
    seconde exécution ne change rien."""
    con = ouvrir(dossier, qgis_bin, integrite=False)
    rapport = []
    inscrits = {r[0] for r in con.execute('SELECT MOD_CODE FROM SYS_MODULE')}
    con.execute('BEGIN')
    try:
        for etape_version, libelle, etape in ETAPES:
            lignes = []
            au_niveau = etape(con, inscrits, lignes)
            for code, v in con.execute('SELECT MOD_CODE, MOD_VERSION FROM SYS_MODULE ORDER BY MOD_ID').fetchall():
                if code in au_niveau and version(v) < version(etape_version):
                    con.execute('UPDATE SYS_MODULE SET MOD_VERSION = ? WHERE MOD_CODE = ?', (etape_version, code))
                    lignes.append(f'SYS_MODULE : {code} {v} → {etape_version}')
            modele = con.execute('SELECT MODELE_VERSION FROM SYS_PROJET').fetchone()[0]
            if version(modele) < version(etape_version):
                con.execute('UPDATE SYS_PROJET SET MODELE_VERSION = ?', (etape_version,))
                lignes.append(f'SYS_PROJET : modèle {modele} → {etape_version}')
            rapport += [f'Étape {etape_version}, {libelle} :'] + [f'  {l}' for l in lignes]
        con.execute('COMMIT')
    except BaseException:
        if con.in_transaction:
            con.execute('ROLLBACK')
        raise
    journal = con.execute("SELECT COALESCE(COM_ORIGINE, 'saisie'), COUNT(*) FROM PRJ_COMMENTAIRE GROUP BY 1 "
                          'ORDER BY 1').fetchall()
    rapport.append(f'Journal : {sum(n for _, n in journal)} entrées'
                   + (f' ({", ".join(f"{o} {n}" for o, n in journal)})' if journal else ''))
    if 'chambre' in inscrits:
        faces = con.execute('SELECT FAC_LARG, FAC_HAUT, COUNT(*) FROM chambre.CHB_FACE GROUP BY 1, 2 '
                            'ORDER BY 3 DESC, 1, 2').fetchall()
        rapport.append(f'Masques : {sum(n for *_, n in faces)} faces'
                       + (f' ({", ".join(f"{l:g} x {h:g} m : {n}" for l, h, n in faces)})' if faces else '')
                       + f', {con.execute("SELECT COUNT(*) FROM chambre.CHB_POSITION").fetchone()[0]} positions, '
                       f'{positions_hors_face(con)} hors de leur face')
    con.close()
    return rapport


# Essai ---------------------------------------------------------------------------------------------

def essai(con):
    """Scénario complet dans un point de sauvegarde annulé à la fin ; renvoie les constats."""
    q = lambda sql, *p: con.execute(sql, p).fetchone()
    constats = []
    con.execute('SAVEPOINT essai')
    try:
        def noeud(code, lib, type_code, x, y):
            con.execute('INSERT INTO PRJ_NOE (NOE_CODE_EXT, NOE_LIB, TYPE_KEY, GEOMETRY) '
                        'SELECT ?, ?, TYPE_ID, MakePoint(?, ?, 2154) FROM DEF_TYPE WHERE TYPE_CODE = ?',
                        (code, lib, x, y, type_code))
            return q('SELECT last_insert_rowid()')[0]

        def lineaire(code, type_code, impl, n1, n2):
            con.execute('INSERT INTO PRJ_LINEAIRE (LIN_CODE_EXT, TYPE_KEY, IMPL_KEY, NOE1_KEY, NOE2_KEY, GEOMETRY) '
                        'SELECT ?, (SELECT TYPE_ID FROM DEF_TYPE WHERE TYPE_CODE = ?), ?, ?, ?, '
                        'MakeLine(a.GEOMETRY, b.GEOMETRY) FROM PRJ_NOE a, PRJ_NOE b WHERE a.NOE_ID = ? AND b.NOE_ID = ?',
                        (code, type_code, impl, n1, n2, n1, n2))
            return q('SELECT last_insert_rowid()')[0]

        c1 = noeud('essai-c1', '1476', 'CHB-FT', 636000, 6835000)
        c2 = noeud('essai-c2', '1475', 'CHB-FT', 636040, 6835010)
        p1 = noeud('essai-p1', '437991', 'POT-FT', 636100, 6835050)
        p2 = noeud('essai-p2', '437997', 'POT-FT', 636130, 6835060)
        f1 = noeud('essai-f1', 'Façade', 'FAC', 636110, 6835080)
        l1 = lineaire('essai-l1', 'LIN-SOUT', 7, c1, c2)
        l2 = lineaire('essai-l2', 'LIN-AER', 0, p1, p2)
        lineaire('essai-l3', 'LIN-FAC', 2, p1, f1)

        etat_x = q("SELECT ETAT_ID FROM infra.DEF_CD_ETAT WHERE ETAT_CODE = 'X'")[0]
        con.execute('INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY, CD_NUM, CD_DIAM, ETAT_KEY) '
                    'VALUES (?, ?, 1, 45, ?)', ('essai-cd1', l1, etat_x))
        cd1 = q('SELECT last_insert_rowid()')[0]
        con.execute('INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY, CD_PARENT_KEY, CD_NUM, CD_DIAM) '
                    'VALUES (?, ?, ?, 1, 28)', ('essai-cd2', l1, cd1))
        # alvéole sans destination connue : conduite rattachée à la chambre, sans linéaire
        con.execute("INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, NOE_KEY, CD_NUM, CD_DIAM) VALUES ('essai-cd3', ?, 2, 45)",
                    (c1,))
        cd3 = q('SELECT last_insert_rowid()')[0]
        cable = q("SELECT MAT_ID FROM infra.MAT_CABLE WHERE MAT_LIB = '5/9'")[0]
        con.execute('INSERT INTO infra.INF_CD_CABLE (CD_KEY, MAT_KEY, CDC_NB) VALUES (?, ?, 2)', (cd1, cable))
        con.execute('INSERT INTO infra.INF_PORTEE (LIN_KEY, PRT_ANG1, PRT_ANG2, PRT_LNG) VALUES (?, 0, 200, 31)', (l2,))
        prt = q('SELECT last_insert_rowid()')[0]
        con.execute('INSERT INTO infra.INF_PORTEE_CABLE (PRT_KEY, PCB_RANG, MAT_KEY, PCB_LNG, PCB_NAPPE, PCB_TENSION) '
                    "VALUES (?, 1, ?, 31, 1, 'STD_AGGLO')", (prt, cable))
        con.execute('INSERT INTO infra.INF_PORTEE_CABLE (PRT_KEY, PCB_RANG, MAT_KEY, PCB_LNG, PCB_NAPPE, PCB_TENSION, '
                    "PCB_FLECHE, PCB_TEMP) VALUES (?, 2, ?, 31, 1, 'RELEVE', 0.8, 20)", (prt, cable))

        # faces aux dimensions intérieures du catalogue, au millimètre : A et B à la largeur de la chambre, C et D à
        # sa longueur, hauteur de la chambre ; positions en m depuis la gauche et le haut de la face
        mat_chb, larg, lng, haut = q("SELECT MAT_ID, round(CHB_LARG_INT, 3), round(CHB_LNG_INT, 3), "
                                     "round(CHB_HAUT_INT, 3) FROM chambre.MAT_CHAMBRE WHERE MAT_LIB = 'L2T'")
        chambres = {}
        for noe in (c1, c2):
            con.execute('INSERT INTO chambre.CHB_CHAMBRE (NOE_KEY, MAT_KEY) VALUES (?, ?)', (noe, mat_chb))
            chambres[noe] = q('SELECT last_insert_rowid()')[0]

        def face(noe, code, largeur):
            con.execute('INSERT INTO chambre.CHB_FACE (CHB_KEY, FAC_CODE, FAC_LARG, FAC_HAUT) VALUES (?, ?, ?, ?)',
                        (chambres[noe], code, largeur, haut))
            return q('SELECT last_insert_rowid()')[0]

        faces = {c1: face(c1, 'A', larg), c2: face(c2, 'B', larg)}
        face(c1, 'C', lng)              # face sans alvéole
        con.execute('INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y) VALUES (?, ?, 0.12, 0.2)',
                    (faces[c1], cd1))
        con.execute('INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y, POS_MIROIR) '
                    'VALUES (?, ?, ?, 0.2, 1)', (faces[c2], cd1, round(larg - 0.12, 3)))
        con.execute('INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y) VALUES (?, ?, 0.25, 0.2)',
                    (faces[c1], cd3))

        mat_pot = q("SELECT MAT_ID FROM poteau.MAT_POTEAU WHERE GES_LIB = 'BS7'")[0]   # type GESPOT de la maquette
        for noe in (p1, p2):
            con.execute('INSERT INTO poteau.POT_POTEAU (NOE_KEY, MAT_KEY, POT_HAUTEUR) VALUES (?, ?, 7)', (noe, mat_pot))
        pot1 = q('SELECT POT_ID FROM poteau.POT_POTEAU WHERE NOE_KEY = ?', p1)[0]
        con.execute("INSERT INTO poteau.POT_CONTROLE (POT_KEY, DATE_CTL, CTL_VISUEL, CTL_PERCUSSION) "
                    "VALUES (?, '2026-10-31', 1, 1)", (pot1,))

        ent_noe = q("SELECT ENT_ID FROM DEF_ENTITE WHERE ENT_TABLE = 'PRJ_NOE'")[0]
        vue_a = q("SELECT VUE_ID FROM DEF_VUE v JOIN DEF_TYPE t ON t.TYPE_ID = v.TYPE_KEY "
                  "WHERE t.TYPE_CODE = 'CHB' AND v.VUE_CODE = 'A'")[0]
        con.execute('INSERT INTO PRJ_FICHIER (FIC_CODE_EXT, ENT_KEY, OBJ_KEY, VUE_KEY, FIC_PRINCIPALE, FIC_NOM, '
                    "FIC_CHEMIN) VALUES ('essai-f1', ?, ?, ?, 1, 'CHA_1476_A_1.jpg', 'photos/CHA_1476_A_1.jpg')",
                    (ent_noe, c1, vue_a))
        con.execute("INSERT INTO PRJ_INTERVENTION (INT_CODE_EXT, ACT_CODE, INT_AUTEUR, DATE_DEBUT) "
                    "VALUES ('essai-i1', 'RELEVE_CHB', 'technicien@essai', '2026-10-31T08:00:00Z')")
        con.execute("INSERT INTO PRJ_INT_OBJET (INT_KEY, ENT_KEY, OBJ_KEY, IOB_ACTION) "
                    "VALUES (last_insert_rowid(), ?, ?, 'M')", (ent_noe, c1))
        # journal de commentaires : texte repris de FOA, saisie signée de l'intervention, entrée retirée au BE
        i1 = q("SELECT INT_ID FROM PRJ_INTERVENTION WHERE INT_CODE_EXT = 'essai-i1'")[0]
        con.execute('INSERT INTO PRJ_COMMENTAIRE (COM_CODE_EXT, ENT_KEY, OBJ_KEY, COM_TEXTE, COM_AUTEUR, COM_ORIGINE, '
                    "DATE_CREA) VALUES ('essai-m1', ?, ?, 'masque c direct dans le central', 'FOA', 'FOA', "
                    "'2016-10-27T06:30:15Z')", (ent_noe, c1))
        con.execute('INSERT INTO PRJ_COMMENTAIRE (COM_CODE_EXT, ENT_KEY, OBJ_KEY, INT_KEY, COM_TYPE, COM_TEXTE, '
                    "COM_AUTEUR) VALUES ('essai-m2', ?, ?, ?, 'alert', 'Tampon fêlé, à remplacer', 'technicien@essai')",
                    (ent_noe, c1, i1))
        con.execute('INSERT INTO PRJ_COMMENTAIRE (COM_CODE_EXT, ENT_KEY, OBJ_KEY, COM_TEXTE, COM_AUTEUR, COM_ORIGINE, '
                    "DATE_ABD, SRC_ABD) VALUES ('essai-m3', ?, ?, 'Doublon', 'BE', 'BE', '2026-10-31T09:00:00Z', 'BE')",
                    (ent_noe, c1))

        # optique : PBO posé sur 437997, câble tiré de 437991 sur la portée, fibres, cassette, route et mesure ;
        # immeuble : adresse de deux logements desservis par ce PBO
        mat_pbo = q("SELECT MAT_ID FROM infra.MAT_EQUIP WHERE MAT_CAPAEPIS = 12 ORDER BY MAT_ID")[0]
        con.execute("INSERT INTO infra.INF_EQUIPEMENT (EQU_CODE_EXT, NOE_KEY, MAT_KEY) VALUES ('essai-e1', ?, ?)",
                    (p2, mat_pbo))
        e1 = q('SELECT last_insert_rowid()')[0]
        con.execute("INSERT INTO optique.OPT_EQUIPEMENT (EQU_KEY, EQO_LIB, OTYP_KEY, EQO_CAPA) "
                    "SELECT ?, 'PBO-1', OTYP_ID, 12 FROM optique.DEF_OPT_EQUIP_TYPE WHERE OTYP_CODE = 'PBO'", (e1,))
        con.execute("INSERT INTO optique.OPT_CABLE (CAB_CODE_EXT, CAB_LIB, CAB_CAPA, CAB_MODULO, NOE1_KEY, NOE2_KEY, "
                    "EQU2_KEY) VALUES ('essai-cb1', 'CDI-1', 12, 12, ?, ?, ?)", (p1, p2, e1))
        cb1 = q('SELECT last_insert_rowid()')[0]
        pcb1 = q('SELECT PCB_ID FROM infra.INF_PORTEE_CABLE WHERE PRT_KEY = ? AND PCB_RANG = 1', prt)[0]
        con.execute('INSERT INTO optique.OPT_PASSAGE (CAB_KEY, LIN_KEY, PCB_KEY, PAS_RANG) VALUES (?, ?, ?, 1)',
                    (cb1, l2, pcb1))
        for n in range(1, 13):
            con.execute('INSERT INTO optique.OPT_FIBRE (CAB_KEY, FIB_NUM, FIB_TUBE, FIB_NUM_TUBE, COUL_KEY, '
                        'TUBE_COUL_KEY) VALUES (?, ?, 1, ?, ?, 1)', (cb1, n, n, n))
        fo1 = q('SELECT FIB_ID FROM optique.OPT_FIBRE WHERE CAB_KEY = ? AND FIB_NUM = 1', cb1)[0]
        con.execute("INSERT INTO optique.OPT_CASSETTE (EQU_KEY, CAS_NUM, CTYP_KEY, CAS_CAPA) VALUES (?, 1, 2, 12)", (e1,))
        cs1 = q('SELECT last_insert_rowid()')[0]
        con.execute("INSERT INTO optique.OPT_POSITION (CAS_KEY, POS_NUM, FIB1_KEY, PFON_KEY, POS_AFFECT) "
                    "SELECT ?, 1, ?, PFON_ID, 'ABONNE' FROM optique.DEF_POS_FONCTION WHERE PFON_CODE = 'AT'", (cs1, fo1))
        con.execute("INSERT INTO optique.OPT_ROUTE (RTE_CODE_EXT) VALUES ('essai-r1')")
        r1 = q('SELECT last_insert_rowid()')[0]
        con.execute('INSERT INTO optique.OPT_ROUTE_FIBRE (RTE_KEY, ROF_RANG, FIB_KEY) VALUES (?, 1, ?)', (r1, fo1))
        con.execute("INSERT INTO optique.OPT_MESURE (MES_CODE_EXT, MMET_KEY, RTE_KEY, FIB_KEY, EQU_KEY, MES_LAMBDA, "
                    "MES_SENS, MES_LNG, MES_PERTE, MES_CONFORME) VALUES ('essai-mes1', 1, ?, ?, ?, 1550, 'OE', 33.5, "
                    "0.21, 1)", (r1, fo1, e1))
        con.execute("INSERT INTO PRJ_ADRESSE (ADR_CODE_EXT, ADR_NUMERO, ADR_VOIE, GEOMETRY) "
                    "VALUES ('essai-a1', 12, 'Rue de l''Essai', MakePoint(636135, 6835070, 2154))")
        a1 = q('SELECT last_insert_rowid()')[0]
        con.execute("INSERT INTO immeuble.IMB_ADRESSE (ADR_KEY, HAB_KEY, IAD_NB_LOG, IAD_NB_PRO, IMPL_KEY) "
                    "VALUES (?, 1, 2, 0, 0)", (a1,))
        for i in (1, 2):
            con.execute("INSERT INTO immeuble.IMB_LOCAL (LOC_CODE_EXT, ADR_KEY, LTYP_KEY, RACCO_KEY, LOC_ETAGE, EQU_KEY) "
                        "VALUES (?, ?, 1, 3, ?, ?)", (f'essai-loc{i}', a1, str(i - 1), e1))

        # lectures attendues
        miroir = con.execute(
            'SELECT n.NOE_LIB, f.FAC_CODE, p.POS_X, p.POS_MIROIR FROM chambre.CHB_POSITION p '
            'JOIN chambre.CHB_FACE f ON f.FAC_ID = p.FAC_KEY JOIN chambre.CHB_CHAMBRE c ON c.CHB_ID = f.CHB_KEY '
            'JOIN PRJ_NOE n ON n.NOE_ID = c.NOE_KEY WHERE p.CD_KEY = ? ORDER BY n.NOE_LIB', (cd1,)).fetchall()
        constats.append(('miroir : une conduite, une position dans chaque chambre', len(miroir) == 2, miroir))
        sans_dest = con.execute(
            'SELECT n.NOE_LIB, p.POS_X FROM infra.INF_CONDUITE cd JOIN PRJ_NOE n ON n.NOE_ID = cd.NOE_KEY '
            'JOIN chambre.CHB_POSITION p ON p.CD_KEY = cd.CD_ID WHERE cd.CD_ID = ? AND cd.LIN_KEY IS NULL',
            (cd3,)).fetchall()
        constats.append(('alvéole sans destination : conduite rattachée à sa chambre, sans linéaire',
                         sans_dest == [('1476', 0.25)], sans_dest))
        dims = con.execute('SELECT n.NOE_LIB, f.FAC_CODE, f.FAC_LARG, f.FAC_HAUT FROM chambre.CHB_FACE f '
                           'JOIN chambre.CHB_CHAMBRE c ON c.CHB_ID = f.CHB_KEY JOIN PRJ_NOE n ON n.NOE_ID = c.NOE_KEY '
                           'WHERE c.CHB_ID IN (?, ?) ORDER BY 1, 2', (chambres[c1], chambres[c2])).fetchall()
        constats.append(('faces aux dimensions intérieures L2T (m) : A et B largeur, C longueur, hauteur de la chambre',
                         dims == [('1475', 'B', larg, haut), ('1476', 'A', larg, haut), ('1476', 'C', lng, haut)],
                         dims))
        constats.append(('positions dans leur face (centre, m)', positions_hors_face(con) == 0,
                         f'{positions_hors_face(con)} hors de leur face'))
        rosace = con.execute(
            'SELECT CASE WHEN l.NOE1_KEY = :p THEN d2.NOE_LIB ELSE d1.NOE_LIB END, '
            'CASE WHEN l.NOE1_KEY = :p THEN r.PRT_ANG1 ELSE r.PRT_ANG2 END, i.IMPL_LIB '
            'FROM PRJ_LINEAIRE l JOIN DEF_IMPLANTATION i ON i.IMPL_ID = l.IMPL_KEY '
            'JOIN PRJ_NOE d1 ON d1.NOE_ID = l.NOE1_KEY JOIN PRJ_NOE d2 ON d2.NOE_ID = l.NOE2_KEY '
            'LEFT JOIN infra.INF_PORTEE r ON r.LIN_KEY = l.LIN_ID '
            'WHERE :p IN (l.NOE1_KEY, l.NOE2_KEY) ORDER BY 1', {'p': p1}).fetchall()
        constats.append(('rosace de 437991 : destinations, angle au poteau, implantation', len(rosace) == 2, rosace))
        vues = con.execute(
            'WITH RECURSIVE anc(id) AS (SELECT TYPE_KEY FROM PRJ_NOE WHERE NOE_ID = ? UNION '
            'SELECT t.TYPE_PARENT_KEY FROM DEF_TYPE t JOIN anc ON t.TYPE_ID = anc.id WHERE t.TYPE_PARENT_KEY IS NOT NULL) '
            'SELECT v.VUE_CODE FROM DEF_VUE v JOIN anc ON v.TYPE_KEY = anc.id ORDER BY v.VUE_ORDRE', (c1,)).fetchall()
        constats.append(('vues d\'une chambre FT héritées du type CHB', len(vues) == 8, [v[0] for v in vues]))
        journal = con.execute(
            'SELECT c.COM_TYPE, c.COM_AUTEUR, c.COM_ORIGINE, i.INT_CODE_EXT FROM PRJ_COMMENTAIRE c '
            'LEFT JOIN PRJ_INTERVENTION i ON i.INT_ID = c.INT_KEY WHERE c.ENT_KEY = ? AND c.OBJ_KEY = ? '
            'AND c.DATE_ABD IS NULL ORDER BY c.DATE_CREA, c.COM_ID', (ent_noe, c1)).fetchall()
        constats.append(('journal de 1476 du plus ancien au plus récent, abandon exclu : texte repris de FOA (type '
                         'standard par défaut), puis saisie signée de l\'intervention',
                         journal == [('standard', 'FOA', 'FOA', None), ('alert', 'technicien@essai', None, 'essai-i1')],
                         journal))
        constats.append(('longueur cartographique L1 (m)', True,
                         round(q('SELECT GLength(GEOMETRY) FROM PRJ_LINEAIRE WHERE LIN_ID = ?', l1)[0], 1)))
        tire = con.execute(
            'SELECT c.CAB_LIB, l.LIN_CODE_EXT, p.PCB_RANG, e.EQO_LIB, (SELECT COUNT(*) FROM optique.OPT_FIBRE f '
            'WHERE f.CAB_KEY = c.CAB_ID) FROM optique.OPT_CABLE c JOIN optique.OPT_PASSAGE s ON s.CAB_KEY = c.CAB_ID '
            'JOIN PRJ_LINEAIRE l ON l.LIN_ID = s.LIN_KEY JOIN infra.INF_PORTEE_CABLE p ON p.PCB_ID = s.PCB_KEY '
            'JOIN optique.OPT_EQUIPEMENT e ON e.EQU_KEY = c.EQU2_KEY WHERE c.CAB_ID = ?', (cb1,)).fetchall()
        constats.append(('câble tiré : portée et câble porté, PBO d\'extrémité, fibres',
                         tire == [('CDI-1', 'essai-l2', 1, 'PBO-1', 12)], tire))
        mesure = con.execute(
            'SELECT m.MES_LNG, f.FIB_NUM, p.POS_AFFECT FROM optique.OPT_MESURE m JOIN optique.OPT_ROUTE_FIBRE r '
            'ON r.RTE_KEY = m.RTE_KEY JOIN optique.OPT_FIBRE f ON f.FIB_ID = r.FIB_KEY JOIN optique.OPT_POSITION p '
            'ON p.FIB1_KEY = f.FIB_ID WHERE m.RTE_KEY = ?', (r1,)).fetchall()
        constats.append(('mesure de la route : fibre en attente abonné au PBO', mesure == [(33.5, 1, 'ABONNE')], mesure))
        bal = con.execute(
            'SELECT i.IAD_NB_LOG, h.HAB_LIB, COUNT(l.LOC_ID), MIN(e.EQU_CODE_EXT) FROM immeuble.IMB_ADRESSE i '
            'JOIN immeuble.DEF_IMB_HABITAT h ON h.HAB_ID = i.HAB_KEY JOIN immeuble.IMB_LOCAL l ON l.ADR_KEY = i.ADR_KEY '
            'JOIN infra.INF_EQUIPEMENT e ON e.EQU_ID = l.EQU_KEY WHERE i.ADR_KEY = ? GROUP BY i.IAD_ID', (a1,)).fetchall()
        constats.append(('BAL : logements, habitat, locaux desservis par le PBO', bal == [(2, 'Pavillon', 2, 'essai-e1')],
                         bal))

        # refus attendus
        for libelle, sql, params in (
                ('chambre sur un nœud inexistant', 'INSERT INTO chambre.CHB_CHAMBRE (NOE_KEY) VALUES (999999)', ()),
                ('position sur une conduite inexistante',
                 'INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y) VALUES (?, 999999, 0, 0)',
                 (faces[c1],)),
                ('face de largeur nulle',
                 "INSERT INTO chambre.CHB_FACE (CHB_KEY, FAC_CODE, FAC_LARG, FAC_HAUT) VALUES (?, 'C', 0, ?)",
                 (chambres[c2], haut)),
                ('face de hauteur négative',
                 'UPDATE chambre.CHB_FACE SET FAC_HAUT = -0.6 WHERE FAC_ID = ?', (faces[c1],)),
                ('face sans dimensions', "INSERT INTO chambre.CHB_FACE (CHB_KEY, FAC_CODE) VALUES (?, 'D')",
                 (chambres[c2],)),
                ('conduite sur un linéaire inexistant',
                 "INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY) VALUES ('x', 999999)", ()),
                ('conduite sans linéaire ni chambre', "INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT) VALUES ('x')", ()),
                ('conduite sur un linéaire et une chambre',
                 "INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY, NOE_KEY) VALUES ('x', ?, ?)", (l1, c1)),
                ('suppression d\'un nœud porteur d\'un poteau',
                 'DELETE FROM PRJ_NOE WHERE NOE_ID = ?', (p2,)),
                ('suppression d\'une conduite placée dans un masque',
                 'DELETE FROM infra.INF_CONDUITE WHERE CD_ID = ?', (cd1,)),
                ('linéaire bouclé sur un même nœud',
                 "INSERT INTO PRJ_LINEAIRE (LIN_CODE_EXT, TYPE_KEY, NOE1_KEY, NOE2_KEY, GEOMETRY) "
                 "VALUES ('x', 1001, ?, ?, MakeLine(MakePoint(0,0,2154), MakePoint(1,1,2154)))", (c1, c1)),
                ('commentaire d\'un type inconnu',
                 "INSERT INTO PRJ_COMMENTAIRE (COM_CODE_EXT, ENT_KEY, OBJ_KEY, COM_TYPE, COM_TEXTE, COM_AUTEUR) "
                 "VALUES ('x', ?, ?, 'urgent', 'x', 'x')", (ent_noe, c1)),
                ('commentaire au texte blanc (espaces, saut de ligne, tabulation)',
                 'INSERT INTO PRJ_COMMENTAIRE (COM_CODE_EXT, ENT_KEY, OBJ_KEY, COM_TEXTE, COM_AUTEUR) '
                 "VALUES ('x', ?, ?, ' ' || char(10, 9) || ' ', 'x')", (ent_noe, c1)),
                ('commentaire à l\'auteur blanc',
                 'INSERT INTO PRJ_COMMENTAIRE (COM_CODE_EXT, ENT_KEY, OBJ_KEY, COM_TEXTE, COM_AUTEUR) '
                 "VALUES ('x', ?, ?, 'x', '  ')", (ent_noe, c1)),
                ('câble vers un nœud inexistant',
                 "INSERT INTO optique.OPT_CABLE (CAB_CODE_EXT, NOE1_KEY, NOE2_KEY) VALUES ('x', ?, 999999)", (p1,)),
                ('passage sur un linéaire inexistant',
                 'INSERT INTO optique.OPT_PASSAGE (CAB_KEY, LIN_KEY) VALUES (?, 999999)', (cb1,)),
                ('passage à la fois porté et en conduite',
                 'INSERT INTO optique.OPT_PASSAGE (CAB_KEY, LIN_KEY, PCB_KEY, CDC_KEY) VALUES '
                 '(?, ?, ?, (SELECT MIN(CDC_ID) FROM infra.INF_CD_CABLE))', (cb1, l1, pcb1)),
                ('deux fibres de même rang dans un câble',
                 'INSERT INTO optique.OPT_FIBRE (CAB_KEY, FIB_NUM) VALUES (?, 1)', (cb1,)),
                ('position sans fibre', 'INSERT INTO optique.OPT_POSITION (CAS_KEY, POS_NUM) VALUES (?, 2)', (cs1,)),
                ('suppression d\'un équipement porteur de cassettes et de locaux',
                 'DELETE FROM infra.INF_EQUIPEMENT WHERE EQU_ID = ?', (e1,)),
                ('BAL d\'une adresse inexistante',
                 'INSERT INTO immeuble.IMB_ADRESSE (ADR_KEY) VALUES (999999)', ()),
                ('suppression d\'une adresse porteuse de locaux', 'DELETE FROM PRJ_ADRESSE WHERE ADR_ID = ?', (a1,))):
            try:
                con.execute('SAVEPOINT refus')
                con.execute(sql, params)
                constats.append((f'refus : {libelle}', False, 'accepté'))
            except sqlite3.Error as e:
                constats.append((f'refus : {libelle}', True, str(e)))
            finally:
                con.execute('ROLLBACK TO refus')
                con.execute('RELEASE refus')
        constats.append(('orphelins après le scénario', all(n == 0 for _, n in orphelins(con)),
                         [o for o in orphelins(con) if o[1]]))
    finally:
        con.execute('ROLLBACK TO essai')
        con.execute('RELEASE essai')
    restes = q('SELECT (SELECT COUNT(*) FROM PRJ_NOE) + (SELECT COUNT(*) FROM infra.INF_CONDUITE) '
               '+ (SELECT COUNT(*) FROM chambre.CHB_POSITION) + (SELECT COUNT(*) FROM poteau.POT_POTEAU) '
               '+ (SELECT COUNT(*) FROM PRJ_COMMENTAIRE) + (SELECT COUNT(*) FROM optique.OPT_FIBRE) '
               '+ (SELECT COUNT(*) FROM immeuble.IMB_LOCAL)')[0]
    constats.append(('annulation complète du scénario (noyau et modules)', restes == 0, restes))
    return constats


def main():
    # migrer-commentaires : ancien nom de la commande, simple alias de migrer
    if len(sys.argv) == 4 and sys.argv[1] in ('migrer', 'migrer-commentaires'):
        try:
            rapport = migrer(*sys.argv[2:4])
        except (RuntimeError, sqlite3.Error) as e:
            sys.exit(f'{sys.argv[1]} : {e} ; projet inchangé')
        for ligne in rapport:
            print(ligne)
        return
    if len(sys.argv) < 5 or sys.argv[1] != 'construire':
        print(__doc__)
        sys.exit(1)
    dossier, foa, qgis = sys.argv[2:5]
    for ligne in construire(dossier, foa, qgis):
        print(ligne)
    con = ouvrir(dossier, qgis)
    print('\nModules attachés :', [r[1] for r in con.execute('PRAGMA database_list')])
    print('Journaux :', {r[1]: con.execute(f'PRAGMA {r[1]}.journal_mode').fetchone()[0]
                         for r in con.execute('PRAGMA database_list') if r[1] != 'temp'})
    print('Triggers TEMP d\'intégrité :', con.execute("SELECT COUNT(*) FROM temp.sqlite_master "
                                                       "WHERE type = 'trigger'").fetchone()[0])
    print('Types :', [r[0] for r in con.execute('SELECT TYPE_CODE FROM DEF_TYPE ORDER BY TYPE_ID')])
    print('Vues :', con.execute('SELECT COUNT(*) FROM DEF_VUE').fetchone()[0],
          '| Entités :', [r[0] for r in con.execute('SELECT ENT_TABLE FROM DEF_ENTITE')])
    print('Orphelins dans les référentiels :', [o for o in orphelins(con) if o[1]] or 'aucun')
    if '--essai' in sys.argv:
        print('\nEssai :')
        for libelle, ok, detail in essai(con):
            print(f'  [{"OK" if ok else "ÉCHEC"}] {libelle} : {detail}')


if __name__ == '__main__':
    main()
