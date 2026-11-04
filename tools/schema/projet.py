"""Construction, ouverture et contrôle d'un projet NgeEsPlorer côté BE (noyau SpatiaLite + modules attachés).

Implémentation de référence de la future bibliothèque noyau C# :
- construire : crée noyau.sqlite et un fichier par module à partir de schema/<module>/ (manifeste + SQL),
  importe les référentiels FOA Explorer, enregistre types, entités et vues des modules dans le noyau ;
- ouvrir : attache les modules (nom de schéma = code du module), contrôle les dépendances, impose le journal
  DELETE, crée les triggers TEMP d'intégrité entre bases à partir des références des manifestes ;
- orphelins : liste les références entre bases sans cible.

Usage :
  python -I tools/schema/projet.py construire <dossier> <base FOA> <dossier QGIS bin> [--essai]
"""
import json, os, sqlite3, sys

sys.stdout.reconfigure(encoding='utf-8')
RACINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCHEMA = os.path.join(RACINE, 'schema')
MODELE_VERSION = '0.1.0'


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
    con = connecter(os.path.join(dossier, 'noyau.sqlite'), qgis_bin, True)
    mods = {m['code']: m for m in manifestes()}
    attaches = {'noyau'}
    for code, fichier in con.execute("SELECT MOD_CODE, MOD_FICHIER FROM SYS_MODULE WHERE MOD_CODE <> 'noyau' "
                                     "ORDER BY MOD_ID").fetchall():
        manquantes = set(mods[code]['dependances']) - attaches
        if manquantes:
            raise RuntimeError(f'module {code} : dépendances non attachées {sorted(manquantes)}')
        con.execute('ATTACH DATABASE ? AS ' + code, (os.path.join(dossier, fichier),))
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
    resultat = []
    for m in manifestes():
        for ref in m['references']:
            s, t, c = schema_de(m['code']), ref['table'], ref['colonne']
            cs, ct, cc = cible(ref)
            n = con.execute(f'SELECT COUNT(*) FROM {s}.{t} x WHERE x.{c} IS NOT NULL AND NOT EXISTS '
                            f'(SELECT 1 FROM {cs}.{ct} y WHERE y.{cc} = x.{c})').fetchone()[0]
            resultat.append((f'{m["code"]}.{t}.{c} → {ref["cible"]}', n))
    return resultat


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

        mat_chb = q("SELECT MAT_ID FROM chambre.MAT_CHAMBRE WHERE MAT_LIB = 'L2T'")[0]
        faces = {}
        for noe, face in ((c1, 'A'), (c2, 'B')):
            con.execute('INSERT INTO chambre.CHB_CHAMBRE (NOE_KEY, MAT_KEY) VALUES (?, ?)', (noe, mat_chb))
            chb = q('SELECT last_insert_rowid()')[0]
            con.execute('INSERT INTO chambre.CHB_FACE (CHB_KEY, FAC_CODE, FAC_NB_COL, FAC_NB_LIG) VALUES (?, ?, 9, 12)',
                        (chb, face))
            faces[noe] = q('SELECT last_insert_rowid()')[0]
        con.execute('INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y) VALUES (?, ?, 3, 4)',
                    (faces[c1], cd1))
        con.execute('INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y, POS_MIROIR) VALUES (?, ?, 5, 4, 1)',
                    (faces[c2], cd1))
        con.execute('INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y) VALUES (?, ?, 6, 4)',
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
                         sans_dest == [('1476', 6.0)], sans_dest))
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
        constats.append(('longueur cartographique L1 (m)', True,
                         round(q('SELECT GLength(GEOMETRY) FROM PRJ_LINEAIRE WHERE LIN_ID = ?', l1)[0], 1)))

        # refus attendus
        for libelle, sql, params in (
                ('chambre sur un nœud inexistant', 'INSERT INTO chambre.CHB_CHAMBRE (NOE_KEY) VALUES (999999)', ()),
                ('position sur une conduite inexistante',
                 'INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y) VALUES (?, 999999, 0, 0)',
                 (faces[c1],)),
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
                 "VALUES ('x', 1001, ?, ?, MakeLine(MakePoint(0,0,2154), MakePoint(1,1,2154)))", (c1, c1))):
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
               '+ (SELECT COUNT(*) FROM chambre.CHB_POSITION) + (SELECT COUNT(*) FROM poteau.POT_POTEAU)')[0]
    constats.append(('annulation complète du scénario (noyau et modules)', restes == 0, restes))
    return constats


def main():
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
