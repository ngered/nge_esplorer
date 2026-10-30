"""Reconstitue une base SpatiaLite GraceTHD v3 à partir des gabarits shapefile + CSV de FibReady.

Usage : python -I build_gracethd_v3.py <dossier shapes_v3> <base gracethd_v2.0.1.sqlite> <sortie.sqlite> <dossier QGIS bin>

Règles :
- tables et colonnes (ordre compris) : gabarits v3 (en-têtes CSV, champs DBF) ;
- type, NOT NULL, clé primaire et référence : v2.0.1 quand la colonne y existe, au besoin sous un autre préfixe
  (t_ltech lt_ → t_local lc_, t_ptech pt_ → t_pointaccueil pa_…) ;
- colonnes nouvelles : règles explicites (NEW_COLUMNS), sinon champ DBF, sinon VARCHAR(254) ;
- listes l_* : contenu v3, complété par la liste v2 équivalente quand le CSV v3 est vide ;
- géométries Lambert 93 (EPSG:2154), zones en MULTIPOLYGON comme en v2, index spatiaux.
"""
import csv, glob, os, re, sqlite3, struct, sys

sys.stdout.reconfigure(encoding='utf-8')
SRC, V2, OUT, QGIS_BIN = sys.argv[1:5]
SRID = 2154

# v3 → v2 : table source et correspondance de préfixe
V2_SOURCE = {
    't_site': ('t_sitetech', 'st_', 'st_'),
    't_local': ('t_ltech', 'lt_', 'lc_'),
    't_pointaccueil': ('t_ptech', 'pt_', 'pa_'),
    't_tranchee': ('t_cheminement', 'cm_', 'tr_'),
    't_cab_chem': ('t_cab_cond', 'cc_', 'cc_'),
}
# listes renommées entre v2 et v3
LIST_RENAMES = {'l_etat_type': 'l_etat', 'l_propriete_type': 'l_propriete', 'l_implantation_type': 'l_implantation',
                'l_clim_type': 'l_clim', 'l_occupation_type': 'l_occupation', 'l_technologie_type': 'l_technologie',
                'l_infra_type_log': 'l_cable_chem_type_log'}
# tables renommées entre v2 et v3 (référence : table, colonne)
TABLE_RENAMES = {'t_ltech': ('t_local', 'lc_code'), 't_sitetech': ('t_site', 'st_code')}
# colonnes propres à v3 : (type, référence)
NEW_COLUMNS = {
    'cb_bp1': ('VARCHAR(254)', 't_ebp(bp_code)'), 'cb_bp2': ('VARCHAR(254)', 't_ebp(bp_code)'),
    'cb_ba1': ('VARCHAR(254)', 't_baie(ba_code)'), 'cb_ba2': ('VARCHAR(254)', 't_baie(ba_code)'),
    'cb_fo_type': ('VARCHAR(10)', 'l_fo_type(code)'), 'cb_cabphy': ('VARCHAR(254)', None),
    'cb_typelog': ('VARCHAR(2)', 'l_cable_chem_type_log(code)'),
    'bp_lc_code': ('VARCHAR(254)', 't_local(lc_code)'), 'ba_lc_code': ('VARCHAR(254)', 't_local(lc_code)'),
    'zn_lc_code': ('VARCHAR(254)', 't_local(lc_code)'), 'zs_lc_code': ('VARCHAR(254)', 't_local(lc_code)'),
    'lc_bp_codf': ('VARCHAR(254)', 't_ebp(bp_code)'), 'lc_bp_codp': ('VARCHAR(254)', 't_ebp(bp_code)'),
    'lc_typelog': ('VARCHAR(10)', 'l_local_type_log(code)'),
    'cc_cm_code': ('VARCHAR(254)', 't_cheminement(cm_code)'),
    'tr_pa1': ('VARCHAR(254)', 't_pointaccueil(pa_code)'), 'tr_pa2': ('VARCHAR(254)', 't_pointaccueil(pa_code)'),
    'tr_couptyp': ('VARCHAR(254)', None),
    'pa_typephy': ('VARCHAR(3)', 'l_pointaccueil_type_phy(code)'),
    'pa_nature': ('VARCHAR(20)', 'l_pointaccueil_nature(code)'), 'pa_datecon': ('DATE', None),
    'cm_typelog': ('VARCHAR(2)', 'l_cable_chem_type_log(code)'),
    'st_typephy': ('VARCHAR(3)', 'l_site_type_phy(code)'), 'st_typelog': ('VARCHAR(10)', 'l_site_type_log(code)'),
    'st_nra': ('BOOLEAN', None), 'st_design': ('VARCHAR(254)', None),
    'ps_usetype': ('VARCHAR(10)', 'l_position_usetype(code)'),
    'bp_dateins': ('DATE', None), 'lc_avct': ('VARCHAR(1)', 'l_avancement(code)'),
    'lc_bat': ('VARCHAR(100)', None), 'lc_escal': ('VARCHAR(100)', None), 'lc_etage': ('VARCHAR(100)', None),
    'pt_local': ('VARCHAR(254)', None),
}
# clés primaires que la v2 ne peut pas fournir (un câble emprunte plusieurs cheminements)
PK_OVERRIDES = {'t_cab_chem': ['cc_cb_code', 'cc_cm_code']}
GENERIC_SUFFIXES ={'perirec': 'VARCHAR(254)', 'abandon': 'BOOLEAN', 'codtemp': 'VARCHAR(254)'}
SHP_GEOM = {1: 'POINT', 3: 'LINESTRING', 5: 'MULTIPOLYGON', 0: 'MULTIPOLYGON'}

report = {'v2': 0, 'v2_renomme': 0, 'nouvelle_regle': 0, 'adresse': 0, 'dbf': 0, 'defaut': [],
          'fk_supprimees': set(), 'listes_completees': [], 'listes_vides': []}


def read_text(path):
    raw = open(path, 'rb').read()
    try:
        return raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        return raw.decode('cp1252')


def read_csv(path):
    rows = list(csv.reader(read_text(path).splitlines(), delimiter=';'))
    return rows[0], [r for r in rows[1:] if any(c.strip() for c in r)]


def read_dbf_fields(path):
    d = open(path, 'rb').read()
    fields, pos = [], 32
    while d[pos] != 0x0D:
        name = d[pos:pos + 11].split(b'\0')[0].decode('latin-1').lower()
        fields.append((name, chr(d[pos + 11]), d[pos + 16], d[pos + 17]))
        pos += 32
    return fields


def dbf_type(ftype, flen, fdec):
    if ftype == 'C':
        return f'VARCHAR({flen})'
    if ftype == 'N':
        return f'NUMERIC({flen},{fdec})' if fdec else 'INTEGER'
    if ftype == 'D':
        return 'DATE'
    if ftype == 'L':
        return 'BOOLEAN'
    return 'VARCHAR(254)'


def parse_v2(con):
    """{table: {'cols': {col: (type, notnull, ref)}, 'pk': [cols]}}"""
    tables = {}
    col_re = re.compile(r'^\s*"?(\w+)"?\s+([A-Za-z]+(?:\s*\([\d,\s]+\))?)\s*(NOT NULL)?\s*'
                        r'(?:REFERENCES\s+(\w+)\s*\((\w+)\))?', re.I)
    for name, sql in con.execute("select name, sql from sqlite_master where type='table' and (name like 't\\_%' "
                                 "escape '\\' or name like 'l\\_%' escape '\\')"):
        cols, pk = {}, []
        body = sql[sql.index('(') + 1:]
        for line in re.split(r',\s*\n', body):
            line = line.strip()
            m = re.search(r'PRIMARY KEY\s*\(([^)]+)\)', line, re.I)
            if m:
                pk = [c.strip().strip('"') for c in m.group(1).split(',')]
                continue
            if line.startswith('--') or line.upper().startswith('CONSTRAINT'):
                continue
            m = col_re.match(line)
            if m and m.group(1).lower() not in ('constraint', 'geom'):
                ref = f'{m.group(4)}({m.group(5)})' if m.group(4) else None
                cols[m.group(1).lower()] = (re.sub(r'\s+', '', m.group(2)).upper(), bool(m.group(3)), ref)
        tables[name] = {'cols': cols, 'pk': pk}
    return tables


def remap_ref(ref, v3_tables):
    """Adapte une référence v2 aux noms v3 ; None si la cible n'existe plus."""
    if not ref:
        return None
    table, col = re.match(r'(\w+)\((\w+)\)', ref).groups()
    table = LIST_RENAMES.get(table, table)
    if table in TABLE_RENAMES:
        table, col = TABLE_RENAMES[table]
    if table in v3_tables:
        return f'{table}({col})'
    report['fk_supprimees'].add(ref)
    return None


def column_def(table, col, dbf_field, v2, v3_tables):
    """Retourne (type, notnull, ref)."""
    src = v2.get(table)
    if src and col in src['cols']:
        t, nn, ref = src['cols'][col]
        report['v2'] += 1
        if col in NEW_COLUMNS and NEW_COLUMNS[col][1]:
            return t, nn, NEW_COLUMNS[col][1]  # la liste v3 prime sur la liste v2
        return t, nn, remap_ref(ref, v3_tables)
    if col in NEW_COLUMNS:
        report['nouvelle_regle'] += 1
        return NEW_COLUMNS[col][0], False, NEW_COLUMNS[col][1]
    if table in V2_SOURCE:
        v2_table, p2, p3 = V2_SOURCE[table]
        old = p2 + col[len(p3):]
        if old in v2[v2_table]['cols']:
            t, nn, ref = v2[v2_table]['cols'][old]
            report['v2_renomme'] += 1
            return t, nn, remap_ref(ref, v3_tables)
    suffix = col.split('_', 1)[1] if '_' in col else col
    if suffix in GENERIC_SUFFIXES:
        report['nouvelle_regle'] += 1
        return GENERIC_SUFFIXES[suffix], False, None
    if 'ad_' + suffix in v2['t_adresse']['cols'] and table != 't_adresse':
        report['adresse'] += 1
        return v2['t_adresse']['cols']['ad_' + suffix][0], False, None
    if dbf_field:
        report['dbf'] += 1
        return dbf_type(*dbf_field[1:]), False, None
    report['defaut'].append(f'{table}.{col}')
    return 'VARCHAR(254)', False, None


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    v2con = sqlite3.connect(V2)
    v2 = parse_v2(v2con)

    # inventaire des gabarits v3
    lists = {os.path.basename(p)[:-4]: p for p in sorted(glob.glob(os.path.join(SRC, 'l_*.csv')))}
    tables = {}  # nom → (colonnes, champs dbf, type géométrique)
    for p in sorted(glob.glob(os.path.join(SRC, 't_*.csv'))):
        header, _ = read_csv(p)
        tables[os.path.basename(p)[:-4]] = ([c.strip().lower() for c in header if c.strip()], {}, None)
    for p in sorted(glob.glob(os.path.join(SRC, 't_*.shp'))):
        name = os.path.basename(p)[:-4]
        gcode = struct.unpack('<i', open(p, 'rb').read(36)[32:36])[0]
        fields = [f for f in read_dbf_fields(p[:-4] + '.dbf') if f[0] != 'geom']
        tables[name] = ([f[0] for f in fields], {f[0]: f for f in fields}, SHP_GEOM[gcode])
    v3_tables = set(tables) | set(lists)

    os.add_dll_directory(QGIS_BIN)
    os.environ['PATH'] = QGIS_BIN + os.pathsep + os.environ['PATH']
    con = sqlite3.connect(OUT)
    con.enable_load_extension(True)
    con.load_extension('mod_spatialite')
    con.execute('SELECT InitSpatialMetadata(1)')

    # listes
    for name, path in lists.items():
        header, rows = read_csv(path)
        v2name = name if name in v2 else next((k for k, v in LIST_RENAMES.items() if v == name), None)
        code_type = v2[v2name]['cols'].get('code', ('VARCHAR(20)',))[0] if v2name in v2 else 'VARCHAR(20)'
        con.execute(f'CREATE TABLE {name} (code {code_type} NOT NULL, libelle VARCHAR(254), '
                    f'definition VARCHAR(254), CONSTRAINT "{name}_pk" PRIMARY KEY (code))')
        if not rows and v2name in v2:
            rows = v2con.execute(f'SELECT code, libelle, definition FROM {v2name}').fetchall()
            report['listes_completees'].append(f'{name} ← {v2name} ({len(rows)})')
        elif not rows:
            report['listes_vides'].append(name)
        con.executemany(f'INSERT INTO {name} VALUES (?,?,?)',
                        [tuple((list(r) + ['', '', ''])[:3]) for r in rows])

    # tables
    fk_cols = []
    for name, (cols, dbf, geom) in tables.items():
        v2name = V2_SOURCE.get(name, (name,))[0]
        defs = []
        for col in cols:
            t, nn, ref = column_def(name, col, dbf.get(col), v2, v3_tables)
            defs.append(f'\t{col} {t}' + (' NOT NULL' if nn else '') + (f' REFERENCES {ref}' if ref else ''))
            if ref:
                fk_cols.append((name, col))
        pk = v2[v2name]['pk'] if v2name in v2 else []
        if name in V2_SOURCE:
            _, p2, p3 = V2_SOURCE[name]
            pk = [p3 + c[len(p2):] for c in pk]
        pk = PK_OVERRIDES.get(name) or [c for c in pk if c in cols] or [cols[0]]
        defs.append(f'CONSTRAINT "{name}_pk" PRIMARY KEY ({", ".join(pk)})')
        con.execute(f'CREATE TABLE {name} (\n' + ',\n'.join(defs) + ')')
        if geom:
            con.execute('SELECT AddGeometryColumn(?, ?, ?, ?, ?, 1)', (name, 'geom', SRID, geom, 'XY'))
            con.execute('SELECT CreateSpatialIndex(?, ?)', (name, 'geom'))
    for table, col in fk_cols:
        con.execute(f'CREATE INDEX idx_{table}_{col} ON {table} ({col})')
    con.commit()

    # contrôles
    geoms = con.execute('SELECT f_table_name, geometry_type, srid FROM geometry_columns ORDER BY 1').fetchall()
    bad_refs = []
    for table, col in fk_cols:
        for row in con.execute(f'PRAGMA foreign_key_list({table})'):
            if row[3] == col and (row[2] not in v3_tables or
                                  row[4] not in [c[1] for c in con.execute(f'PRAGMA table_info({row[2]})')]):
                bad_refs.append(f'{table}.{col} → {row[2]}({row[4]})')
    con.execute('SAVEPOINT essai')
    con.execute("INSERT INTO t_noeud (nd_code, geom) VALUES ('ESSAI', MakePoint(700000, 6600000, 2154))")
    essai = con.execute("SELECT AsText(geom) FROM t_noeud WHERE nd_code = 'ESSAI'").fetchone()[0]
    con.execute('ROLLBACK TO essai')
    con.close()

    print(f'Base : {OUT} ({os.path.getsize(OUT)} octets)')
    print(f'{len(lists)} listes, {len(tables)} tables, {len(fk_cols)} références, {len(geoms)} géométries')
    print('Géométries :', ', '.join(f'{t} {g}' for t, g, _ in geoms))
    print(f"Types : {report['v2']} repris de v2, {report['v2_renomme']} de v2 sous un autre préfixe, "
          f"{report['nouvelle_regle']} par règle v3, {report['adresse']} depuis t_adresse, {report['dbf']} depuis DBF, "
          f"{len(report['defaut'])} par défaut")
    print('Type par défaut (VARCHAR(254)) :', ', '.join(report['defaut']) or 'aucun')
    print('Références v2 sans cible en v3 (supprimées) :', ', '.join(sorted(report['fk_supprimees'])) or 'aucune')
    print('Listes complétées depuis v2 :', ', '.join(report['listes_completees']) or 'aucune')
    print('Listes restées vides :', ', '.join(report['listes_vides']) or 'aucune')
    print('Références invalides :', ', '.join(bad_refs) or 'aucune')
    print('Essai d\'insertion géométrique :', essai)


main()
