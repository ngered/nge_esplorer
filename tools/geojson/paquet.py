"""Paquet de zone NgeEsPlorer (format d'échange GeoJSON, voir docs/paquet.md).

Implémentation de référence côté BE :
- publier : extrait une zone du projet en paquet ZIP (paquet.json, objets.geojson, referentiels.json et,
  sur option, les photos) ; refuse un projet en retard sur son schéma, à reprendre d'abord (projet.py migrer) ;
  ne publie que les modules décrits par le format (MODULES_PUBLIES) et, des fichiers, que les photos ; adresses des
  nœuds publiés et de l'emprise de la zone ;
- verifier : contrôle la structure d'un paquet (en-tête, objets, références entre objets, fichiers, commentaires,
  masques des chambres).

Usage :
  python -I tools/geojson/paquet.py publier <dossier projet> <zone> <dossier QGIS bin> <sortie.zip> [--fichiers]
  python -I tools/geojson/paquet.py verifier <paquet.zip>
"""
import datetime, hashlib, json, math, os, sys, zipfile
from collections import Counter, defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'schema'))
import projet  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')
FORMAT = 'nge-esplorer-paquet'
FORMAT_VERSION = '0.2.0'        # 0.2.0 : journal des commentaires (NOE_COMMENT, CHB_COMMENT, POT_COMMENT retirés)
DECIMALES = 7                   # ~1 cm en WGS84
# Masques métriques depuis le module chambre 0.3.0 (format inchangé) : faces FAC_LARG x FAC_HAUT et positions POS_X,
# POS_Y en m ; avant, en cellules FOA (FAC_NB_COL, FAC_NB_LIG), paquet refusé.
VERSION_MASQUES = '0.3.0'
# Centre d'une alvéole hors de sa face toléré jusqu'à 1 mm : le centre est borné à la face, puis arrondi au micromètre
# au BE (conversions exactes) et au millimètre au plus sur le terminal, soit 0,5 mm de débord au plus. Au-delà, la
# position est dans un autre repère (cellules) ou sa face a été réduite sans recentrage. C'est bien moins qu'un
# demi-diamètre (14 mm pour la plus petite alvéole normalisée, 28 mm) : une alvéole acceptée recouvre toujours sa
# face. Le disque, lui, peut déborder : 206 alvéoles des relevés FOA de Nancy débordent de la fenêtre FOA, aucune n'en
# a le centre dehors.
TOLERANCE_POSITION = 0.001      # m
# Modules dont le format décrit l'espace GeoJSON : ceux d'un projet qui n'y figurent pas (optique, immeuble) ne sont
# pas publiés (ni en-tête, ni référentiels) tant que le terminal ne les lit pas ; leurs types et vues, enregistrés
# dans le noyau, le sont avec lui.
MODULES_PUBLIES = ('noyau', 'infra', 'chambre', 'poteau')

# Références vers une entité : écrites avec le CODE_EXT de la cible (colonne → table, colonne CODE_EXT).
ENTITES = {
    'PRJ_ZONE': 'ZONE_CODE_EXT', 'PRJ_ADRESSE': 'ADR_CODE_EXT', 'PRJ_NOE': 'NOE_CODE_EXT',
    'PRJ_LINEAIRE': 'LIN_CODE_EXT', 'INF_CONDUITE': 'CD_CODE_EXT',
}
REFERENCES = {
    'ZONE_KEY': 'PRJ_ZONE', 'ADR_KEY': 'PRJ_ADRESSE', 'NOE_KEY': 'PRJ_NOE', 'NOE1_KEY': 'PRJ_NOE',
    'NOE2_KEY': 'PRJ_NOE', 'LIN_KEY': 'PRJ_LINEAIRE', 'CD_KEY': 'INF_CONDUITE', 'CD_PARENT_KEY': 'INF_CONDUITE',
}

# Éléments imbriqués : (clé du format, table, colonne vers le parent, une seule ligne ?, enfants).
NOEUD = [
    ('chb', 'chambre.CHB_CHAMBRE', 'NOE_KEY', True, [
        ('masques', 'chambre.CHB_MASQUE_LOGIQUE', 'CHB_KEY', False, []),
        ('faces', 'chambre.CHB_FACE', 'CHB_KEY', False, [
            ('positions', 'chambre.CHB_POSITION', 'FAC_KEY', False, [])])]),
    ('pot', 'poteau.POT_POTEAU', 'NOE_KEY', True, [
        ('controles', 'poteau.POT_CONTROLE', 'POT_KEY', False, [])]),
    ('inf', None, None, True, [
        ('equipements', 'infra.INF_EQUIPEMENT', 'NOE_KEY', False, []),
        ('conduites', 'infra.INF_CONDUITE', 'NOE_KEY', False, [         # alvéoles sans destination connue
            ('cables', 'infra.INF_CD_CABLE', 'CD_KEY', False, [])])]),
]
LINEAIRE = [
    ('inf', None, None, True, [
        ('conduites', 'infra.INF_CONDUITE', 'LIN_KEY', False, [
            ('cables', 'infra.INF_CD_CABLE', 'CD_KEY', False, [])]),
        ('portee', 'infra.INF_PORTEE', 'LIN_KEY', True, [
            ('cables', 'infra.INF_PORTEE_CABLE', 'PRT_KEY', False, [])])]),
]
# Tables dont les fichiers (PRJ_FICHIER) sont rattachés à l'objet du nœud ou du linéaire qui les porte.
PORTEUR_FICHIER = {
    'PRJ_NOE': ('NOE', None), 'PRJ_LINEAIRE': ('LIN', None), 'PRJ_ADRESSE': ('ADR', None),
    'CHB_CHAMBRE': ('NOE', 'chambre.CHB_CHAMBRE'), 'POT_POTEAU': ('NOE', 'poteau.POT_POTEAU'),
    'POT_CONTROLE': ('NOE', 'poteau.POT_CONTROLE'), 'INF_EQUIPEMENT': ('NOE', 'infra.INF_EQUIPEMENT'),
    'INF_CONDUITE': ('LIN', 'infra.INF_CONDUITE'), 'INF_PORTEE': ('LIN', 'infra.INF_PORTEE'),
}
# Tables des objets commentés : le journal (PRJ_COMMENTAIRE) est porté par l'objet lui-même, sans clé ENTITE.
PORTEUR_COMMENTAIRE = {'PRJ_NOE': 'NOE', 'PRJ_LINEAIRE': 'LIN', 'PRJ_ADRESSE': 'ADR'}
TYPES_COMMENTAIRE = ('alert', 'minor', 'standard', 'great')     # COM_TYPE de FibReady, par gravité décroissante


def maintenant():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def lignes(con, table, where='', params=()):
    cur = con.execute(f'SELECT * FROM {table} {where}', params)
    noms = [d[0] for d in cur.description]
    return [dict(zip(noms, r)) for r in cur]


def nom_table(table):
    return table.split('.')[-1]


def cle_primaire(con, table):
    schema, _, nom = table.rpartition('.')
    info = con.execute(f'PRAGMA {schema or "main"}.table_info({nom})').fetchall()
    return next(r[1] for r in info if r[5] == 1)


class Publication:
    def __init__(self, con, zone):
        self.con = con
        self.zone = con.execute('SELECT ZONE_ID, ZONE_CODE_EXT, ZONE_LIB FROM PRJ_ZONE WHERE ZONE_CODE_EXT = ?',
                                (zone,)).fetchone()
        if not self.zone:
            raise SystemExit(f'zone inconnue : {zone}')
        self.codes = {}
        for t, c in ENTITES.items():
            qualifiee = 'infra.' + t if t.startswith('INF_') else t
            self.codes[t] = dict(con.execute(f'SELECT {cle_primaire(con, qualifiee)}, {c} FROM {qualifiee}'))
        self.mlog = dict(con.execute('SELECT MLOG_ID, MLOG_NUM FROM chambre.CHB_MASQUE_LOGIQUE'))
        self.cache = {}

    # -- conversion d'une ligne ----------------------------------------------------------------

    def proprietes(self, table, ligne, parent=None):
        """Colonnes BE d'une ligne : sans sa clé technique ni le lien vers son parent (porté par l'imbrication),
        références vers les entités en CODE_EXT, valeurs nulles omises."""
        pk = cle_primaire(self.con, table)
        out = {}
        for col, v in ligne.items():
            if v is None or col in (pk, parent, 'GEOMETRY'):
                continue
            if col in REFERENCES:
                v = self.codes[REFERENCES[col]].get(v)
            elif col == 'MLOG_KEY':
                col, v = 'MLOG_NUM', self.mlog.get(v)
            out[col] = v
        return out

    def enfants(self, table, parent):
        """Lignes d'une table groupées par la colonne parent (chargées une seule fois)."""
        if (table, parent) not in self.cache:
            schema, _, nom = table.rpartition('.')
            if parent not in {r[1] for r in self.con.execute(f'PRAGMA {schema or "main"}.table_info({nom})')}:
                raise SystemExit(f'{table} sans colonne {parent} : projet construit avec un schéma antérieur, '
                                 f'à reconstruire (tools/essai/charger_essai.py)')
            groupes = defaultdict(list)
            for l in lignes(self.con, table):
                groupes[l[parent]].append(l)
            self.cache[table, parent] = groupes
        return self.cache[table, parent]

    def imbriquer(self, cible, structure, id_parent):
        for cle, table, parent, unique, sous in structure:
            if table is None:                       # simple espace de nommage (ex. « inf » d'un nœud)
                espace = {}
                self.imbriquer(espace, sous, id_parent)
                if espace:
                    cible[cle] = espace
                continue
            trouvees = self.enfants(table, parent).get(id_parent, [])
            objets = []
            for l in trouvees:
                o = self.proprietes(table, l, parent)
                self.imbriquer(o, sous, l[cle_primaire(self.con, table)])
                objets.append(o)
            if objets:
                cible[cle] = objets[0] if unique else objets

    # -- objets ------------------------------------------------------------------------------

    def ids_zone(self):
        z = self.zone[0]
        lin = [r[0] for r in self.con.execute('SELECT LIN_ID FROM PRJ_LINEAIRE WHERE ZONE_KEY = ?', (z,))]
        noe = {r[0] for r in self.con.execute('SELECT NOE_ID FROM PRJ_NOE WHERE ZONE_KEY = ?', (z,))}
        hors = set()
        for n1, n2 in self.con.execute('SELECT NOE1_KEY, NOE2_KEY FROM PRJ_LINEAIRE WHERE ZONE_KEY = ?', (z,)):
            hors |= {n1, n2} - noe
        # adresses des nœuds publiés et adresses situées dans l'emprise de la zone (BAL à relever)
        adr = {r[0] for r in self.con.execute(
            f'SELECT DISTINCT ADR_KEY FROM PRJ_NOE WHERE ADR_KEY IS NOT NULL AND NOE_ID IN '
            f'({",".join(map(str, noe | hors)) or "NULL"})')}
        adr |= {r[0] for r in self.con.execute(
            'SELECT a.ADR_ID FROM PRJ_ADRESSE a, PRJ_ZONE z WHERE z.ZONE_ID = ? AND a.DATE_ABD IS NULL '
            'AND Within(a.GEOMETRY, z.GEOMETRY) = 1', (z,))}
        return sorted(noe), sorted(hors), lin, sorted(adr)

    def geometries(self, table, pk, ids):
        geo = {}
        for i in range(0, len(ids), 500):
            lot = ids[i:i + 500]
            for oid, g in self.con.execute(
                    f'SELECT {pk}, AsGeoJSON(Transform(GEOMETRY, 4326), {DECIMALES}) FROM {table} '
                    f'WHERE {pk} IN ({",".join("?" * len(lot))})', lot):
                geo[oid] = json.loads(g) if g else None
        return geo

    def fichiers(self):
        """PRJ_FICHIER rattachés à leur objet GeoJSON : {(classe, id) : [fichiers]}."""
        entites = dict(self.con.execute('SELECT ENT_ID, ENT_TABLE FROM DEF_ENTITE'))
        vues = dict(self.con.execute('SELECT VUE_ID, VUE_CODE FROM DEF_VUE'))
        porteurs = {}
        for table, (classe, source) in PORTEUR_FICHIER.items():
            if source:
                col = 'LIN_KEY' if classe == 'LIN' else 'NOE_KEY'
                if source.endswith('POT_CONTROLE'):
                    req = ('SELECT c.CTL_ID, p.NOE_KEY FROM poteau.POT_CONTROLE c '
                           'JOIN poteau.POT_POTEAU p ON p.POT_ID = c.POT_KEY')
                else:
                    req = f'SELECT {cle_primaire(self.con, source)}, {col} FROM {source}'
                porteurs[table] = (classe, dict(self.con.execute(req)))
            else:
                porteurs[table] = (classe, None)
        par_objet = defaultdict(list)
        documents = 0
        for f in lignes(self.con, 'PRJ_FICHIER', 'ORDER BY FIC_RANG, FIC_ID'):
            table = entites.get(f['ENT_KEY'])
            if table not in porteurs:
                continue
            if f['FIC_TYPE'] and not f['FIC_TYPE'].startswith('image/'):
                documents += 1          # pièce jointe (PDF, tableur, trace) : le terminal n'affiche que des photos
                continue
            classe, correspondance = porteurs[table]
            oid = f['OBJ_KEY'] if correspondance is None else correspondance.get(f['OBJ_KEY'])
            o = {'ENTITE': table, 'VUE_CODE': vues.get(f['VUE_KEY'])}
            o.update(self.proprietes('PRJ_FICHIER', f))
            for col in ('ENT_KEY', 'OBJ_KEY', 'VUE_KEY'):
                o.pop(col, None)
            o['_chemin'] = f['FIC_CHEMIN']
            par_objet[classe, oid].append(o)
        if documents:
            print(f'pièces jointes non publiées (hors photos) : {documents}', file=sys.stderr)
        return par_objet

    def commentaires(self):
        """Journal PRJ_COMMENTAIRE rattaché à son objet GeoJSON, du plus ancien au plus récent (DATE_CREA puis
        COM_ID), entrées abandonnées exclues : {(classe, id) : [commentaires]}. Sans rattachement (porté par
        l'objet) ; intervention traduite en INT_CODE_EXT, placée avant la traçabilité. Une entrée rattachée à une
        autre table que PRJ_NOE, PRJ_LINEAIRE ou PRJ_ADRESSE n'a pas de place dans le format : non publiée, signalée."""
        if not self.con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'PRJ_COMMENTAIRE'").fetchone():
            raise SystemExit('PRJ_COMMENTAIRE absente : projet construit avant la version 0.2.0 du noyau, à reprendre '
                             '(tools/schema/projet.py migrer)')
        entites = dict(self.con.execute('SELECT ENT_ID, ENT_TABLE FROM DEF_ENTITE'))
        interventions = dict(self.con.execute('SELECT INT_ID, INT_CODE_EXT FROM PRJ_INTERVENTION'))
        par_objet = defaultdict(list)
        omis = Counter()
        for c in lignes(self.con, 'PRJ_COMMENTAIRE', 'WHERE DATE_ABD IS NULL ORDER BY DATE_CREA, COM_ID'):
            table = entites.get(c['ENT_KEY'])
            classe = PORTEUR_COMMENTAIRE.get(table)
            if classe is None:
                omis[table or f'ENT_KEY {c["ENT_KEY"]} inconnue'] += 1
                continue
            o = self.proprietes('PRJ_COMMENTAIRE', c)
            for col in ('ENT_KEY', 'OBJ_KEY', 'INT_KEY'):
                o.pop(col, None)
            trace = {k: o.pop(k) for k in list(o) if k.startswith(('DATE_', 'SRC_'))}
            if interventions.get(c['INT_KEY']):
                o['INT_CODE_EXT'] = interventions[c['INT_KEY']]
            par_objet[classe, c['OBJ_KEY']].append(o | trace)
        if omis:
            n = sum(omis.values())
            print(f'commentaires non publiés : {n} entrée{"s" * (n > 1)} du journal du projet rattachée{"s" * (n > 1)} '
                  f'à une autre table que PRJ_NOE, PRJ_LINEAIRE ou PRJ_ADRESSE '
                  f'({", ".join(f"{t} {k}" for t, k in sorted(omis.items()))}), à rattacher à leur objet',
                  file=sys.stderr)
        return par_objet

    def objets(self):
        noe, hors, lin, adr = self.ids_zone()
        fichiers, commentaires = self.fichiers(), self.commentaires()
        features = []

        def feature(classe, table, pk, ids, structure, hors_zone=()):
            geo = self.geometries(table, pk, ids)
            enregs = {l[pk]: l for l in lignes(self.con, table, f'WHERE {pk} IN ({",".join(map(str, ids)) or "NULL"})')}
            code = ENTITES[table]
            for oid in ids:
                l = enregs[oid]
                props = {'classe': classe}
                props.update(self.proprietes(table, l))
                props.pop(code, None)
                if oid in hors_zone:
                    props['hors_zone'] = True
                self.imbriquer(props, structure, oid)
                fic = fichiers.get((classe, oid))
                if fic:
                    props['fichiers'] = fic
                com = commentaires.get((classe, oid))
                if com:
                    props['commentaires'] = com
                features.append({'type': 'Feature', 'id': l[code], 'geometry': geo.get(oid), 'properties': props})

        feature('ADR', 'PRJ_ADRESSE', 'ADR_ID', adr, [])
        feature('NOE', 'PRJ_NOE', 'NOE_ID', sorted(set(noe) | set(hors)), NOEUD, set(hors))
        feature('LIN', 'PRJ_LINEAIRE', 'LIN_ID', lin, LINEAIRE)
        return features

    def referentiels(self, modules):
        out = {}
        for m in projet.manifestes():
            if m['code'] not in modules:
                continue
            schema = projet.schema_de(m['code'])
            tables = {}
            for t in m['tables']:
                if t.startswith(('DEF_', 'MAT_')) and t not in ('DEF_ENTITE',):
                    tables[t] = [{k: v for k, v in l.items() if v is not None}
                                 for l in lignes(self.con, f'{schema}.{t}')]
            out[m['code']] = tables
        return out


def emprise(features):
    xs, ys = [], []

    def parcourir(c):
        if isinstance(c[0], (int, float)):
            xs.append(c[0]); ys.append(c[1])
        else:
            for s in c:
                parcourir(s)
    for f in features:
        if f['geometry']:
            parcourir(f['geometry']['coordinates'])
    return [min(xs), min(ys), max(xs), max(ys)] if xs else None


def en_retard(con):
    """Modules du projet en retard sur leur schéma (SYS_MODULE.MOD_VERSION antérieure à la version du manifeste) :
    projet construit avec un modèle antérieur, dont le paquet ne suivrait pas le schéma (masques en cellules FOA…)."""
    schema = {m['code']: m['version'] for m in projet.manifestes()}
    return [(code, v, schema[code]) for code, v in con.execute('SELECT MOD_CODE, MOD_VERSION FROM SYS_MODULE '
                                                               'ORDER BY MOD_ID').fetchall()
            if code in schema and projet.version(v) < projet.version(schema[code])]


def publier(dossier, zone, qgis_bin, sortie, avec_fichiers=False):
    con = projet.ouvrir(dossier, qgis_bin, integrite=False)
    retard = en_retard(con)
    if retard:
        raise SystemExit('projet à reprendre avant publication (tools/schema/projet.py migrer) : '
                         + ', '.join(f'module {code} en {v} au lieu de {attendue}' for code, v, attendue in retard))
    pub = Publication(con, zone)
    features = pub.objets()
    prj = con.execute('SELECT PRJ_CODE_EXT, PRJ_LIB, MODELE_VERSION FROM SYS_PROJET').fetchone()
    modules = dict(con.execute('SELECT MOD_CODE, MOD_VERSION FROM SYS_MODULE ORDER BY MOD_ID'))
    omis = [code for code in modules if code not in MODULES_PUBLIES]
    if omis:
        print(f'modules non publiés (espace GeoJSON hors du format {FORMAT_VERSION}) : {", ".join(omis)}',
              file=sys.stderr)
    modules = {code: v for code, v in modules.items() if code in MODULES_PUBLIES}
    contenu = {}
    nb_fic = 0
    for f in features:
        for fic in f['properties'].get('fichiers', []):
            chemin = os.path.join(dossier, fic.pop('_chemin'))
            if avec_fichiers and os.path.isfile(chemin):
                nom = 'fichiers/' + fic['FIC_CODE_EXT'] + os.path.splitext(chemin)[1].lower()
                contenu[nom] = open(chemin, 'rb').read()
                fic['fichier'] = nom
                nb_fic += 1
    entete = {
        'format': FORMAT, 'version': FORMAT_VERSION, 'sens': 'PUBLICATION', 'date': maintenant(),
        'projet': {'code': prj[0], 'lib': prj[1], 'modele': prj[2]},
        'zone': {'code': pub.zone[1], 'lib': pub.zone[2], 'emprise': emprise(features)},
        'modules': modules,
        'effectifs': {c: sum(1 for f in features if f['properties']['classe'] == c) for c in ('NOE', 'LIN', 'ADR')}
                     | {'fichiers': nb_fic},
    }
    geojson = {'type': 'FeatureCollection', 'features': features}
    with zipfile.ZipFile(sortie, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('paquet.json', json.dumps(entete, ensure_ascii=False, indent=1))
        z.writestr('objets.geojson', json.dumps(geojson, ensure_ascii=False, separators=(',', ':')))
        z.writestr('referentiels.json', json.dumps(pub.referentiels(modules), ensure_ascii=False, separators=(',', ':')))
        for nom, data in contenu.items():
            z.writestr(nom, data, zipfile.ZIP_STORED)
    con.close()
    return entete


# -- vérification ------------------------------------------------------------------------------

def verifier_commentaires(oid, journal, vus, intervention):
    """Anomalies du journal d'un objet. vus : COM_CODE_EXT déjà rencontrés dans le paquet ; intervention : celle
    de l'en-tête d'un retour (vide pour une publication), dont les commentaires sont signés de son auteur."""
    if journal is None:
        return []
    if not isinstance(journal, list):
        return [f'{oid} : commentaires hors liste']
    err = []
    for c in journal:
        if not isinstance(c, dict):
            err.append(f'{oid} : commentaire illisible {str(c)[:60]}')
            continue
        code = c.get('COM_CODE_EXT')
        nom = f'{oid} commentaire {code}'
        if not (isinstance(code, str) and code.strip()):
            err.append(f'{oid} : commentaire sans COM_CODE_EXT')
        elif code in vus:
            err.append(f'{nom} : COM_CODE_EXT en double dans le paquet')
        else:
            vus.add(code)
        if not (isinstance(c.get('COM_TEXTE'), str) and c['COM_TEXTE'].strip()):
            err.append(f'{nom} : texte vide')
        if c.get('COM_TYPE') not in TYPES_COMMENTAIRE:
            err.append(f'{nom} : type inattendu {c.get("COM_TYPE")}')
        if not (isinstance(c.get('COM_AUTEUR'), str) and c['COM_AUTEUR'].strip()):
            err.append(f'{nom} : sans auteur')
        if not c.get('DATE_CREA'):
            err.append(f'{nom} : sans DATE_CREA')
        if (intervention.get('INT_CODE_EXT') and c.get('INT_CODE_EXT') == intervention['INT_CODE_EXT']
                and c.get('COM_AUTEUR') != intervention.get('INT_AUTEUR')):
            err.append(f'{nom} : saisi par l\'intervention du retour mais signé {c.get("COM_AUTEUR")} au lieu de '
                       f'{intervention.get("INT_AUTEUR")}')
    return err


def nombre(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def verifier_masques(oid, chb):
    """Anomalies des faces d'une chambre (espace chb), au repère métrique du module chambre 0.3.0 : FAC_LARG et
    FAC_HAUT nombres strictement positifs (m), sans les clés de l'ancien repère ; centre de chaque position dans sa
    face, à TOLERANCE_POSITION près. Une position abandonnée (DATE_ABD), qui n'est plus dessinée, n'est pas bornée."""
    if chb is None:
        return []
    if not isinstance(chb, dict):
        return [f'{oid} : chb illisible']
    faces = chb.get('faces')
    if faces is None:
        return []
    if not isinstance(faces, list):
        return [f'{oid} : faces hors liste']
    err = []
    for face in faces:
        if not isinstance(face, dict):
            err.append(f'{oid} : face illisible {str(face)[:60]}')
            continue
        nom = f'{oid} face {face.get("FAC_CODE")}'
        dims = {}
        for col in ('FAC_LARG', 'FAC_HAUT'):
            if nombre(face.get(col)) and face[col] > 0:
                dims[col] = face[col]
            else:
                err.append(f'{nom} : {col} {face.get(col)} au lieu d\'une dimension en m strictement positive')
        anciennes = [c for c in ('FAC_NB_COL', 'FAC_NB_LIG') if c in face]
        if anciennes:
            err.append(f'{nom} : {", ".join(anciennes)}, repère antérieur au module chambre {VERSION_MASQUES}')
        positions = face.get('positions') or []
        if not isinstance(positions, list):
            err.append(f'{nom} : positions hors liste')
            continue
        for pos in positions:
            if not isinstance(pos, dict):
                err.append(f'{nom} : position illisible {str(pos)[:60]}')
                continue
            if pos.get('DATE_ABD'):
                continue
            for col, dim in (('POS_X', 'FAC_LARG'), ('POS_Y', 'FAC_HAUT')):
                v = pos.get(col)
                if not nombre(v):
                    err.append(f'{nom} : position {pos.get("CD_KEY")} sans {col} numérique ({v})')
                elif dim in dims and not -TOLERANCE_POSITION <= v <= dims[dim] + TOLERANCE_POSITION:
                    err.append(f'{nom} : position {pos.get("CD_KEY")} hors de la face ({col} {v} m, {dim} '
                               f'{dims[dim]} m)')
    return err


def verifier_version_masques(entete, objets):
    """Module chambre de l'en-tête : 0.3.0 au moins (masques en m) ; avant, positions en cellules FOA, que le
    terminal refuse sans les convertir."""
    v = (entete.get('modules') or {}).get('chambre')
    if v is None:
        chambres = [(f.get('properties') or {}).get('chb') for f in objets.get('features', [])]
        if any(isinstance(c, dict) and c.get('faces') for c in chambres):
            return ['faces de chambre sans module chambre dans l\'en-tête']
        return []
    try:
        lue = projet.version(str(v))
    except ValueError:
        return [f'module chambre en version illisible : {v}']
    if lue < projet.version(VERSION_MASQUES):
        return [f'module chambre {v} antérieur à {VERSION_MASQUES} : masques dans l\'ancien repère (cellules FOA), '
                f'refusés par le terminal ; projet à reprendre (tools/schema/projet.py migrer) et paquet à republier']
    return []


def verifier(chemin):
    """Contrôles de structure ; renvoie la liste des anomalies (vide si le paquet est conforme)."""
    err = []
    with zipfile.ZipFile(chemin) as z:
        noms = set(z.namelist())
        if 'paquet.json' not in noms:
            return ['paquet.json absent']
        entete = json.loads(z.read('paquet.json'))
        retour = entete.get('sens') == 'RETOUR'
        # un retour ne porte que les objets modifiés : ses références peuvent viser des objets du BE
        for n in ('objets.geojson',) if retour else ('objets.geojson', 'referentiels.json'):
            if n not in noms:
                err.append(f'{n} absent')
        if err:
            return err
        objets = json.loads(z.read('objets.geojson'))
        ref = None if retour else json.loads(z.read('referentiels.json'))
        if entete.get('format') != FORMAT:
            err.append(f'format inattendu : {entete.get("format")}')
        if entete.get('sens') not in ('PUBLICATION', 'RETOUR'):
            err.append(f'sens inattendu : {entete.get("sens")}')
        if retour:
            for cle in ('base', 'intervention'):
                if not entete.get(cle):
                    err.append(f'retour sans {cle}')
            for cle in ('INT_CODE_EXT', 'ACT_CODE', 'INT_AUTEUR', 'DATE_DEBUT'):
                if not (entete.get('intervention') or {}).get(cle):
                    err.append(f'intervention sans {cle}')
        if objets.get('type') != 'FeatureCollection':
            err.append('objets.geojson n\'est pas une FeatureCollection')
        err += verifier_version_masques(entete, objets)
        intervention = (entete.get('intervention') or {}) if retour else {}
        ids, commentaires = {}, set()
        for f in objets['features']:
            p = f.get('properties') or {}
            if not f.get('id'):
                err.append('objet sans id')
                continue
            if f['id'] in ids:
                err.append(f'id en double : {f["id"]}')
            ids[f['id']] = p.get('classe')
            if p.get('classe') not in ('NOE', 'LIN', 'ADR'):
                err.append(f'{f["id"]} : classe inattendue {p.get("classe")}')
            attendu = {'NOE': 'Point', 'ADR': 'Point', 'LIN': 'LineString'}.get(p.get('classe'))
            if f.get('geometry') and f['geometry']['type'] != attendu:
                err.append(f'{f["id"]} : géométrie {f["geometry"]["type"]} au lieu de {attendu}')
            if p.get('statut') not in (('C', 'M', 'A') if retour else (None,)):
                err.append(f'{f["id"]} : statut inattendu {p.get("statut")}')
            for fic in p.get('fichiers', []):
                if fic.get('fichier') and fic['fichier'] not in noms:
                    err.append(f'{f["id"]} : fichier absent du paquet {fic["fichier"]}')
            err += verifier_commentaires(f['id'], p.get('commentaires'), commentaires, intervention)
            err += verifier_masques(f['id'], p.get('chb'))
        if retour:
            return err
        conduites = {c['CD_CODE_EXT'] for f in objets['features']
                     for c in (f['properties'].get('inf') or {}).get('conduites', [])}
        for f in objets['features']:
            p = f['properties']
            for col in ('NOE1_KEY', 'NOE2_KEY'):
                if p['classe'] == 'LIN' and ids.get(p.get(col)) != 'NOE':
                    err.append(f'{f["id"]} : {col} {p.get(col)} absent du paquet')
            if p.get('ADR_KEY') and ids.get(p['ADR_KEY']) != 'ADR':
                err.append(f'{f["id"]} : adresse {p["ADR_KEY"]} absente du paquet')
            for face in (p.get('chb') or {}).get('faces', []):
                for pos in face.get('positions', []):
                    if pos.get('CD_KEY') not in conduites:
                        err.append(f'{f["id"]} face {face.get("FAC_CODE")} : conduite {pos.get("CD_KEY")} absente')
        for module in entete.get('modules', {}):
            if module not in ref:
                err.append(f'référentiels du module {module} absents')
    return err


def main():
    if len(sys.argv) >= 6 and sys.argv[1] == 'publier':
        e = publier(*sys.argv[2:6], avec_fichiers='--fichiers' in sys.argv)
        print(json.dumps(e, ensure_ascii=False, indent=1))
        anomalies = verifier(sys.argv[5])
        print('vérification :', 'conforme' if not anomalies else '\n  ' + '\n  '.join(anomalies[:50]))
    elif len(sys.argv) == 3 and sys.argv[1] == 'verifier':
        anomalies = verifier(sys.argv[2])
        print('conforme' if not anomalies else '\n'.join(anomalies))
        sys.exit(1 if anomalies else 0)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
