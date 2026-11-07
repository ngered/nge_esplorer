"""Jeu d'essai DOE « 71 » sur données réelles : DOE NGE du SRO LOI_25 (NRO 71263 LOI, Louhans, Saône-et-Loire, 2022),
chargé dans un projet NgeEsPlorer (schema/) avec tous ses modules, puis publié en paquet de zone (tools/geojson).

Source : docs/essai/71_data/in/NRO71263LOI_25_D_DOE_P1_V1/, un dossier par type de document du DOE, nommé
REC-<type>-NRO71263LOI_25_D-V<n> ; les types sont ceux de l'index du DOE (REC-ETU-…/REC-ETU-….xlsx, lu au
chargement : CIM conventions d'immeuble, CPV permissions de voirie, DCI localisation d'infrastructure, DIT DICT, DLG
livrables SIG, DPO appuis aériens, FOT photos, KEQ documentation des équipements, PCB plan de câblage, PGC plan de
génie civil, PMQ fiches de chambre, RFR fiches de recette, RVR PV de réception de voirie, SBP plans de boîte, SOP
synoptique).

Reprise du réseau : export GraceTHD v2 de FibReady (DLG/SHAPE/Grace) et relevé FibReady (DLG/SHAPE/ETUDE/
Shapes_Origine/INFRA_POINTS), par les règles de charger_doe.py (nœuds, linéaires, conduites, portées, matériel,
câbles, passages, lovages, fibres, cassettes et positions, adresses, BAL, locaux) ; codes GraceTHD préfixés LOI-.
L'export n'a pas de routes optiques (t_ropt vide).

Règles propres à ce DOE :
- photos (FOT, sans légende : noms d'appareil photo) : appuis rangés par dossier au nom du support (APPUI/POTEAUX
  ORANGE/<n° d'appui>, POTEAUX CD71/<A717…>, étiquette GraceTHD <nom>/71263 ; ENEDIS/BT <n>, numéro du relevé
  FibReady, zéros et suffixe -NC ignorés, poteau BT d'abord quand un poteau créé porte le même numéro ; POTELET/FAC<n>)
  en visuel libre « Appui (DOE) » ; boîtiers (BOITIER/BPE|PBO/PT <n>) dans la galerie de leur équipement, visuel libre
  « Boîtier optique » ; SRO en visuel libre de l'armoire ; date de prise lue dans le nom du fichier (iOS, Android,
  horodatage en ms), sinon date du fichier ;
- fiches de chambre (PMQ) : relevé Orange (annexe C16) : photos intégrées rangées d'après leur case dans la fiche
  (vue d'ensemble → environnement, vue de dessus, masques A à D ; vues complémentaires en visuel libre), relevé
  d'occupation des alvéoles au journal de la chambre (les masques ne disent pas vers quel cheminement part chaque
  alvéole : pas de position dans les faces) ; fiche CD71 : photos en visuel libre ; fiche jointe à la chambre ;
- mesures réflectométriques (RFR/MESURE/PEC <n>/PT <n>/DOSSIER.txt, FiberCable) : une par fibre, longueur d'onde et
  sens, rattachée au boîtier d'extrémité et à la fibre que l'appareil nomme (câble du départ, « TR 700002 » =
  …/TR 70 0002, et rang de la fibre) ; traces .sor jointes à leur mesure, synthèses au boîtier ;
- documents : plans de boîte (SBP) à leur boîtier ou au SRO, plan de câblage et synoptique au SRO, conventions
  d'immeuble (CIM) à leur adresse (dossier <numéro>-<voie>), le reste à la zone, commenté du libellé de son type
  dans l'index ; non repris : l'archive FN_…_RTE_P1_V3.7z (version antérieure du même DOE), les livrables SIG (DLG,
  source de la reprise).

Usage :
  python -I tools/essai/charger_71.py <dossier projet> <dossier QGIS bin> [<dossier source>]
"""
import io, os, re, shutil, sys, zipfile
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

sys.stdout.reconfigure(encoding='utf-8')
ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(ICI), 'schema'))
sys.path.insert(0, ICI)
import projet  # noqa: E402
import charger_essai  # noqa: E402
import charger_doe as doe  # noqa: E402
from charger_doe import entier, reel, lire_xlsx, lire_mesure, SENS  # noqa: E402

SOURCE = os.path.join(projet.RACINE, 'docs', 'essai', '71_data', 'in', 'NRO71263LOI_25_D_DOE_P1_V1')
P = 'LOI'                                       # préfixe des codes repris de la source
PROJET = ('NGE71', 'DOE NGE NRO71263 LOI_25 (Louhans, Saône-et-Loire)')
ZONE = ('NRO71263LOI_25', 'SRO LOI_25 Louhans (DOE NRO71263LOI_25_D)')
INSEE = '71263'
ETIQUETTE = '71263/UHH/'                        # préfixe des étiquettes GraceTHD des boîtiers et des câbles
IGNORES = ('thumbs.db', 'desktop.ini')
# cases photo de la fiche de chambre Orange (annexe C16, feuille « Fiche descriptive ») : ligne et colonne (base 1 et
# 0) du coin de l'image → vue de la chambre ; libellés de la fiche : « PHOTO vue d'ensemble » A6, « PHOTO masque D »
# AC21, « PHOTO chambre vue de dessus » M33, « PHOTO masque C » B51 ; les cases A (haut gauche) et B (bas droite) n'ont
# pas de libellé (vérifié sur les photos : B peint sur la paroi) ; au-delà de la ligne 70, vues complémentaires.
VISUEL_C16 = 'Vue complémentaire (relevé de chambre)'
doe.MIME.update({'.xlsm': 'application/vnd.ms-excel.sheet.macroEnabled.12', '.zip': 'application/zip',
                 '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                 '.log': 'text/plain', '.jpeg': 'image/jpeg'})


def case_c16(ligne, colonne):
    if ligne < 15:
        return 'ENV'
    if ligne < 30:
        return 'A' if colonne < 15 else 'D'
    if ligne < 45:
        return 'DESSUS'
    if ligne < 70:
        return 'C' if colonne < 15 else 'B'
    return None


def dossier_rec(source, code):
    """Dossier REC-<code>-… du DOE, ou None."""
    return next((os.path.join(source, d) for d in sorted(os.listdir(source)) if d.startswith(f'REC-{code}-')), None)


def index_etu(source):
    """Index des documents du DOE (REC-ETU) : {type : libellé}."""
    d = dossier_rec(source, 'ETU')
    fichier = next((os.path.join(d, f) for f in os.listdir(d) if f.lower().endswith('.xlsx')), None) if d else None
    if not fichier:
        return {}
    lignes = next(iter(lire_xlsx(open(fichier, 'rb').read()).values()))
    return {r[1].strip(): r[0].strip().capitalize() for r in lignes[2:] if r and len(r) > 1 and r[0] and r[1]}


def fichiers(dossier):
    """Fichiers d'un dossier et de ses sous-dossiers, triés, sans vignettes Windows ni fichiers verrous Office."""
    for racine, _, noms in sorted(os.walk(dossier)):
        for n in sorted(noms):
            if n.lower() not in IGNORES and not n.startswith('~$'):
                yield os.path.join(racine, n)


def date_photo(chemin):
    """Date de prise d'après le nom (« 20211209_151922000_iOS », « IMG_20220111_141604 », « 1648462060764 » en ms
    depuis 1970, « IMG-20220110-WA0045 »), sinon date du fichier ; heure locale de Paris → UTC."""
    nom = os.path.basename(chemin)
    m = re.search(r'(20\d{6})_(\d{6})', nom)
    if m:
        return projet.utc(datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S').isoformat(' '))
    m = re.match(r'(1[5-7]\d{11})\b', nom)
    if m:
        return projet.utc(int(m.group(1)) / 1000)
    m = re.search(r'IMG-(20\d{6})-WA', nom)
    if m:
        return projet.utc(datetime.strptime(m.group(1), '%Y%m%d').isoformat(' '))
    return projet.utc(datetime.fromtimestamp(os.path.getmtime(chemin)).isoformat(' '))


def date_excel(v):
    """Date d'une cellule Excel (nombre de jours depuis le 30/12/1899) → ISO 8601 UTC, heure de Paris à midi."""
    n = reel(v)
    return projet.utc((datetime(1899, 12, 30) + timedelta(days=int(n), hours=12)).isoformat(' ')) if n else None


# Classeurs : cellules par référence et images ancrées --------------------------------------------------------------

NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
      'xdr': 'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}


def feuilles(z):
    """{nom de feuille : chemin de sa partie XML}."""
    liens = {r.get('Id'): r.get('Target') for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
    out = {}
    for s in ET.fromstring(z.read('xl/workbook.xml')).find('m:sheets', NS):
        cible = liens[s.get('{%s}id' % NS['r'])].lstrip('/')
        out[s.get('name')] = cible if cible.startswith('xl/') else 'xl/' + cible
    return out


def cellules(z, partie):
    """{référence (« T2 ») : valeur} d'une feuille."""
    partages = []
    if 'xl/sharedStrings.xml' in z.namelist():
        for si in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si', NS):
            partages.append(''.join(t.text or '' for t in si.iter('{%s}t' % NS['m'])))
    out = {}
    for c in ET.fromstring(z.read(partie)).iter('{%s}c' % NS['m']):
        v, t = c.find('m:v', NS), c.get('t')
        if t == 's' and v is not None:
            x = partages[int(v.text)]
        elif t == 'inlineStr':
            x = ''.join(e.text or '' for e in c.iter('{%s}t' % NS['m']))
        else:
            x = v.text if v is not None else None
        if x not in (None, ''):
            out[c.get('r')] = x.strip() if isinstance(x, str) else x
    return out


def images(z, partie):
    """Images d'une feuille : [(ligne, colonne du coin haut gauche (base 1, base 0), octets)]."""
    rels = partie.replace('worksheets/', 'worksheets/_rels/') + '.rels'
    if rels not in z.namelist():
        return []
    out = []
    for dessin in re.findall(r'Target="\.\./drawings/(drawing\d+\.xml)"', z.read(rels).decode()):
        drels = f'xl/drawings/_rels/{dessin}.rels'
        medias = dict(re.findall(r'Id="([^"]+)"[^>]*Target="\.\./media/([^"]+)"', z.read(drels).decode())) \
            if drels in z.namelist() else {}
        for ancre in ET.fromstring(z.read(f'xl/drawings/{dessin}')):
            de, blip = ancre.find('xdr:from', NS), ancre.find('.//a:blip', NS)
            media = medias.get(blip.get('{%s}embed' % NS['r'])) if blip is not None else None
            if de is not None and media:
                out.append((int(de.find('xdr:row', NS).text) + 1, int(de.find('xdr:col', NS).text),
                            z.read('xl/media/' + media)))
    return out


# Chargement -------------------------------------------------------------------------------------------------------

class Doe71(doe.Doe):
    INTERVENTION = 'Chargement du DOE NGE NRO71263LOI_25_D (Louhans)'

    def __init__(self, dossier, qgis, source):
        super().__init__(dossier, qgis, None, None)
        self.code_projet = PROJET[0]
        self.source = source
        self.index = index_etu(source)

    def joindre(self, chemin, ent, obj, dossier, vue=None, visuel=None, comment=None, date=None, nom=None):
        """Fichier de la source joint tel quel à un objet."""
        with open(chemin, 'rb') as f:
            donnees = f.read()
        rel = os.path.join(dossier, nom or os.path.basename(chemin))
        cle = os.path.relpath(chemin, self.source).replace('\\', '/')
        if vue is None and visuel is None and (doe.MIME.get(os.path.splitext(rel)[1].lower()) or '').startswith('image/'):
            visuel = 'Document du DOE'              # image jointe parmi des documents : visuel libre
        return self.fichier(ent, obj, donnees, rel, cle, vue, visuel, date or date_photo(chemin), comment)

    def equipement_lib(self, nom):
        """Équipement optique d'après son nom court (« PT 700004 »)."""
        return self.eqo.get(ETIQUETTE + re.sub(r'\s+', ' ', nom.strip()))

    def noeud_equipement(self, e):
        return self.un('SELECT NOE_KEY FROM infra.INF_EQUIPEMENT WHERE EQU_ID = ?', e)

    # -- photos du DOE (FOT) ---------------------------------------------------------------------

    def appuis(self):
        """Nœuds des appuis par nom de dossier photo : étiquette GraceTHD, numéro du relevé FibReady."""
        par_etiquette = {e: self.noe[nd] for e, nd in self.con.execute('SELECT pt_etiquet, pt_nd_code FROM grc.t_ptech')
                         if e and nd in self.noe}
        par_numero = {}
        for num, typ, nd in self.con.execute(
                'SELECT i.inf_num, i.inf_type, p.pt_nd_code FROM grc.fbr_infra_points i '
                'JOIN grc.t_ptech p ON p.pt_codeext = i.noe_codext WHERE i.inf_num IS NOT NULL'):
            cle = numero_appui(num)
            if cle and nd in self.noe and (cle not in par_numero or typ == 'POT-BT'):
                par_numero[cle] = self.noe[nd]
        return par_etiquette, par_numero

    def photos(self, zone):
        fot = dossier_rec(self.source, 'FOT')
        if not fot:
            return
        par_etiquette, par_numero = self.appuis()
        sro = self.un("SELECT NOE_ID FROM PRJ_NOE n JOIN DEF_TYPE t ON t.TYPE_ID = n.TYPE_KEY WHERE t.TYPE_CODE = 'SIT-SRO'")
        for chemin in fichiers(fot):
            if os.path.splitext(chemin)[1].lower() not in ('.jpg', '.jpeg', '.png'):
                continue
            parties = os.path.relpath(chemin, fot).replace('\\', '/').split('/')
            if parties[0] == 'APPUI' and len(parties) == 4:
                famille, support = parties[1], parties[2]
                noe = par_etiquette.get(f'{support}/{INSEE}') or par_numero.get(numero_appui(support))
                if noe is None:
                    self.stats['photos d\'appui sans support'] += 1
                    continue
                visuel = 'Façade (DOE)' if famille == 'POTELET' else 'Appui (DOE)'
                if self.joindre(chemin, 'PRJ_NOE', noe, os.path.join('photos', P, support), visuel=visuel,
                                comment=f'Photo du DOE (appuis, {famille.lower()} {support})'):
                    self.stats['photos d\'appui'] += 1
            elif parties[0] == 'BOITIER' and len(parties) == 4:
                e = self.equipement_lib(parties[2])
                if e is None:
                    self.stats['photos de boîtier sans boîtier'] += 1
                    continue
                if self.joindre(chemin, 'INF_EQUIPEMENT', e, os.path.join('photos', P, parties[2]),
                                visuel=doe.VISUEL_BOITIER, comment=f'Photo du DOE ({parties[1]} {parties[2]})'):
                    self.stats['photos de boîtier'] += 1
            elif parties[0] == 'SRO':
                if self.joindre(chemin, 'PRJ_NOE', sro, os.path.join('photos', P, ZONE[0]), visuel='Armoire (DOE)'):
                    self.stats['photos du SRO'] += 1
            else:
                self.joindre(chemin, 'PRJ_ZONE', zone, os.path.join('photos', P, 'zone', *parties[:-1]),
                             visuel='Génie civil (DOE)' if parties[0] == 'GC' else 'Photo du DOE')
                self.stats['photos de la zone'] += 1

    # -- fiches de chambre (PMQ) -------------------------------------------------------------------

    def chambre(self, nom):
        """Chambre d'après le nom de sa fiche (« 71263-305 », « C717002-71263 »)."""
        m = re.match(r'(?:\d{5}-)?([A-Z]*\d+|FT\d+)(?:-\d{5})?$', nom)
        if not m:
            return None
        n = m.group(1)
        etiquettes = [f'{n}/{INSEE}'] + ([f'{int(n):05d}/{INSEE}'] if n.isdigit() else [])
        for e in etiquettes:
            noe = self.un('SELECT pt_nd_code FROM grc.t_ptech WHERE pt_etiquet = ?', e)
            if noe in self.noe:
                return self.noe[noe]
        return None

    def fiches_chambre(self):
        pmq = dossier_rec(self.source, 'PMQ')
        if not pmq:
            return
        for chemin in fichiers(pmq):
            if not chemin.lower().endswith('.xlsx'):
                continue
            nom = os.path.splitext(os.path.basename(chemin))[0]
            noe = self.chambre(nom)
            if noe is None:
                self.stats['fiches de chambre sans chambre'] += 1
                self.joindre(chemin, 'PRJ_ZONE', self.zone, os.path.join('documents', P, 'PMQ'),
                             comment='Fiche de chambre (chambre non retrouvée)')
                continue
            z = zipfile.ZipFile(chemin)
            parties = feuilles(z)
            if 'Fiche descriptive' in parties:
                self.fiche_orange(chemin, z, parties, noe, nom)
            else:
                self.fiche_autre(chemin, z, parties, noe, nom)
            self.stats['fiches de chambre'] += 1

    def fiche_orange(self, chemin, z, parties, noe, nom):
        """Relevé de chambre Orange (annexe C16)."""
        c = cellules(z, parties['Fiche descriptive'])
        date = date_excel(c.get('AI2')) or date_photo(chemin)
        self.joindre(chemin, 'PRJ_NOE', noe, os.path.join('documents', P, 'chambres'), date=date,
                     comment='Relevé de chambre (annexe C16 Orange)')
        dossier = os.path.join('photos', P, nom)
        for i, (ligne, colonne, octets) in enumerate(sorted(images(z, parties['Fiche descriptive'])), 1):
            if not octets.startswith(b'\xff\xd8') or len(octets) < 3000:
                continue
            code = case_c16(ligne, colonne)
            vue = self.vue(noe, code) if code else None
            if self.fichier('PRJ_NOE', noe, octets, os.path.join(dossier, f'{nom}_{i:02d}.jpg'), f'pmq:{nom}:{i}', vue,
                            None if vue else VISUEL_C16, date,
                            f'Relevé de chambre Orange {nom} (extraite de {os.path.basename(chemin)})'):
                self.stats['photos des fiches de chambre : ' + ('vue attendue' if vue else 'visuel libre')] += 1
        # relevé d'occupation : une ligne par alvéole, masque porté par la première ligne de son groupe
        masques = defaultdict(list)
        if 'Relevé occupation' in parties:
            r = cellules(z, parties['Relevé occupation'])
            masque = None
            for ligne in range(3, 200):
                masque = r.get(f'A{ligne}') or masque
                if r.get(f'C{ligne}') is None and r.get(f'D{ligne}') is None:
                    continue
                masques[masque].append((reel(r.get(f'C{ligne}')), reel(r.get(f'D{ligne}')), r.get(f'E{ligne}')))
        details = []
        for m in sorted(x for x in masques if x):
            alv = masques[m]
            occ = [a for a in alv if a[1]]
            diam = Counter(f'Ø{a[0]:g}' for a in alv if a[0])
            texte = f'masque {m} : {len(alv)} alvéole(s) ' + ', '.join(f'{v} {k}' if v > 1 else k for k, v in diam.items())
            if occ:
                texte += ', câbles ' + ', '.join(f'{a[2] or "?"} {a[1]:g} mm' for a in occ)
            details.append(texte)
        jour = (date or '')[:10]
        texte = (f'Relevé de chambre Orange du {jour[8:10]}/{jour[5:7]}/{jour[:4]}' if jour else 'Relevé de chambre Orange') \
            + (f', {c["AD2"]}' if c.get('AD2') else '') + (f' ({c["T3"]})' if c.get('T3') else '') \
            + (' ; ' + ' ; '.join(details) if details else ' ; pas de relevé d\'alvéoles')
        self.commentaire('PRJ_NOE', noe, f'pmq:{nom}', texte, 'BE', date=date)

    def fiche_autre(self, chemin, z, parties, noe, nom):
        """Fiche de chambre d'un autre modèle (CD71) : jointe, photos en visuel libre."""
        date = date_photo(chemin)
        self.joindre(chemin, 'PRJ_NOE', noe, os.path.join('documents', P, 'chambres'), date=date,
                     comment='Fiche de chambre (CD71)')
        n = 0
        for partie in parties.values():
            for i, (ligne, colonne, octets) in enumerate(sorted(images(z, partie)), 1):
                if octets.startswith(b'\xff\xd8') and len(octets) >= 3000:
                    if self.fichier('PRJ_NOE', noe, octets, os.path.join('photos', P, nom, f'{nom}_{i:02d}.jpg'),
                                    f'pmq:{nom}:{partie}:{i}', None, 'Fiche de chambre CD71', date,
                                    f'Fiche de chambre {nom} (extraite de {os.path.basename(chemin)})'):
                        n += 1
        self.stats['photos des fiches de chambre : visuel libre'] += n
        self.commentaire('PRJ_NOE', noe, f'pmq:{nom}', f'Fiche de chambre CD71 {nom} jointe ({n} photo(s))', 'BE',
                         date=date)

    # -- mesures (RFR) --------------------------------------------------------------------------------

    def mesures(self):
        rfr = dossier_rec(self.source, 'RFR')
        mesure = os.path.join(rfr, 'MESURE') if rfr else None
        if not mesure or not os.path.isdir(mesure):
            return
        cables = {re.sub(r'\s+', '', lib.rsplit('/', 1)[-1]): cab for cab, lib in
                  self.con.execute('SELECT CAB_ID, CAB_LIB FROM optique.OPT_CABLE WHERE CAB_LIB IS NOT NULL')}
        n, sans_fibre, sans_boitier, vus = 0, 0, 0, set()
        for synthese in fichiers(mesure):
            if os.path.basename(synthese).upper() != 'DOSSIER.TXT':
                continue
            dossier = os.path.dirname(synthese)
            tete, mesures = lire_mesure(open(synthese, 'rb').read().decode('utf-16'))
            extremite = (tete.get('Extrémité') or [os.path.basename(dossier)])[0]
            e = self.equipement_lib(extremite) or self.equipement_lib(os.path.basename(dossier))
            sans_boitier += e is None
            rel = os.path.join('documents', P, 'mesures', os.path.basename(dossier))
            for doc in fichiers(dossier):
                if os.path.dirname(doc) == dossier and not doc.lower().endswith('.sor'):
                    self.joindre(doc, 'INF_EQUIPEMENT' if e else 'PRJ_ZONE', e or self.zone, rel,
                                 comment='Synthèse des mesures réflectométriques')
            sens = SENS.get((tete.get('Sens') or [''])[0])
            for (cable, fibre, lam), m in sorted(mesures.items()):
                code = f'{P}-M-{extremite}-{cable}-{fibre}-{lam}-{sens}'.replace(' ', '')
                if code in vus:
                    self.stats['mesures en double'] += 1
                    continue
                vus.add(code)
                cab = cables.get(re.sub(r'\s+', '', cable))
                fib = self.un('SELECT FIB_ID FROM optique.OPT_FIBRE WHERE CAB_KEY = ? AND FIB_NUM = ?', cab, fibre) \
                    if cab else None
                sans_fibre += fib is None
                mes = self.inserer('optique.OPT_MESURE', {
                    'MES_CODE_EXT': code, 'MMET_KEY': 1, 'FIB_KEY': fib, 'EQU_KEY': e, 'MES_CABLE': cable,
                    'MES_FIBRE': fibre, 'MES_ORIGINE': (tete.get('Origine') or [None])[0], 'MES_EXTREMITE': extremite,
                    'MES_LAMBDA': lam, 'MES_SENS': sens, 'MES_LNG': m['lng'], 'MES_PERTE': m['perte'],
                    'MES_EVT_MAX': m['evt_max'], 'MES_PENTE_MAX': m['pente_max'], 'MES_ORL': m['orl'],
                    'MES_CONFORME': m['conforme'], 'MES_APPAREIL': (tete.get('Appareil de mesure') or [None])[0] or None,
                    'MES_DATE': m['date'], 'SRC_MODIF': 'import'})
                n += 1
                sor = os.path.join(dossier, m['fichier']) if m['fichier'] else None
                if sor and os.path.isfile(sor):
                    self.joindre(sor, 'OPT_MESURE', mes, rel, comment='Trace réflectométrique')
        self.rapport.append(f'mesures : {n} réflectométries, {n - sans_fibre} rattachées à leur fibre, '
                            f'{self.un("SELECT COUNT(*) FROM optique.OPT_MESURE WHERE MES_CONFORME = 0")} hors seuils, '
                            f'{sans_boitier} synthèses sans boîtier d\'extrémité')

    # -- documents ------------------------------------------------------------------------------------

    def adresse_dossier(self, nom):
        """Adresse d'un dossier de convention (« 42-RUE-DE-L-ECOTET »)."""
        m = re.match(r'(\d+)-(.+)$', nom)
        if not m:
            return None
        voie = m.group(2).replace('-', ' ').upper()
        return self.un("SELECT ADR_ID FROM PRJ_ADRESSE WHERE ADR_NUMERO = ? AND replace(replace(upper(ADR_VOIE), "
                       "'''', ' '), '-', ' ') = ? ORDER BY ADR_ID LIMIT 1", int(m.group(1)), voie)

    def documents(self, zone):
        sro = self.un("SELECT NOE_ID FROM PRJ_NOE n JOIN DEF_TYPE t ON t.TYPE_ID = n.TYPE_KEY WHERE t.TYPE_CODE = 'SIT-SRO'")
        for d in sorted(os.listdir(self.source)):
            m = re.match(r'REC-([A-Z]{3})-', d)
            code = m.group(1) if m else None
            if code in (None, 'FOT', 'PMQ', 'DLG') or not os.path.isdir(os.path.join(self.source, d)):
                continue
            lib = f'{self.index.get(code, code)} ({code})'
            for chemin in fichiers(os.path.join(self.source, d)):
                parties = os.path.relpath(chemin, os.path.join(self.source, d)).replace('\\', '/').split('/')
                rel = os.path.join('documents', P, code, *parties[:-1])
                if code == 'RFR' and parties[0] == 'MESURE':
                    continue                        # mesures
                if code == 'SBP':
                    pt = re.search(r'(PT \d+)\.xlsx$', parties[-1])
                    e = self.equipement_lib(pt.group(1)) if pt else None
                    if e:
                        self.joindre(chemin, 'INF_EQUIPEMENT', e, rel, comment='Plan de boîte')
                    else:
                        self.joindre(chemin, 'PRJ_NOE', sro, rel, comment='Plan de boîte')
                    self.stats['plans de boîte'] += 1
                elif code in ('PCB', 'SOP'):
                    self.joindre(chemin, 'PRJ_NOE', sro, rel, comment=lib)
                elif code == 'CIM':
                    a = self.adresse_dossier(parties[0])
                    self.joindre(chemin, 'PRJ_ADRESSE' if a else 'PRJ_ZONE', a or zone, rel,
                                 comment=f'{lib} : {parties[0]}')
                    self.stats['conventions d\'immeuble' + ('' if a else ' sans adresse')] += 1
                else:
                    self.joindre(chemin, 'PRJ_ZONE', zone, rel, comment=lib)


def numero_appui(nom):
    """« BT 01 », « BT 4-NC » → « BT4 » ; « FAC1 » → « FAC1 » ; autre → None."""
    m = re.match(r'(BT|FAC)\s*0*(\d+)', (nom or '').strip().upper())
    return f'{m.group(1)}{m.group(2)}' if m else None


def base_grace(source, dossier, qgis):
    shape = os.path.join(dossier_rec(source, 'DLG'), 'SHAPE')
    grace = os.path.join(shape, 'Grace')
    origine = os.path.join(shape, 'ETUDE', 'Shapes_Origine')
    lus = [(n, open(os.path.join(grace, n), 'rb').read()) for n in sorted(os.listdir(grace))]
    lus += [(n, open(os.path.join(origine, n), 'rb').read()) for n in sorted(os.listdir(origine))
            if n.startswith('INFRA_POINTS.') and os.path.splitext(n)[1].lower() in ('.shp', '.shx', '.dbf', '.prj', '.cpg')]
    return doe.base_grace_fichiers(lus, dossier, qgis)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    dossier, qgis = sys.argv[1:3]
    source = sys.argv[3] if len(sys.argv) > 3 else SOURCE
    doe.P = P                                       # préfixe des codes des méthodes reprises de charger_doe
    if os.path.isdir(dossier):
        shutil.rmtree(dossier)
    for _ in projet.construire(dossier, charger_essai.ESSONNE, qgis, *PROJET):
        pass
    os.makedirs(os.path.join(dossier, 'sources'), exist_ok=True)
    grace = base_grace(source, os.path.join(dossier, 'sources'), qgis)
    ch = Doe71(dossier, qgis, source)
    ch.qgis = qgis
    ch.con.execute('ATTACH DATABASE ? AS grc', (grace,))
    ch.con.execute('BEGIN')
    try:
        zone = ch.zone = ch.inserer('PRJ_ZONE', {'ZONE_CODE_EXT': ZONE[0], 'ZONE_LIB': ZONE[1], 'SRC_MODIF': 'import'})
        ch.catalogues()
        ch.adresses()
        ch.noeuds(zone)
        ch.lineaires(zone)
        ch.materiel()
        ch.cables()
        ch.cassettes()
        ch.locaux()
        ch.photos(zone)
        ch.fiches_chambre()
        ch.documents(zone)
        ch.mesures()
        ch.finir(zone)
        ch.con.execute('COMMIT')
    except Exception:
        ch.con.execute('ROLLBACK')
        raise
    ch.con.execute('DETACH DATABASE grc')
    for ligne in ch.rapport:
        print(ligne)
    print('Effectifs :', dict(ch.stats))
    print('Index du DOE :', ch.index)
    controles(ch)


def controles(ch):
    con = ch.con
    q = lambda s: con.execute(s).fetchall()
    print('\nContrôles :')
    print('  orphelins :', [o for o in projet.orphelins(con) if o[1]] or 'aucun')
    print('  équipements sans support :', q('SELECT COUNT(*) FROM infra.INF_EQUIPEMENT WHERE NOE_KEY IS NULL')[0][0])
    print('  nœuds par type :', q('SELECT t.TYPE_CODE, COUNT(*) FROM PRJ_NOE n JOIN DEF_TYPE t ON t.TYPE_ID = n.TYPE_KEY '
                                  'GROUP BY 1'))
    print('  supports sans photo (type, nombre) :', q(
        'SELECT t.TYPE_CODE, COUNT(*) FROM PRJ_NOE n JOIN DEF_TYPE t ON t.TYPE_ID = n.TYPE_KEY WHERE NOT EXISTS (SELECT 1 '
        "FROM PRJ_FICHIER f WHERE f.OBJ_KEY = n.NOE_ID AND f.ENT_KEY = (SELECT ENT_ID FROM DEF_ENTITE WHERE ENT_TABLE = "
        "'PRJ_NOE') AND f.FIC_TYPE LIKE 'image/%') GROUP BY 1"))
    print('  photos par vue :', q(
        "SELECT COALESCE(v.VUE_CODE, 'libre : ' || f.VIS_LIB), COUNT(*) FROM PRJ_FICHIER f "
        "LEFT JOIN DEF_VUE v ON v.VUE_ID = f.VUE_KEY WHERE f.FIC_TYPE LIKE 'image/%' GROUP BY 1 ORDER BY 2 DESC"))
    print('  câbles sans passage :', q('SELECT COUNT(*) FROM optique.OPT_CABLE c WHERE NOT EXISTS (SELECT 1 FROM '
                                       'optique.OPT_PASSAGE p WHERE p.CAB_KEY = c.CAB_ID)')[0][0])
    print('  fibres par câble conformes à la capacité :', q(
        'SELECT SUM(n = CAB_CAPA), COUNT(*) FROM (SELECT c.CAB_CAPA, COUNT(f.FIB_ID) n FROM optique.OPT_CABLE c '
        'LEFT JOIN optique.OPT_FIBRE f ON f.CAB_KEY = c.CAB_ID GROUP BY c.CAB_ID)')[0])
    print('  occupation des conduites :', projet.resume_occupation(con))
    print('  poteaux par type et nature :', q(
        'SELECT t.TYPE_CODE, COUNT(*), COUNT(p.NAT_KEY) FROM poteau.POT_POTEAU p JOIN PRJ_NOE n ON n.NOE_ID = p.NOE_KEY '
        'JOIN DEF_TYPE t ON t.TYPE_ID = n.TYPE_KEY GROUP BY 1'))
    print('  chambres par référence :', q(
        'SELECT m.MAT_LIB, COUNT(*) FROM chambre.CHB_CHAMBRE c LEFT JOIN chambre.MAT_CHAMBRE m ON m.MAT_ID = c.MAT_KEY '
        'GROUP BY 1'))
    print('  fichiers par entité et type :', q(
        'SELECT e.ENT_TABLE, f.FIC_TYPE, COUNT(*), round(SUM(f.FIC_TAILLE) / 1e6, 1) FROM PRJ_FICHIER f '
        'JOIN DEF_ENTITE e ON e.ENT_ID = f.ENT_KEY GROUP BY 1, 2 ORDER BY 1, 2'))
    print('  photos principales en double (objet, vue) :', q(
        'SELECT COUNT(*) FROM (SELECT 1 FROM PRJ_FICHIER WHERE FIC_PRINCIPALE = 1 GROUP BY ENT_KEY, OBJ_KEY, '
        'VUE_KEY, VIS_CODE HAVING COUNT(*) > 1)')[0][0])
    print('  chemins partagés par des contenus différents :', q(
        'SELECT COUNT(*) FROM (SELECT FIC_CHEMIN FROM PRJ_FICHIER GROUP BY FIC_CHEMIN '
        'HAVING COUNT(DISTINCT FIC_SHA256) > 1)')[0][0])
    print('  journal (origine, type, nombre) :', q(
        'SELECT COM_ORIGINE, COM_TYPE, COUNT(*) FROM PRJ_COMMENTAIRE GROUP BY 1, 2'))
    print('  zone (emprise km²) :', q('SELECT ZONE_CODE_EXT, round(Area(GEOMETRY) / 1e6, 3) FROM PRJ_ZONE'))


if __name__ == '__main__':
    main()
