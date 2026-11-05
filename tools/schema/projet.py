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
  converties des cellules FOA en m) ; 0.4.0, occupation des conduites (module infra 0.2.0 : état XM, référentiel des
  diamètres DEF_CD_DIAM, rang et nature des câbles de conduite, sous-tubes numérotés dans leur parent, état et taux
  d'occupation recalculés) ; 0.5.0, visuels des équipements (DEF_VUE.VUE_ENTITE, vues de la galerie d'un équipement,
  vue « Boîtier optique » des supports retirée, ses photos reprises en visuel libre de l'équipement ou du support) ;
  0.6.0, câbles de raccordement (module optique 0.3.0 : OPT_CABLE.NOE2_KEY facultatif, adresse desservie ADR2_KEY,
  tracé propre GEOMETRY, base du module déclarée à SpatiaLite après la transaction).
  migrer-commentaires, ancien nom de la commande, en est un simple alias ;
- recalculer_occupation : règle d'état de FOA (conduite portant un câble ou un sous-tube : V → X, R → XR, M → XM) et
  taux d'occupation CD_OCCUP par la formule des sections, pour tout le projet.

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
# 0.2.0 : journal des commentaires (PRJ_COMMENTAIRE) ; 0.3.0 : masques métriques ; 0.4.0 : occupation des conduites ;
# 0.5.0 : visuels des équipements ; 0.6.0 : câbles de raccordement (optique 0.3.0)
MODELE_VERSION = '0.6.0'
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

def inserer_vue(noyau, module, v):
    """Vue attendue v d'un manifeste (DEF_VUE) : d'un type de support (« type » : TYPE_CODE) ou des éléments d'une
    table porteuse (« entite » : INF_EQUIPEMENT, galerie d'un équipement, noyau 0.3.0)."""
    if ('type' in v) == ('entite' in v):
        raise ValueError(f'vue {v["code"]} du module {module} : « type » ou « entite », l\'un ou l\'autre')
    type_id = None
    if 'type' in v:
        type_id = noyau.execute('SELECT TYPE_ID FROM DEF_TYPE WHERE TYPE_CODE = ?', (v['type'],)).fetchone()[0]
    noyau.execute('INSERT INTO DEF_VUE (TYPE_KEY, VUE_ENTITE, VUE_CODE, VUE_LIB, VUE_ORDRE, VUE_OBLIGATOIRE, '
                  'VUE_ACTION, MOD_CODE) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                  (type_id, v.get('entite'), v['code'], v['lib'], v['ordre'], v['obligatoire'], v.get('action'),
                   module))


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
            inserer_vue(noyau, m['code'], v)
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


def instructions_du_module(module):
    """Instructions des scripts d'un module, dans l'ordre, sans les commentaires qui les précèdent : ceux de leur
    corps restent, comme dans le texte que SQLite conserve pour un projet neuf."""
    m = next(m for m in manifestes() if m['code'] == module)
    courante = ''
    for script in m['scripts']:
        for ligne in open(os.path.join(m['dossier'], script), encoding='utf-8'):
            courante += ligne
            if sqlite3.complete_statement(courante):
                lignes = courante.splitlines()
                while lignes and (not lignes[0].strip() or lignes[0].lstrip().startswith('--')):
                    lignes.pop(0)
                yield '\n'.join(lignes).strip()
                courante = ''


def instructions(module, table):
    """Instructions des scripts d'un module qui créent une table non spatiale et ses index : mise à niveau d'un
    projet existant à partir du schéma, sans le recopier."""
    return [sql for sql in instructions_du_module(module)
            if re.match(rf'CREATE (UNIQUE )?(TABLE|INDEX \w+ ON) {table}\b', sql)]


def insertions(module, table, schema):
    """Instructions des scripts d'un module qui remplissent un référentiel, à exécuter dans la base attachée schema
    sans écraser l'existant (INSERT OR IGNORE : une ligne déjà là, par sa clé ou un code unique, est gardée telle
    quelle) : lignes du schéma ajoutées à un projet existant."""
    return [re.sub(r'^INSERT INTO (\w+)', rf'INSERT OR IGNORE INTO {schema}.\1', sql, count=1)
            for sql in instructions_du_module(module) if re.match(rf'INSERT INTO {table}\b', sql)]


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
    l'ancienne ligne}, pour une colonne nouvelle ou convertie (une colonne nouvelle laissée vide y figure aussi, avec
    l'expression 'NULL' : toute colonne nouvelle est un choix explicite de l'étape, jamais un oubli) ; retirees :
    {table : colonnes que le schéma ne porte plus}, seules à pouvoir se perdre. Une autre colonne perdue, une colonne
    nouvelle absente de valeurs ou un effectif changé annulent la reprise. Rend les effectifs par table."""
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


# Occupation des conduites (module infra 0.2.0) ------------------------------------------------------

# Règle d'état de FOA Explorer : une conduite qui porte un câble ou un sous-tube est occupée (FOA ajoute « 2 » au code
# d'état dès qu'il y a des câbles). Un état vide vaut V.
ETAT_OCCUPE = (('V', 'X'), ('R', 'XR'), ('M', 'XM'))
ETATS_MAUVAIS = ('M', 'XM')         # taux de 100 % sans câble
DECIMALES_OCCUPATION = 1            # taux arrondi au dixième


def recalculer_occupation(con, schema='infra'):
    """État et taux d'occupation de toutes les conduites du projet, recalculés d'après leurs câbles (INF_CD_CABLE) et
    leurs sous-tubes non abandonnés : comme le terminal à chaque modification des câbles.
    - état : une conduite qui porte un câble ou un sous-tube passe de V (ou vide) à X, de R à XR, de M à XM ;
    - CD_OCCUP (%) = Σ CDC_NB × (CDC_DIAM / DIAM_INT)² × 100, DIAM_INT diamètre intérieur du diamètre nominal CD_DIAM
      (DEF_CD_DIAM), arrondi au dixième ; sans câble, 100 pour une conduite M ou XM, 0 sinon ; NULL si le calcul est
      impossible (CD_DIAM absent de DEF_CD_DIAM, câble sans diamètre). Les sous-tubes ne comptent pas dans le taux de
      leur parent, comme dans FOA.
    Idempotent. Rend ({(ancien état, nouvel état) : conduites}, nombre de taux modifiés)."""
    s = schema
    etats = dict(con.execute(f'SELECT ETAT_CODE, ETAT_ID FROM {s}.DEF_CD_ETAT'))
    manquants = sorted({c for paire in ETAT_OCCUPE for c in paire} - set(etats))
    if manquants:
        raise RuntimeError(f'{s}.DEF_CD_ETAT sans les états {manquants}')
    cables = (f'SELECT 1 FROM {s}.INF_CD_CABLE c WHERE c.CD_KEY = INF_CONDUITE.CD_ID AND c.DATE_ABD IS NULL')
    sous_tubes = (f'SELECT 1 FROM {s}.INF_CONDUITE e WHERE e.CD_PARENT_KEY = INF_CONDUITE.CD_ID '
                  'AND e.DATE_ABD IS NULL')
    passages = Counter()
    for avant, apres in ETAT_OCCUPE:
        n = con.execute(f'UPDATE {s}.INF_CONDUITE SET ETAT_KEY = ? WHERE COALESCE(ETAT_KEY, ?) = ? '
                        f'AND (EXISTS ({cables}) OR EXISTS ({sous_tubes}))',
                        (etats[apres], etats['V'], etats[avant])).rowcount
        if n:
            passages[avant, apres] = n
    mauvais = ', '.join(str(etats[c]) for c in ETATS_MAUVAIS)
    taux = (f'CASE WHEN NOT EXISTS ({cables}) THEN CASE WHEN ETAT_KEY IN ({mauvais}) THEN 100.0 ELSE 0.0 END '
            f'ELSE (SELECT CASE WHEN COUNT(c.CDC_DIAM) = COUNT(*) AND d.DIAM_INT > 0 THEN '
            f'ROUND(SUM(c.CDC_NB * (c.CDC_DIAM / d.DIAM_INT) * (c.CDC_DIAM / d.DIAM_INT)) * 100, '
            f'{DECIMALES_OCCUPATION}) END FROM {s}.INF_CD_CABLE c LEFT JOIN {s}.DEF_CD_DIAM d '
            f'ON d.DIAM_NOMINAL = INF_CONDUITE.CD_DIAM WHERE c.CD_KEY = INF_CONDUITE.CD_ID AND c.DATE_ABD IS NULL) END')
    modifies = con.execute(f'UPDATE {s}.INF_CONDUITE SET CD_OCCUP = {taux} WHERE CD_OCCUP IS NOT ({taux})').rowcount
    return passages, modifies


def numeroter_sous_tubes(con, schema='infra'):
    """CD_NUM d'un sous-tube = son rang dans son parent (1, 2… ; affiché N.k), dans l'ordre de l'ancien numéro (numéro
    de l'alvéole dans la chambre pour un sous-tube repris de FOA), puis de CD_ID. Idempotent. Rend le nombre de
    sous-tubes renumérotés."""
    rangs, n = Counter(), 0
    for cd, parent, num in con.execute(f'SELECT CD_ID, CD_PARENT_KEY, CD_NUM FROM {schema}.INF_CONDUITE '
                                       'WHERE CD_PARENT_KEY IS NOT NULL ORDER BY CD_PARENT_KEY, CD_NUM IS NULL, CD_NUM, '
                                       'CD_ID').fetchall():
        rangs[parent] += 1
        if num != rangs[parent]:
            con.execute(f'UPDATE {schema}.INF_CONDUITE SET CD_NUM = ? WHERE CD_ID = ?', (rangs[parent], cd))
            n += 1
    return n


def resume_occupation(con, schema='infra'):
    """Constat sur l'occupation : câbles de conduite, taux calculés, non calculables, au-delà de 100 %."""
    lignes, cables = con.execute(f'SELECT COUNT(*), COALESCE(SUM(CDC_NB), 0) FROM {schema}.INF_CD_CABLE '
                                 'WHERE DATE_ABD IS NULL').fetchone()
    calcules, vides, pleins = con.execute(
        f'SELECT COUNT(CD_OCCUP), SUM(CD_OCCUP IS NULL), SUM(CD_OCCUP > 100) FROM {schema}.INF_CONDUITE').fetchone()
    return (f'{lignes} ligne{"s" * (lignes > 1)} de câbles ({cables} câble{"s" * (cables > 1)}), {calcules} taux '
            f'calculés, {vides or 0} non calculables, {pleins or 0} au-delà de 100 %')


CLES_RECOPIE = ('CDC_NB', 'CDC_DIAM', 'MAT_KEY', 'CDC_COMMENT')    # colonnes comparées des deux moitiés d'une liste


def retirer_recopies_miroir(con, inscrits):
    """Câbles recopiés en miroir par le chargement FOA antérieur au module infra 0.2.0 : FOA recopie les câbles d'une
    alvéole dans l'alvéole d'en face (RepliqueCoCab), et l'ancien tools/essai/charger_essai.py reprenait les deux
    listes dans la conduite commune. Pour une conduite placée (positions non abandonnées) dans deux chambres distinctes,
    dont toutes les lignes viennent d'un chargement (SRC_MODIF = 'import') et dont la liste, dans l'ordre des CDC_ID,
    est faite de deux moitiés identiques sur CLES_RECOPIE, la seconde moitié est retirée, sauf si un passage du module
    optique (OPT_PASSAGE.CDC_KEY) y renvoie (conduite laissée telle quelle et signalée). Une liste d'au moins deux lignes
    qui ne se scinde pas ainsi (relevé divergent des deux côtés, ou câbles différents réellement présents) est signalée,
    à contrôler sur la base FOA. Sans module chambre, rien n'est fait. Rend (lignes retirées, conduites dédoublées,
    conduites gardées pour un passage optique, conduites à contrôler), codes CD_CODE_EXT."""
    if 'chambre' not in inscrits:
        return 0, [], [], []
    deux = {r[0] for r in con.execute(
        'SELECT p.CD_KEY FROM chambre.CHB_POSITION p JOIN chambre.CHB_FACE f ON f.FAC_ID = p.FAC_KEY '
        'WHERE p.DATE_ABD IS NULL GROUP BY p.CD_KEY HAVING COUNT(DISTINCT f.CHB_KEY) >= 2')}
    listes, importees = {}, {}
    for cdc, cd, src, *cles in con.execute(f'SELECT CDC_ID, CD_KEY, SRC_MODIF, {", ".join(CLES_RECOPIE)} '
                                           'FROM infra.INF_CD_CABLE ORDER BY CDC_ID'):
        if cd in deux:
            listes.setdefault(cd, []).append((cdc, tuple(cles)))
            importees[cd] = importees.get(cd, True) and src == 'import'
    codes = dict(con.execute('SELECT CD_ID, CD_CODE_EXT FROM infra.INF_CONDUITE'))
    optique = 'optique' in inscrits
    retirees, dedoublees, gardees, a_controler = 0, [], [], []
    for cd, lignes in sorted(listes.items()):
        if len(lignes) < 2 or not importees[cd]:
            continue
        n = len(lignes) // 2
        if len(lignes) % 2 or [c for _, c in lignes[:n]] != [c for _, c in lignes[n:]]:
            a_controler.append(codes[cd])
            continue
        ids = [i for i, _ in lignes[n:]]
        marques = ','.join('?' * len(ids))
        if optique and con.execute(f'SELECT 1 FROM optique.OPT_PASSAGE WHERE CDC_KEY IN ({marques})', ids).fetchone():
            gardees.append(codes[cd])
            continue
        con.execute(f'DELETE FROM infra.INF_CD_CABLE WHERE CDC_ID IN ({marques})', ids)
        retirees += len(ids)
        dedoublees.append(codes[cd])
    return retirees, dedoublees, gardees, a_controler


def liste_codes(codes, nombre=10):
    return ', '.join(codes[:nombre]) + (f'… ({len(codes)} en tout)' if len(codes) > nombre else '')


def reprendre_occupation(con, inscrits, rapport):
    """Étape 0.4.0, occupation des conduites (module infra 0.2.0) : référentiel des diamètres DEF_CD_DIAM créé et
    rempli, état XM (FOA 32) ajouté à DEF_CD_ETAT (lignes du schéma ajoutées sans écraser l'existant) ; câbles recopiés
    en miroir par l'ancien chargement retirés (retirer_recopies_miroir) ; INF_CD_CABLE reconstruite d'après
    schema/infra/schema.sql (reconstruire) avec CDC_RANG = rang de la ligne dans sa conduite dans l'ordre des CDC_ID et
    CDC_NATURE = FO pour un câble dont la référence MAT_CABLE a des fibres (CAB_NB_FIB > 0), vide sinon (nature
    inconnue) ; sous-tubes numérotés dans leur parent (numeroter_sous_tubes), puis état et taux d'occupation recalculés
    (recalculer_occupation). Annulent la reprise : une table absente, un câble de conduite sans conduite, un CDC_NB
    inférieur à 1, une ligne du référentiel occupée par une autre valeur (identifiant ou code déjà pris). Faite quand
    INF_CD_CABLE porte CDC_RANG et CDC_NATURE (retrait des recopies compris) ; numérotation et recalcul, idempotents,
    sont toujours repassés. Rend {'infra'} quand le module est au niveau, maintenant ou avant."""
    if 'infra' not in inscrits:
        rapport.append('INF_CD_CABLE : module infra non inscrit au projet, rien à reprendre')
        return set()
    absentes = [t for t in ('DEF_CD_ETAT', 'INF_CONDUITE', 'INF_CD_CABLE')
                if not con.execute(f'PRAGMA infra.table_info({t})').fetchall()]
    if absentes:
        raise RuntimeError(f'infra.{", infra.".join(absentes)} : absente{"s" * (len(absentes) > 1)} (base du '
                           f'module incomplète), reprise annulée')
    # référentiels : table créée si elle manque, lignes du schéma ajoutées
    for table in ('DEF_CD_DIAM', 'DEF_CD_ETAT'):
        creee = not con.execute(f'PRAGMA infra.table_info({table})').fetchall()
        if creee:
            for sql in instructions('infra', table):
                con.execute(qualifier(sql, 'infra'))
        avant = con.execute(f'SELECT COUNT(*) FROM infra.{table}').fetchone()[0]
        for sql in insertions('infra', table, 'infra'):
            con.execute(sql)
        ajout = con.execute(f'SELECT COUNT(*) FROM infra.{table}').fetchone()[0] - avant
        rapport.append(f'{table} : ' + ('table créée, ' if creee else '')
                       + (f'{ajout} ligne{"s" * (ajout > 1)} ajoutée{"s" * (ajout > 1)}' if ajout
                          else 'lignes du schéma déjà présentes'))
    attendus = {'DEF_CD_ETAT': ('ETAT_ID', 'ETAT_CODE', [(5, 'XM')]),
                'DEF_CD_DIAM': ('DIAM_ID', 'DIAM_NOMINAL', [(1, 20), (2, 24), (3, 28), (4, 33), (5, 45), (6, 60),
                                                             (7, 80), (8, 100), (9, 150)])}
    for table, (cle, code, lignes) in attendus.items():
        lues = dict(con.execute(f'SELECT {cle}, {code} FROM infra.{table}'))
        ecarts = [f'{cle} {i} : {lues.get(i)} au lieu de {v}' for i, v in lignes if lues.get(i) != v]
        if ecarts:
            raise RuntimeError(f'{table} : ligne déjà prise par une autre valeur ({", ".join(ecarts)}), reprise annulée')
    colonnes = {r[1] for r in con.execute('PRAGMA infra.table_info(INF_CD_CABLE)')}
    nouvelles = {'CDC_RANG', 'CDC_NATURE'}
    if nouvelles <= colonnes:
        rapport.append('INF_CD_CABLE : CDC_RANG et CDC_NATURE déjà là (reprise faite), rien à reconstruire')
    elif nouvelles & colonnes:
        raise RuntimeError(f'INF_CD_CABLE : {", ".join(sorted(nouvelles & colonnes))} sans '
                           f'{", ".join(sorted(nouvelles - colonnes))}, reprise annulée')
    else:
        orphelines = con.execute('SELECT COUNT(*) FROM infra.INF_CD_CABLE c WHERE NOT EXISTS '
                                 '(SELECT 1 FROM infra.INF_CONDUITE d WHERE d.CD_ID = c.CD_KEY)').fetchone()[0]
        if orphelines:
            raise RuntimeError(f'INF_CD_CABLE : {orphelines} câble{"s" * (orphelines > 1)} sans conduite, reprise '
                               f'annulée')
        n = con.execute("SELECT COUNT(*) FROM infra.INF_CD_CABLE WHERE NOT (typeof(CDC_NB) = 'integer' "
                        'AND CDC_NB >= 1)').fetchone()[0]
        if n:
            raise RuntimeError(f'INF_CD_CABLE : {n} ligne{"s" * (n > 1)} de CDC_NB non entier ou inférieur à 1, '
                               f'reprise annulée')
        retirees, dedoublees, gardees, a_controler = retirer_recopies_miroir(con, inscrits)
        rapport.append('INF_CD_CABLE : ' + (
            f'{retirees} ligne{"s" * (retirees > 1)} recopiée{"s" * (retirees > 1)} en miroir retirée'
            f'{"s" * (retirees > 1)} ({len(dedoublees)} conduite{"s" * (len(dedoublees) > 1)} : '
            f'{liste_codes(dedoublees)})' if retirees
            else 'aucune ligne recopiée en miroir') + (
            f' ; gardées, un passage optique y renvoyant : {liste_codes(gardees)}' if gardees else '') + (
            f' ; listes divergentes des deux côtés, à contrôler sur la base FOA : {liste_codes(a_controler)}'
            if a_controler else ''))
        effectifs = reconstruire(con, 'infra', ('INF_CD_CABLE',), {
            ('INF_CD_CABLE', 'CDC_RANG'): 'ROW_NUMBER() OVER (PARTITION BY CD_KEY ORDER BY CDC_ID)',
            ('INF_CD_CABLE', 'CDC_NATURE'): "CASE WHEN EXISTS (SELECT 1 FROM infra.MAT_CABLE m WHERE m.MAT_ID = "
                                            "reprise_INF_CD_CABLE.MAT_KEY AND m.CAB_NB_FIB > 0) THEN 'FO' END"}, {})
        rangs = con.execute('SELECT COUNT(DISTINCT CD_KEY), MAX(CDC_RANG), SUM(CDC_NATURE IS NOT NULL), '
                            'SUM(CDC_NATURE IS NULL) FROM infra.INF_CD_CABLE').fetchone()
        n, pl = effectifs['INF_CD_CABLE'], 's' * (effectifs['INF_CD_CABLE'] > 1)
        rapport.append(f'INF_CD_CABLE : {n} ligne{pl} reconstruite{pl} d\'après schema/infra/schema.sql, identifiants, '
                       f'séquence et index gardés ; CDC_RANG dans l\'ordre des CDC_ID ({rangs[0]} conduite'
                       f'{"s" * (rangs[0] > 1)}, rang maximal {rangs[1] or 0}) ; CDC_NATURE : FO {rangs[2] or 0} '
                       f'(référence à fibres), inconnue {rangs[3] or 0}')
    n = numeroter_sous_tubes(con)
    rapport.append(f'INF_CONDUITE : {n} sous-tube{"s" * (n > 1)} renuméroté{"s" * (n > 1)} (CD_NUM = rang dans le '
                   f'parent)' if n else 'INF_CONDUITE : sous-tubes déjà numérotés dans leur parent')
    passages, modifies = recalculer_occupation(con)
    detail = ', '.join(f'{a} → {b} {n}' for (a, b), n in sorted(passages.items()))
    rapport.append('INF_CONDUITE : ' + (f'états passés à occupé ({detail})' if passages
                                         else 'aucun état à passer à occupé')
                   + f', {modifies} taux d\'occupation recalculé{"s" * (modifies > 1)}')
    return {'infra'}


# Visuels des équipements (noyau 0.3.0, optique 0.2.0) -------------------------------------------------

VERSION_VISUELS = '0.5.0'           # version du modèle qui donne aux équipements leur galerie
VUE_BOITIER = 'BOITIER'             # vue « Boîtier optique » des supports jusqu'à chambre 0.3.0, poteau 0.2.0, immeuble 0.1.0
VUE_BOITIER_LIB = 'Boîtier optique'
VISUELS_VERSIONS = {'noyau': '0.3.0', 'optique': '0.2.0', 'chambre': '0.4.0', 'poteau': '0.3.0', 'immeuble': '0.2.0'}
# Tables porteuses des photos d'un support : table → (table du module, clé, colonne du nœud) ; None : PRJ_NOE lui-même.
PORTEUR_NOEUD = {'PRJ_NOE': None, 'CHB_CHAMBRE': ('chambre.CHB_CHAMBRE', 'CHB_ID', 'NOE_KEY'),
                 'POT_POTEAU': ('poteau.POT_POTEAU', 'POT_ID', 'NOE_KEY')}


def code_visuel_boitier(code_projet, table, code_objet):
    """VIS_CODE du visuel libre « Boîtier optique » repris de la vue BOITIER, porté par l'objet code_objet (NOE_CODE_EXT
    ou EQU_CODE_EXT) de la table PRJ_NOE ou INF_EQUIPEMENT : UUID v5, le même d'une reprise ou d'un chargement à
    l'autre (tools/essai/charger_essai.py)."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL,
                          f'urn:nge-esplorer:{code_projet}:visuel:{table}:{code_objet}:{VUE_BOITIER}'))


def porteur_boitier(con, ent_table, obj, equipements):
    """Porteur d'une photo de la vue BOITIER : (table, identifiant) de l'équipement auquel elle est déjà rattachée
    (INF_EQUIPEMENT), sinon du seul équipement non abandonné de son nœud, sinon du nœud (PRJ_NOE). equipements : nœud →
    équipements non abandonnés. Une autre table porteuse annule la reprise."""
    if ent_table == 'INF_EQUIPEMENT':
        return 'INF_EQUIPEMENT', obj
    if ent_table not in PORTEUR_NOEUD:
        raise RuntimeError(f'photo de la vue {VUE_BOITIER} portée par {ent_table} : porteur inattendu, reprise annulée')
    source = PORTEUR_NOEUD[ent_table]
    noe = obj if source is None else (con.execute(f'SELECT {source[2]} FROM {source[0]} WHERE {source[1]} = ?',
                                                  (obj,)).fetchone() or [None])[0]
    if noe is None:
        raise RuntimeError(f'photo de la vue {VUE_BOITIER} de {ent_table} {obj} sans nœud, reprise annulée')
    equ = equipements.get(noe, [])
    return ('INF_EQUIPEMENT', equ[0]) if len(equ) == 1 else ('PRJ_NOE', noe)


def reprendre_visuels(con, inscrits, rapport):
    """Étape 0.5.0, visuels des équipements : DEF_VUE reconstruite d'après schema/noyau/schema.sql (reconstruire :
    VUE_ENTITE vide, TYPE_KEY facultatif, mêmes VUE_ID, PRJ_FICHIER.VUE_KEY intact) ; vues de la galerie d'un
    équipement (VUE_ENTITE INF_EQUIPEMENT) ajoutées d'après le manifeste optique si le module est inscrit ; vue
    « Boîtier optique » (BOITIER) des supports retirée : ses photos, abandonnées comprises, deviennent le visuel libre
    « Boîtier optique » (VUE_KEY vide, VIS_CODE déterministe : code_visuel_boitier) de leur équipement s'il est déjà
    leur porteur ou si leur nœud porte exactement un équipement non abandonné, sinon de leur nœud (porteur_boitier) ;
    rangs renumérotés par porteur dans l'ordre FIC_RANG, FIC_ID, la première en photo de référence. Ordres des vues des
    supports alignés sur les manifestes. Idempotente : une seconde reprise ne trouve ni colonne à créer, ni vue à
    ajouter, ni vue BOITIER. Rend les modules au niveau."""
    au_niveau = {'noyau'}
    colonnes = {r[1] for r in con.execute('PRAGMA main.table_info(DEF_VUE)')}
    if 'VUE_ENTITE' in colonnes:
        rapport.append('DEF_VUE : VUE_ENTITE déjà présente (reprise faite)')
    else:
        # PRJ_FICHIER.VUE_KEY désigne DEF_VUE : contrôle des références différé à la fin de la transaction, les vues
        # étant recopiées avec leurs identifiants
        con.execute('PRAGMA defer_foreign_keys = ON')
        n = reconstruire(con, 'noyau', ('DEF_VUE',), {('DEF_VUE', 'VUE_ENTITE'): 'NULL'}, {})['DEF_VUE']
        rapport.append(f'DEF_VUE : reconstruite d\'après schema/noyau/schema.sql ({n} vues, VUE_ENTITE, TYPE_KEY '
                       f'facultatif, identifiants gardés)')
    mods = {m['code']: m for m in manifestes()}
    if 'optique' in inscrits:
        ajoutees = []
        for v in mods['optique']['vues']:
            if 'entite' in v and not con.execute('SELECT 1 FROM DEF_VUE WHERE VUE_ENTITE = ? AND VUE_CODE = ?',
                                                 (v['entite'], v['code'])).fetchone():
                inserer_vue(con, 'optique', v)
                ajoutees.append(v['code'])
        rapport.append(f'DEF_VUE : vues d\'équipement ajoutées ({", ".join(ajoutees)})' if ajoutees
                       else 'DEF_VUE : vues d\'équipement déjà présentes')
        au_niveau.add('optique')
    else:
        rapport.append('DEF_VUE : module optique non inscrit, pas de vue d\'équipement')
    ids = [r[0] for r in con.execute('SELECT VUE_ID FROM DEF_VUE WHERE TYPE_KEY IS NOT NULL AND VUE_CODE = ?',
                                     (VUE_BOITIER,))]
    if ids:
        code_projet = con.execute('SELECT PRJ_CODE_EXT FROM SYS_PROJET').fetchone()[0]
        entites = dict(con.execute('SELECT ENT_ID, ENT_TABLE FROM DEF_ENTITE'))
        ent_id = {t: i for i, t in entites.items()}
        equipements = {}
        if 'infra' in inscrits:
            for equ, noe in con.execute('SELECT EQU_ID, NOE_KEY FROM infra.INF_EQUIPEMENT WHERE DATE_ABD IS NULL '
                                        'ORDER BY EQU_ID'):
                equipements.setdefault(noe, []).append(equ)
        codes = {'PRJ_NOE': 'SELECT NOE_CODE_EXT FROM PRJ_NOE WHERE NOE_ID = ?',
                 'INF_EQUIPEMENT': 'SELECT EQU_CODE_EXT FROM infra.INF_EQUIPEMENT WHERE EQU_ID = ?'}
        groupes, effectifs = {}, Counter()
        marques = ','.join('?' * len(ids))
        for fic, ent, obj in con.execute(f'SELECT FIC_ID, ENT_KEY, OBJ_KEY FROM PRJ_FICHIER WHERE VUE_KEY IN ({marques}) '
                                         f'ORDER BY FIC_RANG, FIC_ID', ids).fetchall():
            table, porteur = porteur_boitier(con, entites.get(ent), obj, equipements)
            if table not in ent_id:
                raise RuntimeError(f'DEF_ENTITE : {table} absente, reprise annulée')
            code = con.execute(codes[table], (porteur,)).fetchone()
            if code is None:
                raise RuntimeError(f'{table} {porteur} absent, porteur de la photo {fic}, reprise annulée')
            groupes.setdefault((table, porteur, code[0]), []).append(fic)
            effectifs[table] += 1
        for (table, porteur, code), fics in groupes.items():
            vis = code_visuel_boitier(code_projet, table, code)
            for rang, fic in enumerate(fics, 1):
                con.execute('UPDATE PRJ_FICHIER SET ENT_KEY = ?, OBJ_KEY = ?, VUE_KEY = NULL, VIS_CODE = ?, '
                            'VIS_LIB = ?, FIC_RANG = ?, FIC_PRINCIPALE = ? WHERE FIC_ID = ?',
                            (ent_id[table], porteur, vis, VUE_BOITIER_LIB, rang, int(rang == 1), fic))
        con.execute(f'DELETE FROM DEF_VUE WHERE VUE_ID IN ({marques})', ids)
        rapport.append(f'PRJ_FICHIER : photos de la vue {VUE_BOITIER} reprises en visuel libre « {VUE_BOITIER_LIB} » : '
                       f'{effectifs["INF_EQUIPEMENT"]} d\'équipement, {effectifs["PRJ_NOE"]} de support '
                       f'({len(groupes)} visuel{"s" * (len(groupes) > 1)})' if groupes
                       else f'PRJ_FICHIER : aucune photo de la vue {VUE_BOITIER}')
        rapport.append(f'DEF_VUE : {len(ids)} vue{"s" * (len(ids) > 1)} {VUE_BOITIER} retirée{"s" * (len(ids) > 1)}')
    else:
        rapport.append(f'DEF_VUE : aucune vue {VUE_BOITIER} de support (reprise faite)')
    # ordres des vues des supports d'après les manifestes (BOITIER retirée en tête des chambres et des poteaux)
    reordonnees = 0
    for code, m in mods.items():
        if code not in inscrits:
            continue
        for v in m['vues']:
            if 'type' in v:
                reordonnees += con.execute(
                    'UPDATE DEF_VUE SET VUE_ORDRE = ? WHERE VUE_CODE = ? AND VUE_ORDRE <> ? AND TYPE_KEY = '
                    '(SELECT TYPE_ID FROM DEF_TYPE WHERE TYPE_CODE = ?)',
                    (v['ordre'], v['code'], v['ordre'], v['type'])).rowcount
        if code in ('chambre', 'poteau', 'immeuble'):
            au_niveau.add(code)
    if reordonnees:
        rapport.append(f'DEF_VUE : {reordonnees} ordre{"s" * (reordonnees > 1)} de vue aligné{"s" * (reordonnees > 1)} '
                       f'sur les manifestes')
    return au_niveau

# Câbles de raccordement (module optique 0.3.0) -------------------------------------------------------

VERSION_RACCORDEMENT = '0.6.0'      # version du modèle qui passe le module optique en 0.3.0
OPTIQUE_RACCORDEMENT = '0.3.0'


def reprendre_raccordements(con, inscrits, rapport):
    """Étape 0.6.0, câbles de raccordement (module optique 0.3.0) : OPT_CABLE reconstruite d'après
    schema/optique/schema.sql (reconstruire : NOE2_KEY facultatif, ADR2_KEY vide, contrôle « NOE2_KEY ou ADR2_KEY »,
    index ; mêmes CAB_ID et séquence), puis colonne GEOMETRY ajoutée vide (tracé propre d'un câble de raccordement),
    déclarée à SpatiaLite après la transaction (spatialiser_optique). Les tables qui référencent OPT_CABLE (passages,
    lovages, fibres, et par elles positions, routes et mesures) restent intactes : clés étrangères différées le temps
    de la reconstruction (supprimer l'ancienne table orpheline un instant leurs lignes, la recopie les rattache), puis
    contrôlées (foreign_key_check) avant de rendre la main. Annulent la reprise : une table absente, une référence
    interne sans cible avant ou après. Faite quand OPT_CABLE porte ADR2_KEY. Rend {'optique'} quand le module est au
    niveau, maintenant ou avant."""
    if 'optique' not in inscrits:
        rapport.append('OPT_CABLE : module optique non inscrit au projet, rien à reprendre')
        return set()
    colonnes = {r[1] for r in con.execute('PRAGMA optique.table_info(OPT_CABLE)')}
    if not colonnes:
        raise RuntimeError('optique.OPT_CABLE absente (base du module incomplète), reprise annulée')
    if 'ADR2_KEY' in colonnes:
        rapport.append('OPT_CABLE : adresse desservie et tracé propre déjà en place (reprise faite)')
        return {'optique'}

    def orphelines():
        return Counter(f'{t} → {parent}' for t, _, parent, _ in con.execute('PRAGMA optique.foreign_key_check'))

    avant = orphelines()
    if avant:
        detail = ', '.join(f'{k} {v}' for k, v in sorted(avant.items()))
        raise RuntimeError(f'optique : références internes sans cible ({detail}), reprise annulée')
    # contraintes différées jusqu'à la fin de la transaction (remises d'office au COMMIT ou au ROLLBACK)
    con.execute('PRAGMA defer_foreign_keys = ON')
    effectifs = reconstruire(con, 'optique', ('OPT_CABLE',), {('OPT_CABLE', 'ADR2_KEY'): 'NULL'}, {})
    con.execute('ALTER TABLE optique.OPT_CABLE ADD COLUMN GEOMETRY LINESTRING')
    apres = orphelines()
    if apres:
        detail = ', '.join(f'{k} {v}' for k, v in sorted(apres.items()))
        raise RuntimeError(f'optique : références perdues par la reconstruction ({detail}), reprise annulée')
    enfants = {t: con.execute(f'SELECT COUNT(*) FROM optique.{t}').fetchone()[0]
               for t in ('OPT_PASSAGE', 'OPT_LOVE', 'OPT_FIBRE')}
    rapport.append(f'OPT_CABLE : {effectifs["OPT_CABLE"]} câbles, table reconstruite d\'après '
                   f'schema/optique/schema.sql (NOE2_KEY facultatif, ADR2_KEY, GEOMETRY), identifiants et séquence '
                   f'gardés ; tables qui la référencent intactes (' + ', '.join(f'{t} {n}' for t, n in enfants.items())
                   + ')')
    return {'optique'}


def spatialiser_optique(dossier, qgis_bin, rapport):
    """Base du module optique déclarée à SpatiaLite (module spatial depuis la version 0.3.0) : métadonnées sans les
    EPSG inutiles (Lambert 93 seul, comme un projet neuf), puis colonne OPT_CABLE.GEOMETRY déclarée
    (RecoverGeometryColumn : ligne 2154, contrôles de type et de SRID à l'écriture). SpatiaLite ne déclare une colonne
    que dans la base principale d'une connexion : faite sur une connexion à la base du module, après la transaction de
    la reprise. Idempotente ; sans effet si la colonne n'existe pas encore (reprise annulée)."""
    noyau = connecter(os.path.join(dossier, 'noyau.sqlite'))
    try:
        r = noyau.execute("SELECT MOD_FICHIER FROM SYS_MODULE WHERE MOD_CODE = 'optique'").fetchone()
    finally:
        noyau.close()
    if r is None:
        return
    con = connecter(os.path.join(dossier, r[0]), qgis_bin, True)
    try:
        if 'GEOMETRY' not in {c[1] for c in con.execute('PRAGMA table_info(OPT_CABLE)')}:
            return
        existe = lambda t: con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
                                       (t,)).fetchone() is not None
        if not existe('geometry_columns'):
            con.execute("SELECT InitSpatialMetadata(1, 'NONE')")
            rapport.append('optique : métadonnées SpatiaLite créées')
        if not con.execute('SELECT 1 FROM spatial_ref_sys WHERE srid = 2154').fetchone():
            con.execute('SELECT InsertEpsgSrid(2154)')
        if not con.execute("SELECT 1 FROM geometry_columns WHERE lower(f_table_name) = 'opt_cable' "
                           "AND lower(f_geometry_column) = 'geometry'").fetchone():
            if con.execute("SELECT RecoverGeometryColumn('OPT_CABLE', 'GEOMETRY', 2154, 'LINESTRING', 'XY')"
                           ).fetchone()[0] != 1:
                raise RuntimeError('OPT_CABLE.GEOMETRY : RecoverGeometryColumn en échec')
            rapport.append('OPT_CABLE.GEOMETRY : déclarée à SpatiaLite (LINESTRING, EPSG:2154)')
    finally:
        con.close()


# Étapes de la reprise, dans l'ordre des versions du modèle : (version du modèle, libellé, étape, version de chaque
# module mis au niveau par l'étape). Une étape (con, modules inscrits, rapport) est idempotente et rend les modules mis
# à son niveau, maintenant ou avant.
VERSION_OCCUPATION = '0.4.0'        # version du modèle qui passe le module infra en 0.2.0
ETAPES = ((VERSION_JOURNAL, 'journal des commentaires', reprendre_commentaires,
           {'noyau': VERSION_JOURNAL, 'chambre': VERSION_JOURNAL, 'poteau': VERSION_JOURNAL}),
          (VERSION_MASQUES, 'masques métriques', reprendre_masques, {'chambre': VERSION_MASQUES}),
          (VERSION_OCCUPATION, 'occupation des conduites', reprendre_occupation, {'infra': '0.2.0'}),
          (VERSION_VISUELS, 'visuels des équipements', reprendre_visuels, VISUELS_VERSIONS),
          (VERSION_RACCORDEMENT, 'câbles de raccordement', reprendre_raccordements,
           {'optique': OPTIQUE_RACCORDEMENT}))


def migrer(dossier, qgis_bin):
    """Reprise d'un projet construit avec un modèle antérieur : applique dans l'ordre les étapes en attente (ETAPES)
    en une seule transaction sur le noyau et les modules. Un module inscrit dont le fichier manque est refusé par
    ouvrir, avant toute écriture ; une table absente ou une anomalie propre à une étape annulent toute la reprise. Les
    modules rendus par une étape passent à la version que l'étape leur donne (ETAPES) dans SYS_MODULE, le modèle du
    projet (SYS_PROJET.MODELE_VERSION) à celle de chaque étape passée ; un module non inscrit est ignoré. Idempotente :
    une seconde exécution ne change rien. Après la transaction, la base du module optique est déclarée à SpatiaLite
    (spatialiser_optique), ce qui ne se fait pas dans une base attachée."""
    con = ouvrir(dossier, qgis_bin, integrite=False)
    rapport = []
    inscrits = {r[0] for r in con.execute('SELECT MOD_CODE FROM SYS_MODULE')}
    con.execute('BEGIN')
    try:
        for etape_version, libelle, etape, versions in ETAPES:
            lignes = []
            au_niveau = etape(con, inscrits, lignes)
            for code, v in con.execute('SELECT MOD_CODE, MOD_VERSION FROM SYS_MODULE ORDER BY MOD_ID').fetchall():
                if code in au_niveau and version(v) < version(versions[code]):
                    con.execute('UPDATE SYS_MODULE SET MOD_VERSION = ? WHERE MOD_CODE = ?', (versions[code], code))
                    lignes.append(f'SYS_MODULE : {code} {v} → {versions[code]}')
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
    if 'infra' in inscrits:
        rapport.append(f'Occupation : {resume_occupation(con)}')
    if 'optique' in inscrits:
        n, rac = con.execute('SELECT COUNT(*), SUM(ADR2_KEY IS NOT NULL) FROM optique.OPT_CABLE').fetchone()
        rapport.append(f'Câbles : {n}, dont {rac or 0} de raccordement d\'une adresse')
    con.close()
    if 'optique' in inscrits:
        spatialiser_optique(dossier, qgis_bin, rapport)
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

        etats = dict(con.execute('SELECT ETAT_CODE, ETAT_ID FROM infra.DEF_CD_ETAT'))
        # alvéole réservée de 45 mm, sous-tubée (un sous-tube de 28 mm, rang 1 dans son parent), occupée par trois
        # câbles constatés : deux cuivres de 6 mm (5/9) et une fibre de 10 mm
        con.execute('INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY, CD_NUM, CD_DIAM, ETAT_KEY) '
                    'VALUES (?, ?, 1, 45, ?)', ('essai-cd1', l1, etats['R']))
        cd1 = q('SELECT last_insert_rowid()')[0]
        con.execute('INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY, CD_PARENT_KEY, CD_NUM, CD_DIAM) '
                    'VALUES (?, ?, ?, 1, 28)', ('essai-cd2', l1, cd1))
        cd2 = q('SELECT last_insert_rowid()')[0]
        # alvéole mauvaise sans destination connue : conduite rattachée à la chambre, sans linéaire
        con.execute('INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, NOE_KEY, CD_NUM, CD_DIAM, ETAT_KEY) '
                    "VALUES ('essai-cd3', ?, 2, 45, ?)", (c1, etats['M']))
        cd3 = q('SELECT last_insert_rowid()')[0]
        cable = q("SELECT MAT_ID FROM infra.MAT_CABLE WHERE MAT_LIB = '5/9'")[0]
        con.execute('INSERT INTO infra.INF_CD_CABLE (CD_KEY, CDC_RANG, MAT_KEY, CDC_NB, CDC_DIAM, CDC_NATURE) '
                    "VALUES (?, 1, ?, 2, 6, 'CU')", (cd1, cable))
        con.execute("INSERT INTO infra.INF_CD_CABLE (CD_KEY, CDC_RANG, CDC_DIAM, CDC_NATURE) VALUES (?, 2, 10, 'FO')",
                    (cd1,))
        recalculer_occupation(con)
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
        # raccordement final : du PBO de 437997 à l'adresse, tracé propre (pas de linéaire, pas de nœud aval)
        con.execute("INSERT INTO optique.OPT_CABLE (CAB_CODE_EXT, CAB_LIB, CFON_KEY, CAB_CAPA, NOE1_KEY, EQU1_KEY, "
                    "ADR2_KEY, GEOMETRY) SELECT 'essai-rac1', 'RAC-1', CFON_ID, 1, ?, ?, ?, "
                    "MakeLine(MakePoint(636130, 6835060, 2154), MakePoint(636135, 6835070, 2154)) "
                    "FROM optique.DEF_CAB_FONCTION WHERE CFON_CODE = 'RA'", (p2, e1, a1))
        rac1 = q('SELECT last_insert_rowid()')[0]

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
        # 45 mm → 38 mm intérieurs : (2 x (6 / 38)² + (10 / 38)²) x 100 = 11,9 %
        occupation = con.execute(
            'SELECT cd.CD_CODE_EXT, e.ETAT_CODE, cd.CD_OCCUP, p.CD_CODE_EXT FROM infra.INF_CONDUITE cd '
            'LEFT JOIN infra.DEF_CD_ETAT e ON e.ETAT_ID = cd.ETAT_KEY LEFT JOIN infra.INF_CONDUITE p '
            'ON p.CD_ID = cd.CD_PARENT_KEY WHERE cd.CD_ID IN (?, ?, ?) ORDER BY 1', (cd1, cd2, cd3)).fetchall()
        constats.append(('occupation recalculée : alvéole réservée occupée par ses câbles et son sous-tube (R → XR, '
                         '11,9 %), sous-tube vide (0 %), alvéole mauvaise sans câble (100 %)',
                         occupation == [('essai-cd1', 'XR', 11.9, None), ('essai-cd2', None, 0.0, 'essai-cd1'),
                                        ('essai-cd3', 'M', 100.0, None)], occupation))
        cables_cd1 = con.execute('SELECT CDC_RANG, CDC_NB, CDC_DIAM, CDC_NATURE FROM infra.INF_CD_CABLE '
                                 'WHERE CD_KEY = ? ORDER BY CDC_RANG', (cd1,)).fetchall()
        constats.append(('câbles de conduite rangés dans leur conduite, nature fibre / cuivre',
                         cables_cd1 == [(1, 2, 6.0, 'CU'), (2, 1, 10.0, 'FO')], cables_cd1))
        diametres = con.execute('SELECT DIAM_NOMINAL, DIAM_INT FROM infra.DEF_CD_DIAM WHERE DIAM_SOUS_TUBE = 1 '
                                'ORDER BY 1').fetchall()
        constats.append(('diamètres proposés pour le sous-tubage (nominal, intérieur)',
                         [d for d, _ in diametres] == [20, 24, 28, 33], diametres))
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
        constats.append(('vues d\'une chambre FT héritées du type CHB, sans boîtier optique (porté par l\'équipement)',
                         [v[0] for v in vues] == ['ENV', 'DESSUS', 'A', 'B', 'C', 'D', 'MES'], [v[0] for v in vues]))
        vues_equ = [v[0] for v in con.execute("SELECT VUE_CODE FROM DEF_VUE WHERE VUE_ENTITE = 'INF_EQUIPEMENT' "
                                              'ORDER BY VUE_ORDRE')]
        constats.append(('vues d\'un équipement (galerie propre, module optique)',
                         vues_equ == ['FERME', 'OUVERT', 'CASSETTES', 'MESURES'], vues_equ))
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
        rac = con.execute(
            'SELECT c.CAB_LIB, f.CFON_CODE, n.NOE_LIB, a.ADR_CODE_EXT, c.NOE2_KEY, GeometryType(c.GEOMETRY), '
            'round(GLength(c.GEOMETRY), 2), (SELECT COUNT(*) FROM optique.OPT_PASSAGE WHERE CAB_KEY = c.CAB_ID) '
            'FROM optique.OPT_CABLE c JOIN optique.DEF_CAB_FONCTION f ON f.CFON_ID = c.CFON_KEY '
            'JOIN PRJ_NOE n ON n.NOE_ID = c.NOE1_KEY JOIN PRJ_ADRESSE a ON a.ADR_ID = c.ADR2_KEY '
            'WHERE c.CAB_ID = ?', (rac1,)).fetchall()
        constats.append(('câble de raccordement : du PBO à l\'adresse, sans nœud aval ni passage, tracé propre',
                         rac == [('RAC-1', 'RA', '437997', 'essai-a1', None, 'LINESTRING', 11.18, 0)], rac))

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
                ('deux câbles de même rang dans une conduite',
                 'INSERT INTO infra.INF_CD_CABLE (CD_KEY, CDC_RANG) VALUES (?, 1)', (cd1,)),
                ('câble de conduite sans rang', 'INSERT INTO infra.INF_CD_CABLE (CD_KEY) VALUES (?)', (cd1,)),
                ('câble de conduite de nature inconnue',
                 "INSERT INTO infra.INF_CD_CABLE (CD_KEY, CDC_RANG, CDC_NATURE) VALUES (?, 3, 'AL')", (cd1,)),
                ('ligne de câbles de conduite sans câble (CDC_NB 0)',
                 'INSERT INTO infra.INF_CD_CABLE (CD_KEY, CDC_RANG, CDC_NB) VALUES (?, 3, 0)', (cd1,)),
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
                ('câble sans nœud ni adresse aval',
                 "INSERT INTO optique.OPT_CABLE (CAB_CODE_EXT, NOE1_KEY) VALUES ('x', ?)", (p1,)),
                ('raccordement d\'une adresse inexistante',
                 "INSERT INTO optique.OPT_CABLE (CAB_CODE_EXT, NOE1_KEY, ADR2_KEY) VALUES ('x', ?, 999999)", (p1,)),
                ('suppression d\'une adresse raccordée',
                 'DELETE FROM PRJ_ADRESSE WHERE ADR_ID = ?', (a1,)),
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
                ('suppression d\'une adresse porteuse de locaux', 'DELETE FROM PRJ_ADRESSE WHERE ADR_ID = ?', (a1,)),
                ('vue à la fois d\'un type et d\'un équipement',
                 "INSERT INTO DEF_VUE (TYPE_KEY, VUE_ENTITE, VUE_CODE, VUE_LIB, VUE_ORDRE, MOD_CODE) "
                 "SELECT TYPE_ID, 'INF_EQUIPEMENT', 'X', 'x', 9, 'x' FROM DEF_TYPE WHERE TYPE_CODE = 'CHB'", ()),
                ('vue sans type ni porteur',
                 "INSERT INTO DEF_VUE (VUE_CODE, VUE_LIB, VUE_ORDRE, MOD_CODE) VALUES ('X', 'x', 9, 'x')", ()),
                ('deux vues d\'équipement de même code',
                 "INSERT INTO DEF_VUE (VUE_ENTITE, VUE_CODE, VUE_LIB, VUE_ORDRE, MOD_CODE) "
                 "VALUES ('INF_EQUIPEMENT', 'FERME', 'x', 9, 'x')", ())):
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
