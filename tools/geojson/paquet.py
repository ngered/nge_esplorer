"""Paquet de zone NgeEsPlorer (format d'échange GeoJSON, voir docs/paquet.md).

Implémentation de référence côté BE :
- publier : extrait une zone du projet en paquet ZIP (paquet.json, objets.geojson, referentiels.json et,
  sur option, les photos) ;
- verifier : contrôle la structure d'un paquet (en-tête, objets, références entre objets, fichiers).

Usage :
  python -I tools/geojson/paquet.py publier <dossier projet> <zone> <dossier QGIS bin> <sortie.zip> [--fichiers]
  python -I tools/geojson/paquet.py verifier <paquet.zip>
"""
import datetime, hashlib, json, os, sys, zipfile
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'schema'))
import projet  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
FORMAT = 'nge-esplorer-paquet'
FORMAT_VERSION = '0.1.0'
DECIMALES = 7                   # ~1 cm en WGS84

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
        ('equipements', 'infra.INF_EQUIPEMENT', 'NOE_KEY', False, [])]),
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
        adr = {r[0] for r in self.con.execute(
            f'SELECT DISTINCT ADR_KEY FROM PRJ_NOE WHERE ADR_KEY IS NOT NULL AND NOE_ID IN '
            f'({",".join(map(str, noe | hors)) or "NULL"})')}
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
        for f in lignes(self.con, 'PRJ_FICHIER', 'ORDER BY FIC_RANG, FIC_ID'):
            table = entites.get(f['ENT_KEY'])
            if table not in porteurs:
                continue
            classe, correspondance = porteurs[table]
            oid = f['OBJ_KEY'] if correspondance is None else correspondance.get(f['OBJ_KEY'])
            o = {'ENTITE': table, 'VUE_CODE': vues.get(f['VUE_KEY'])}
            o.update(self.proprietes('PRJ_FICHIER', f))
            for col in ('ENT_KEY', 'OBJ_KEY', 'VUE_KEY'):
                o.pop(col, None)
            o['_chemin'] = f['FIC_CHEMIN']
            par_objet[classe, oid].append(o)
        return par_objet

    def objets(self):
        noe, hors, lin, adr = self.ids_zone()
        fichiers = self.fichiers()
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
                features.append({'type': 'Feature', 'id': l[code], 'geometry': geo.get(oid), 'properties': props})

        feature('ADR', 'PRJ_ADRESSE', 'ADR_ID', adr, [])
        feature('NOE', 'PRJ_NOE', 'NOE_ID', sorted(set(noe) | set(hors)), NOEUD, set(hors))
        feature('LIN', 'PRJ_LINEAIRE', 'LIN_ID', lin, LINEAIRE)
        return features

    def referentiels(self):
        out = {}
        for m in projet.manifestes():
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


def publier(dossier, zone, qgis_bin, sortie, avec_fichiers=False):
    con = projet.ouvrir(dossier, qgis_bin, integrite=False)
    pub = Publication(con, zone)
    features = pub.objets()
    prj = con.execute('SELECT PRJ_CODE_EXT, PRJ_LIB, MODELE_VERSION FROM SYS_PROJET').fetchone()
    modules = dict(con.execute('SELECT MOD_CODE, MOD_VERSION FROM SYS_MODULE ORDER BY MOD_ID'))
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
        z.writestr('referentiels.json', json.dumps(pub.referentiels(), ensure_ascii=False, separators=(',', ':')))
        for nom, data in contenu.items():
            z.writestr(nom, data, zipfile.ZIP_STORED)
    con.close()
    return entete


# -- vérification ------------------------------------------------------------------------------

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
        ids = {}
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
