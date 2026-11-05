"""Paquet de zone NgeEsPlorer (format d'échange GeoJSON, voir docs/paquet.md).

Implémentation de référence côté BE :
- publier : extrait une zone du projet en paquet ZIP (paquet.json, objets.geojson, referentiels.json et,
  sur option, les photos) ; refuse un projet en retard sur son schéma, à reprendre d'abord (projet.py migrer) ;
  ne publie que les modules décrits par le format (MODULES_PUBLIES) et, des fichiers, que les photos ; adresses des
  nœuds publiés et de l'emprise de la zone ; câbles de la zone (classe CAB ; un câble de raccordement mène du PBO à
  l'adresse desservie, ADR2_KEY, avec son tracé propre), contenu optique de ses nœuds (opt),
  immeubles et locaux de ses adresses (imb) ;
- verifier : contrôle la structure d'un paquet (en-tête et versions des modules chambre et infra, objets, références
  entre objets, fichiers : photos de la galerie d'un équipement et vues attendues, commentaires, masques des chambres, conduites : câbles de conduite et sous-tubes ; optique :
  câbles (extrémité aval : nœud ou adresse desservie ; géométrie nulle ou ligne), parcours, fibres, cassettes et
  positions ; locaux des adresses).

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
# 0.2.0 : journal des commentaires (NOE_COMMENT, CHB_COMMENT, POT_COMMENT retirés) ; 0.3.0 : modules optique et
# immeuble (classe CAB des câbles, espaces opt des nœuds et imb des adresses) ; 0.4.0 : galerie des équipements (photo
# d'ENTITE INF_EQUIPEMENT désignée par EQU_KEY, vues d'équipement DEF_VUE.VUE_ENTITE, plus de vue BOITIER des supports) ;
# 0.5.0 : câbles de raccordement (CAB du PBO à l'adresse desservie ADR2_KEY, sans NOE2_KEY, avec son tracé propre en
# géométrie LineString ; les autres câbles restent sans géométrie)
FORMAT_VERSION = '0.5.0'
ENTITE_EQUIPEMENT = 'INF_EQUIPEMENT'    # table porteuse des photos de la galerie d'un équipement
DECIMALES = 7                   # ~1 cm en WGS84
# Masques métriques depuis le module chambre 0.3.0 (format inchangé) : faces FAC_LARG x FAC_HAUT et positions POS_X,
# POS_Y en m ; avant, en cellules FOA (FAC_NB_COL, FAC_NB_LIG), paquet refusé.
VERSION_MASQUES = '0.3.0'
# Occupation des conduites depuis le module infra 0.2.0 (format inchangé) : câbles de conduite identifiés par CDC_RANG,
# nature CDC_NATURE, taux CD_OCCUP ; avant, câbles sans clé naturelle, paquet refusé.
VERSION_OCCUPATION = '0.2.0'
# Centre d'une alvéole hors de sa face toléré jusqu'à 1 mm : le centre est borné à la face, puis arrondi au micromètre
# au BE (conversions exactes) et au millimètre au plus sur le terminal, soit 0,5 mm de débord au plus. Au-delà, la
# position est dans un autre repère (cellules) ou sa face a été réduite sans recentrage. C'est bien moins qu'un
# demi-diamètre (14 mm pour la plus petite alvéole normalisée, 28 mm) : une alvéole acceptée recouvre toujours sa
# face. Le disque, lui, peut déborder : 206 alvéoles des relevés FOA de Nancy débordent de la fenêtre FOA, aucune n'en
# a le centre dehors.
TOLERANCE_POSITION = 0.001      # m
# Modules dont le format décrit l'espace GeoJSON : ceux d'un projet qui n'y figurent pas ne sont pas publiés (ni
# en-tête, ni référentiels) tant que le terminal ne les lit pas ; leurs types et vues, enregistrés dans le noyau, le
# sont avec lui.
MODULES_PUBLIES = ('noyau', 'infra', 'chambre', 'poteau', 'optique', 'immeuble')
# Base attachée d'une table selon son préfixe (noyau : base principale).
SCHEMAS = {'INF_': 'infra', 'OPT_': 'optique', 'IMB_': 'immeuble'}

# Références vers une entité : écrites avec le CODE_EXT de la cible (colonne → table, colonne CODE_EXT).
ENTITES = {
    'PRJ_ZONE': 'ZONE_CODE_EXT', 'PRJ_ADRESSE': 'ADR_CODE_EXT', 'PRJ_NOE': 'NOE_CODE_EXT',
    'PRJ_LINEAIRE': 'LIN_CODE_EXT', 'INF_CONDUITE': 'CD_CODE_EXT', 'INF_EQUIPEMENT': 'EQU_CODE_EXT',
    'OPT_CABLE': 'CAB_CODE_EXT',
}
REFERENCES = {
    'ZONE_KEY': 'PRJ_ZONE', 'ADR_KEY': 'PRJ_ADRESSE', 'ADR2_KEY': 'PRJ_ADRESSE', 'NOE_KEY': 'PRJ_NOE', 'NOE1_KEY': 'PRJ_NOE',
    'NOE2_KEY': 'PRJ_NOE', 'LIN_KEY': 'PRJ_LINEAIRE', 'CD_KEY': 'INF_CONDUITE', 'CD_PARENT_KEY': 'INF_CONDUITE',
    'EQU_KEY': 'INF_EQUIPEMENT', 'EQU1_KEY': 'INF_EQUIPEMENT', 'EQU2_KEY': 'INF_EQUIPEMENT', 'CAB_KEY': 'OPT_CABLE',
}
# Référence vers une fibre (OPT_FIBRE, sans CODE_EXT) : écrite par son câble (CAB_CODE_EXT) et son rang dans le câble.
FIBRES = {'FIB_KEY': ('CAB_KEY', 'FIB_NUM'), 'FIB1_KEY': ('CAB1_KEY', 'FIB1_NUM'), 'FIB2_KEY': ('CAB2_KEY', 'FIB2_NUM')}

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
# Câble (classe CAB, OPT_CABLE) : son parcours, ses lovages et ses fibres.
CABLE = [
    ('passages', 'optique.OPT_PASSAGE', 'CAB_KEY', False, []),
    ('lovages', 'optique.OPT_LOVE', 'CAB_KEY', False, []),
    ('fibres', 'optique.OPT_FIBRE', 'CAB_KEY', False, []),
]
# Contenu optique d'un équipement (opt.equipements d'un nœud, une entrée par OPT_EQUIPEMENT) : cassettes et leurs
# positions, mesures prises à l'équipement.
EQUIPEMENT_OPTIQUE = [
    ('cassettes', 'optique.OPT_CASSETTE', 'EQU_KEY', False, [
        ('positions', 'optique.OPT_POSITION', 'CAS_KEY', False, [])]),
    ('mesures', 'optique.OPT_MESURE', 'EQU_KEY', False, []),
]
# Ordre des éléments imbriqués (ordre d'insertion à défaut).
ORDRE = {
    'optique.OPT_PASSAGE': 'PAS_RANG IS NULL, PAS_RANG, PAS_ID', 'optique.OPT_LOVE': 'LOV_ID',
    'optique.OPT_FIBRE': 'FIB_NUM', 'optique.OPT_CASSETTE': 'CAS_NUM', 'optique.OPT_POSITION': 'POS_NUM, POS_ID',
    'optique.OPT_MESURE': 'MES_DATE, MES_ID', 'immeuble.IMB_LOCAL': 'LOC_ID',
}
# Tables dont les fichiers (PRJ_FICHIER) sont rattachés à l'objet du nœud, du linéaire, de l'adresse ou du câble qui
# les porte.
PORTEUR_FICHIER = {
    'PRJ_NOE': ('NOE', None), 'PRJ_LINEAIRE': ('LIN', None), 'PRJ_ADRESSE': ('ADR', None),
    'CHB_CHAMBRE': ('NOE', 'chambre.CHB_CHAMBRE'), 'POT_POTEAU': ('NOE', 'poteau.POT_POTEAU'),
    'POT_CONTROLE': ('NOE', 'poteau.POT_CONTROLE'), 'INF_EQUIPEMENT': ('NOE', 'infra.INF_EQUIPEMENT'),
    'INF_CONDUITE': ('LIN', 'infra.INF_CONDUITE'), 'INF_PORTEE': ('LIN', 'infra.INF_PORTEE'),
    'OPT_CABLE': ('CAB', None), 'IMB_LOCAL': ('ADR', 'immeuble.IMB_LOCAL'),
}
# Colonne de la table source désignant l'objet porteur, selon sa classe.
COLONNE_PORTEUR = {'NOE': 'NOE_KEY', 'LIN': 'LIN_KEY', 'ADR': 'ADR_KEY'}
# Tables des objets commentés : le journal (PRJ_COMMENTAIRE) est porté par l'objet lui-même, sans clé ENTITE.
PORTEUR_COMMENTAIRE = {'PRJ_NOE': 'NOE', 'PRJ_LINEAIRE': 'LIN', 'PRJ_ADRESSE': 'ADR', 'OPT_CABLE': 'CAB'}
CLASSES = ('NOE', 'LIN', 'ADR', 'CAB')
# Géométrie attendue par classe : un câble n'en a en général pas (null), son tracé est celui des linéaires de son
# parcours ; un câble de raccordement porte son tracé propre (LineString, format 0.5.0).
GEOMETRIES = {'NOE': 'Point', 'ADR': 'Point', 'LIN': 'LineString', 'CAB': 'LineString'}
TYPES_COMMENTAIRE = ('alert', 'minor', 'standard', 'great')     # COM_TYPE de FibReady, par gravité décroissante
NATURES_CABLE = ('FO', 'CU')    # CDC_NATURE d'un câble de conduite : fibre optique, cuivre (module infra 0.2.0)


def maintenant():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def lignes(con, table, where='', params=()):
    cur = con.execute(f'SELECT * FROM {table} {where}', params)
    noms = [d[0] for d in cur.description]
    return [dict(zip(noms, r)) for r in cur]


def nom_table(table):
    return table.split('.')[-1]


def qualifier(table):
    """Table préfixée de sa base attachée (INF_EQUIPEMENT → infra.INF_EQUIPEMENT ; table du noyau inchangée)."""
    schema = next((s for p, s in SCHEMAS.items() if table.startswith(p)), None)
    return f'{schema}.{table}' if schema else table


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
        # bases attachées : un projet sans module optique ou immeuble n'a ni câbles, ni opt, ni imb
        self.schemas = {r[1] for r in con.execute('PRAGMA database_list')}
        self.codes = {}
        for t, c in ENTITES.items():
            if self.present(t):
                self.codes[t] = dict(con.execute(f'SELECT {cle_primaire(con, qualifier(t))}, {c} FROM {qualifier(t)}'))
        self.mlog = dict(con.execute('SELECT MLOG_ID, MLOG_NUM FROM chambre.CHB_MASQUE_LOGIQUE'))
        self.optique = 'optique' in self.schemas
        self.immeuble = 'immeuble' in self.schemas
        if self.optique:
            cables = self.codes['OPT_CABLE']
            self.fibres = {f: (cables[c], n) for f, c, n in con.execute(
                'SELECT FIB_ID, CAB_KEY, FIB_NUM FROM optique.OPT_FIBRE')}
            self.pcb = dict(con.execute('SELECT PCB_ID, PCB_RANG FROM infra.INF_PORTEE_CABLE'))
            self.cdc = {i: (self.codes['INF_CONDUITE'][cd], r) for i, cd, r in con.execute(
                'SELECT CDC_ID, CD_KEY, CDC_RANG FROM infra.INF_CD_CABLE')}
            self.eqo = dict(con.execute('SELECT EQO_ID, EQU_KEY FROM optique.OPT_EQUIPEMENT'))
        self.cache = {}

    def present(self, table):
        """Vrai si la base de la table (qualifiée, ou désignée par son préfixe) est attachée : module du projet."""
        schema = qualifier(table).rpartition('.')[0]
        return not schema or schema in self.schemas

    # -- conversion d'une ligne ----------------------------------------------------------------

    def proprietes(self, table, ligne, parent=None):
        """Colonnes BE d'une ligne : sans sa clé technique ni le lien vers son parent (porté par l'imbrication),
        références vers les entités en CODE_EXT, valeurs nulles omises. Références propres à l'optique : fibre par
        son câble et son rang (FIBRES), câble porté par son rang PCB_RANG dans la portée, câble de conduite par sa
        conduite et son rang (CD_KEY, CDC_RANG), équipement parent (EQO_PARENT_KEY) par le CODE_EXT de son
        équipement de l'infra ; route d'une mesure (RTE_KEY) omise : les routes restent au BE."""
        pk = cle_primaire(self.con, table)
        out = {}
        for col, v in ligne.items():
            if v is None or col in (pk, parent, 'GEOMETRY', 'RTE_KEY'):
                continue
            if col in REFERENCES:
                v = self.codes[REFERENCES[col]].get(v)
            elif col == 'MLOG_KEY':
                col, v = 'MLOG_NUM', self.mlog.get(v)
            elif col in FIBRES:
                col_cab, col_num = FIBRES[col]
                out[col_cab], v = self.fibres[v]
                col = col_num
            elif col == 'PCB_KEY':
                col, v = 'PCB_RANG', self.pcb[v]
            elif col == 'CDC_KEY':
                out['CD_KEY'], v = self.cdc[v]
                col = 'CDC_RANG'
            elif col == 'EQO_PARENT_KEY':
                v = self.codes['INF_EQUIPEMENT'].get(self.eqo.get(v))
            out[col] = v
        return out

    def enfants(self, table, parent):
        """Lignes d'une table groupées par la colonne parent (chargées une seule fois), dans l'ordre ORDRE."""
        if (table, parent) not in self.cache:
            schema, _, nom = table.rpartition('.')
            if parent not in {r[1] for r in self.con.execute(f'PRAGMA {schema or "main"}.table_info({nom})')}:
                raise SystemExit(f'{table} sans colonne {parent} : projet construit avec un schéma antérieur, '
                                 f'à reconstruire (tools/essai/charger_essai.py)')
            groupes = defaultdict(list)
            for l in lignes(self.con, table, f'ORDER BY {ORDRE[table]}' if table in ORDRE else ''):
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
        """Nœuds, nœuds hors zone, linéaires, adresses et câbles d'une zone. Câbles : ceux qui ont une extrémité ou un
        passage dans la zone, ou une fibre dans une position ou une mesure d'un équipement de la zone, et les câbles de
        raccordement des adresses de la zone (ADR2_KEY : le raccordement suit son PBO, NOE1_KEY, et son adresse) ;
        leurs extrémités situées ailleurs sont publiées hors zone, comme celles des linéaires ; l'adresse desservie
        par un câble publié l'est aussi."""
        z = self.zone[0]
        lin = [r[0] for r in self.con.execute('SELECT LIN_ID FROM PRJ_LINEAIRE WHERE ZONE_KEY = ?', (z,))]
        noe = {r[0] for r in self.con.execute('SELECT NOE_ID FROM PRJ_NOE WHERE ZONE_KEY = ?', (z,))}
        hors = set()
        for n1, n2 in self.con.execute('SELECT NOE1_KEY, NOE2_KEY FROM PRJ_LINEAIRE WHERE ZONE_KEY = ?', (z,)):
            hors |= {n1, n2} - noe
        # adresses des nœuds de la zone et adresses situées dans son emprise (BAL à relever)
        adr = {r[0] for r in self.con.execute(
            f'SELECT DISTINCT ADR_KEY FROM PRJ_NOE WHERE ADR_KEY IS NOT NULL AND NOE_ID IN '
            f'({",".join(map(str, noe)) or "NULL"})')}
        adr |= {r[0] for r in self.con.execute(
            'SELECT a.ADR_ID FROM PRJ_ADRESSE a, PRJ_ZONE z WHERE z.ZONE_ID = ? AND a.DATE_ABD IS NULL '
            'AND Within(a.GEOMETRY, z.GEOMETRY) = 1', (z,))}
        cab = set()
        if self.optique:
            liste = lambda ids: ','.join(map(str, ids)) or 'NULL'
            equ = f'SELECT EQU_ID FROM infra.INF_EQUIPEMENT WHERE NOE_KEY IN ({liste(noe)})'
            cab = {r[0] for r in self.con.execute(
                f'SELECT CAB_ID FROM optique.OPT_CABLE WHERE NOE1_KEY IN ({liste(noe)}) OR NOE2_KEY IN ({liste(noe)}) '
                f'OR ADR2_KEY IN ({liste(adr)}) '
                f'UNION SELECT CAB_KEY FROM optique.OPT_PASSAGE WHERE LIN_KEY IN ({liste(lin)}) '
                f'UNION SELECT f.CAB_KEY FROM optique.OPT_FIBRE f JOIN optique.OPT_POSITION p '
                f'ON f.FIB_ID IN (p.FIB1_KEY, p.FIB2_KEY) JOIN optique.OPT_CASSETTE c ON c.CAS_ID = p.CAS_KEY '
                f'WHERE c.EQU_KEY IN ({equ}) '
                f'UNION SELECT f.CAB_KEY FROM optique.OPT_FIBRE f JOIN optique.OPT_MESURE m ON m.FIB_KEY = f.FIB_ID '
                f'WHERE m.EQU_KEY IN ({equ})')}
            for n1, n2, a2 in self.con.execute(f'SELECT NOE1_KEY, NOE2_KEY, ADR2_KEY FROM optique.OPT_CABLE '
                                               f'WHERE CAB_ID IN ({liste(cab)})'):
                hors |= {n for n in (n1, n2) if n is not None} - noe
                if a2 is not None:
                    adr.add(a2)
        # adresses des nœuds hors zone
        adr |= {r[0] for r in self.con.execute(
            f'SELECT DISTINCT ADR_KEY FROM PRJ_NOE WHERE ADR_KEY IS NOT NULL AND NOE_ID IN '
            f'({",".join(map(str, hors)) or "NULL"})')}
        return sorted(noe), sorted(hors), lin, sorted(adr), sorted(cab)

    def optique_noeud(self, noe):
        """Espace opt d'un nœud : contenu optique de ses équipements (OPT_EQUIPEMENT, avec leurs cassettes, leurs
        positions et leurs mesures), dans l'ordre de ses équipements de l'infra ; None s'il n'en a pas."""
        equipements = []
        for e in self.enfants('infra.INF_EQUIPEMENT', 'NOE_KEY').get(noe, []):
            for l in self.enfants('optique.OPT_EQUIPEMENT', 'EQU_KEY').get(e['EQU_ID'], []):
                o = self.proprietes('optique.OPT_EQUIPEMENT', l)
                self.imbriquer(o, EQUIPEMENT_OPTIQUE, e['EQU_ID'])
                equipements.append(o)
        return {'equipements': equipements} if equipements else None

    def immeuble_adresse(self, adr):
        """Espace imb d'une adresse : colonnes de IMB_ADRESSE (immeuble, logements, convention) et locaux de
        l'adresse (IMB_LOCAL, chacun avec son PBO) ; None s'il n'y a ni l'un ni les autres."""
        imb = {}
        for l in self.enfants('immeuble.IMB_ADRESSE', 'ADR_KEY').get(adr, []):
            imb = self.proprietes('immeuble.IMB_ADRESSE', l, 'ADR_KEY')
        locaux = [self.proprietes('immeuble.IMB_LOCAL', l, 'ADR_KEY')
                  for l in self.enfants('immeuble.IMB_LOCAL', 'ADR_KEY').get(adr, [])]
        if locaux:
            imb['locaux'] = locaux
        return imb or None

    def geometrique(self, table):
        """La table porte une colonne GEOMETRY (OPT_CABLE depuis le module optique 0.3.0)."""
        schema, _, nom = table.rpartition('.')
        return 'GEOMETRY' in {r[1].upper() for r in self.con.execute(f'PRAGMA {schema or "main"}.table_info({nom})')}

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
            if not self.present(source or table):
                continue
            if source:
                col = COLONNE_PORTEUR[classe]
                if source.endswith('POT_CONTROLE'):
                    req = ('SELECT c.CTL_ID, p.NOE_KEY FROM poteau.POT_CONTROLE c '
                           'JOIN poteau.POT_POTEAU p ON p.POT_ID = c.POT_KEY')
                else:
                    req = f'SELECT {cle_primaire(self.con, source)}, {col} FROM {source}'
                porteurs[table] = (classe, dict(self.con.execute(req)))
            else:
                porteurs[table] = (classe, None)
        # équipement d'une photo de sa galerie : EQU_CODE_EXT, l'équipement est un élément du nœud (inf.equipements)
        equipements = (dict(self.con.execute('SELECT EQU_ID, EQU_CODE_EXT FROM infra.INF_EQUIPEMENT'))
                       if self.present('infra.INF_EQUIPEMENT') else {})
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
            o = {'ENTITE': table}
            if table == ENTITE_EQUIPEMENT:
                o['EQU_KEY'] = equipements.get(f['OBJ_KEY'])
            o['VUE_CODE'] = vues.get(f['VUE_KEY'])
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
        autre table que celles des objets (PORTEUR_COMMENTAIRE) n'a pas de place dans le format : non publiée,
        signalée."""
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
                  f'à une autre table que {", ".join(PORTEUR_COMMENTAIRE)} '
                  f'({", ".join(f"{t} {k}" for t, k in sorted(omis.items()))}), à rattacher à leur objet',
                  file=sys.stderr)
        return par_objet

    def objets(self):
        noe, hors, lin, adr, cab = self.ids_zone()
        fichiers, commentaires = self.fichiers(), self.commentaires()
        features = []

        def feature(classe, table, pk, ids, structure, hors_zone=(), espace=None):
            """espace : (clé, fonction) d'un espace de module construit à part (opt d'un nœud, imb d'une adresse),
            absent d'un nœud hors zone : son contenu relève de sa zone."""
            geo = self.geometries(table, pk, ids) if GEOMETRIES[classe] and self.geometrique(table) else {}
            enregs = {l[pk]: l for l in lignes(self.con, table, f'WHERE {pk} IN ({",".join(map(str, ids)) or "NULL"})')}
            code = ENTITES[nom_table(table)]
            for oid in ids:
                l = enregs[oid]
                props = {'classe': classe}
                props.update(self.proprietes(table, l))
                props.pop(code, None)
                if oid in hors_zone:
                    props['hors_zone'] = True
                self.imbriquer(props, structure, oid)
                if espace and oid not in hors_zone:
                    contenu = espace[1](oid)
                    if contenu:
                        props[espace[0]] = contenu
                fic = fichiers.get((classe, oid))
                if fic:
                    props['fichiers'] = fic
                com = commentaires.get((classe, oid))
                if com:
                    props['commentaires'] = com
                features.append({'type': 'Feature', 'id': l[code], 'geometry': geo.get(oid), 'properties': props})

        feature('ADR', 'PRJ_ADRESSE', 'ADR_ID', adr, [],
                espace=('imb', self.immeuble_adresse) if self.immeuble else None)
        feature('NOE', 'PRJ_NOE', 'NOE_ID', sorted(set(noe) | set(hors)), NOEUD, set(hors),
                espace=('opt', self.optique_noeud) if self.optique else None)
        feature('LIN', 'PRJ_LINEAIRE', 'LIN_ID', lin, LINEAIRE)
        if self.optique:
            feature('CAB', 'optique.OPT_CABLE', 'CAB_ID', cab, CABLE)
            sans = self.con.execute(
                'SELECT COUNT(*) FROM optique.OPT_CASSETTE c WHERE NOT EXISTS (SELECT 1 FROM optique.OPT_EQUIPEMENT e '
                'WHERE e.EQU_KEY = c.EQU_KEY)').fetchone()[0]
            if sans:
                print(f'cassettes non publiées : {sans} d\'un équipement sans contenu optique (OPT_EQUIPEMENT)',
                      file=sys.stderr)
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
        'effectifs': {c: sum(1 for f in features if f['properties']['classe'] == c) for c in CLASSES}
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


def entier(v):
    return isinstance(v, int) and not isinstance(v, bool)


def verifier_conduites(oid, inf):
    """Anomalies des conduites d'un objet (espace inf : conduites d'un linéaire, ou d'une chambre pour celles sans
    destination connue), module infra 0.2.0 : chaque câble de conduite (cables) a un CDC_RANG entier unique dans sa
    conduite et un CDC_NB entier d'au moins 1, CDC_NATURE absente ou FO / CU ; un sous-tube (CD_PARENT_KEY) désigne
    une conduite de la même liste conduites (même porteur : même linéaire, ou même chambre sans destination), qui n'a
    pas elle-même de parent (un seul niveau)."""
    if inf is None:
        return []
    if not isinstance(inf, dict):
        return [f'{oid} : inf illisible']
    conduites = inf.get('conduites')
    if conduites is None:
        return []
    if not isinstance(conduites, list):
        return [f'{oid} : conduites hors liste']
    err = []
    parents = {c.get('CD_CODE_EXT'): c.get('CD_PARENT_KEY') for c in conduites if isinstance(c, dict)}
    for cd in conduites:
        if not isinstance(cd, dict):
            err.append(f'{oid} : conduite illisible {str(cd)[:60]}')
            continue
        code, parent = cd.get('CD_CODE_EXT'), cd.get('CD_PARENT_KEY')
        nom = f'{oid} conduite {code}'
        if parent is not None:
            if parent == code:
                err.append(f'{nom} : sous-tube de lui-même')
            elif parent not in parents:
                err.append(f'{nom} : sous-tube de {parent}, conduite absente de ce porteur')
            elif parents[parent] is not None:
                err.append(f'{nom} : sous-tube de {parent}, lui-même sous-tube de {parents[parent]} (un seul niveau)')
        cables = cd.get('cables')
        if cables is None:
            continue
        if not isinstance(cables, list):
            err.append(f'{nom} : cables hors liste')
            continue
        rangs = set()
        for c in cables:
            if not isinstance(c, dict):
                err.append(f'{nom} : câble illisible {str(c)[:60]}')
                continue
            rang = c.get('CDC_RANG')
            if not entier(rang):
                err.append(f'{nom} : câble sans CDC_RANG entier ({rang})')
            elif rang in rangs:
                err.append(f'{nom} : CDC_RANG {rang} en double')
            else:
                rangs.add(rang)
            if not (entier(c.get('CDC_NB')) and c['CDC_NB'] >= 1):
                err.append(f'{nom} câble {rang} : CDC_NB {c.get("CDC_NB")} au lieu d\'un entier d\'au moins 1')
            if c.get('CDC_NATURE') not in (None,) + NATURES_CABLE:
                err.append(f'{nom} câble {rang} : CDC_NATURE {c.get("CDC_NATURE")} au lieu de FO ou CU')
    return err


def liste(oid, cle, v):
    """(éléments, anomalies) d'une clé de liste du format : absente, vide ; hors liste, anomalie ; éléments qui ne sont
    pas des objets, signalés et écartés."""
    if v is None:
        return [], []
    if not isinstance(v, list):
        return [], [f'{oid} : {cle} hors liste']
    return [x for x in v if isinstance(x, dict)], [f'{oid} : {cle} : élément illisible {str(x)[:60]}'
                                                    for x in v if not isinstance(x, dict)]


def fibre(nom, o, col_cab, col_num, refs):
    """Anomalies d'une référence à une fibre (câble col_cab et rang col_num, ensemble) ; la référence lue est ajoutée
    à refs (nom, câble, rang) pour le contrôle croisé de la publication."""
    cab, num = o.get(col_cab), o.get(col_num)
    if cab is None and num is None:
        return []
    if not (isinstance(cab, str) and cab and entier(num)):
        return [f'{nom} : fibre {col_cab} {cab}, {col_num} {num} au lieu d\'un câble et d\'un rang entier']
    refs.append((nom, cab, num))
    return []


def verifier_optique(oid, p, refs):
    """Anomalies de l'espace opt d'un nœud (module optique) : equipements, une entrée par équipement du nœud
    (EQU_KEY parmi les EQU_CODE_EXT de inf.equipements, une seule fois) ; cassettes à CAS_NUM entier unique dans
    l'équipement ; positions portant au moins une fibre (FIB1, FIB2 : câble et rang ensemble) ; mesures à MES_CODE_EXT.
    Les fibres désignées sont ajoutées à refs."""
    opt = p.get('opt')
    if opt is None:
        return []
    if not isinstance(opt, dict):
        return [f'{oid} : opt illisible']
    equipements, err = liste(oid, 'opt.equipements', opt.get('equipements'))
    infra, _ = liste(oid, 'inf.equipements', (p.get('inf') or {}).get('equipements'))
    codes = {e.get('EQU_CODE_EXT') for e in infra}
    vus = set()
    for e in equipements:
        equ = e.get('EQU_KEY')
        nom = f'{oid} équipement {equ}'
        if equ not in codes:
            err.append(f'{nom} : contenu optique d\'un équipement absent de inf.equipements du nœud')
        elif equ in vus:
            err.append(f'{nom} : contenu optique en double')
        vus.add(equ)
        cassettes, e_err = liste(nom, 'cassettes', e.get('cassettes'))
        err += e_err
        numeros = set()
        for c in cassettes:
            num = c.get('CAS_NUM')
            if not entier(num):
                err.append(f'{nom} : cassette sans CAS_NUM entier ({num})')
            elif num in numeros:
                err.append(f'{nom} : cassette {num} en double')
            numeros.add(num)
            positions, c_err = liste(f'{nom} cassette {num}', 'positions', c.get('positions'))
            err += c_err
            for pos in positions:
                np = f'{nom} cassette {num} position {pos.get("POS_NUM")}'
                err += fibre(np, pos, 'CAB1_KEY', 'FIB1_NUM', refs) + fibre(np, pos, 'CAB2_KEY', 'FIB2_NUM', refs)
                if pos.get('CAB1_KEY') is None and pos.get('CAB2_KEY') is None:
                    err.append(f'{np} : sans fibre')
        mesures, m_err = liste(nom, 'mesures', e.get('mesures'))
        err += m_err
        for m in mesures:
            if not m.get('MES_CODE_EXT'):
                err.append(f'{nom} : mesure sans MES_CODE_EXT')
            err += fibre(f'{nom} mesure {m.get("MES_CODE_EXT")}', m, 'CAB_KEY', 'FIB_NUM', refs)
    return err


def verifier_cable(oid, p):
    """Anomalies d'un câble (classe CAB) : extrémité NOE1_KEY, extrémité aval NOE2_KEY ou adresse desservie ADR2_KEY
    (câble de raccordement) ; passages à LIN_KEY unique, PAS_RANG
    entier ou absent, câble porté (PCB_RANG entier) ou câble de conduite (CD_KEY et CDC_RANG entier ensemble), pas les
    deux ; lovages à NOE_KEY unique ; fibres à FIB_NUM entier unique."""
    err = [] if p.get('NOE1_KEY') else [f'{oid} : sans NOE1_KEY']
    if not p.get('NOE2_KEY') and not p.get('ADR2_KEY'):
        err.append(f'{oid} : sans NOE2_KEY ni ADR2_KEY')
    passages, e = liste(oid, 'passages', p.get('passages'))
    err += e
    lins = set()
    for pas in passages:
        lin = pas.get('LIN_KEY')
        nom = f'{oid} passage {lin}'
        if not lin:
            err.append(f'{oid} : passage sans LIN_KEY')
        elif lin in lins:
            err.append(f'{nom} : en double')
        lins.add(lin)
        if pas.get('PAS_RANG') is not None and not entier(pas['PAS_RANG']):
            err.append(f'{nom} : PAS_RANG {pas["PAS_RANG"]} non entier')
        porte = pas.get('PCB_RANG') is not None
        conduite = pas.get('CD_KEY') is not None or pas.get('CDC_RANG') is not None
        if porte and not entier(pas['PCB_RANG']):
            err.append(f'{nom} : PCB_RANG {pas["PCB_RANG"]} non entier')
        if conduite and not (pas.get('CD_KEY') and entier(pas.get('CDC_RANG'))):
            err.append(f'{nom} : câble de conduite sans CD_KEY ou sans CDC_RANG entier')
        if porte and conduite:
            err.append(f'{nom} : câble porté et câble de conduite à la fois')
    lovages, e = liste(oid, 'lovages', p.get('lovages'))
    err += e
    noeuds = Counter(l.get('NOE_KEY') for l in lovages)
    err += [f'{oid} : lovage sans NOE_KEY' if n is None else f'{oid} : lovage {n} en double'
            for n, k in noeuds.items() if n is None or k > 1]
    fibres, e = liste(oid, 'fibres', p.get('fibres'))
    err += e
    nums = Counter(f.get('FIB_NUM') for f in fibres)
    err += [f'{oid} : fibre sans FIB_NUM entier ({n})' if not entier(n) else f'{oid} : fibre {n} en double'
            for n, k in nums.items() if not entier(n) or k > 1]
    return err


def verifier_immeuble(oid, p, locaux_vus):
    """Anomalies de l'espace imb d'une adresse (module immeuble) : locaux à LOC_CODE_EXT présent, unique dans le
    paquet (locaux_vus)."""
    imb = p.get('imb')
    if imb is None:
        return []
    if not isinstance(imb, dict):
        return [f'{oid} : imb illisible']
    locaux, err = liste(oid, 'imb.locaux', imb.get('locaux'))
    for l in locaux:
        code = l.get('LOC_CODE_EXT')
        if not code:
            err.append(f'{oid} : local sans LOC_CODE_EXT')
        elif code in locaux_vus:
            err.append(f'{oid} local {code} : LOC_CODE_EXT en double dans le paquet')
        locaux_vus.add(code)
    return err


def verifier_modules(entete, objets):
    """Modules optique et immeuble de l'en-tête présents dès qu'un objet porte leurs données."""
    modules = entete.get('modules') or {}
    features = [f.get('properties') or {} for f in objets.get('features', [])]
    err = []
    if 'optique' not in modules and any(p.get('classe') == 'CAB' or p.get('opt') for p in features):
        err.append('câbles ou contenu optique sans module optique dans l\'en-tête')
    if 'immeuble' not in modules and any(p.get('imb') for p in features):
        err.append('immeubles ou locaux sans module immeuble dans l\'en-tête')
    return err


def verifier_masques(oid, chb):
    """Anomalies des faces d'une chambre (espace chb), au repère métrique du module chambre 0.3.0 : FAC_LARG et
    FAC_HAUT nombres strictement positifs (m), sans les clés de l'ancien repère ; centre de chaque position dans sa
    face, à TOLERANCE_POSITION près ; au plus une position par conduite dans la chambre, toutes faces confondues (la
    conduite a une position à chaque bout, dans deux chambres). Une position abandonnée (DATE_ABD), qui n'est plus
    dessinée, n'est ni bornée ni comptée."""
    if chb is None:
        return []
    if not isinstance(chb, dict):
        return [f'{oid} : chb illisible']
    faces = chb.get('faces')
    if faces is None:
        return []
    if not isinstance(faces, list):
        return [f'{oid} : faces hors liste']
    err, placees = [], Counter()
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
            placees[pos.get('CD_KEY')] += 1
            for col, dim in (('POS_X', 'FAC_LARG'), ('POS_Y', 'FAC_HAUT')):
                v = pos.get(col)
                if not nombre(v):
                    err.append(f'{nom} : position {pos.get("CD_KEY")} sans {col} numérique ({v})')
                elif dim in dims and not -TOLERANCE_POSITION <= v <= dims[dim] + TOLERANCE_POSITION:
                    err.append(f'{nom} : position {pos.get("CD_KEY")} hors de la face ({col} {v} m, {dim} '
                               f'{dims[dim]} m)')
    for cd, n in placees.items():
        if n > 1:
            err.append(f'{oid} : conduite {cd} placée {n} fois dans la chambre (une position au plus)')
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


def verifier_version_infra(entete, objets):
    """Module infra de l'en-tête : 0.2.0 au moins (VERSION_OCCUPATION : câbles de conduite rangés, CDC_RANG, et taux
    d'occupation) ; avant, câbles sans clé naturelle, que le terminal refuse. Présent dès qu'un objet a des conduites."""
    v = (entete.get('modules') or {}).get('infra')
    if v is None:
        if any(isinstance((f.get('properties') or {}).get('inf'), dict) and f['properties']['inf'].get('conduites')
               for f in objets.get('features', [])):
            return ['conduites sans module infra dans l\'en-tête']
        return []
    try:
        lue = projet.version(str(v))
    except ValueError:
        return [f'module infra en version illisible : {v}']
    if lue < projet.version(VERSION_OCCUPATION):
        return [f'module infra {v} antérieur à {VERSION_OCCUPATION} : câbles de conduite sans rang (CDC_RANG), refusés '
                f'par le terminal ; projet à reprendre (tools/schema/projet.py migrer) et paquet à republier']
    return []


def vues_attendues(ref):
    """Codes des vues attendues par porteur : {None : vues des supports, 'INF_EQUIPEMENT' : vues d'un équipement…},
    d'après DEF_VUE des référentiels publiés, sinon (retour, sans référentiels) d'après les manifestes du schéma."""
    lignes_vue = ((ref or {}).get('noyau') or {}).get('DEF_VUE')
    if lignes_vue is None:
        lignes_vue = [{'VUE_ENTITE': v.get('entite'), 'VUE_CODE': v['code']}
                      for m in projet.manifestes() for v in m['vues']]
    vues = defaultdict(set)
    for v in lignes_vue:
        vues[v.get('VUE_ENTITE')].add(v.get('VUE_CODE'))
    return vues


def verifier_fichiers(oid, p, vues):
    """Photos d'un objet : celle de la galerie d'un équipement (ENTITE INF_EQUIPEMENT) est portée par un nœud et
    désigne par EQU_KEY un équipement de son inf.equipements (créé sur le terminal compris) ; EQU_KEY n'a pas de sens
    ailleurs ; une vue attendue (VUE_CODE) est une vue de son porteur (vues_attendues : support ou équipement), jamais
    avec un visuel libre (VIS_CODE)."""
    err = []
    equipements = {e.get('EQU_CODE_EXT') for e in (p.get('inf') or {}).get('equipements', []) if isinstance(e, dict)}
    for fic in p.get('fichiers', []):
        if not isinstance(fic, dict):
            err.append(f'{oid} : fichier qui n\'est pas un objet')
            continue
        nom = f'{oid} fichier {fic.get("FIC_CODE_EXT")}'
        equipement = fic.get('ENTITE') == ENTITE_EQUIPEMENT
        if equipement:
            if p.get('classe') != 'NOE':
                err.append(f'{nom} : photo d\'équipement portée par un objet {p.get("classe")}')
            if not fic.get('EQU_KEY'):
                err.append(f'{nom} : photo d\'équipement sans EQU_KEY')
            elif fic['EQU_KEY'] not in equipements:
                err.append(f'{nom} : équipement {fic["EQU_KEY"]} absent de inf.equipements')
        elif 'EQU_KEY' in fic:
            err.append(f'{nom} : EQU_KEY hors d\'une photo d\'équipement (ENTITE {fic.get("ENTITE")})')
        vue = fic.get('VUE_CODE')
        if vue:
            porteur = ENTITE_EQUIPEMENT if equipement else None
            if vue not in vues.get(porteur, ()):
                err.append(f'{nom} : vue {vue} inconnue pour ' + ('un équipement' if equipement else 'un support'))
            if fic.get('VIS_CODE'):
                err.append(f'{nom} : vue attendue {vue} et visuel libre {fic["VIS_CODE"]} à la fois')
    return err


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
        err += verifier_version_infra(entete, objets)
        err += verifier_modules(entete, objets)
        intervention = (entete.get('intervention') or {}) if retour else {}
        vues = vues_attendues(ref)
        ids, commentaires, locaux, fibres_citees = {}, set(), set(), []
        for f in objets['features']:
            p = f.get('properties') or {}
            if not f.get('id'):
                err.append('objet sans id')
                continue
            if f['id'] in ids:
                err.append(f'id en double : {f["id"]}')
            ids[f['id']] = p.get('classe')
            if p.get('classe') not in CLASSES:
                err.append(f'{f["id"]} : classe inattendue {p.get("classe")}')
            attendu = GEOMETRIES.get(p.get('classe'))
            if f.get('geometry') and f['geometry']['type'] != attendu:
                err.append(f'{f["id"]} : géométrie {f["geometry"]["type"]} au lieu de {attendu or "null"}')
            if p.get('statut') not in (('C', 'M', 'A') if retour else (None,)):
                err.append(f'{f["id"]} : statut inattendu {p.get("statut")}')
            for fic in p.get('fichiers', []):
                if fic.get('fichier') and fic['fichier'] not in noms:
                    err.append(f'{f["id"]} : fichier absent du paquet {fic["fichier"]}')
            err += verifier_fichiers(f['id'], p, vues)
            err += verifier_commentaires(f['id'], p.get('commentaires'), commentaires, intervention)
            err += verifier_masques(f['id'], p.get('chb'))
            err += verifier_conduites(f['id'], p.get('inf'))
            err += verifier_optique(f['id'], p, fibres_citees)
            err += verifier_immeuble(f['id'], p, locaux)
            if p.get('classe') == 'CAB':
                err += verifier_cable(f['id'], p)
        if retour:
            return err
        par_id = {f['id']: f['properties'] for f in objets['features'] if f.get('id')}
        conduites = {c['CD_CODE_EXT'] for f in objets['features']
                     for c in (f['properties'].get('inf') or {}).get('conduites', [])}
        for f in objets['features']:
            p = f['properties']
            for col in ('NOE1_KEY', 'NOE2_KEY'):
                # câble de raccordement : extrémité aval à l'adresse (ADR2_KEY), sans nœud
                if col == 'NOE2_KEY' and p['classe'] == 'CAB' and p.get(col) is None and p.get('ADR2_KEY'):
                    continue
                if p['classe'] in ('LIN', 'CAB') and ids.get(p.get(col)) != 'NOE':
                    err.append(f'{f["id"]} : {col} {p.get(col)} absent du paquet')
            for col in ('ADR_KEY', 'ADR2_KEY'):
                if p.get(col) and ids.get(p[col]) != 'ADR':
                    err.append(f'{f["id"]} : adresse {col} {p[col]} absente du paquet')
            for face in (p.get('chb') or {}).get('faces', []):
                for pos in face.get('positions', []):
                    if pos.get('CD_KEY') not in conduites:
                        err.append(f'{f["id"]} face {face.get("FAC_CODE")} : conduite {pos.get("CD_KEY")} absente')
            if p['classe'] == 'CAB':
                err += verifier_cable_publie(f['id'], p, par_id)
        # fibres des positions et des mesures : câble du paquet, rang parmi ses fibres
        rangs = {cid: {x.get('FIB_NUM') for x in q.get('fibres') or [] if isinstance(x, dict)}
                 for cid, q in par_id.items() if q.get('classe') == 'CAB'}
        for nom, cab, num in fibres_citees:
            if cab not in rangs:
                err.append(f'{nom} : câble {cab} absent du paquet')
            elif num not in rangs[cab]:
                err.append(f'{nom} : fibre {num} absente du câble {cab}')
        for module in entete.get('modules', {}):
            if module not in ref:
                err.append(f'référentiels du module {module} absents')
    return err


def verifier_cable_publie(oid, p, par_id):
    """Contrôles croisés d'un câble publié : équipements d'extrémité EQU1_KEY et EQU2_KEY parmi ceux de leur nœud
    (NOE1_KEY, NOE2_KEY : inf.equipements) ; passage sur un linéaire du paquet : câble porté (PCB_RANG) parmi ceux de
    sa portée, câble de conduite (CD_KEY, CDC_RANG) parmi ceux d'une conduite du linéaire. Un passage ou un lovage
    peut viser un linéaire ou un nœud d'une autre zone, absent du paquet."""
    err = []
    for i in ('1', '2'):
        equ, noe = p.get(f'EQU{i}_KEY'), par_id.get(p.get(f'NOE{i}_KEY')) or {}
        if equ and equ not in {e.get('EQU_CODE_EXT') for e in (noe.get('inf') or {}).get('equipements', [])}:
            err.append(f'{oid} : EQU{i}_KEY {equ} absent des équipements de NOE{i}_KEY {p.get(f"NOE{i}_KEY")}')
    for pas in p.get('passages') or []:
        lin = par_id.get(pas.get('LIN_KEY'))
        if not isinstance(pas, dict) or lin is None:
            continue
        inf = lin.get('inf') or {}
        if pas.get('PCB_RANG') is not None and pas['PCB_RANG'] not in {
                c.get('PCB_RANG') for c in (inf.get('portee') or {}).get('cables', [])}:
            err.append(f'{oid} passage {pas["LIN_KEY"]} : câble porté {pas["PCB_RANG"]} absent de la portée')
        if pas.get('CD_KEY') is not None:
            cd = next((c for c in inf.get('conduites', []) if c.get('CD_CODE_EXT') == pas['CD_KEY']), None)
            if cd is None:
                err.append(f'{oid} passage {pas["LIN_KEY"]} : conduite {pas["CD_KEY"]} absente du linéaire')
            elif pas.get('CDC_RANG') not in {c.get('CDC_RANG') for c in cd.get('cables', [])}:
                err.append(f'{oid} passage {pas["LIN_KEY"]} : câble {pas.get("CDC_RANG")} absent de la conduite '
                           f'{pas["CD_KEY"]}')
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
