"""Jeu d'essai sur données réelles : charge dans un projet NgeEsPlorer (schema/) trois sources, une zone chacune.

- HEILLECOURT (FOA Explorer, Lambert II étendu bien que déclarée 2154) : chambres, alvéoles, masques, photos ;
- ESSONNE (FOA Explorer, Lambert II étendu) : chambres, alvéoles, occupation par câbles, liaisons entre chambres,
  destinations poteaux / façades / BAL / immeubles ;
- GRACE (export GraceTHD v2 de test, Lambert 93) : appuis, chambres, cheminements aériens (portées, angles calculés,
  câbles portés) et souterrains (conduites).

Règles de reprise FOA :
- alvéole d'une face réelle (A à D) → conduite sur le linéaire chambre → destination ; deux alvéoles de faces réelles
  appariées par ALV_DESTALV_KEY → une seule conduite, positionnée dans les deux chambres (miroir) ;
- copies « MIROIR_… » (face d'accueil non enregistrée) : non reprises, la conduite reste à placer côté destination ;
- destination absente ou inconnue → nœud « destination à localiser » à 1 m de la chambre (mode INDT) ;
- positions : grille FOA 9 x 12 cellules de 6,3 x 4,5 unités, origine en bas à gauche → colonne / ligne depuis le haut ;
- rotation FOA en degrés → grades ; dates Unix → ISO 8601.

Usage :
  python -I tools/essai/charger_essai.py <dossier projet> <dossier QGIS bin>
"""
import hashlib, math, os, shutil, sqlite3, sys, tempfile
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'schema'))
import projet  # noqa: E402

HEILLECOURT = r'c:\NoDrive\Documents\data\FOA\FTTH_OR_HEILLECOURT'
ESSONNE = r'c:\NoDrive\Documents\Etudes\essonne\09_DOU_12-13_FOA_EXP.db'
GRACE = r'c:\NoDrive\Documents\Etudes\Auvergne\projets\test_grace\data\Export\GraceTHD\test_grace_EXP_GRACETHD.sqlite'

FOA_COL, FOA_LIG, FOA_CASE_L, FOA_CASE_H = 9, 12, 6.3, 4.5
ETAT_FOA = {None: 'V', 0: 'V', 1: 'R', 2: 'X', 12: 'XR', 3: 'M'}
IMPLANT_FOA = {'chaussée': 'CHS', 'chaussee': 'CHS', 'trottoir': 'TRT', 'façade': 'FAC', 'facade': 'FAC'}
VUE_FOA = {'DESSUS': 'DESSUS', 'ENV': 'ENV', 'A': 'A', 'B': 'B', 'C': 'C', 'D': 'D', 'BOITIER': 'BOITIER'}


def iso(ts):
    if ts in (None, '', 0):
        return None
    if isinstance(ts, (int, float)):
        return datetime.fromtimestamp(ts, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    return str(ts).replace(' ', 'T')


class Chargeur:
    def __init__(self, dossier, qgis):
        self.dossier = dossier
        self.con = projet.ouvrir(dossier, qgis)
        self.rapport = []
        q = self.con.execute
        self.etat = {code: i for i, code in q('SELECT ETAT_ID, ETAT_CODE FROM infra.DEF_CD_ETAT')}
        self.imps = {code: i for i, code in q('SELECT IMPS_ID, IMPS_CODE FROM infra.DEF_SUPPORT_IMPLANT')}
        self.types = {code: i for i, code in q('SELECT TYPE_ID, TYPE_CODE FROM DEF_TYPE')}
        self.vues = {(t, code): i for i, t, code in q('SELECT VUE_ID, TYPE_KEY, VUE_CODE FROM DEF_VUE')}
        self.ent = {t: i for i, t in q('SELECT ENT_ID, ENT_TABLE FROM DEF_ENTITE')}
        self.indt = q("SELECT GMOD_ID FROM DEF_GEOL_MODE WHERE GMOD_CODE = 'INDT'").fetchone()[0]
        self.mat_chb = {lib: i for i, lib in q('SELECT MAT_ID, MAT_LIB FROM chambre.MAT_CHAMBRE')}

    def un(self, sql, *p):
        r = self.con.execute(sql, p).fetchone()
        return r[0] if r else None

    def dernier(self):
        return self.un('SELECT last_insert_rowid()')

    def zone(self, code, lib):
        self.con.execute('INSERT INTO PRJ_ZONE (ZONE_CODE_EXT, ZONE_LIB) VALUES (?, ?)', (code, lib))
        return self.dernier()

    def noeud(self, code, lib, type_id, geom_sql, geom_params, zone, adr=None, crea=None, modif=None,
              geol_mod=None, comment=None):
        self.con.execute(
            f'INSERT INTO PRJ_NOE (NOE_CODE_EXT, NOE_LIB, TYPE_KEY, ADR_KEY, ZONE_KEY, NOE_COMMENT, GEOL_MOD_KEY, '
            f'DATE_CREA, DATE_MODIF, SRC_MODIF, GEOMETRY) VALUES (?, ?, ?, ?, ?, ?, ?, '
            f"COALESCE(?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), ?, 'import', {geom_sql})",
            (code, lib, type_id, adr, zone, comment, geol_mod, crea, modif, *geom_params))
        return self.dernier()

    def lineaire(self, code, type_code, impl, n1, n2, zone, geom_sql=None, geom_params=(), lng=None):
        geom = geom_sql or ('(SELECT MakeLine(a.GEOMETRY, b.GEOMETRY) FROM PRJ_NOE a, PRJ_NOE b '
                            'WHERE a.NOE_ID = ? AND b.NOE_ID = ?)')
        params = geom_params if geom_sql else (n1, n2)
        self.con.execute(
            f'INSERT INTO PRJ_LINEAIRE (LIN_CODE_EXT, TYPE_KEY, IMPL_KEY, NOE1_KEY, NOE2_KEY, ZONE_KEY, LIN_LNG, '
            f"SRC_MODIF, GEOMETRY) VALUES (?, ?, ?, ?, ?, ?, ?, 'import', {geom})",
            (code, self.types[type_code], impl, n1, n2, zone, lng, *params))
        return self.dernier()

    def compter(self):
        tables = ['PRJ_ZONE', 'PRJ_ADRESSE', 'PRJ_NOE', 'PRJ_LINEAIRE', 'PRJ_FICHIER', 'PRJ_INTERVENTION',
                  'infra.INF_CONDUITE', 'infra.INF_CD_CABLE', 'infra.INF_PORTEE', 'infra.INF_PORTEE_CABLE',
                  'chambre.CHB_CHAMBRE', 'chambre.CHB_FACE', 'chambre.CHB_MASQUE_LOGIQUE', 'chambre.CHB_POSITION',
                  'poteau.POT_POTEAU']
        return {t: self.un(f'SELECT COUNT(*) FROM {t}') for t in tables}

    # FOA Explorer ------------------------------------------------------------------------------

    def charger_foa(self, prefixe, srid, zone_lib, photos=None):
        """Source attachée sous le nom « src »."""
        con, un = self.con, self.un
        zone = self.zone(prefixe, zone_lib)
        g = lambda col: f'Transform(SetSRID({col}, {srid}), 2154)' if srid != 2154 else f'SetSRID({col}, 2154)'

        # adresses référencées par les chambres
        adr = {}
        for a_id, num, rep, voie, com, cp, insee in con.execute(
                'SELECT a.ADR_ID, a.ADR_NUM, a.ADR_NUM2, v.VOIE_LIB, c.COM_LIB, c.COM_CP, c.COM_INSEE '
                'FROM src.ADR_ADRESSE a LEFT JOIN src.ADR_VOIE v ON v.VOIE_ID = a.VOIE_KEY '
                'LEFT JOIN src.ADR_COMMUNE c ON c.COM_ID = v.COM_KEY '
                'WHERE a.ADR_ID IN (SELECT ADR_KEY FROM src.PRJ_CHB_NOE)').fetchall():
            con.execute('INSERT INTO PRJ_ADRESSE (ADR_CODE_EXT, ADR_NUMERO, ADR_REP, ADR_VOIE, ADR_CP, ADR_INSEE, '
                        "ADR_COMMUNE, SRC_MODIF) VALUES (?, ?, ?, ?, ?, ?, ?, 'import')",
                        (f'{prefixe}-A{a_id}', num, rep or None, voie, cp, insee, com))
            adr[a_id] = self.dernier()

        # chambres
        chb, chb_noe = {}, {}
        for (n_id, lib, mat, adr_k, implant, larg, haut, lng, rot, statut, comment, crea, modif) in con.execute(
                'SELECT NOE_ID, NOE_LIB, MAT_KEY, ADR_KEY, CHB_IMPLANT, CHB_CUSTOM_LARG, CHB_CUSTOM_HAUT, '
                'CHB_CUSTOM_LNG, NOE_ROTATION, NOE_STATUT, NOE_COMMENT, DATE_CREA, DATE_MODIF '
                'FROM src.PRJ_CHB_NOE WHERE GEOMETRY IS NOT NULL').fetchall():
            noe = self.noeud(f'{prefixe}-C{n_id}', lib, self.types['CHB'],
                             f'(SELECT {g("GEOMETRY")} FROM src.PRJ_CHB_NOE WHERE NOE_ID = ?)', (n_id,), zone,
                             adr.get(adr_k), iso(crea), iso(modif))
            mat_k = un('SELECT MAT_ID FROM chambre.MAT_CHAMBRE WHERE MAT_ID = ?', mat) if mat else None
            con.execute('INSERT INTO chambre.CHB_CHAMBRE (NOE_KEY, MAT_KEY, IMPS_KEY, CHB_LNG, CHB_LARG, CHB_HAUT, '
                        "CHB_ROTATION, CHB_NIVEAU, CHB_COMMENT, SRC_MODIF) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'import')",
                        (noe, mat_k, self.imps.get(IMPLANT_FOA.get((implant or '').strip().lower())),
                         lng or None, larg or None, haut or None, rot * 400 / 360 if rot else None,
                         min(max(statut or 0, 0), 2), comment or None))
            chb[n_id], chb_noe[n_id] = self.dernier(), noe

        # autres nœuds FOA (poteaux, façades, BAL, immeubles) : destinations sans géométrie dans FOA, créées à
        # 1 m de la première chambre qui les cite (position indéterminée, à relever)
        geo, foa_geo = {}, {}
        types_geo = {13: ('POT', ''), 30: ('FAC', ''), 11: ('AUT', 'BAL '), 12: ('AUT', 'Immeuble ')}
        for n_id, t, lib in con.execute('SELECT NOE_ID, TYPE_KEY, NOE_LIB FROM src.PRJ_NOE_GEOM').fetchall():
            if t in types_geo:
                foa_geo[(n_id, t)] = lib

        def destination_geo(cle, noe_chb):
            if cle not in geo:
                code, pre = types_geo[cle[1]]
                geo[cle] = self.noeud(
                    f'{prefixe}-G{cle[1]}-{cle[0]}', f'{pre}{foa_geo[cle] or ""}'.strip() or None, self.types[code],
                    '(SELECT MakePoint(X(GEOMETRY) + 1, Y(GEOMETRY), 2154) FROM PRJ_NOE WHERE NOE_ID = ?)', (noe_chb,),
                    zone, geol_mod=self.indt, comment='Destination FOA sans géométrie : position à relever')
                if code == 'POT':
                    con.execute("INSERT INTO poteau.POT_POTEAU (NOE_KEY, SRC_MODIF) VALUES (?, 'import')", (geo[cle],))
            return geo[cle]

        # liaisons entre chambres (géométrie relevée)
        lin = {}
        for l_id, c1, c2 in con.execute('SELECT LNK_ID, CHB1_KEY, CHB2_KEY FROM src.PRJ_LNK_INTER_CHB '
                                        'WHERE GEOMETRY IS NOT NULL').fetchall():
            if c1 in chb_noe and c2 in chb_noe and c1 != c2:
                n1, n2 = chb_noe[c1], chb_noe[c2]
                lin[frozenset((n1, n2))] = self.lineaire(
                    f'{prefixe}-L{l_id}', 'LIN-SOUT', 7, n1, n2, zone,
                    f'(SELECT CastToLineString({g("GEOMETRY")}) FROM src.PRJ_LNK_INTER_CHB WHERE LNK_ID = ?)', (l_id,))

        # alvéoles des faces réelles → conduites, faces, masques logiques, positions
        faces, mlog, inconnue, conduite = {}, {}, {}, {}
        stats = dict(conduites=0, positions=0, miroirs=0, copies=0, inconnues=0, lineaires=0)
        stats['copies'] = un("SELECT COUNT(*) FROM src.PRJ_CHB_ALVEOLE WHERE MASK_LIB NOT IN ('A','B','C','D')")
        rows = con.execute(
            "SELECT ALV_ID, CHB_KEY, MASK_LIB, ALV_NUM, ALV_DIAM, ALV_ETAT, ALV_DEST_KEY, ALV_DEST_TYPE_KEY, "
            "ALV_DESTALV_KEY, ALV_X, ALV_Y, ALV_COMMENT, MASK_LOGIC_NUM, MASK_LOGIC_NAME, MASK_LOGIC_COUL, "
            "ALV_PARENT_KEY, DATE_CREA FROM src.PRJ_CHB_ALVEOLE WHERE MASK_LIB IN ('A','B','C','D') "
            "ORDER BY COALESCE(ALV_PARENT_KEY, 0) > 0, ALV_ID").fetchall()
        reel = {r[0]: r for r in rows}
        for (a_id, c_id, face, num, diam, etat, dest, dest_t, destalv, x, y, comment, lnum, lnom, lcoul,
             parent, crea) in rows:
            if c_id not in chb:
                continue
            noe = chb_noe[c_id]
            if (c_id, face) not in faces:
                con.execute('INSERT INTO chambre.CHB_FACE (CHB_KEY, FAC_CODE, FAC_NB_COL, FAC_NB_LIG) VALUES (?, ?, ?, ?)',
                            (chb[c_id], face, FOA_COL, FOA_LIG))
                faces[(c_id, face)] = self.dernier()
            mlog_k = None
            if lnum is not None:
                if (c_id, lnum) not in mlog:
                    couleur = f'#{lcoul & 0xFF:02X}{(lcoul >> 8) & 0xFF:02X}{(lcoul >> 16) & 0xFF:02X}' if lcoul else None
                    con.execute('INSERT INTO chambre.CHB_MASQUE_LOGIQUE (CHB_KEY, MLOG_NUM, MLOG_LIB, MLOG_COULEUR) '
                                'VALUES (?, ?, ?, ?)', (chb[c_id], lnum, lnom, couleur))
                    mlog[(c_id, lnum)] = self.dernier()
                mlog_k = mlog[(c_id, lnum)]

            # même tube vu de la chambre d'en face ?
            partenaire = destalv if destalv in reel and reel[destalv][1] == dest else None
            if partenaire in conduite:
                cd = conduite[partenaire]
                stats['miroirs'] += 1
                miroir = 1
            else:
                miroir = 0
                if dest and (dest_t in (None, 16)) and dest in chb_noe and dest != c_id:
                    cible = chb_noe[dest]
                elif dest and (dest, dest_t) in foa_geo:
                    cible = destination_geo((dest, dest_t), noe)
                else:
                    if c_id not in inconnue:
                        inconnue[c_id] = self.noeud(
                            f'{prefixe}-X{c_id}', 'Destination à localiser', self.types['AUT'],
                            '(SELECT MakePoint(X(GEOMETRY) + 1, Y(GEOMETRY), 2154) FROM PRJ_NOE WHERE NOE_ID = ?)',
                            (noe,), zone, geol_mod=self.indt,
                            comment=f'Destination d\'alvéole non renseignée ou inconnue (FOA {dest_t}/{dest})')
                    cible = inconnue[c_id]
                    stats['inconnues'] += 1
                paire = frozenset((noe, cible))
                if paire not in lin:
                    impl = 7 if cible in chb_noe.values() else None
                    lin[paire] = self.lineaire(f'{prefixe}-L{min(paire)}-{max(paire)}', 'LIN-SOUT', impl,
                                               noe, cible, zone)
                    stats['lineaires'] += 1
                con.execute('INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY, CD_PARENT_KEY, CD_NUM, CD_DIAM, '
                            "ETAT_KEY, CD_COMMENT, DATE_CREA, SRC_MODIF) VALUES (?, ?, ?, ?, ?, ?, ?, "
                            "COALESCE(?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), 'import')",
                            (f'{prefixe}-CD{a_id}', lin[paire], conduite.get(parent), num, diam,
                             self.etat[ETAT_FOA.get(etat, 'V')], comment or None, iso(crea)))
                cd = self.dernier()
                stats['conduites'] += 1
            conduite[a_id] = cd
            con.execute('INSERT INTO chambre.CHB_POSITION (FAC_KEY, CD_KEY, POS_X, POS_Y, MLOG_KEY, POS_MIROIR, '
                        "SRC_MODIF) VALUES (?, ?, ?, ?, ?, ?, 'import')",
                        (faces[(c_id, face)], cd, round(x / FOA_CASE_L, 3), round(FOA_LIG - y / FOA_CASE_H, 3),
                         mlog_k, miroir))
            stats['positions'] += 1

        # occupation par câbles
        occ = 0
        if un("SELECT COUNT(*) FROM src.sqlite_master WHERE name = 'PRJ_CHB_ALVCAB'"):
            for alv, nb, cdiam in con.execute('SELECT ALV_KEY, CAB_NB, CAB_DIAM FROM src.PRJ_CHB_ALVCAB').fetchall():
                if alv in conduite:
                    con.execute("INSERT INTO infra.INF_CD_CABLE (CD_KEY, CDC_NB, CDC_DIAM, SRC_MODIF) "
                                "VALUES (?, ?, ?, 'import')", (conduite[alv], nb or 1, cdiam))
                    occ += 1

        # photos
        ph = manq = 0
        if photos:
            ent = self.ent['PRJ_NOE']
            type_chb = self.types['CHB']
            principales = set()
            for f_id, chemin, k, lien, ordre, crea in con.execute(
                    'SELECT FILE_ID, FILE_PATH, ENT_KEY, ENT_LINK_NAME, ENT_LINK_ORDER, DATE_CREA '
                    'FROM src.PRJ_ATTACH_FILE ORDER BY ENT_KEY, ENT_LINK_NAME, ENT_LINK_ORDER, FILE_ID').fetchall():
                nom = os.path.basename(chemin or '')
                source = next((p for p in (os.path.join(photos, f'ID{k}', 'Photos', nom), os.path.join(photos, f'ID{k}', nom))
                               if os.path.isfile(p)), None)
                if not source or k not in chb_noe:
                    manq += 1
                    continue
                vue_code = 'MES' if (lien or '').startswith('MES') else VUE_FOA.get(lien)
                vue = self.vues.get((type_chb, vue_code))
                rel = os.path.join('photos', prefixe, f'C{k}', nom)
                os.makedirs(os.path.join(self.dossier, os.path.dirname(rel)), exist_ok=True)
                shutil.copy2(source, os.path.join(self.dossier, rel))
                donnees = open(source, 'rb').read()
                prise = nom.split('_')[0]
                cle = (k, vue)
                con.execute('INSERT INTO PRJ_FICHIER (FIC_CODE_EXT, ENT_KEY, OBJ_KEY, VUE_KEY, FIC_RANG, FIC_PRINCIPALE, '
                            'FIC_NOM, FIC_CHEMIN, FIC_TYPE, FIC_TAILLE, FIC_SHA256, DATE_PRISE, SRC_MODIF) '
                            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'image/jpeg', ?, ?, ?, 'import')",
                            (f'{prefixe}-F{f_id}', ent, chb_noe[k], vue, ordre or 1, int(cle not in principales), nom,
                             rel.replace('\\', '/'), len(donnees), hashlib.sha256(donnees).hexdigest(),
                             iso(int(prise)) if prise.isdigit() else iso(crea)))
                principales.add(cle)
                ph += 1

        self.rapport.append(
            f'{prefixe} : {len(chb)} chambres, {len(geo)} autres nœuds, {len(adr)} adresses, {len(faces)} faces, '
            f'{stats["conduites"]} conduites ({stats["miroirs"]} vues des deux côtés), {stats["positions"]} positions, '
            f'{stats["copies"]} copies « MIROIR » non reprises, {stats["inconnues"]} alvéoles vers une destination '
            f'à localiser, {len(lin)} linéaires, {occ} occupations, {ph} photos ({manq} introuvables)')
        return zone

    # GraceTHD ------------------------------------------------------------------------------------

    def charger_grace(self):
        """Source attachée sous le nom « grc »."""
        con = self.con
        zone = self.zone('GRACE', 'Export GraceTHD de test (Auvergne)')
        types = {'A': 'POT', 'C': 'CHB', 'F': 'FAC'}
        nat = {lib.lower(): i for i, lib in con.execute('SELECT NAT_ID, NAT_LIB FROM poteau.DEF_POT_NAT')}
        nat_grace = {'PBOI': nat.get('bois'), 'PBET': next((v for k, v in nat.items() if k.startswith('b') and 'ton' in k), None)}
        noe = {}
        for nd, typephy, nature, codeext, etiquet, crea, maj in con.execute(
                'SELECT n.nd_code, p.pt_typephy, p.pt_nature, p.pt_codeext, p.pt_etiquet, n.nd_creadat, n.nd_majdate '
                'FROM grc.t_noeud n JOIN grc.t_ptech p ON p.pt_nd_code = n.nd_code').fetchall():
            t = types.get(typephy, 'AUT')
            noe[nd] = self.noeud(f'GRA-{nd}', etiquet or codeext or nd, self.types[t],
                                 '(SELECT SetSRID(geom, 2154) FROM grc.t_noeud WHERE nd_code = ?)', (nd,), zone,
                                 crea=iso(crea), modif=iso(maj))
            if t == 'POT':
                con.execute("INSERT INTO poteau.POT_POTEAU (NOE_KEY, NAT_KEY, POT_COMMENT, SRC_MODIF) "
                            "VALUES (?, ?, ?, 'import')", (noe[nd], nat_grace.get(nature), f'GraceTHD nature {nature}'))
            elif t == 'CHB':
                con.execute("INSERT INTO chambre.CHB_CHAMBRE (NOE_KEY, MAT_KEY, SRC_MODIF) VALUES (?, ?, 'import')",
                            (noe[nd], self.mat_chb.get(nature)))
        for nd, nom in con.execute('SELECT n.nd_code, s.st_nom FROM grc.t_noeud n JOIN grc.t_sitetech s '
                                   'ON s.st_nd_code = n.nd_code').fetchall():
            noe[nd] = self.noeud(f'GRA-{nd}', nom or 'Site technique', self.types['AUT'],
                                 '(SELECT SetSRID(geom, 2154) FROM grc.t_noeud WHERE nd_code = ?)', (nd,), zone)

        sorte = {'0': ('LIN-AER', 0), '1': ('LIN-AER', 1), '2': ('LIN-FAC', 2)}
        portees = conduites = cables = 0
        for cm, n1, n2, imp, lng in con.execute(
                'SELECT cm_code, cm_ndcode1, cm_ndcode2, cm_typ_imp, COALESCE(cm_lgreel, cm_long) FROM grc.t_cheminement').fetchall():
            t, impl = sorte.get(imp, ('LIN-SOUT', int(imp) if (imp or '').isdigit() else None))
            l = self.lineaire(f'GRA-{cm}', t, impl, noe[n1], noe[n2], zone,
                              '(SELECT CastToLineString(SetSRID(geom, 2154)) FROM grc.t_cheminement WHERE cm_code = ?)',
                              (cm,), lng)
            if t == 'LIN-AER':
                # angles des extrémités sur la rosace : azimut en grades, 0 = nord, sens horaire
                a1, a2 = con.execute(
                    'SELECT Azimuth(StartPoint(GEOMETRY), PointN(GEOMETRY, 2)), '
                    'Azimuth(EndPoint(GEOMETRY), PointN(GEOMETRY, NumPoints(GEOMETRY) - 1)) '
                    'FROM PRJ_LINEAIRE WHERE LIN_ID = ?', (l,)).fetchone()
                gr = lambda a: round((a * 200 / math.pi) % 400, 2) if a is not None else None
                con.execute("INSERT INTO infra.INF_PORTEE (LIN_KEY, PRT_ANG1, PRT_ANG2, PRT_LNG, SRC_MODIF) "
                            "VALUES (?, ?, ?, ?, 'import')", (l, gr(a1), gr(a2), lng))
                prt = self.dernier()
                portees += 1
                for rang, (cb, capa, typelog, etiq) in enumerate(con.execute(
                        'SELECT DISTINCT c.cb_code, c.cb_capafo, c.cb_typelog, c.cb_etiquet FROM grc.t_cond_chem dm '
                        'JOIN grc.t_cab_cond cc ON cc.cc_cd_code = dm.dm_cd_code JOIN grc.t_cable c ON c.cb_code = cc.cc_cb_code '
                        'WHERE dm.dm_cm_code = ? ORDER BY c.cb_code', (cm,)).fetchall(), 1):
                    con.execute("INSERT INTO infra.INF_PORTEE_CABLE (PRT_KEY, PCB_RANG, PCB_LNG, PCB_NAPPE, PCB_COMMENT, "
                                "SRC_MODIF) VALUES (?, ?, ?, 1, ?, 'import')",
                                (prt, rang, lng, f'GraceTHD {cb} {etiq or ""} {capa} FO {typelog}'.replace('  ', ' ')))
                    cables += 1
            else:
                for cd, dia, cdtype in con.execute(
                        'SELECT d.cd_code, d.cd_dia_int, d.cd_type FROM grc.t_cond_chem dm JOIN grc.t_conduite d '
                        'ON d.cd_code = dm.dm_cd_code WHERE dm.dm_cm_code = ?', (cm,)).fetchall():
                    con.execute("INSERT INTO infra.INF_CONDUITE (CD_CODE_EXT, LIN_KEY, CD_DIAM, CD_COMMENT, SRC_MODIF) "
                                "VALUES (?, ?, ?, ?, 'import')", (f'GRA-{cd}', l, dia, f'GraceTHD {cdtype}'))
                    conduites += 1
        self.rapport.append(f'GRACE : {len(noe)} nœuds, {portees} portées (angles calculés), {cables} câbles portés, '
                            f'{conduites} conduites souterraines')
        return zone

    def finir(self):
        # emprise des zones et intervention d'import
        self.con.execute('UPDATE PRJ_ZONE SET GEOMETRY = (SELECT CastToMultiPolygon(Buffer(ConvexHull(Collect(n.GEOMETRY)), 50)) '
                         'FROM PRJ_NOE n WHERE n.ZONE_KEY = PRJ_ZONE.ZONE_ID)')
        self.con.execute("INSERT INTO PRJ_INTERVENTION (INT_CODE_EXT, INT_LIB, ACT_CODE, INT_AUTEUR, DATE_DEBUT, INT_STATUT) "
                         "VALUES ('IMPORT-ESSAI', 'Chargement du jeu d''essai', 'IMPORT', 'tools/essai', "
                         "strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 'INTEGREE')")
        i = self.dernier()
        self.con.execute("INSERT INTO PRJ_INT_OBJET (INT_KEY, ENT_KEY, OBJ_KEY, IOB_ACTION) SELECT ?, ?, NOE_ID, 'C' "
                         'FROM PRJ_NOE', (i, self.ent['PRJ_NOE']))


def controles(con):
    q = lambda s: con.execute(s).fetchall()
    print('\nContrôles :')
    print('  orphelins :', [o for o in projet.orphelins(con) if o[1]] or 'aucun')
    print('  conduites FOA vues d\'un seul côté entre deux chambres (miroir à appliquer) :', q(
        "SELECT COUNT(*) FROM infra.INF_CONDUITE cd JOIN PRJ_LINEAIRE l ON l.LIN_ID = cd.LIN_KEY "
        "JOIN PRJ_NOE a ON a.NOE_ID = l.NOE1_KEY JOIN PRJ_NOE b ON b.NOE_ID = l.NOE2_KEY "
        "WHERE a.TYPE_KEY = 16 AND b.TYPE_KEY = 16 AND cd.CD_CODE_EXT NOT LIKE 'GRA-%' "
        "AND (SELECT COUNT(*) FROM chambre.CHB_POSITION p WHERE p.CD_KEY = cd.CD_ID) = 1")[0][0])
    print('  niveaux de renseignement des chambres :', q('SELECT CHB_NIVEAU, COUNT(*) FROM chambre.CHB_CHAMBRE GROUP BY 1'))
    print('  exemple de chambre relevée :', q(
        "SELECT n.NOE_LIB, n.NOE_CODE_EXT, (SELECT COUNT(*) FROM chambre.CHB_FACE f WHERE f.CHB_KEY = c.CHB_ID), "
        "(SELECT COUNT(*) FROM chambre.CHB_POSITION p JOIN chambre.CHB_FACE f ON f.FAC_ID = p.FAC_KEY WHERE f.CHB_KEY = c.CHB_ID), "
        "(SELECT COUNT(*) FROM PRJ_FICHIER fi WHERE fi.OBJ_KEY = n.NOE_ID) "
        "FROM chambre.CHB_CHAMBRE c JOIN PRJ_NOE n ON n.NOE_ID = c.NOE_KEY WHERE c.CHB_NIVEAU = 2 LIMIT 3"))
    print('  rosace d\'un appui GraceTHD (destination, angle au poteau en grades, câbles) :', q(
        "SELECT CASE WHEN l.NOE1_KEY = p.NOE_ID THEN d2.NOE_LIB ELSE d1.NOE_LIB END, "
        "CASE WHEN l.NOE1_KEY = p.NOE_ID THEN r.PRT_ANG1 ELSE r.PRT_ANG2 END, "
        "(SELECT COUNT(*) FROM infra.INF_PORTEE_CABLE c WHERE c.PRT_KEY = r.PRT_ID) "
        "FROM (SELECT n.NOE_ID FROM PRJ_NOE n JOIN PRJ_LINEAIRE x ON n.NOE_ID IN (x.NOE1_KEY, x.NOE2_KEY) "
        "WHERE n.NOE_CODE_EXT LIKE 'GRA-%' AND n.TYPE_KEY = 13 GROUP BY n.NOE_ID HAVING COUNT(*) >= 3 LIMIT 1) p "
        "JOIN PRJ_LINEAIRE l ON p.NOE_ID IN (l.NOE1_KEY, l.NOE2_KEY) JOIN infra.INF_PORTEE r ON r.LIN_KEY = l.LIN_ID "
        "JOIN PRJ_NOE d1 ON d1.NOE_ID = l.NOE1_KEY JOIN PRJ_NOE d2 ON d2.NOE_ID = l.NOE2_KEY"))
    print('  zones (emprise km²) :', q('SELECT ZONE_CODE_EXT, round(Area(GEOMETRY) / 1e6, 3) FROM PRJ_ZONE'))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    dossier, qgis = sys.argv[1:3]
    if os.path.isdir(dossier):
        shutil.rmtree(dossier)
    for ligne in projet.construire(dossier, ESSONNE, qgis, 'ESSAI', 'Jeu d\'essai chambres et poteaux'):
        pass
    ch = Chargeur(dossier, qgis)
    # l'export GraceTHD contient des vues qui empêchent de l'attacher sous un autre nom que main : copie sans vues
    grace = os.path.join(tempfile.mkdtemp(), 'grace.sqlite')
    shutil.copy2(GRACE, grace)
    g = sqlite3.connect(grace)
    for (v,) in g.execute("SELECT name FROM sqlite_master WHERE type = 'view'").fetchall():
        g.execute(f'DROP VIEW "{v}"')
    g.commit()
    g.close()
    etapes = (
        ('src', os.path.join(HEILLECOURT, 'FOA_HEILLECOURT.db'),
         # déclarée 2154 dans geometry_columns, mais coordonnées en Lambert II étendu (x 883 000, y 2 411 000)
         lambda: ch.charger_foa('HEI', 27572, 'Heillecourt (FOA Explorer)', photos=os.path.join(HEILLECOURT, 'Chambres'))),
        ('src', ESSONNE, lambda: ch.charger_foa('ESS', 27572, 'Essonne DOU 12-13 (FOA Explorer)')),
        ('grc', grace, ch.charger_grace),
        (None, None, ch.finir))
    for alias, base, charger in etapes:   # ATTACH impossible dans une transaction : une transaction par source
        if alias:
            ch.con.execute(f'ATTACH DATABASE ? AS {alias}', (base,))
        ch.con.execute('BEGIN')
        try:
            charger()
            ch.con.execute('COMMIT')
        except Exception:
            ch.con.execute('ROLLBACK')
            raise
        finally:
            if alias:
                ch.con.execute(f'DETACH DATABASE {alias}')
    for ligne in ch.rapport:
        print(ligne)
    print('\nEffectifs :', ch.compter())
    controles(ch.con)


if __name__ == '__main__':
    main()
