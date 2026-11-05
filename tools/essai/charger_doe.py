"""Jeu d'essai DOE sur données réelles : dossier des ouvrages exécutés d'une zone de sous-répartition optique, chargé
dans un projet NgeEsPlorer (schema/) avec tous ses modules, optique et immeuble compris.

Source : DOE Evicom du SRO-2-02HG (Hussigny-Godbrange, Meurthe-et-Moselle, réseau EVICOM 2000),
docs/essai/evicom_data/in/, lu dans les archives sans les extraire :
- PRE-DOE_SRO-2-02HG_V1.zip, référence du DOE : 02_GRACETHD (export GraceTHD v2.0.1 de FibReady du 16 septembre
  2026) ; 01_PLAN/Shapes_Origine (relevé d'infrastructure FibReady : type d'appui, matière, commentaires) ; photos
  (11_PHOTOS : rapports PDF des boîtes et du tirage, photos d'appuis ; 03_SRO), plans de boîte (04), route optique
  (05), synoptiques (06), génie civil (07), mesures (08 : réflectométrie FiberCable, photos de photométrie),
  conventions d'immeuble (09), infrastructures tierces (10), conventions diverses (12) ;
- Livrables calculs SRO-2-02HG.zip : études COMAC de l'APD (juillet 2025), une archive par rue (appuis : hauteur,
  classe, effort, année, orientation ; photos) et le suivi des études (conclusions).
- DOE_SRO-2-02HG.fbt, base FibReady du DOE (l'export GraceTHD en est tiré) : câbles de raccordement (absents de
  GraceTHD) et contrôle du support de chaque boîtier (INF_KEY, attaches du plan).
Non repris : les points d'infrastructure de la base FibReady (PDT :
passage d'un câble sur un support, les passages viennent de GraceTHD), les nœuds GraceTHD des sites utilisateurs
(l'adresse les porte), les copies des études COMAC
(10_INFRA-TIERS/ENEDIS, identiques aux livrables), le projet QGIS du DOE, le rapport de réserves
(reserves/rapport_distribution-SRO-08LG.xls : il porte sur le SRO-1-08LG).

Règles de reprise (codes GraceTHD préfixés EVI-, dates GraceTHD sans fuseau lues en heure de Paris) :
- nœuds : appuis (A) → poteaux, BT (énergie) ou télécom selon le relevé FibReady (POT-BT, sinon POT-EX ou POT-AC),
  nature d'après la matière relevée, sinon pt_nature ; chambres (C), référence MAT_CHAMBRE = pt_nature ; façades (F) ;
  sites techniques : NRO, SRO (armoire de rue) ; immeubles (sites BAT) à leur adresse ;
- cheminements orientés de NOE1 vers NOE2 : aérien (0, 1) et façade (2) → portée (angles calculés : azimut géodésique
  en grades, 0 = nord géographique) et un câble porté par câble passé dans sa conduite virtuelle (AER ou NC), nappe
  inconnue ; souterrain (7) → conduites (PVC, PEHD, NC) occupées par leurs câbles, une ligne par câble, rangée dans
  sa conduite (CDC_RANG, ordre des étiquettes), nature FO pour un câble à fibres ; diamètre nominal (CD_DIAM) = le plus
  grand de cd_dia_int et cd_dia_ext (diamètre extérieur du tube ; FibReady exporte les deux inversés) ; état et taux
  d'occupation recalculés (pas de taux : les câbles n'ont pas de diamètre) ;
- matériel : boîtiers (t_ebp, sur leur appui, chambre ou façade, ou dans le local technique de l'immeuble), baie et
  tiroirs du SRO → équipements, catalogue MAT_EQUIP complété d'après t_reference (une ligne par référence, de la
  capacité qu'elle nomme ; une par capacité posée pour un manchon, qui n'en nomme pas), et leur contenu optique
  (étiquette, fonction, capacité utile, emplacement) ; câbles, catalogue MAT_CABLE complété, avec leurs passages rangés
  depuis NOE1, lovages et fibres ; cassettes et positions ; routes optiques ;
- câbles de raccordement de la base FibReady (CABLES.CAB_TYPE RAC, du PBO à la boîte aux lettres de l'adresse) :
  câbles de fonction RA (Raccordement final) du support du PBO (NOE1_KEY, EQU1_KEY) à l'adresse desservie (ADR2_KEY,
  sans nœud aval), avec leur tracé FibReady (GEOMETRY, Lambert 93, dessiné de la BAL au PBO : retourné pour partir du
  PBO), à créer (non posés au DOE) ; adresse d'après la table de correspondance de FibReady, à défaut (BAL d'immeuble
  collectif, une seule adresse exportée) par la voie, le numéro et le complément ; étiquette RAC- et
  rang dans le PBO (RAC-2-02HG-2075-03), mode de pose (aérien, fourreau, immeuble) en commentaire ; sans fibres ni
  parcours (ni dans GraceTHD, ni décrits fibre à fibre par la base FibReady) ;
- adresses → PRJ_ADRESSE et IMB_ADRESSE (BAL) ; sites utilisateurs (t_suf) → locaux, desservis par le PBO de leur
  zone ; conventions d'immeuble jointes à leur adresse ;
- études COMAC : support rapproché à 10 m au plus (paires les plus proches d'abord) d'un poteau, ou d'une façade pour
  un support de classe FACADE ; un nœud reçoit toutes les études d'un même support (même nom au suffixe -IN près :
  rues étudiées deux fois, appuis d'angle) ; poteau : référence MAT_POTEAU (hauteur, classe, effort), effort en daN,
  année, orientation reprise de l'étude ; conclusion au journal (alerte si l'appui est insuffisant), photos de l'étude
  (état avant travaux) après celles du DOE, classées d'après evicom_comac_vues.csv (classement à l'œil : tête et
  ensemble en vues attendues, marquage en visuel libre), une copie par nom au suffixe -IN près, et photos de
  l'infrastructure tierce Evicom du même nom ;
- mesures réflectométriques : une par fibre, longueur d'onde et sens, rattachée à la route que l'appareil nomme
  (câble d'extrémité et rang de la fibre au départ du SRO), à sa première fibre et au boîtier d'extrémité ; trace .sor
  jointe à la mesure ;
- photos : images JPEG extraites des rapports PDF Kizeo Forms (11_PHOTOS : E.Tirage poteau, façade ou chambre,
  E.Chambre, E.Boite), chacune classée par le libellé qui la précède : vue attendue du support quand son type l'a
  (tête de poteau, ensemble, environnement, dessus, faces A à D des masques) ou, pour une boîte, vue de la galerie de
  son équipement (boîtier fermé à la pose, ouvert, cassettes, mesures photométriques), sinon visuel libre au titre du
  libellé (étiquettes, règle, accroche, protection…) ; date de réponse du formulaire comme
  date de prise, câble tiré et technicien en commentaire, remontée au journal ; SRO : visuel libre ; photos d'appuis et
  de photométrie ; documents (PDF, tableurs, synthèses de mesure) joints sans être publiés.

Usage :
  python -I tools/essai/charger_doe.py <dossier projet> <dossier QGIS bin> [<dossier source>]
"""
import csv, hashlib, io, math, os, re, shutil, sqlite3, sys, tempfile, uuid, zipfile, zlib
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')
ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(ICI), 'schema'))
sys.path.insert(0, ICI)
import projet  # noqa: E402
import charger_essai  # noqa: E402

SOURCE = os.path.join(projet.RACINE, 'docs', 'essai', 'evicom_data', 'in')
DOE = 'PRE-DOE_SRO-2-02HG_V1.zip'
CALCULS = 'Livrables calculs SRO-2-02HG.zip'
FIBREADY = 'DOE_SRO-2-02HG.fbt'
P = 'EVI'                                       # préfixe des codes repris de la source
PROJET = ('EVICOM', 'DOE Evicom SRO-2-02HG (Hussigny-Godbrange)')
ZONE = ('SRO-2-02HG', 'SRO-2-02HG Hussigny-Godbrange (DOE Evicom)')
RAPPROCHEMENT_COMAC = 10                        # m
TAILLE_IMAGE_MIN = 300                          # px : en dessous, image d'un rapport PDF ignorée (logo)
MIME = {'.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.heic': 'image/heic',
        '.pdf': 'application/pdf', '.xls': 'application/vnd.ms-excel',
        '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.txt': 'text/plain',
        '.xml': 'application/xml', '.sor': 'application/octet-stream', '.dwg': 'application/acad'}
NATURE = {'BETON': 'Béton', 'BOIS': 'Bois', 'METAL': 'Métal', 'PBET': 'Béton', 'PBOI': 'Bois', 'PMET': 'Métal'}
SITES = {'NRO': 'SIT-NRO', 'SRO': 'SIT-SRO', 'CLIENT': 'IMM'}
OTYP = {'BPE': 'BPE', 'PBO': 'PBO', 'PTO': 'PTO', 'DTI': 'DTI'}
SENS = {'O-->E': 'OE', 'O<--E': 'EO', 'O<->E': 'BI'}
# Rapports Kizeo Forms (11_PHOTOS : E.Tirage poteau, façade ou chambre, E.Chambre, E.Boite) : libellé d'une photo →
# vue attendue du support (DEF_VUE), quand son type l'a ; sinon visuel libre au titre du libellé. « Masque chambre
# ABCD » (E.Chambre) : quatre photos, faces A à D dans l'ordre du formulaire ; un autre nombre, visuel libre.
VUES_KIZEO = {'Tête de poteau/Traverse': 'TETE', 'Ensemble': 'ENSEMBLE', 'Environnement': 'ENV',
              'Chambre ouverte': 'DESSUS'}
# E.Boite : photos du boîtier dans la galerie de son équipement (noyau 0.3.0, vues VUE_ENTITE INF_EQUIPEMENT du module
# optique) ; titre du libellé (titre_kizeo) → vue de l'équipement, sinon visuel libre de l'équipement (étiquettes,
# règle). « Pose boîte » : le boîtier posé sur son support, fermé.
VUES_BOITE = {'Pose boîte': 'FERME', 'Boîte ouverte': 'OUVERT', 'Cassettes': 'CASSETTES',
              'Mesure photométrique': 'MESURES', 'Mesures photométriques': 'MESURES'}
VISUEL_BOITIER = 'Boîtier optique'  # images d'un rapport de boîte hors Kizeo, comme la reprise (projet.py)
MASQUES_KIZEO = 'Masque chambre ABCD'
# Photos des études COMAC (Rue …_Photos/<appui>_<n>.jpg) : sans légende, leur rang ne dit pas la vue (tête en _2,
# marquage puis ensemble pour un appui BT, l'inverse pour un appui télécom, avec des exceptions) ; classement fait à
# l'œil, pour ce jeu d'essai, dans COMAC_VUES (rue ; fichier ; vue : TETE, ENSEMBLE, MARQUAGE ou AUTRE ; remarque).
COMAC_VUES = os.path.join(ICI, 'evicom_comac_vues.csv')
VISUELS_COMAC = {'MARQUAGE': 'Marquage du poteau (APD)'}


def iso(t):
    return charger_essai.iso(t)


def entier(v):
    try:
        return int(float(str(v).replace(',', '.')))
    except (TypeError, ValueError):
        return None


def reel(v):
    try:
        return float(str(v).replace(',', '.').strip())
    except (TypeError, ValueError):
        return None


def code_uuid(*parties):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'urn:nge-esplorer:' + ':'.join(map(str, parties))))


def date_zip(info):
    return projet.utc(datetime(*info.date_time).isoformat())


def date_fr(texte):
    """« 06/04/2026 12:39:45 » ou « 29/07/2025 », heure de Paris → ISO 8601 UTC."""
    m = re.match(r'(\d{2})/(\d{2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?', (texte or '').strip())
    if not m:
        return None
    j, mo, a, h, mi, s = m.groups()
    return projet.utc(datetime(int(a), int(mo), int(j), int(h or 0), int(mi or 0), int(s or 0)).isoformat())


# Lecture des sources ---------------------------------------------------------------------------

def lire_xlsx(donnees):
    """Classeur xlsx (zip + XML) → {feuille : lignes de valeurs}."""
    ns = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
          'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
    m_ = '{%s}' % ns['m']
    z = zipfile.ZipFile(io.BytesIO(donnees))
    partages = []
    if 'xl/sharedStrings.xml' in z.namelist():
        for si in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si', ns):
            partages.append(''.join(t.text or '' for t in si.iter(m_ + 't')))
    liens = {r.get('Id'): r.get('Target') for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
    feuilles = {}
    for s in ET.fromstring(z.read('xl/workbook.xml')).find('m:sheets', ns):
        cible = liens[s.get('{%s}id' % ns['r'])].lstrip('/')
        cible = cible if cible.startswith('xl/') else 'xl/' + cible
        lignes = []
        for row in ET.fromstring(z.read(cible)).iter(m_ + 'row'):
            vals = {}
            for c in row.findall('m:c', ns):
                v, t = c.find('m:v', ns), c.get('t')
                if t == 's' and v is not None:
                    x = partages[int(v.text)]
                elif t == 'inlineStr':
                    x = ''.join(e.text or '' for e in c.iter(m_ + 't'))
                else:
                    x = v.text if v is not None else None
                if x not in (None, ''):
                    lettres = re.match(r'[A-Z]+', c.get('r')).group()
                    vals[sum((ord(ch) - 64) * 26 ** i for i, ch in enumerate(reversed(lettres))) - 1] = x
            if vals:
                lignes.append([vals.get(i) for i in range(max(vals) + 1)])
        feuilles[s.get('name')] = lignes
    return feuilles


def images_pdf(donnees):
    """Images JPEG (filtre DCTDecode) d'un PDF, telles qu'enregistrées ; les petites (logo) sont écartées."""
    images = []
    for m in re.finditer(rb'stream\r?\n', donnees):
        avant = donnees[max(0, m.start() - 800):m.start()]
        dico = avant[avant.rfind(b'obj'):]
        if b'/DCTDecode' not in dico:
            continue
        larg = re.search(rb'/Width\s+(\d+)', dico)
        haut = re.search(rb'/Height\s+(\d+)', dico)
        if larg and haut and max(int(larg.group(1)), int(haut.group(1))) < TAILLE_IMAGE_MIN:
            continue
        fin = donnees.find(b'endstream', m.end())
        jpeg = donnees[m.end():fin].rstrip(b'\r\n')
        if jpeg.startswith(b'\xff\xd8'):
            images.append(jpeg)
    return images


UNITE = (1, 0, 0, 1, 0, 0)
# jetons d'un flux de contenu : tableau (TJ), chaîne hexadécimale, nom, chaîne littérale, nombre, opérateur
JETON_PDF = re.compile(rb'\[[^\]]*\]|<[0-9A-Fa-f\s]*>|/[^\s/\[\]<>()]+|\((?:\\.|[^\\)])*\)|-?(?:\d+\.?\d*|\.\d+)'
                       rb'|[A-Za-z\'"*]+')


def produit(m, n):
    """Produit de deux matrices PDF [a b c d e f] (m appliquée d'abord, puis n)."""
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + b * c2, a * b2 + b * d2, c * a2 + d * c2, c * b2 + d * d2, e * a2 + f * c2 + e2,
            e * b2 + f * d2 + f2)


def lire_pdf(donnees):
    """Texte et images d'un PDF simple (rapports Kizeo Forms mis en page par wkhtmltopdf : polices Identity-H avec leur
    ToUnicode, texte en <…> Tj, images appelées par Do), page après page et de haut en bas (position calculée par les
    matrices cm, Tm et Td : le flux ne suit pas toujours l'ordre de lecture) : [('T', taille de police, texte d'une
    ligne) | ('I', JPEG)] ; petites images (logo) écartées. Lecture minimale, sans dépendance, vérifiée sur les
    142 rapports du DOE Evicom (mêmes libellés et mêmes images que PyMuPDF) : un PDF d'une autre facture rend une liste
    vide ou incomplète."""
    objets = {int(m.group(1)): m.start() for m in re.finditer(rb'(\d+) 0 obj\b', donnees)}

    def corps(n):
        debut = objets[n]
        return donnees[debut:donnees.find(b'endobj', debut)]

    def flux(n):
        o = corps(n)
        d = o[:o.find(b'stream')]
        a = o.find(b'stream') + 6
        a += 2 if o[a:a + 2] == b'\r\n' else 1          # fin de ligne qui suit le mot-clé stream
        lng = re.search(rb'/Length\s+(\d+)(\s+0\s+R)?', d)
        if lng and lng.group(2):
            lng = int(re.search(rb'obj\s+(\d+)', corps(int(lng.group(1)))).group(1))
        else:
            lng = int(lng.group(1)) if lng else None
        brut = o[a:a + lng] if lng else o[a:o.rfind(b'endstream')].rstrip(b'\r\n')
        return zlib.decompressobj().decompress(brut) if b'/FlateDecode' in d else brut

    def dico(n):
        o = corps(n)
        return o[:o.find(b'stream')] if b'stream' in o else o

    def noms(d, cle):
        m = re.search(rb'/' + cle + rb'\s*<<(.*?)>>', d, re.S)
        return {k.decode(): int(v) for k, v in re.findall(rb'/(\w+)\s+(\d+) 0 R', m.group(1))} if m else {}

    def cmap(n):
        texte, table = flux(n).decode('latin-1'), {}
        for bloc in re.findall(r'beginbfchar(.*?)endbfchar', texte, re.S):
            for src, dst in re.findall(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>', bloc):
                table[int(src, 16)] = bytes.fromhex(dst).decode('utf-16-be', 'replace')
        for bloc in re.findall(r'beginbfrange(.*?)endbfrange', texte, re.S):
            for a, b, dst in re.findall(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]+>|\[[^\]]*\])', bloc):
                cibles = re.findall(r'<([0-9A-Fa-f]+)>', dst)
                for i, code in enumerate(range(int(a, 16), int(b, 16) + 1)):
                    if dst.startswith('['):
                        if i < len(cibles):
                            table[code] = bytes.fromhex(cibles[i]).decode('utf-16-be', 'replace')
                    else:
                        base = int(cibles[0], 16) + i
                        table[code] = chr(base) if base < 0x110000 else ''
        return table

    def pages(n):
        d = dico(n)
        if b'/Kids' not in d:
            return [n]
        kids = re.search(rb'/Kids\s*\[(.*?)\]', d, re.S).group(1)
        return [p for k in re.findall(rb'(\d+) 0 R', kids) for p in pages(int(k))]

    racine = next((n for n in objets if re.search(rb'/Type\s*/Pages\b', dico(n))
                   and not re.search(rb'/Parent\b', dico(n))), None)
    if racine is None:
        return []
    elements, cmaps = [], {}
    for page in pages(racine):
        d = dico(page)
        res = re.search(rb'/Resources\s+(\d+) 0 R', d)
        ressources = dico(int(res.group(1))) if res else d
        polices = noms(ressources, rb'Font')
        images = noms(ressources, rb'XObject')
        contenus = re.search(rb'/Contents\s+(?:(\d+) 0 R|\[(.*?)\])', d, re.S)
        if not contenus:
            continue
        refs = [int(contenus.group(1))] if contenus.group(1) else [int(x) for x in re.findall(rb'(\d+) 0 R', contenus.group(2))]
        contenu = b'\n'.join(flux(r) for r in refs)
        # état graphique : matrice courante (cm, pile q / Q) et matrice du texte (Tm, Td), pour placer chaque bloc de
        # texte et chaque image sur la page (le flux ne suit pas toujours l'ordre de lecture)
        ctm, pile, tlm, operandes = UNITE, [], UNITE, []
        police, taille, bloc, sur_page = None, 0, None, []
        for m in JETON_PDF.finditer(contenu):
            t = m.group()
            if t[:1] in b'-.0123456789':
                operandes.append(float(t))
                continue
            if t[:1] in b'/<[(':
                operandes.append(t)
                continue
            nombres = [x for x in operandes if isinstance(x, float)]
            if t == b'q':
                pile.append(ctm)
            elif t == b'Q':
                ctm = pile.pop() if pile else UNITE
            elif t == b'cm' and len(nombres) >= 6:
                ctm = produit(nombres[-6:], ctm)
            elif t == b'BT':
                tlm, bloc = UNITE, None
            elif t == b'Tm' and len(nombres) >= 6:
                tlm = tuple(nombres[-6:])
            elif t == b'Td' and len(nombres) >= 2:
                tlm = produit((1, 0, 0, 1, nombres[-2], nombres[-1]), tlm)
            elif t == b'Tf' and operandes and isinstance(operandes[0], bytes):
                nom = operandes[0][1:].decode()
                if nom in polices and nom not in cmaps:
                    tu = re.search(rb'/ToUnicode\s+(\d+) 0 R', dico(polices[nom]))
                    cmaps[nom] = cmap(int(tu.group(1))) if tu else {}
                police, taille = nom, nombres[-1] if nombres else 0
            elif t in (b'Tj', b'TJ'):
                hexa = ''.join(x.decode() for o in operandes if isinstance(o, bytes)
                               for x in re.findall(rb'<([0-9A-Fa-f]*)>', o))
                table = cmaps.get(police, {})
                texte = ''.join(table.get(int(hexa[i:i + 4], 16), '') for i in range(0, len(hexa) - 3, 4))
                if bloc is None:
                    bloc = [taille, '', produit(tlm, ctm)[5]]
                bloc[1] += texte
            elif t == b'ET' and bloc:
                sur_page.append((bloc[2], len(sur_page), ('T', bloc[0], bloc[1])))
                bloc = None
            elif t == b'Do' and operandes and isinstance(operandes[-1], bytes):
                n = images.get(operandes[-1][1:].decode())
                di = dico(n) if n is not None else b''
                larg, haut = re.search(rb'/Width\s+(\d+)', di), re.search(rb'/Height\s+(\d+)', di)
                if (b'/DCTDecode' in di and larg and haut
                        and max(int(larg.group(1)), int(haut.group(1))) >= TAILLE_IMAGE_MIN):
                    jpeg = flux(n)
                    if jpeg.startswith(b'\xff\xd8'):
                        # haut de l'image : carré unité placé par la matrice courante
                        haut_image = max(ctm[1] * x + ctm[3] * y + ctm[5] for x in (0, 1) for y in (0, 1))
                        sur_page.append((haut_image, len(sur_page), ('I', jpeg)))
            operandes = []
        # de haut en bas (ordonnée PDF décroissante), l'ordre du flux départageant ; blocs d'une même ligne (libellé,
        # « : », valeur) réunis
        for y, _, e in sorted(sur_page, key=lambda x: (-round(x[0], 1), x[1])):
            if e[0] == 'T' and elements and elements[-1][0] == 'T' and abs(elements[-1][3] - y) < 1:
                elements[-1] = ('T', elements[-1][1], elements[-1][2] + ' ' + e[2], y)
            else:
                elements.append(e + (y,) if e[0] == 'T' else e)
    return [e[:3] for e in elements]


def rapport_kizeo(donnees):
    """Rapport de formulaire Kizeo Forms → (formulaire, champs {libellé : valeur}, photos [(libellé, JPEG)]) ; None si
    le PDF n'en a pas l'allure. Titres (grand corps) : le premier nomme le formulaire, les suivants coupent les
    champs ; ligne « libellé : valeur », ou libellé seul terminé par « : » (photos, valeur sur plusieurs lignes) ;
    photo : rattachée au dernier libellé ; pied de page (petit corps) ignoré."""
    elements = lire_pdf(donnees)
    if not any(k == 'T' and 'Kizeo' in e[1] for k, *e in elements):
        return None
    formulaire, champs, photos, libelle = None, {}, [], None
    for k, *e in elements:
        if k == 'I':
            photos.append((libelle, e[0]))
            continue
        taille, texte = e[0], re.sub(r'\s+', ' ', e[1]).strip()
        if not texte or taille < 9 or 'Kizeo' in texte:
            continue
        if taille >= 13:
            formulaire = formulaire or texte
            libelle = None
        elif texte.endswith(':'):
            libelle = texte[:-1].strip()
            champs.setdefault(libelle, '')
        elif ' : ' in texte:
            libelle, valeur = (x.strip() for x in texte.split(' : ', 1))
            champs[libelle] = valeur
        elif libelle is not None:
            champs[libelle] = f'{champs[libelle]} {texte}'.strip()
    return formulaire, champs, photos


def titre_kizeo(libelle):
    """Titre d'un visuel libre d'après le libellé du formulaire, accents rétablis (« Etiquettes entrées » →
    « Étiquettes entrées », « Boite ouverte » → « Boîte ouverte »)."""
    t = re.sub(r'\bEtiquette', 'Étiquette', libelle or 'Photo')
    return re.sub(r'\b([Bb])oite\b', r'\1oîte', t)


def lire_mesure(texte):
    """Synthèse réflectométrique FiberCable (export texte) → (en-tête, mesures par (câble, fibre, lambda))."""
    lignes = texte.splitlines()
    tete = {}
    for l in lignes[:60]:
        c = l.split('\t')
        if len(c) >= 2 and c[0].strip():
            tete.setdefault(c[0].strip(), [x.strip() for x in c[1:]])

    def section(titre):
        i = next((k for k, l in enumerate(lignes) if l.strip() == titre), None)
        if i is None:
            return [], []
        sous = lignes[i + 2].split('\t')
        rangs = []
        for l in lignes[i + 3:]:
            if not l.strip():
                break
            rangs.append(l.split('\t'))
        return sous, rangs

    def triplets(titre):
        """Valeur de chaque groupe (sens O→E, sens O←E, moyenne) : la moyenne, sinon le premier sens renseigné."""
        sous, rangs = section(titre)
        out = {}
        for r in rangs:
            r = r + [''] * (len(sous) + 3 - len(r))
            groupes = []
            for k in range(3, len(sous) - 2, 3):
                v = next((reel(x) for x in (r[k + 2], r[k], r[k + 1]) if reel(x) is not None), None)
                groupes.append(((sous[k] or '').strip(), v))
            out[(r[0].strip(), entier(r[1]), entier(r[2]))] = groupes
        return out

    att, pentes, lng = triplets('Atténuations (dB)'), triplets('Pentes (dB/km)'), triplets('Longueurs (m)')
    _, infos = section('Informations mesures')
    lambdas = [entier(x.split()[0]) for x in tete.get('Lambda', []) if x]

    def seuil(cle, lam):
        vals = tete.get(cle, [])
        v = reel(vals[lambdas.index(lam)]) if lam in lambdas and lambdas.index(lam) < len(vals) else None
        return v if v is not None and v < 9999 else None

    mesures = {}
    for r in infos:
        r = r + [''] * (17 - len(r))
        cle = (r[0].strip(), entier(r[1]), entier(r[2]))
        evts = [v for lab, v in att.get(cle, []) if lab != 'Perte totale' and v is not None]
        perte = next((v for lab, v in att.get(cle, []) if lab == 'Perte totale'), None)
        sections_p = [v for _, v in pentes.get(cle, []) if v is not None]
        sections_l = [v for _, v in lng.get(cle, []) if v is not None]
        s_att, s_pente = seuil('Seuils atténuations (dB)', cle[2]), seuil('Seuils pentes (dB/km)', cle[2])
        conforme = None
        if s_att is not None or s_pente is not None:
            conforme = int(all(v <= s_att for v in evts if s_att is not None)
                           and all(v <= s_pente for v in sections_p if s_pente is not None))
        mesures[cle] = {
            'fichier': next((x.strip() for x in r[3:7] if x.strip()), None),
            'date': date_fr(next((x for x in r[7:11] if x.strip()), '')),
            'orl': next((reel(x) for x in r[15:17] if reel(x) is not None), None),
            'lng': round(sum(sections_l), 3) if sections_l else None, 'perte': perte,
            'evt_max': max(evts) if evts else None, 'pente_max': max(sections_p) if sections_p else None,
            'conforme': conforme}
    return tete, mesures


def nom_photo(fichier):
    """« BT31_2.jpg », « 10656_S.jpg » → nom du support (BT31, 10656)."""
    base = os.path.splitext(os.path.basename(fichier))[0]
    return re.sub(r'(?i)_(\d+|s)$', '', base).upper()


def lire_comac_vues():
    """Classement des photos COMAC : {(rue, fichier) : (vue, remarque)}."""
    if not os.path.isfile(COMAC_VUES):
        return {}
    with open(COMAC_VUES, encoding='utf-8', newline='') as f:
        return {(r['rue'], r['fichier']): (r['vue'], r['remarque'] or None) for r in csv.DictReader(f, delimiter=';')}


def base_grace(zdoe, dossier, qgis):
    """Export GraceTHD (02_GRACETHD) et relevé d'infrastructure FibReady (Shapes_Origine/INFRA_POINTS) du DOE → base
    SpatiaLite (shapefiles en Lambert 93, CSV en texte, champ vide → NULL)."""
    tmp = tempfile.mkdtemp()
    for n in zdoe.namelist():
        if (n.startswith('02_GRACETHD/') and not n.endswith('/')) or n.startswith('01_PLAN/Shapes_Origine/INFRA_POINTS.'):
            with open(os.path.join(tmp, os.path.basename(n)), 'wb') as f:
                f.write(zdoe.read(n))
    chemin = os.path.join(dossier, 'gracethd_doe.sqlite')
    if os.path.exists(chemin):
        os.remove(chemin)
    con = projet.connecter(chemin, qgis, spatial=True)
    con.execute('SELECT InitSpatialMetadata(1)')
    for nom in sorted(os.listdir(tmp)):
        base, ext = os.path.splitext(nom)
        if ext == '.shp':
            cpg = os.path.join(tmp, base + '.cpg')
            cs = 'UTF-8' if os.path.exists(cpg) and 'UTF' in open(cpg).read().upper() else 'CP1252'
            table = 'fbr_infra_points' if base == 'INFRA_POINTS' else base
            con.execute('SELECT ImportSHP(?, ?, ?, 2154, ?, NULL, NULL, 1, 0, 1, 1, ?, 1, 0)',
                        (os.path.join(tmp, base), table, cs, 'geom', 'LOWER'))
        elif ext == '.csv':
            brut = open(os.path.join(tmp, nom), 'rb').read()
            try:
                texte = brut.decode('utf-8-sig')
            except UnicodeDecodeError:
                texte = brut.decode('cp1252')
            rangs = [r for r in csv.reader(texte.splitlines(), delimiter=';') if r]
            cols = rangs[0]
            con.execute(f'CREATE TABLE "{base}" ({", ".join(f"{chr(34)}{c}{chr(34)} TEXT" for c in cols)})')
            con.executemany(f'INSERT INTO "{base}" VALUES ({",".join("?" * len(cols))})',
                            [[v or None for v in r] + [None] * (len(cols) - len(r)) for r in rangs[1:]])
    con.close()
    shutil.rmtree(tmp)
    return chemin


def etudes_comac(zcalc, qgis):
    """Études COMAC : appuis des SIG de chaque rue (Supports.shp), détail des appuis BT (ExportComac), conclusions
    (suivi multi études, feuille RECAP), photos ; {(rue, nom) : appui}, conclusions par nom, photos par (rue, nom)."""
    appuis, photos, tmp = {}, defaultdict(list), tempfile.mkdtemp()
    con = projet.connecter(':memory:', qgis, spatial=True)
    con.execute('SELECT InitSpatialMetadata(1)')
    for i, n in enumerate(sorted(x for x in zcalc.namelist() if x.lower().endswith('.zip'))):
        rue = os.path.splitext(os.path.basename(n))[0]
        z = zipfile.ZipFile(io.BytesIO(zcalc.read(n)))
        date = None
        for m in z.namelist():
            low = m.lower()
            if low.endswith('_sig/supports.shp') or re.search(r'_sig/supports\.(shx|dbf|prj|cpg)$', low):
                with open(os.path.join(tmp, f'c{i}' + os.path.splitext(m)[1].lower()), 'wb') as f:
                    f.write(z.read(m))
            elif '_photos/' in low and low.endswith('.jpg'):
                photos[(rue, nom_photo(m))].append((z, m))
        if not os.path.isfile(os.path.join(tmp, f'c{i}.shp')):
            continue
        con.execute('SELECT ImportSHP(?, ?, ?, 2154, ?, NULL, NULL, 1, 0, 0, 1, ?, 0, 0)',
                    (os.path.join(tmp, f'c{i}'), f'c{i}', 'UTF-8', 'geom', 'LOWER'))
        for nom, h, eff, classe, x, y in con.execute(f'SELECT nom, hauteur, effort, classe, X(geom), Y(geom) FROM c{i}'):
            appuis[(rue, (nom or '').upper())] = {'rue': rue, 'nom': (nom or '').upper(), 'hauteur': h, 'effort': eff,
                                                  'classe': classe, 'x': x, 'y': y}
        export = next((m for m in z.namelist() if m.endswith('_ExportComac.xlsx')), None)
        if export:
            for lignes in lire_xlsx(z.read(export)).values():
                if lignes and len(lignes[0]) > 11 and lignes[0][10] == 'Date :':
                    date = date_fr(lignes[0][11])
                for r in lignes[3:]:
                    r = (r or []) + [None] * 30
                    a = appuis.get((rue, (r[0] or '').upper()))
                    if a and r[10]:
                        a.update(type=r[3], hauteur=reel(r[4]) or a['hauteur'], classe=r[7] or a['classe'],
                                 effort=reel(r[8]) if reel(r[8]) is not None else a['effort'], annee=entier(r[9]),
                                 orientation=reel((r[15] or '').replace('gr', '')), traverses=entier(r[27]),
                                 a_poser=entier(r[28]))
        for a in appuis.values():
            if a['rue'] == rue:
                a['date'] = date
    con.close()
    shutil.rmtree(tmp)
    conclusions = {}
    suivi = next((n for n in zcalc.namelist() if 'Suivi multi' in n), None)
    if suivi:
        for r in lire_xlsx(zcalc.read(suivi)).get('RECAP', [])[2:]:
            r = (r or []) + [None] * 22
            if r[0]:
                conclusions.setdefault(r[0].strip().upper(), {'etat': r[1], 'commentaire': r[2], 'taux': reel(r[19]),
                                                               'conclusion': r[20]})
    return appuis, conclusions, photos


# Chargement ------------------------------------------------------------------------------------

class Doe:
    def __init__(self, dossier, qgis, zdoe, zcalc):
        self.dossier, self.zdoe, self.zcalc = dossier, zdoe, zcalc
        self.con = projet.ouvrir(dossier, qgis)
        self.rapport = []
        q = self.con.execute
        self.types = dict(q('SELECT TYPE_CODE, TYPE_ID FROM DEF_TYPE'))
        self.ent = dict(q('SELECT ENT_TABLE, ENT_ID FROM DEF_ENTITE'))
        self.avct = dict(q('SELECT AVCT_CODE, AVCT_ID FROM DEF_AVANCEMENT'))
        self.gmod = dict(q('SELECT GMOD_CODE, GMOD_ID FROM DEF_GEOL_MODE'))
        self.gclasse = dict(q('SELECT CLASSE_CODE, CLASSE_ID FROM DEF_GEOL_CLASSE'))
        self.etat = dict(q('SELECT ETAT_CODE, ETAT_ID FROM infra.DEF_CD_ETAT'))
        self.nat = {lib: i for i, lib in q('SELECT NAT_ID, NAT_LIB FROM poteau.DEF_POT_NAT')}
        self.mat_chb = {lib: i for i, lib in q('SELECT MAT_ID, MAT_LIB FROM chambre.MAT_CHAMBRE')}
        self.mat_pot = {lib: i for i, lib in q('SELECT MAT_ID, MAT_LIB FROM poteau.MAT_POTEAU')}
        self.otyp = dict(q('SELECT OTYP_CODE, OTYP_ID FROM optique.DEF_OPT_EQUIP_TYPE'))
        self.cfon = dict(q('SELECT CFON_CODE, CFON_ID FROM optique.DEF_CAB_FONCTION'))
        self.ctyp = dict(q('SELECT CTYP_CODE, CTYP_ID FROM optique.DEF_CASSETTE_TYPE'))
        self.pfon = dict(q('SELECT PFON_CODE, PFON_ID FROM optique.DEF_POS_FONCTION'))
        self.hab = dict(q('SELECT HAB_CODE, HAB_ID FROM immeuble.DEF_IMB_HABITAT'))
        self.ietat = dict(q('SELECT IETAT_CODE, IETAT_ID FROM immeuble.DEF_IMB_ETAT'))
        self.ltyp = dict(q('SELECT LTYP_CODE, LTYP_ID FROM immeuble.DEF_LOC_TYPE'))
        self.racco = dict(q('SELECT RACCO_CODE, RACCO_ID FROM immeuble.DEF_LOC_RACCO'))
        self.vues = {(t, c): i for i, t, c in q('SELECT VUE_ID, TYPE_KEY, VUE_CODE FROM DEF_VUE '
                                                 'WHERE TYPE_KEY IS NOT NULL')}
        self.vues_equ = dict(q("SELECT VUE_CODE, VUE_ID FROM DEF_VUE WHERE VUE_ENTITE = 'INF_EQUIPEMENT'"))
        self.parent = dict(q('SELECT TYPE_ID, TYPE_PARENT_KEY FROM DEF_TYPE'))
        self.code_projet = PROJET[0]
        self.org, self.adr, self.noe, self.type_noe, self.lin = {}, {}, {}, {}, {}
        self.mat_equip, self.mat_cable, self.equ, self.eqo, self.cab, self.fib = {}, {}, {}, {}, {}, {}
        self.pcb, self.cdc, self.cas = {}, {}, {}
        self.rangs, self.copies, self.comac, self.photos_comac = Counter(), set(), {}, []
        self.stats = Counter()

    def un(self, sql, *p):
        r = self.con.execute(sql, p).fetchone()
        return r[0] if r else None

    def dernier(self):
        return self.un('SELECT last_insert_rowid()')

    def inserer(self, table, valeurs):
        valeurs = {k: v for k, v in valeurs.items() if v is not None}
        self.con.execute(f'INSERT INTO {table} ({", ".join(valeurs)}) VALUES ({", ".join("?" * len(valeurs))})',
                         list(valeurs.values()))
        return self.dernier()

    def commentaire(self, ent, obj, cle, texte, origine='BE', type_='standard', date=None):
        """Texte repris d'une source au journal de l'objet : sans intervention, code déterministe (projet, objet,
        source), auteur « BE » (FibReady, COMAC) ou « GRACE » pour GraceTHD comme charger_essai.py (auteur BE)."""
        self.inserer('PRJ_COMMENTAIRE', {
            'COM_CODE_EXT': code_uuid(self.code_projet, ent, obj, cle), 'ENT_KEY': self.ent[ent], 'OBJ_KEY': obj,
            'COM_TYPE': type_, 'COM_TEXTE': texte, 'COM_AUTEUR': projet.auteur_reprise(origine),
            'COM_ORIGINE': origine, 'DATE_CREA': date})

    def organisme(self, code):
        if not code:
            return None
        if code not in self.org:
            r = self.con.execute('SELECT or_nom, or_siren FROM grc.t_organisme WHERE or_code = ?', (code,)).fetchone()
            if not r:
                return None
            self.org[code] = self.inserer('DEF_ORGANISME', {'ORG_CODE': code, 'ORG_LIB': (r[0] or code).strip(),
                                                            'ORG_SIREN': r[1]})
        return self.org[code]

    def fabricant(self, code):
        """Fabricant d'une référence GraceTHD (organisme) : celui du catalogue FOA de même nom, sinon créé."""
        nom = self.un('SELECT or_nom FROM grc.t_organisme WHERE or_code = ?', code)
        if not nom:
            return None
        fab = self.un('SELECT FAB_ID FROM DEF_FABRICANT WHERE upper(FAB_LIB) = upper(?)', nom.strip())
        if fab is None:
            fab = self.un('SELECT COALESCE(MAX(FAB_ID), 0) + 1 FROM DEF_FABRICANT')
            self.con.execute('INSERT INTO DEF_FABRICANT (FAB_ID, FAB_LIB) VALUES (?, ?)', (fab, nom.strip()))
        return fab

    # -- fichiers --------------------------------------------------------------------------------

    def vue(self, noe, code):
        """Vue attendue code pour le type du nœud ou l'un de ses parents, sinon None."""
        t = self.type_noe.get(noe)
        while t is not None:
            if (t, code) in self.vues:
                return self.vues[(t, code)]
            t = self.parent.get(t)
        return None

    def fichier(self, ent, obj, donnees, rel, cle, vue=None, visuel=None, date=None, comment=None):
        """Fichier joint à un objet, copié dans le projet (rel) ; une seule copie d'un même contenu par objet. Rang et
        photo principale par visuel (vue attendue ou visuel libre de titre visuel)."""
        sha = hashlib.sha256(donnees).hexdigest()
        if (ent, obj, sha) in self.copies:
            return None
        self.copies.add((ent, obj, sha))
        chemin = os.path.join(self.dossier, rel)
        os.makedirs(os.path.dirname(chemin), exist_ok=True)
        with open(chemin, 'wb') as f:
            f.write(donnees)
        mime = MIME.get(os.path.splitext(rel)[1].lower())
        image = (mime or '').startswith('image/')
        groupe = (ent, obj, vue, visuel)
        self.rangs[groupe] += 1
        self.stats['fichiers ' + ('image' if image else 'document')] += 1
        return self.inserer('PRJ_FICHIER', {
            'FIC_CODE_EXT': f'{P}-{code_uuid(self.code_projet, "fichier", cle)}', 'ENT_KEY': self.ent[ent],
            'OBJ_KEY': obj, 'VUE_KEY': vue,
            'VIS_CODE': code_uuid(self.code_projet, 'visuel', ent, obj, visuel) if visuel and image else None,
            'VIS_LIB': visuel if image else None, 'FIC_RANG': self.rangs[groupe],
            'FIC_PRINCIPALE': int(image and self.rangs[groupe] == 1), 'FIC_NOM': os.path.basename(rel),
            'FIC_CHEMIN': rel.replace('\\', '/'), 'FIC_TYPE': mime, 'FIC_TAILLE': len(donnees), 'FIC_SHA256': sha,
            'DATE_PRISE': date, 'FIC_COMMENT': comment, 'SRC_MODIF': 'import'})

    def membre(self, z, nom, ent, obj, dossier, vue=None, visuel=None, comment=None):
        """Membre d'une archive joint tel quel."""
        rel = os.path.join(dossier, os.path.basename(nom))
        return self.fichier(ent, obj, z.read(nom), rel, nom, vue, visuel, date_zip(z.getinfo(nom)), comment)

    def cable_kizeo(self, chiffres):
        """Câble nommé par les 4 derniers chiffres de son étiquette (rapports de tirage) : son étiquette s'il est le
        seul à finir ainsi, sinon les chiffres tels quels."""
        if not chiffres:
            return None
        trouves = [r[0] for r in self.con.execute("SELECT CAB_LIB FROM optique.OPT_CABLE WHERE CAB_LIB LIKE ?",
                                                  (f'%-{chiffres.strip()}',))]
        return trouves[0] if len(trouves) == 1 else f'…{chiffres.strip()}'

    def rapport_photos(self, z, nom, ent, obj, noe, dossier, vue=None, visuel=None):
        """Rapport Kizeo Forms (11_PHOTOS) : PDF joint comme document ; chaque photo dans la vue attendue que nomme son
        libellé, du support noe (VUES_KIZEO, faces des masques) ou, rapport d'une boîte (ent INF_EQUIPEMENT), de
        l'équipement obj (VUES_BOITE), sinon dans un visuel libre au titre du libellé ; date de réponse du formulaire (heure de
        Paris) comme date de prise ; formulaire, libellé, câble tiré et technicien en commentaire ; remontée et
        commentaire écrit au journal du support. Rapport d'une autre facture : images extraites, vue ou visuel donnés."""
        donnees = z.read(nom)
        r = rapport_kizeo(donnees)
        if r is None or not r[2]:
            self.stats['rapports PDF hors Kizeo'] += 1
            return self.images(z, nom, ent, obj, dossier, vue, visuel)
        formulaire, champs, photos = r
        base = os.path.splitext(os.path.basename(nom))[0].replace('#', '')
        date = date_fr(champs.get('Date de réponse')) or date_zip(z.getinfo(nom))
        self.fichier(ent, obj, donnees, os.path.join(dossier, base + '.pdf'), nom, date=date,
                     comment=f'Rapport {formulaire}')
        cable = self.cable_kizeo(champs.get('Numéro câble (4 derniers digits)'))
        technicien = ' '.join(x for x in (champs.get('Prénom'), champs.get('Nom')) if x)
        faces = iter('ABCD') if sum(lib == MASQUES_KIZEO for lib, _ in photos) == 4 else None
        n = 0
        for i, (lib, jpeg) in enumerate(photos, 1):
            if ent == 'INF_EQUIPEMENT':
                vue_photo = self.vues_equ.get(VUES_BOITE.get(titre_kizeo(lib)))
            else:
                code = VUES_KIZEO.get(lib) or (next(faces) if faces and lib == MASQUES_KIZEO else None)
                vue_photo = self.vue(noe, code) if code else None
            libre = None if vue_photo else titre_kizeo(lib)
            comment = ', '.join(x for x in (f'{formulaire} : {lib or "photo"}', f'câble {cable}' if cable else None,
                                            technicien or None) if x) + f' (extraite de {os.path.basename(nom)})'
            if self.fichier(ent, obj, jpeg, os.path.join(dossier, f'{base}_{i:02d}.jpg'), f'{nom}#{i}', vue_photo,
                            libre, date, comment):
                n += 1
                self.stats['photos des rapports : ' + ('vue attendue' if vue_photo else 'visuel libre')] += 1
        jour = (champs.get('Date de réponse') or '')[:10] or (date or '')[:10]
        if (champs.get('Remontée') or '').lower() == 'oui':
            self.commentaire('PRJ_NOE', noe, f'kizeo:{nom}:remontee',
                             f'{formulaire} du {jour} : remontée' + (f' du câble {cable}' if cable else ''), date=date)
            self.stats['remontées relevées'] += 1
        if champs.get('Commentaire écrit'):
            self.commentaire('PRJ_NOE', noe, f'kizeo:{nom}:commentaire',
                             f'{formulaire} du {jour} ({technicien}) : {champs["Commentaire écrit"]}', date=date)
        return n

    def images(self, z, nom, ent, obj, dossier, vue=None, visuel=None):
        """Rapport PDF : joint comme document, ses images JPEG comme photos."""
        donnees = z.read(nom)
        base = os.path.splitext(os.path.basename(nom))[0].replace('#', '')
        self.fichier(ent, obj, donnees, os.path.join(dossier, base + '.pdf'), nom, date=date_zip(z.getinfo(nom)))
        n = 0
        for i, jpeg in enumerate(images_pdf(donnees), 1):
            if self.fichier(ent, obj, jpeg, os.path.join(dossier, f'{base}_{i:02d}.jpg'), f'{nom}#{i}', vue, visuel,
                            date_zip(z.getinfo(nom)), f'Extraite de {os.path.basename(nom)}'):
                n += 1
        return n

    # -- référentiels et adresses ----------------------------------------------------------------

    def catalogues(self):
        """Références GraceTHD des boîtiers, baies, tiroirs et câbles chargés → MAT_EQUIP et MAT_CABLE, identifiants à
        la suite du catalogue FOA. Une ligne par référence, de la capacité qu'elle nomme (« PBO 48 fo ») : épissures
        d'un boîtier, connecteurs d'un tiroir ; une référence sans capacité (manchon) a une ligne par capacité posée
        (bp_typephy). La capacité utile de chaque boîtier est dans OPT_EQUIPEMENT."""
        con = self.con
        prochain = lambda t: self.un(f'SELECT COALESCE(MAX(MAT_ID), 0) + 1 FROM infra.{t}')
        usages = con.execute(
            "SELECT 'BP', bp_rf_code, CAST(substr(bp_typephy, 2) AS INTEGER) FROM grc.t_ebp UNION "
            "SELECT 'BA', ba_rf_code, NULL FROM grc.t_baie UNION SELECT 'TI', ti_rf_code, NULL FROM grc.t_tiroir").fetchall()
        for sorte, rf, capa in sorted(usages, key=lambda u: (u[1] or '', u[2] or 0)):
            r = con.execute('SELECT rf_design, rf_fabric FROM grc.t_reference WHERE rf_code = ?', (rf,)).fetchone()
            if not r:
                continue
            lib = r[0].strip()
            nommee = re.search(r'(\d+)\s*FO\b', lib, re.I)
            if nommee:
                capa = None
            elif capa:
                lib = f'{lib} {capa} FO'
            if (rf, capa) in self.mat_equip:
                continue
            n = entier(nommee.group(1)) if nommee else capa
            mat = prochain('MAT_EQUIP')
            con.execute('INSERT INTO infra.MAT_EQUIP (MAT_ID, MAT_LIB, FAB_KEY, MAT_NBPORTS, MAT_CAPAEPIS) '
                        'VALUES (?, ?, ?, ?, ?)', (mat, lib, self.fabricant(r[1]), n if sorte == 'TI' else None,
                                                   n if sorte == 'BP' else None))
            self.mat_equip[(rf, capa)] = mat
        for (rf,) in con.execute('SELECT DISTINCT cb_rf_code FROM grc.t_cable WHERE cb_rf_code IS NOT NULL').fetchall():
            design, fab = con.execute('SELECT rf_design, rf_fabric FROM grc.t_reference WHERE rf_code = ?', (rf,)).fetchone()
            m = re.search(r'(\d+)MOD(\d+)', design)
            ref = design.split(' - ')[-1].strip() if design.count(' - ') >= 3 else None
            mat = prochain('MAT_CABLE')
            con.execute("INSERT INTO infra.MAT_CABLE (MAT_ID, MAT_LIB, MAT_REF, FAB_KEY, CAB_NB_FIB, CAB_MODULO, CAB_TYPE, "
                        "CAB_USAGE) VALUES (?, ?, ?, ?, ?, ?, 'FO', 'RESEAU')",
                        (mat, design.strip(), ref, self.fabricant(fab), entier(m.group(1)) if m else None,
                         m.group(2) if m else None))
            self.mat_cable[rf] = mat
        self.rapport.append(f'catalogues : {len(self.mat_equip)} références MAT_EQUIP, {len(self.mat_cable)} MAT_CABLE '
                            f'ajoutées d\'après t_reference')

    def adresses(self):
        con = self.con
        for (code, ban, voie, num, rep, insee, cp, commune, comment, crea, maj, hab, ietat, nblhab, nblpro, nbprhab,
             nbprpro, neuf, batcode, nombat, racc, gest, datsgn, accgst) in con.execute(
                'SELECT ad_code, ad_ban_id, ad_nomvoie, ad_numero, ad_rep, ad_insee, ad_postal, ad_commune, ad_comment, '
                'ad_creadat, ad_majdate, ad_itypeim, ad_ietat, ad_nblhab, ad_nblpro, ad_nbprhab, ad_nbprpro, ad_imneuf, '
                'ad_batcode, ad_nombat, ad_racc, ad_gest, ad_idatsgn, ad_iaccgst FROM grc.t_adresse').fetchall():
            self.con.execute(
                'INSERT INTO PRJ_ADRESSE (ADR_CODE_EXT, ADR_BAN_ID, ADR_NUMERO, ADR_REP, ADR_VOIE, ADR_CP, ADR_INSEE, '
                'ADR_COMMUNE, ADR_COMMENT, DATE_CREA, DATE_MODIF, SRC_MODIF, GEOMETRY) VALUES (?, ?, ?, ?, ?, ?, ?, ?, '
                "?, COALESCE(?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), ?, 'import', "
                '(SELECT geom FROM grc.t_adresse WHERE ad_code = ?))',
                (f'{P}-{code}', ban or None, num, rep or None, voie, cp, insee, commune, comment or None, iso(crea),
                 iso(maj), code))
            a = self.adr[code] = self.dernier()
            self.inserer('immeuble.IMB_ADRESSE', {
                'ADR_KEY': a, 'HAB_KEY': self.hab.get(hab), 'IETAT_KEY': self.ietat.get(ietat), 'IAD_NB_LOG': nblhab,
                'IAD_NB_PRO': nblpro, 'IAD_NB_PRISE_LOG': nbprhab, 'IAD_NB_PRISE_PRO': nbprpro,
                'IAD_NEUF': None if neuf is None else int(bool(neuf)), 'IAD_BATCODE': batcode or None,
                'IAD_BATIMENT': nombat or None, 'IMPL_KEY': entier(racc), 'GEST_KEY': self.organisme(gest),
                'IAD_CONV_DATE': iso(datsgn) if datsgn else None,
                'IAD_ACCORD_GEST': None if accgst is None else int(bool(accgst)), 'SRC_MODIF': 'import'})
        self.rapport.append(f'adresses : {len(self.adr)}, BAL de {self.un("SELECT SUM(IAD_NB_LOG) FROM immeuble.IMB_ADRESSE")} '
                            f'logements et {self.un("SELECT SUM(IAD_NB_PRO) FROM immeuble.IMB_ADRESSE")} locaux professionnels')

    # -- nœuds -------------------------------------------------------------------------------

    def noeud(self, nd, type_code, lib, zone, adr=None, avct=None):
        g = self.con.execute('SELECT nd_creadat, nd_majdate, nd_geolqlt, nd_geolmod, nd_dtclass, nd_geolsrc '
                             'FROM grc.t_noeud WHERE nd_code = ?', (nd,)).fetchone()
        self.con.execute(
            'INSERT INTO PRJ_NOE (NOE_CODE_EXT, NOE_LIB, TYPE_KEY, ADR_KEY, ZONE_KEY, AVCT_KEY, GEOL_QLT, GEOL_MOD_KEY, '
            "GEOL_CLASSE_KEY, GEOL_SRC, DATE_CREA, DATE_MODIF, SRC_MODIF, GEOMETRY) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
            "COALESCE(?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), ?, 'import', "
            '(SELECT geom FROM grc.t_noeud WHERE nd_code = ?))',
            (f'{P}-{nd}', lib, self.types[type_code], self.adr.get(adr), zone, self.avct.get(avct), g[2] or None,
             self.gmod.get(g[3]), self.gclasse.get(g[4]), g[5] or None, iso(g[0]), iso(g[1]), nd))
        n = self.noe[nd] = self.dernier()
        self.type_noe[n] = self.types[type_code]
        return n

    def noeuds(self, zone):
        con = self.con
        releve = {r[0]: r[1:] for r in con.execute(
            'SELECT noe_codext, inf_type, inf_mat, inf_propri, commentair FROM grc.fbr_infra_points').fetchall()}
        n = Counter()
        for (pt, nd, typephy, nature, codeext, etiquet, ad, prop, gest, avct, comment) in con.execute(
                'SELECT pt_code, pt_nd_code, pt_typephy, pt_nature, pt_codeext, pt_etiquet, pt_ad_code, pt_prop, '
                'pt_gest, pt_avct, pt_comment FROM grc.t_ptech').fetchall():
            inf_type, inf_mat, _, inf_comment = releve.get(codeext, (None,) * 4)
            if typephy == 'A':
                t = 'POT-BT' if inf_type == 'POT-BT' else 'POT-FT'
            else:
                t = {'C': 'CHB', 'F': 'FAC'}.get(typephy, 'AUT')
            noe = self.noeud(nd, t, etiquet or codeext, zone, ad, avct)
            n[t] += 1
            if t.startswith('POT'):
                nat = NATURE.get((inf_mat or '').upper()) or NATURE.get(nature)
                self.inserer('poteau.POT_POTEAU', {'NOE_KEY': noe, 'NAT_KEY': self.nat.get(nat),
                                                   'PROPRIO_KEY': self.organisme(prop), 'GEST_KEY': self.organisme(gest),
                                                   'SRC_MODIF': 'import'})
            elif t == 'CHB':
                self.inserer('chambre.CHB_CHAMBRE', {'NOE_KEY': noe, 'MAT_KEY': self.mat_chb.get(nature),
                                                     'PROPRIO_KEY': self.organisme(prop),
                                                     'GEST_KEY': self.organisme(gest), 'SRC_MODIF': 'import'})
            date = self.un('SELECT DATE_CREA FROM PRJ_NOE WHERE NOE_ID = ?', noe)
            if comment:
                self.commentaire('PRJ_NOE', noe, 'pt_comment', comment.strip(), 'GRACE', date=date)
            if (inf_type or '').endswith('-AC'):
                self.commentaire('PRJ_NOE', noe, 'fibready-ac', 'Créé par les travaux (relevé FibReady : à créer)',
                                 date=date)
            if inf_comment and inf_comment.strip() not in ('A CREER TR',):
                self.commentaire('PRJ_NOE', noe, 'fibready', f'Relevé FibReady : {inf_comment.strip()}', date=date)
        for nd, typelog, nom, ad, prop in con.execute(
                'SELECT st_nd_code, st_typelog, st_nom, st_ad_code, st_prop FROM grc.t_sitetech').fetchall():
            t = SITES.get(typelog, 'SIT')
            self.noeud(nd, t, nom, zone, ad)
            n[t] += 1
        self.rapport.append('nœuds : ' + ', '.join(f'{v} {k}' for k, v in sorted(n.items())))

    # -- linéaires, conduites, portées -----------------------------------------------------------

    def lineaires(self, zone):
        con = self.con
        sorte = {'0': 'LIN-AER', '1': 'LIN-AER', '2': 'LIN-FAC'}
        cables = defaultdict(list)          # conduite → câbles (code, étiquette, référence)
        optiques = set()                    # câbles à fibres (cb_capafo > 0) : nature FO dans une conduite
        for cd, cb, etiq, rf, capa in con.execute(
                'SELECT cc.cc_cd_code, c.cb_code, c.cb_etiquet, c.cb_rf_code, c.cb_capafo FROM grc.t_cab_cond cc '
                'JOIN grc.t_cable c ON c.cb_code = cc.cc_cb_code ORDER BY c.cb_etiquet').fetchall():
            cables[cd].append((cb, etiq, rf))
            if (entier(capa) or 0) > 0:
                optiques.add(cb)
        gr = lambda a: round((a * 200 / math.pi) % 400, 2) if a is not None else None
        for (cm, n1, n2, imp, lng, codeext, crea, maj, avct, qlt, gmod, dtc, gsrc, inverse) in con.execute(
                'SELECT cm_code, cm_ndcode1, cm_ndcode2, cm_typ_imp, COALESCE(cm_lgreel, cm_long), cm_codeext, '
                'cm_creadat, cm_majdate, cm_avct, cm_geolqlt, cm_geolmod, cm_dtclass, cm_geolsrc, '
                'Distance(StartPoint(m.geom), a.geom) > Distance(EndPoint(m.geom), a.geom) '
                'FROM grc.t_cheminement m JOIN grc.t_noeud a ON a.nd_code = m.cm_ndcode1').fetchall():
            t = sorte.get(imp, 'LIN-SOUT')
            geom = 'ST_Reverse(CastToLineString(geom))' if inverse else 'CastToLineString(geom)'
            self.con.execute(
                'INSERT INTO PRJ_LINEAIRE (LIN_CODE_EXT, LIN_LIB, TYPE_KEY, IMPL_KEY, NOE1_KEY, NOE2_KEY, ZONE_KEY, '
                'AVCT_KEY, LIN_LNG, GEOL_QLT, GEOL_MOD_KEY, GEOL_CLASSE_KEY, GEOL_SRC, DATE_CREA, DATE_MODIF, SRC_MODIF, '
                "GEOMETRY) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, strftime('%Y-%m-%dT%H:%M:%SZ', "
                f"'now')), ?, 'import', (SELECT {geom} FROM grc.t_cheminement WHERE cm_code = ?))",
                (f'{P}-{cm}', codeext, self.types[t], entier(imp), self.noe[n1], self.noe[n2], zone, self.avct.get(avct),
                 round(lng, 2) if lng else None, qlt or None, self.gmod.get(gmod), self.gclasse.get(dtc), gsrc or None,
                 iso(crea), iso(maj), cm))
            lin = self.lin[cm] = self.dernier()
            self.stats[t] += 1
            conduites = con.execute('SELECT d.cd_code, d.cd_type, d.cd_dia_int, d.cd_dia_ext, d.cd_creadat '
                                    'FROM grc.t_cond_chem dm '
                                    'JOIN grc.t_conduite d ON d.cd_code = dm.dm_cd_code WHERE dm.dm_cm_code = ? '
                                    'ORDER BY d.cd_code', (cm,)).fetchall()
            if t != 'LIN-SOUT':
                # angles des extrémités sur la rosace : azimut géodésique (WGS84) en grades, 0 = nord géographique, sens
                # horaire ; en Lambert 93, le nord du quadrillage s'en écarte de la convergence des méridiens
                # (2,3 grades à 5,9° E)
                a1, a2 = con.execute(
                    'SELECT Azimuth(Transform(StartPoint(GEOMETRY), 4326), Transform(PointN(GEOMETRY, 2), 4326)), '
                    'Azimuth(Transform(EndPoint(GEOMETRY), 4326), '
                    'Transform(PointN(GEOMETRY, NumPoints(GEOMETRY) - 1), 4326)) '
                    'FROM PRJ_LINEAIRE WHERE LIN_ID = ?', (lin,)).fetchone()
                prt = self.inserer('infra.INF_PORTEE', {'LIN_KEY': lin, 'PRT_ANG1': gr(a1), 'PRT_ANG2': gr(a2),
                                                        'PRT_LNG': round(lng, 2) if lng else None, 'SRC_MODIF': 'import'})
                portes = [c for cd, *_ in conduites for c in cables.get(cd, [])]
                for rang, (cb, etiq, rf) in enumerate(sorted(set(portes), key=lambda c: c[1] or ''), 1):
                    self.pcb[(cb, cm)] = self.inserer('infra.INF_PORTEE_CABLE', {
                        'PRT_KEY': prt, 'PCB_RANG': rang, 'MAT_KEY': self.mat_cable.get(rf),
                        'PCB_LNG': round(lng, 2) if lng else None, 'PCB_COMMENT': etiq, 'SRC_MODIF': 'import'})
                    self.stats['câbles portés'] += 1
            else:
                for num, (cd, cdtype, dia, dia_ext, crea_cd) in enumerate(conduites, 1):
                    occ = cables.get(cd, [])
                    # diamètre nominal d'un tube = diamètre extérieur ; FibReady exporte les deux diamètres inversés
                    # (cd_dia_int 40 / cd_dia_ext 33 pour un PEHD 40, 45 / 42 et 63 / 60 pour le PVC) : le plus grand
                    diametres = [d for d in (reel(dia), reel(dia_ext)) if d]
                    k = self.inserer('infra.INF_CONDUITE', {
                        'CD_CODE_EXT': f'{P}-{cd}', 'LIN_KEY': lin, 'CD_NUM': num,
                        'CD_DIAM': max(diametres) if diametres else None,
                        'ETAT_KEY': self.etat['X' if occ else 'V'], 'CD_COMMENT': f'GraceTHD {cdtype}',
                        'DATE_CREA': iso(crea_cd), 'SRC_MODIF': 'import'})
                    self.stats['conduites'] += 1
                    for rang, (cb, etiq, rf) in enumerate(occ, 1):      # rang dans la conduite, ordre des étiquettes
                        self.cdc.setdefault((cb, cm), self.inserer('infra.INF_CD_CABLE', {
                            'CD_KEY': k, 'CDC_RANG': rang, 'MAT_KEY': self.mat_cable.get(rf), 'CDC_NB': 1,
                            'CDC_NATURE': 'FO' if cb in optiques else None, 'CDC_COMMENT': etiq,
                            'SRC_MODIF': 'import'}))
                        self.stats['occupations'] += 1

    # -- matériel optique ----------------------------------------------------------------------

    def noeud_local(self, lt):
        nd = self.un('SELECT s.st_nd_code FROM grc.t_ltech l JOIN grc.t_sitetech s ON s.st_code = l.lt_st_code '
                     'WHERE l.lt_code = ?', lt)
        return self.noe.get(nd)

    def equipement(self, code, noe, mat, lib, otyp, capa=None, taille=None, parent=None, emplacement=None, avct=None,
                   prop=None, crea=None):
        e = self.equ[code] = self.inserer('infra.INF_EQUIPEMENT', {
            'EQU_CODE_EXT': f'{P}-{code}', 'NOE_KEY': noe, 'MAT_KEY': mat, 'EQU_QTE': 1, 'DATE_CREA': iso(crea),
            'SRC_MODIF': 'import'})
        self.eqo[lib] = e
        self.inserer('optique.OPT_EQUIPEMENT', {
            'EQU_KEY': e, 'EQO_LIB': lib, 'OTYP_KEY': self.otyp.get(otyp), 'EQO_PARENT_KEY': parent, 'EQO_CAPA': capa,
            'EQO_TAILLE': taille, 'EQO_EMPLACEMENT': emplacement, 'AVCT_KEY': self.avct.get(avct),
            'PROPRIO_KEY': self.organisme(prop), 'SRC_MODIF': 'import'})
        return e

    def materiel(self):
        con = self.con
        for (bp, etiq, typelog, typephy, pt, lt, rf, avct, prop, crea, bat, escal, etage) in con.execute(
                'SELECT b.bp_code, b.bp_etiquet, b.bp_typelog, b.bp_typephy, b.bp_pt_code, b.bp_lt_code, b.bp_rf_code, '
                'b.bp_avct, b.bp_prop, b.bp_creadat, l.lt_bat, l.lt_escal, l.lt_etage FROM grc.t_ebp b '
                'LEFT JOIN grc.t_ltech_patch201 l ON l.lt_code = b.bp_lt_code').fetchall():
            noe = self.noe.get(self.un('SELECT pt_nd_code FROM grc.t_ptech WHERE pt_code = ?', pt)) if pt \
                else self.noeud_local(lt)
            capa = entier(typephy[1:]) if typephy else None
            place = ', '.join(x for x in (f'bâtiment {bat}' if bat else None, f'escalier {escal}' if escal else None,
                                          f'étage {etage}' if etage else None) if x) or None
            self.equipement(bp, noe, self.mat_equip.get((rf, capa), self.mat_equip.get((rf, None))), etiq, OTYP.get(typelog), capa, None, None, place,
                            avct, prop, crea)
            self.stats[typelog] += 1
        baies = {}
        for ba, etiq, lt, rf, nb_u, prop, crea in con.execute(
                'SELECT ba_code, ba_etiquet, ba_lt_code, ba_rf_code, ba_nb_u, ba_prop, ba_creadat FROM grc.t_baie'):
            self.equipement(ba, self.noeud_local(lt), self.mat_equip.get((rf, None)), etiq, 'BAIE', None, entier(nb_u),
                            prop=prop, crea=crea)
            baies[ba] = self.un('SELECT EQO_ID FROM optique.OPT_EQUIPEMENT WHERE EQU_KEY = ?', self.equ[ba])
            self.stats['baies'] += 1
        for ti, etiq, ba, rf, taille, prop, crea in con.execute(
                'SELECT ti_code, ti_etiquet, ti_ba_code, ti_rf_code, ti_taille, ti_prop, ti_creadat FROM grc.t_tiroir'):
            noe = self.un('SELECT NOE_KEY FROM infra.INF_EQUIPEMENT WHERE EQU_ID = ?', self.equ[ba])
            mat = self.mat_equip.get((rf, None))
            capa = self.un('SELECT MAT_NBPORTS FROM infra.MAT_EQUIP WHERE MAT_ID = ?', mat)
            self.equipement(ti, noe, mat, etiq, 'TIROIR', capa, entier(taille), baies.get(ba), prop=prop, crea=crea)
            self.stats['tiroirs'] += 1

    def cables(self):
        con = self.con
        for (cb, etiq, nd1, nd2, typelog, rf, capa, modulo, lng, avct, prop, crea, maj, comment, bp1, ba1, bp2,
             ba2) in con.execute(
                'SELECT c.cb_code, c.cb_etiquet, c.cb_nd1, c.cb_nd2, c.cb_typelog, c.cb_rf_code, c.cb_capafo, c.cb_modulo, '
                'c.cb_lgreel, c.cb_avct, c.cb_prop, c.cb_creadat, c.cb_majdate, c.cb_comment, p.cb_bp1, p.cb_ba1, '
                'p.cb_bp2, p.cb_ba2 FROM grc.t_cable c LEFT JOIN grc.t_cable_patch201 p ON p.cb_code = c.cb_code').fetchall():
            self.cab[cb] = self.inserer('optique.OPT_CABLE', {
                'CAB_CODE_EXT': f'{P}-{cb}', 'CAB_LIB': etiq, 'MAT_KEY': self.mat_cable.get(rf),
                'CFON_KEY': self.cfon.get(typelog), 'CAB_CAPA': entier(capa), 'CAB_MODULO': entier(modulo),
                'NOE1_KEY': self.noe[nd1], 'NOE2_KEY': self.noe[nd2], 'EQU1_KEY': self.equ.get(bp1 or ba1),
                'EQU2_KEY': self.equ.get(bp2 or ba2), 'CAB_LNG': reel(lng), 'AVCT_KEY': self.avct.get(avct),
                'PROPRIO_KEY': self.organisme(prop), 'CAB_COMMENT': comment, 'DATE_CREA': iso(crea),
                'DATE_MODIF': iso(maj), 'SRC_MODIF': 'import'})
        # passages : linéaires du câble rangés depuis NOE1 en suivant le parcours (rang vide si le parcours se ramifie)
        parcours = defaultdict(set)
        for cb, cm in con.execute('SELECT DISTINCT cc.cc_cb_code, dm.dm_cm_code FROM grc.t_cab_cond cc '
                                  'JOIN grc.t_cond_chem dm ON dm.dm_cd_code = cc.cc_cd_code').fetchall():
            parcours[cb].add(cm)
        ends = {cm: (self.noe[a], self.noe[b]) for cm, a, b in con.execute(
            'SELECT cm_code, cm_ndcode1, cm_ndcode2 FROM grc.t_cheminement')}
        ranges = 0
        for cb, cms in parcours.items():
            rang, courant, restants = {}, self.un('SELECT NOE1_KEY FROM optique.OPT_CABLE WHERE CAB_ID = ?', self.cab[cb]), set(cms)
            while True:
                suite = [cm for cm in restants if courant in ends[cm]]
                if len(suite) != 1:
                    break
                cm = suite[0]
                rang[cm] = len(rang) + 1
                restants.discard(cm)
                courant = ends[cm][1] if ends[cm][0] == courant else ends[cm][0]
            ranges += not restants
            for cm in sorted(cms, key=lambda c: rang.get(c, 10 ** 6)):
                self.inserer('optique.OPT_PASSAGE', {'CAB_KEY': self.cab[cb], 'LIN_KEY': self.lin[cm],
                                                     'PCB_KEY': self.pcb.get((cb, cm)), 'CDC_KEY': self.cdc.get((cb, cm)),
                                                     'PAS_RANG': rang.get(cm), 'SRC_MODIF': 'import'})
        self.rapport.append(f'câbles : {len(self.cab)}, {len(parcours)} avec un parcours ({ranges} rangés de bout en '
                            f'bout), {sum(map(len, parcours.values()))} passages')
        for cb, nd, lv in con.execute('SELECT lv_cb_code, lv_nd_code, lv_long FROM grc.t_love').fetchall():
            self.inserer('optique.OPT_LOVE', {'CAB_KEY': self.cab[cb], 'NOE_KEY': self.noe[nd], 'LOV_LNG': reel(lv),
                                              'SRC_MODIF': 'import'})
        for fo, cb, num, tube, ntube, coul, reper, typ, comment in con.execute(
                'SELECT fo_code, fo_cb_code, fo_nincab, fo_numtub, fo_nintub, fo_color, fo_reper, fo_type, fo_comment '
                'FROM grc.t_fibre').fetchall():
            # repère Orange 1.n : au-delà de 12 tubes, la couleur revient avec des bagues noires (1.13 : rouge, une bague)
            rang_tube = entier(reper.split('.')[-1]) if reper and '.' in reper else None
            tcoul = (rang_tube - 1) % 12 + 1 if rang_tube else None
            self.fib[fo] = self.inserer('optique.OPT_FIBRE', {
                'CAB_KEY': self.cab[cb], 'FIB_NUM': entier(num), 'FIB_TUBE': entier(tube), 'FIB_NUM_TUBE': entier(ntube),
                'COUL_KEY': entier(coul), 'TUBE_COUL_KEY': tcoul, 'FIB_TYPE': typ, 'FIB_COMMENT': comment,
                'SRC_MODIF': 'import'})

    def cassettes(self):
        con = self.con
        for cs, nb_pas, bp, num, typ, ti in con.execute(
                'SELECT c.cs_code, c.cs_nb_pas, c.cs_bp_code, c.cs_num, c.cs_type, p.cs_ti_code FROM grc.t_cassette c '
                'LEFT JOIN grc.t_cassette_patch201 p ON p.cs_code = c.cs_code').fetchall():
            self.cas[cs] = self.inserer('optique.OPT_CASSETTE', {
                'EQU_KEY': self.equ[bp or ti], 'CAS_NUM': entier(num), 'CTYP_KEY': self.ctyp.get(typ),
                'CAS_CAPA': entier(nb_pas), 'SRC_MODIF': 'import'})
        for cs, num, f1, f2, typ, fonct, comment in con.execute(
                'SELECT ps_cs_code, ps_numero, ps_1, ps_2, ps_type, ps_fonct, ps_comment FROM grc.t_position').fetchall():
            self.inserer('optique.OPT_POSITION', {
                'CAS_KEY': self.cas[cs], 'POS_NUM': entier(num), 'FIB1_KEY': self.fib.get(f1), 'FIB2_KEY': self.fib.get(f2),
                'PFON_KEY': self.pfon.get(fonct), 'POS_CONNECTEUR': typ, 'POS_AFFECT': comment, 'SRC_MODIF': 'import'})
        routes = defaultdict(list)
        for rt, fo, ordre in con.execute('SELECT rt_code, rt_fo_code, rt_fo_ordr FROM grc.t_ropt').fetchall():
            routes[rt].append((entier(ordre), fo))
        for rt, fibres in routes.items():
            r = self.inserer('optique.OPT_ROUTE', {'RTE_CODE_EXT': f'{P}-{rt}', 'SRC_MODIF': 'import'})
            for rang, fo in sorted(fibres):
                self.inserer('optique.OPT_ROUTE_FIBRE', {'RTE_KEY': r, 'ROF_RANG': rang, 'FIB_KEY': self.fib[fo]})
        # libellé : position de départ (connecteur du tiroir) → boîtier où la dernière fibre est en attente
        con.execute(
            "UPDATE optique.OPT_ROUTE SET RTE_LIB = ("
            "SELECT COALESCE(o1.EQO_LIB || ' K' || c1.CAS_NUM || ' P' || p1.POS_NUM, '?') || ' → ' || COALESCE(o2.EQO_LIB, '?') "
            "FROM optique.OPT_ROUTE_FIBRE f1 JOIN optique.OPT_ROUTE_FIBRE f2 ON f2.RTE_KEY = f1.RTE_KEY "
            "AND f2.ROF_RANG = (SELECT MAX(ROF_RANG) FROM optique.OPT_ROUTE_FIBRE WHERE RTE_KEY = f1.RTE_KEY) "
            "LEFT JOIN optique.OPT_POSITION p1 ON p1.POS_ID = (SELECT MIN(POS_ID) FROM optique.OPT_POSITION "
            f"WHERE FIB2_KEY = f1.FIB_KEY AND PFON_KEY = {self.pfon['CO']}) "
            "LEFT JOIN optique.OPT_CASSETTE c1 ON c1.CAS_ID = p1.CAS_KEY "
            "LEFT JOIN optique.OPT_EQUIPEMENT o1 ON o1.EQU_KEY = c1.EQU_KEY "
            "LEFT JOIN optique.OPT_POSITION p2 ON p2.POS_ID = (SELECT MIN(POS_ID) FROM optique.OPT_POSITION "
            f"WHERE f2.FIB_KEY IN (FIB1_KEY, FIB2_KEY) AND PFON_KEY = {self.pfon['AT']}) "
            "LEFT JOIN optique.OPT_CASSETTE c2 ON c2.CAS_ID = p2.CAS_KEY "
            "LEFT JOIN optique.OPT_EQUIPEMENT o2 ON o2.EQU_KEY = c2.EQU_KEY "
            "WHERE f1.RTE_KEY = OPT_ROUTE.RTE_ID AND f1.ROF_RANG = (SELECT MIN(ROF_RANG) FROM optique.OPT_ROUTE_FIBRE "
            "WHERE RTE_KEY = OPT_ROUTE.RTE_ID))")
        self.rapport.append(f'optique : {len(self.fib)} fibres, {len(self.cas)} cassettes, '
                            f'{self.un("SELECT COUNT(*) FROM optique.OPT_POSITION")} positions, {len(routes)} routes')

    def locaux(self):
        con = self.con
        for sf, ad, zp, escal, etage, typ, local, racco, comment, crea in con.execute(
                'SELECT s.sf_code, s.sf_ad_code, z.zp_bp_code, s.sf_escal, s.sf_etage, s.sf_type, s.sf_local, s.sf_racco, '
                's.sf_comment, s.sf_creadat FROM grc.t_suf s LEFT JOIN grc.t_zpbo_patch201 z ON z.zp_code = s.sf_zp_code'
                ).fetchall():
            self.inserer('immeuble.IMB_LOCAL', {
                'LOC_CODE_EXT': f'{P}-{sf}', 'ADR_KEY': self.adr[ad], 'LTYP_KEY': self.ltyp.get(typ),
                'RACCO_KEY': self.racco.get(racco), 'LOC_ESCALIER': escal, 'LOC_ETAGE': etage, 'LOC_LIB': local,
                'EQU_KEY': self.equ.get(zp), 'LOC_COMMENT': comment, 'DATE_CREA': iso(crea), 'SRC_MODIF': 'import'})
        self.rapport.append(f'locaux : {self.un("SELECT COUNT(*) FROM immeuble.IMB_LOCAL")}, '
                            f'{self.un("SELECT COUNT(*) FROM immeuble.IMB_LOCAL WHERE EQU_KEY IS NOT NULL")} rattachés à '
                            f'leur PBO ; immeubles : {self.un("SELECT COUNT(*) FROM PRJ_NOE WHERE TYPE_KEY = ?", self.types["IMM"])}')

    # -- études COMAC --------------------------------------------------------------------------

    def etudes(self):
        """Une rue peut avoir deux études (Rue Carnot, Rue Carnot 1) et un appui d'angle figurer dans celles de deux
        rues, son nom suffixé de -IN (insuffisant) dans l'une seulement : un nœud reçoit toutes les études d'un même
        nom. Appuis rapprochés des poteaux, supports de classe FACADE des façades (journal et photos seulement)."""
        appuis, conclusions, photos = etudes_comac(self.zcalc, self.qgis)
        supports = {famille: self.con.execute(
            'SELECT n.NOE_ID, X(n.GEOMETRY), Y(n.GEOMETRY) FROM PRJ_NOE n JOIN DEF_TYPE t ON t.TYPE_ID = n.TYPE_KEY '
            f"WHERE t.TYPE_CODE {'LIKE' if famille == 'POT' else '='} ?", (famille + '%' if famille == 'POT' else famille,)
            ).fetchall() for famille in ('POT', 'FAC')}
        nom_de = lambda a: re.sub(r'-IN$', '', a['nom'])
        paires = sorted((math.hypot(x - a['x'], y - a['y']), cle, noe) for cle, a in appuis.items()
                        for noe, x, y in supports['FAC' if (a['classe'] or '').upper() == 'FACADE' else 'POT']
                        if math.hypot(x - a['x'], y - a['y']) <= RAPPROCHEMENT_COMAC)
        pris = {}
        for d, cle, noe in paires:
            if cle in self.comac or pris.get(noe, nom_de(appuis[cle])) != nom_de(appuis[cle]):
                continue
            self.comac[cle] = noe
            pris[noe] = nom_de(appuis[cle])
        mat = 0
        for cle, noe in self.comac.items():
            a = appuis[cle]
            h, classe, eff = a['hauteur'], (a['classe'] or '').strip(), a['effort']
            ref = f'{h:g} {classe} {eff:g}'.replace('.', ',') if h and classe and eff else None
            facade = classe.upper() == 'FACADE'
            if not facade:
                mat_key = self.mat_pot.get(ref)
                mat += mat_key is not None
                self.con.execute(
                    'UPDATE poteau.POT_POTEAU SET MAT_KEY = COALESCE(?, MAT_KEY), POT_HAUTEUR = COALESCE(?, POT_HAUTEUR), '
                    'POT_EFFORT = COALESCE(?, POT_EFFORT), POT_ANNEE = COALESCE(?, POT_ANNEE), '
                    'POT_ANG_CARTO = COALESCE(?, POT_ANG_CARTO) WHERE NOE_KEY = ?',
                    (mat_key, h or None, round(eff * 100) if eff else None, a.get('annee'),
                     round(a['orientation'] % 400, 1) if a.get('orientation') is not None else None, noe))
            c = conclusions.get(a['nom']) if a.get('type') else None
            texte = (f'Étude COMAC de l\'APD ({a["rue"]}) : {"façade" if facade else "appui"} {a["nom"]}'
                     + (f', {ref or f"{h:g} m classe {classe}"}' if h and classe and not facade else '')
                     + (f', {a["annee"]}' if a.get('annee') else '')
                     + (f', {a["traverses"]} traverse(s) existante(s)' if a.get('traverses') is not None else ''))
            if c and c['conclusion']:
                taux = f'taux global après pose {c["taux"]:.1f} %'.replace('.', ',') if c['taux'] is not None else None
                texte += ' ; ' + ' : '.join(x for x in (taux, c['conclusion'].strip()) if x) + (
                    f' ({c["commentaire"].strip()})' if c['commentaire'] else '')
            alerte = bool(c) and (c['conclusion'] or '').strip().lower().startswith('insuffisant')
            self.commentaire('PRJ_NOE', noe, f'comac:{cle[0]}:{cle[1]}', texte, 'BE', 'alert' if alerte else 'standard',
                             a.get('date'))
            self.stats['appuis COMAC en alerte'] += alerte
            for z, m in photos.get(cle, []):
                self.photos_comac.append((noe, cle[0], a['nom'], z, m))
        par_nom = defaultdict(set)
        for cle, noe in self.comac.items():
            par_nom[nom_de(appuis[cle])].add(noe)
        self.par_nom = {nom: next(iter(s)) for nom, s in par_nom.items() if len(s) == 1}
        self.rapport.append(f'COMAC : {len(appuis)} supports étudiés, {len(self.comac)} études rapprochées à '
                            f'{RAPPROCHEMENT_COMAC} m au plus de {len(pris)} nœuds ('
                            f'{len(set(pris) & {r[0] for r in supports["POT"]})} poteaux, dont {mat} études donnant '
                            f'leur référence MAT_POTEAU), {self.stats["appuis COMAC en alerte"]} études concluant à un '
                            f'appui insuffisant')

    def joindre_photos_comac(self):
        """Photos des études COMAC, après celles du DOE (une photo Kizeo reste la principale de sa vue) : vue attendue
        ou visuel libre selon le classement de COMAC_VUES (rue, fichier), sinon visuel libre « Étude COMAC (APD) ».
        Un appui étudié dans deux rues a ses photos dans les deux archives, réencodées (contenus différents) : une
        seule copie par nœud et nom de fichier, au suffixe -IN près."""
        classement = lire_comac_vues()
        vus = set()
        for noe, rue, nom, z, m in self.photos_comac:
            base = os.path.basename(m)
            cle = (noe, re.sub(r'(?i)-IN(?=_)', '', base).lower())
            if cle in vus:
                continue
            vus.add(cle)
            code, remarque = classement.get((rue, base), (None, None))
            vue = self.vue(noe, code) if code in ('TETE', 'ENSEMBLE') else None
            self.stats['photos COMAC ' + ('en vue attendue' if vue else 'en visuel libre')] += 1
            self.fichier('PRJ_NOE', noe, z.read(m), os.path.join('photos', P, 'comac', rue, base), f'comac:{rue}:{m}',
                         vue=vue, visuel=None if vue else VISUELS_COMAC.get(code, 'Étude COMAC (APD)'),
                         date=date_zip(z.getinfo(m)),
                         comment=f'Étude COMAC de l\'APD ({rue}, appui {nom}), avant travaux'
                                 + (f' ; {remarque}' if remarque else ''))

    # -- photos, documents, mesures --------------------------------------------------------------

    def noeud_lib(self, lib):
        return self.un('SELECT NOE_ID FROM PRJ_NOE WHERE NOE_LIB = ?', lib)

    def documents(self, zone):
        z = self.zdoe
        dossier = os.path.join('documents', P)
        sro = self.noeud_lib('SRO-2-02HG')
        boite = re.compile(r'((?:PBO|BPE)-\d-\d{2}HG-\d{4})')
        for n in sorted(z.namelist()):
            if n.endswith('/'):
                continue
            base, ext = os.path.basename(n), os.path.splitext(n)[1].lower()
            if n.startswith('11_PHOTOS/01_BOITES/'):
                lib = boite.search(base).group(1)
                e = self.eqo.get(lib)
                if e is None:
                    self.stats['rapports de boîte sans boîtier'] += 1
                    continue
                noe = self.un('SELECT NOE_KEY FROM infra.INF_EQUIPEMENT WHERE EQU_ID = ?', e)
                # galerie propre du boîtier (vues de l'équipement) ; images d'un rapport hors Kizeo : visuel libre
                self.stats['images boîtes'] += self.rapport_photos(z, n, 'INF_EQUIPEMENT', e, noe, os.path.join('photos', P, lib),
                                                            visuel=VISUEL_BOITIER)
            elif n.startswith('11_PHOTOS/02_TIRAGE/'):
                # support nommé (façade, appui, chambre), sinon PBO de la zone (SRO-2-02HG_<n° de zone>_…)
                support = re.search(r'((?:FAC|POT|CHA)-\d-(?:\d{2}HG-)?\d{4})', base)
                zone_pbo = re.match(r'SRO-2-02HG_(\d{4})_', base)
                lib = support.group(1) if support else f'PBO-2-02HG-{zone_pbo.group(1)}' if zone_pbo else None
                noe = self.noeud_lib(lib) if support else self.un(
                    'SELECT NOE_KEY FROM infra.INF_EQUIPEMENT WHERE EQU_ID = ?', self.eqo.get(lib))
                if noe is None:
                    self.stats['rapports de tirage sans support'] += 1
                    continue
                self.stats['images tirage'] += self.rapport_photos(z, n, 'PRJ_NOE', noe, noe, os.path.join('photos', P, lib),
                                                            visuel='Tirage')
            elif n.startswith('11_PHOTOS/03_POTEAUX/'):
                lib = n.split('/')[2]
                if self.noeud_lib(lib):
                    self.membre(z, n, 'PRJ_NOE', self.noeud_lib(lib), os.path.join('photos', P, lib),
                                visuel='Appui (DOE)')
                else:
                    self.stats['photos sans appui'] += 1
            elif n.startswith('03_SRO/photo/'):
                if ext == '.pdf':
                    self.images(z, n, 'PRJ_NOE', sro, os.path.join('photos', P, 'SRO-2-02HG'), visuel='Armoire')
                else:
                    code = os.path.splitext(base)[0][4:].split(' ')[0].upper()
                    vue = self.vue(sro, {'FERME': 'FERME', 'OUVERT': 'OUVERT', 'ETIQUETTE': 'ETIQUETTE',
                                         'TIROIR': 'TIROIR', 'FOURREAU': 'FOURREAU', 'MISE_A_TERRE': 'TERRE'}.get(
                        re.sub(r'_(ENTREE|SORTIE)$', '', code)))
                    self.membre(z, n, 'PRJ_NOE', sro, os.path.join('photos', P, 'SRO-2-02HG'), vue,
                                None if vue else 'SRO')
            elif n.startswith(('03_SRO/', '05_ROUTE_OPTIQUE/', '06_SYNOPTIQUE/')):
                self.membre(z, n, 'PRJ_NOE', sro, os.path.join(dossier, 'SRO-2-02HG'))
            elif n.startswith('04_PLAN_DE_BOITE/'):
                lib = boite.search(base).group(1)
                if lib in self.eqo:
                    self.membre(z, n, 'INF_EQUIPEMENT', self.eqo[lib], os.path.join(dossier, lib),
                                comment='Plan de boîte')
                else:
                    self.membre(z, n, 'PRJ_ZONE', zone, os.path.join(dossier, 'plans_de_boite'), comment='Plan de boîte')
                    self.stats['plans de boîte sans boîtier'] += 1
            elif n.startswith(('07_GC/', '12_CONVENTION')):
                self.membre(z, n, 'PRJ_ZONE', zone, os.path.join(dossier, *n.split('/')[:-1]))
            elif n.startswith('09_IMMEUBLES/'):
                m = re.match(r'CONVENTION IMMEUBLE-(\d+)-(.+?)-\d{5}-', base)
                a = self.un('SELECT ADR_ID FROM PRJ_ADRESSE WHERE ADR_NUMERO = ? AND upper(ADR_VOIE) = ?',
                            int(m.group(1)), m.group(2).upper()) if m else None
                if a:
                    self.membre(z, n, 'PRJ_ADRESSE', a, os.path.join(dossier, 'immeubles'), comment='Convention d\'immeuble')
                    self.stats['conventions'] += 1
                else:
                    self.membre(z, n, 'PRJ_ZONE', zone, os.path.join(dossier, 'immeubles'))
                    self.stats['conventions sans adresse'] += 1
            elif n.startswith('10_INFRA-TIERS/EVICOM/'):
                noe = self.par_nom.get(nom_photo(n.split('/')[2]))
                if ext in ('.jpg', '.png') and noe:
                    self.membre(z, n, 'PRJ_NOE', noe, os.path.join('photos', P, 'evicom', n.split('/')[2]),
                                visuel='Infrastructure tierce Evicom')
                    self.stats['photos infrastructure tierce'] += 1
                elif ext not in ('.jpg', '.png'):
                    self.membre(z, n, 'PRJ_ZONE', zone, os.path.join(dossier, 'infra_tiers'))
                else:
                    self.stats['photos infrastructure tierce sans appui'] += 1
            elif n.startswith('08_MESURES/02-LASER/'):
                m = re.search(r'(?i)pb[o]?[-_ ]?(\d{4})', n.split('/')[2])
                e = self.eqo.get(f'PBO-2-02HG-{m.group(1)}') if m else None
                if e and ext in MIME:
                    self.membre(z, n, 'INF_EQUIPEMENT', e, os.path.join('photos', P, f'PBO-2-02HG-{m.group(1)}'),
                                vue=self.vues_equ['MESURES'])
                    self.stats['photos de photométrie'] += 1

    def mesures(self):
        """Synthèses réflectométriques (MESURE-*.txt) → OPT_MESURE ; synthèses jointes au boîtier d'extrémité, traces
        .sor à leur mesure."""
        z, con = self.zdoe, self.con
        routes = {}
        for rte, premier, libs in con.execute(
                'SELECT r.RTE_ID, (SELECT f.FIB_NUM FROM optique.OPT_ROUTE_FIBRE x JOIN optique.OPT_FIBRE f '
                'ON f.FIB_ID = x.FIB_KEY WHERE x.RTE_KEY = r.RTE_ID ORDER BY x.ROF_RANG LIMIT 1), '
                "(SELECT group_concat(c.CAB_LIB, '|') FROM optique.OPT_ROUTE_FIBRE x JOIN optique.OPT_FIBRE f "
                'ON f.FIB_ID = x.FIB_KEY JOIN optique.OPT_CABLE c ON c.CAB_ID = f.CAB_KEY WHERE x.RTE_KEY = r.RTE_ID) '
                'FROM optique.OPT_ROUTE r').fetchall():
            for lib in set((libs or '').split('|')):
                routes.setdefault((lib, premier), []).append(rte)
        noms = set(z.namelist())
        n = sans_route = 0
        vus = set()
        for nom in sorted(x for x in noms if re.search(r'08_MESURES/01-MESURE/.*/MESURE-[^/]*\.txt$', x)):
            dossier_cable = nom.rsplit('/', 1)[0]
            tete, mesures = lire_mesure(z.read(nom).decode('utf-16'))
            suffixe = dossier_cable.rsplit('/', 1)[1].split('-', 1)[1]          # CDI-2-02HG-1015 → 2-02HG-1015
            e = next((self.eqo[f'{t}-{suffixe}'] for t in ('PBO', 'BPE') if f'{t}-{suffixe}' in self.eqo), None)
            for doc in sorted(x for x in noms if x.startswith(dossier_cable + '/MESURE-')):
                self.membre(z, doc, 'INF_EQUIPEMENT' if e else 'PRJ_ZONE', e or self.zone,
                            os.path.join('documents', P, 'mesures', suffixe), comment='Synthèse des mesures réflectométriques')
            sens = SENS.get((tete.get('Sens') or [''])[0])
            for (cable, fibre, lam), m in sorted(mesures.items()):
                code = f'{P}-M-{cable}-{fibre}-{lam}-{sens}'
                if code in vus:
                    self.stats['mesures en double'] += 1
                    continue
                vus.add(code)
                lib = cable.split('_')[0]
                trouvees = routes.get((lib, fibre), [])
                rte = trouvees[0] if len(trouvees) == 1 else None
                sans_route += rte is None
                fib = self.un('SELECT FIB_KEY FROM optique.OPT_ROUTE_FIBRE WHERE RTE_KEY = ? ORDER BY ROF_RANG LIMIT 1',
                              rte) if rte else None
                mes = self.inserer('optique.OPT_MESURE', {
                    'MES_CODE_EXT': code, 'MMET_KEY': 1, 'RTE_KEY': rte, 'FIB_KEY': fib,
                    'EQU_KEY': e, 'MES_CABLE': cable, 'MES_FIBRE': fibre,
                    'MES_ORIGINE': (tete.get('Origine') or [None])[0], 'MES_EXTREMITE': (tete.get('Extrémité') or [None])[0],
                    'MES_LAMBDA': lam, 'MES_SENS': sens, 'MES_LNG': m['lng'], 'MES_PERTE': m['perte'],
                    'MES_EVT_MAX': m['evt_max'], 'MES_PENTE_MAX': m['pente_max'], 'MES_ORL': m['orl'],
                    'MES_CONFORME': m['conforme'], 'MES_APPAREIL': (tete.get('Appareil de mesure') or [None])[0] or None,
                    'MES_DATE': m['date'], 'SRC_MODIF': 'import'})
                n += 1
                sor = f'{dossier_cable}/{m["fichier"]}' if m['fichier'] else None
                if sor in noms:
                    self.membre(z, sor, 'OPT_MESURE', mes, os.path.join('documents', P, 'mesures', suffixe),
                                comment='Trace réflectométrique')
        self.rapport.append(f'mesures : {n} réflectométries, {n - sans_route} rattachées à leur route, '
                            f'{self.un("SELECT COUNT(*) FROM optique.OPT_MESURE WHERE MES_CONFORME = 0")} hors seuils')

    def raccordements(self):
        """Câbles de raccordement de la base FibReady (CAB_TYPE RAC) : amont, le PBO (NOEUDS.NOEID = NOE_AMONT_KEY, son
        étiquette NOE_CODEXT est celle du boîtier chargé) ; aval, la boîte aux lettres (NOEUDS de type LRI dont
        CAB_AMONT_KEY désigne le câble), dont l'adresse GraceTHD (ad_code) est donnée par la table de correspondance
        L_FBT_GRA (GRA_TBL T_ADRESSE ; NOE_CODEXT est l'identifiant national de l'adresse), à défaut par la voie, le
        numéro et le complément de la BAL (immeuble collectif : une seule adresse exportée). Câble ignoré, compté au
        rapport, si son PBO ou son adresse n'est pas retrouvé."""
        fbt = os.path.join(self.source, FIBREADY)
        f = sqlite3.connect(Path(os.path.abspath(fbt)).as_uri() + '?mode=ro', uri=True)
        try:
            lignes = f.execute(
                "SELECT c.CAB_ID, c.CAB_CAPA, c.CAB_MODULO, c.CAB_LNG, c.CAB_POSE, c.Geometry, a.NOE_CODEXT, "
                "g.GRA_CODE, b.STREET, b.ADRNUM, b.ADRCPLT FROM CABLES c LEFT JOIN NOEUDS a ON a.NOEID = c.NOE_AMONT_KEY "
                "LEFT JOIN NOEUDS b ON b.CAB_AMONT_KEY = c.CAB_ID AND b.NOE_TYPE = 'LRI' "
                "LEFT JOIN L_FBT_GRA g ON g.FBT_TBL = 'NOEUDS' AND g.FBT_KEY = b.NOEID AND g.GRA_TBL = 'T_ADRESSE' "
                "WHERE c.CAB_TYPE = 'RAC' ORDER BY a.NOE_CODEXT, c.CAB_ID").fetchall()
        finally:
            f.close()
        poses = {'AER': 'aérienne', 'FOU': 'en fourreau', 'IMM': 'en immeuble'}
        cle = lambda voie, num, rep: (str(voie or '').strip().upper(), str(num or '').strip(), str(rep or '').strip().upper())
        par_voie = defaultdict(list)
        for code, voie, num, rep in self.con.execute('SELECT ad_code, ad_nomvoie, ad_numero, ad_rep FROM grc.t_adresse'):
            par_voie[cle(voie, num, rep)].append(code)
        rangs, n, sans_pbo, sans_adr, sans_trace, par_voie_n, retournes = Counter(), Counter(), 0, 0, 0, 0, 0
        for cid, capa, modulo, lng, pose, geom, pbo, ad, voie, num, rep in lignes:
            e, a = self.eqo.get(pbo), self.adr.get(ad)
            if a is None:
                # BAL d'un immeuble collectif : l'export GraceTHD n'a gardé qu'une adresse par immeuble, que l'on
                # retrouve par la voie, le numéro et le complément (BIS, TER)
                m = par_voie.get(cle(voie, num, rep), [])
                a = self.adr.get(m[0]) if len(m) == 1 else None
                par_voie_n += a is not None
            if e is None:
                sans_pbo += 1
                continue
            if a is None:
                sans_adr += 1
                continue
            rangs[pbo] += 1
            lib = f'RAC-{pbo.split("-", 1)[1]}-{rangs[pbo]:02d}' if '-' in pbo else f'RAC-{pbo}-{rangs[pbo]:02d}'
            c = self.inserer('optique.OPT_CABLE', {
                'CAB_CODE_EXT': f'{P}-FBT-RAC-{cid}', 'CAB_LIB': lib, 'CFON_KEY': self.cfon['RA'],
                'CAB_CAPA': entier(capa), 'CAB_MODULO': entier(modulo),
                'NOE1_KEY': self.un('SELECT NOE_KEY FROM infra.INF_EQUIPEMENT WHERE EQU_ID = ?', e), 'EQU1_KEY': e,
                'ADR2_KEY': a, 'CAB_LNG': reel(lng), 'AVCT_KEY': self.avct['C'],
                'CAB_COMMENT': f'Raccordement FibReady, pose {poses.get(pose, pose or "inconnue")}',
                'SRC_MODIF': 'import'})
            # tracé FibReady, ligne en Lambert 93 ; autre forme : sans tracé (CastToLinestring rend NULL) ; FibReady le
            # dessine de la BAL au PBO : retourné pour aller du PBO (NOE1) à l'adresse, comme le câble
            if geom is not None:
                self.con.execute('UPDATE optique.OPT_CABLE SET GEOMETRY = CastToLinestring(SetSRID(?, 2154)) '
                                 'WHERE CAB_ID = ?', (geom, c))
                retournes += self.con.execute(
                    'UPDATE optique.OPT_CABLE SET GEOMETRY = ST_Reverse(GEOMETRY) WHERE CAB_ID = ? '
                    'AND Distance(StartPoint(GEOMETRY), (SELECT GEOMETRY FROM PRJ_ADRESSE WHERE ADR_ID = ADR2_KEY)) < '
                    'Distance(StartPoint(GEOMETRY), (SELECT GEOMETRY FROM PRJ_NOE WHERE NOE_ID = NOE1_KEY))',
                    (c,)).rowcount
            if self.un('SELECT GEOMETRY IS NULL FROM optique.OPT_CABLE WHERE CAB_ID = ?', c):
                sans_trace += 1
            n[pose] += 1
        self.rapport.append(
            f'raccordements (FibReady) : {sum(n.values())} câbles du PBO à l\'adresse '
            f'({", ".join(f"{poses.get(k, k)} {v}" for k, v in sorted(n.items()))}), {len(rangs)} PBO, '
            f'{sans_trace} sans tracé, {retournes} tracés retournés (du PBO à l\'adresse), {par_voie_n} adresses retrouvées par la voie et le numéro (BAL d\'immeuble '
            f'absente de l\'export GraceTHD) ; ignorés : {sans_pbo} sans PBO chargé, {sans_adr} sans adresse chargée')

    def finir(self, zone):
        """État et taux d'occupation des conduites (projet.recalculer_occupation : sans diamètre, les câbles du DOE ne
        donnent pas de taux) ; emprise de la zone : zone du SRO GraceTHD et nœuds du projet à 50 m ; intervention
        d'import."""
        projet.recalculer_occupation(self.con)
        self.con.execute(
            'UPDATE PRJ_ZONE SET GEOMETRY = (SELECT CastToMultiPolygon(GUnion((SELECT geom FROM grc.t_zsro LIMIT 1), '
            'Buffer(ConvexHull(Collect(n.GEOMETRY)), 50))) FROM PRJ_NOE n WHERE n.ZONE_KEY = ?) WHERE ZONE_ID = ?',
            (zone, zone))
        self.con.execute("INSERT INTO PRJ_INTERVENTION (INT_CODE_EXT, INT_LIB, ACT_CODE, INT_AUTEUR, DATE_DEBUT, "
                         "INT_STATUT) VALUES ('IMPORT-DOE', 'Chargement du DOE Evicom SRO-2-02HG', 'IMPORT', "
                         "'tools/essai', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 'INTEGREE')")
        i = self.dernier()
        for table, pk in (('PRJ_NOE', 'NOE_ID'), ('PRJ_LINEAIRE', 'LIN_ID'), ('PRJ_ADRESSE', 'ADR_ID')):
            self.con.execute(f"INSERT INTO PRJ_INT_OBJET (INT_KEY, ENT_KEY, OBJ_KEY, IOB_ACTION) SELECT ?, ?, {pk}, 'C' "
                             f'FROM {table}', (i, self.ent[table]))


def fibready(ch):
    """Contrôle croisé avec la base FibReady du DOE (l'export GraceTHD en est tiré) : chaque équipement FibReady
    (boîtier : nœud EQU hors points d'infrastructure PDT) est attaché à son support par INF_KEY (attaches du plan) ;
    il doit être sur le même support que le boîtier chargé de même étiquette (bp_pt_code de GraceTHD)."""
    fbt = os.path.join(ch.source, FIBREADY)
    if not os.path.isfile(fbt):
        return f'{FIBREADY} absente'
    f = sqlite3.connect(Path(os.path.abspath(fbt)).as_uri() + '?mode=ro', uri=True)
    try:
        supports = dict(f.execute('SELECT ID, noe_codext FROM TEMP_INFRA_POINTS'))
        attendus = {lib: supports.get(k) for lib, k in f.execute(
            "SELECT NOE_CODEXT, INF_KEY FROM NOEUDS WHERE NOE_TYPE = 'EQU' AND TYPE IN ('PBO', 'BPE')")}
    finally:
        f.close()
    charges = dict(ch.con.execute(
        'SELECT o.EQO_LIB, n.NOE_LIB FROM optique.OPT_EQUIPEMENT o JOIN infra.INF_EQUIPEMENT e ON e.EQU_ID = o.EQU_KEY '
        'JOIN PRJ_NOE n ON n.NOE_ID = e.NOE_KEY'))
    ecarts = [(lib, sup, charges.get(lib)) for lib, sup in sorted(attendus.items()) if charges.get(lib) != sup]
    return (f'{len(attendus) - len(ecarts)} sur {len(attendus)} au même support'
            + (f', écarts (boîtier, FibReady, chargé) : {ecarts[:10]}' if ecarts else ''))


def controles(ch):
    con = ch.con
    q = lambda s: con.execute(s).fetchall()
    print('\nContrôles :')
    print('  orphelins :', [o for o in projet.orphelins(con) if o[1]] or 'aucun')
    print('  équipements sans support :', q('SELECT COUNT(*) FROM infra.INF_EQUIPEMENT WHERE NOE_KEY IS NULL')[0][0])
    print('  équipements par fonction :', q(
        'SELECT t.OTYP_CODE, COUNT(*), SUM(o.AVCT_KEY = 2) FROM optique.OPT_EQUIPEMENT o '
        'JOIN optique.DEF_OPT_EQUIP_TYPE t ON t.OTYP_ID = o.OTYP_KEY GROUP BY 1'))
    print('  boîtiers sur leur support d\'après la base FibReady :', fibready(ch))
    print('  photos des rapports par vue :', q(
        "SELECT COALESCE(v.VUE_CODE, 'libre : ' || f.VIS_LIB), COUNT(*) FROM PRJ_FICHIER f "
        "LEFT JOIN DEF_VUE v ON v.VUE_ID = f.VUE_KEY WHERE f.FIC_COMMENT LIKE '%(extraite de %' "
        "AND f.FIC_TYPE LIKE 'image/%' GROUP BY 1 ORDER BY 2 DESC"))
    print('  câbles sans passage (colonne d\'immeuble comprise, raccordements exclus) :', q(
        'SELECT COUNT(*) FROM optique.OPT_CABLE c WHERE c.ADR2_KEY IS NULL AND NOT EXISTS (SELECT 1 FROM '
        'optique.OPT_PASSAGE p WHERE p.CAB_KEY = c.CAB_ID)')[0][0])
    print('  raccordements : câbles, avec tracé, longueur réelle et tracée (km), adresses, PBO :', q(
        'SELECT COUNT(*), COUNT(GEOMETRY), round(SUM(CAB_LNG) / 1000, 2), round(SUM(GLength(GEOMETRY)) / 1000, 2), '
        'COUNT(DISTINCT ADR2_KEY), COUNT(DISTINCT EQU1_KEY) FROM optique.OPT_CABLE WHERE ADR2_KEY IS NOT NULL')[0])
    print('  occupation des conduites :', projet.resume_occupation(con), '; diamètres nominaux :', q(
        'SELECT CD_DIAM, COUNT(*) FROM infra.INF_CONDUITE GROUP BY 1 ORDER BY 1'))
    print('  passages sans ligne de l\'infra :', q(
        'SELECT COUNT(*) FROM optique.OPT_PASSAGE WHERE PCB_KEY IS NULL AND CDC_KEY IS NULL')[0][0])
    print('  fibres par câble conformes à la capacité (raccordements exclus, sans fibres) :', q(
        'SELECT SUM(n = CAB_CAPA), COUNT(*) FROM (SELECT c.CAB_CAPA, COUNT(f.FIB_ID) n FROM optique.OPT_CABLE c '
        'LEFT JOIN optique.OPT_FIBRE f ON f.CAB_KEY = c.CAB_ID WHERE c.ADR2_KEY IS NULL GROUP BY c.CAB_ID)')[0])
    print('  positions par fonction :', q(
        'SELECT d.PFON_CODE, COUNT(*) FROM optique.OPT_POSITION p JOIN optique.DEF_POS_FONCTION d '
        'ON d.PFON_ID = p.PFON_KEY GROUP BY 1'))
    print('  exemple de route :', q('SELECT RTE_CODE_EXT, RTE_LIB, (SELECT COUNT(*) FROM optique.OPT_ROUTE_FIBRE '
                                    'WHERE RTE_KEY = RTE_ID) FROM optique.OPT_ROUTE ORDER BY RTE_ID LIMIT 2'))
    print('  exemple de mesure :', q(
        'SELECT m.MES_CABLE, m.MES_FIBRE, m.MES_LAMBDA, m.MES_LNG, m.MES_PERTE, m.MES_CONFORME, r.RTE_LIB '
        'FROM optique.OPT_MESURE m LEFT JOIN optique.OPT_ROUTE r ON r.RTE_ID = m.RTE_KEY ORDER BY m.MES_ID LIMIT 2'))
    print('  poteaux par type et référence :', q(
        'SELECT t.TYPE_CODE, COUNT(*), COUNT(p.MAT_KEY), COUNT(p.POT_HAUTEUR) FROM poteau.POT_POTEAU p '
        'JOIN PRJ_NOE n ON n.NOE_ID = p.NOE_KEY JOIN DEF_TYPE t ON t.TYPE_ID = n.TYPE_KEY GROUP BY 1'))
    print('  chambres par référence :', q(
        'SELECT m.MAT_LIB, COUNT(*) FROM chambre.CHB_CHAMBRE c LEFT JOIN chambre.MAT_CHAMBRE m ON m.MAT_ID = c.MAT_KEY '
        'GROUP BY 1'))
    print('  portées (angles calculés) et câbles portés :', q(
        'SELECT COUNT(*), SUM(PRT_ANG1 IS NOT NULL AND PRT_ANG2 IS NOT NULL), (SELECT COUNT(*) FROM '
        'infra.INF_PORTEE_CABLE) FROM infra.INF_PORTEE')[0])
    print('  BAL : adresses, habitat, logements :', q(
        'SELECT h.HAB_LIB, COUNT(*), SUM(i.IAD_NB_LOG) FROM immeuble.IMB_ADRESSE i LEFT JOIN immeuble.DEF_IMB_HABITAT h '
        'ON h.HAB_ID = i.HAB_KEY GROUP BY 1'))
    print('  fichiers par entité et type :', q(
        'SELECT e.ENT_TABLE, f.FIC_TYPE, COUNT(*) FROM PRJ_FICHIER f JOIN DEF_ENTITE e ON e.ENT_ID = f.ENT_KEY '
        'GROUP BY 1, 2 ORDER BY 1, 2'))
    print('  photos principales en double (objet, vue) :', q(
        'SELECT COUNT(*) FROM (SELECT 1 FROM PRJ_FICHIER WHERE FIC_PRINCIPALE = 1 GROUP BY ENT_KEY, OBJ_KEY, '
        'VUE_KEY, VIS_CODE HAVING COUNT(*) > 1)')[0][0])
    print('  journal (origine, type, nombre) :', q(
        'SELECT COM_ORIGINE, COM_TYPE, COUNT(*) FROM PRJ_COMMENTAIRE GROUP BY 1, 2'))
    print('  zone (emprise km²) :', q('SELECT ZONE_CODE_EXT, round(Area(GEOMETRY) / 1e6, 3) FROM PRJ_ZONE'))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    dossier, qgis = sys.argv[1:3]
    source = sys.argv[3] if len(sys.argv) > 3 else SOURCE
    if os.path.isdir(dossier):
        shutil.rmtree(dossier)
    for _ in projet.construire(dossier, charger_essai.ESSONNE, qgis, *PROJET):
        pass
    zdoe = zipfile.ZipFile(os.path.join(source, DOE))
    zcalc = zipfile.ZipFile(os.path.join(source, CALCULS))
    os.makedirs(os.path.join(dossier, 'sources'), exist_ok=True)
    grace = base_grace(zdoe, os.path.join(dossier, 'sources'), qgis)
    ch = Doe(dossier, qgis, zdoe, zcalc)
    ch.qgis = qgis
    ch.source = source
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
        ch.raccordements()
        ch.etudes()
        ch.documents(zone)
        ch.joindre_photos_comac()
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
    controles(ch)


if __name__ == '__main__':
    main()
