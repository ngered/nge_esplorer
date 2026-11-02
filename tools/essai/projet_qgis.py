"""Génère un projet QGIS de consultation d'un projet NgeEsPlorer (noyau + modules) : projet_essai.qgs.

Contenu : nœuds et linéaires stylés par type ; couches de contrôle (niveau de renseignement des chambres, conduites
vues d'un seul côté, destinations à localiser, rosace des portées) ; tables des modules reliées entre elles
(relations QGIS : la fiche d'un nœud montre sa chambre ou son poteau, ses photos, ses équipements…) ; libellés des
référentiels à la place des clés ; photos affichées dans les fiches ; signets par zone ; fond OpenStreetMap.

Usage (Python de QGIS) :
  "C:\\Program Files\\QGIS 3.44.7\\bin\\python-qgis.bat" tools\\essai\\projet_qgis.py <dossier projet>
"""
import math, os, sys

from qgis.core import (Qgis, QgsApplication, QgsBookmark, QgsCategorizedSymbolRenderer, QgsCoordinateReferenceSystem,
                       QgsDataSourceUri, QgsEditorWidgetSetup, QgsFillSymbol, QgsLineSymbol, QgsMarkerLineSymbolLayer,
                       QgsMarkerSymbol,
                       QgsPalLayerSettings, QgsProject, QgsRasterLayer, QgsReferencedRectangle, QgsRelation,
                       QgsRendererCategory, QgsTextBufferSettings, QgsTextFormat, QgsVectorLayer,
                       QgsVectorLayerSimpleLabeling, QgsVirtualLayerDefinition, QgsWkbTypes)

DOSSIER = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else None
CRS = QgsCoordinateReferenceSystem('EPSG:2154')


def chemin(fichier):
    return os.path.join(DOSSIER, fichier)


def geo(table, nom, filtre=None):
    u = QgsDataSourceUri()
    u.setDatabase(chemin('noyau.sqlite'))
    u.setDataSource('', table, 'GEOMETRY', filtre or '')
    return verifier(QgsVectorLayer(u.uri(), nom, 'spatialite'))


def table(fichier, nom_table, nom):
    return verifier(QgsVectorLayer(f'{chemin(fichier)}|layername={nom_table}', nom, 'ogr'))


def virtuelle(nom, sources, sql, geom_type):
    d = QgsVirtualLayerDefinition()
    for alias, couche in sources.items():
        d.addSource(alias, couche.id())
    d.setQuery(sql)
    d.setGeometryField('geometry')
    d.setGeometryWkbType(geom_type)
    d.setGeometrySrid(2154)
    return verifier(QgsVectorLayer(d.toString(), nom, 'virtual'))


def verifier(couche):
    if not couche.isValid():
        raise RuntimeError(f'couche invalide : {couche.name()} ({couche.source()})')
    return couche


def etiquettes(couche, expression, taille=8, ligne=False, echelle_max=6000):
    s = QgsPalLayerSettings()
    s.isExpression = True
    s.fieldName = expression
    fmt = QgsTextFormat()
    fmt.setSize(taille)
    tampon = QgsTextBufferSettings()
    tampon.setEnabled(True)
    tampon.setSize(0.8)
    fmt.setBuffer(tampon)
    s.setFormat(fmt)
    if ligne:
        s.placement = Qgis.LabelPlacement.Line
    s.scaleVisibility = True
    s.minimumScale = echelle_max
    s.maximumScale = 1
    couche.setLabeling(QgsVectorLayerSimpleLabeling(s))
    couche.setLabelsEnabled(True)


def categories(couche, expression, valeurs):
    cats = [QgsRendererCategory(v, sym, lib) for v, lib, sym in valeurs]
    couche.setRenderer(QgsCategorizedSymbolRenderer(expression, cats))


def point(forme, couleur, taille='2.6', contour='white'):
    return QgsMarkerSymbol.createSimple({'name': forme, 'color': couleur, 'size': taille, 'outline_color': contour,
                                         'outline_width': '0.3'})


def trait(couleur, largeur='0.5', style='solid'):
    return QgsLineSymbol.createSimple({'color': couleur, 'width': largeur, 'line_style': style})


def libelle(couche, champ, ref, cle, valeur):
    i = couche.fields().indexOf(champ)
    couche.setEditorWidgetSetup(i, QgsEditorWidgetSetup('ValueRelation', {
        'Layer': ref.id(), 'Key': cle, 'Value': valeur, 'AllowNull': True, 'OrderByValue': True}))


def relation(projet, nom, parent, champ_parent, enfant, champ_enfant):
    r = QgsRelation()
    r.setId(f'rel_{enfant.name()}_{champ_enfant}'.replace(' ', '_'))
    r.setName(nom)
    r.setReferencedLayer(parent.id())
    r.setReferencingLayer(enfant.id())
    r.addFieldPair(champ_enfant, champ_parent)
    if not r.isValid():
        raise RuntimeError(f'relation invalide : {nom} ({r.validationError()})')
    projet.relationManager().addRelation(r)


RAYON = 8           # rayon de la rosace (m)
POTEAUX = '(13, 14, 15)'
ECHELLE_ROSACE = 2500


def rosaces(ajouter, noe, lin, prt):
    """Rosace au pied de chaque poteau relié : cercle gradué (10 gr), repères 0 / 100 / 200 / 300, une flèche par
    linéaire. Angle : celui relevé sur la portée à l'extrémité du poteau, à défaut l'azimut de la géométrie.
    Convention affichée : grades, 0 = nord, sens horaire (à confirmer ; la maquette Figma place 0 à l'est)."""
    sources = {'noe': noe, 'lin': lin, 'prt': prt}
    rayons = virtuelle('Rosaces — portées', sources,
        'SELECT x.LIN_ID, p.NOE_ID, p.NOE_LIB AS POTEAU, d.NOE_LIB AS DESTINATION, x.IMPL_KEY, x.ANGLE, '
        f'MakeLine(p.geometry, MakePoint(X(p.geometry) + {RAYON} * Sin(x.ANGLE * PI() / 200), '
        f'Y(p.geometry) + {RAYON} * Cos(x.ANGLE * PI() / 200), 2154)) AS geometry FROM ('
        '  SELECT l.LIN_ID, l.IMPL_KEY, l.NOE1_KEY AS POT, l.NOE2_KEY AS DEST, '
        '    COALESCE(r.PRT_ANG1, (Azimuth(StartPoint(l.geometry), PointN(l.geometry, 2)) * 200 / PI() + 400) % 400) AS ANGLE '
        '  FROM lin l LEFT JOIN prt r ON r.LIN_KEY = l.LIN_ID '
        '  UNION ALL '
        '  SELECT l.LIN_ID, l.IMPL_KEY, l.NOE2_KEY, l.NOE1_KEY, '
        '    COALESCE(r.PRT_ANG2, (Azimuth(EndPoint(l.geometry), PointN(l.geometry, NumPoints(l.geometry) - 1)) * 200 / PI() + 400) % 400) '
        '  FROM lin l LEFT JOIN prt r ON r.LIN_KEY = l.LIN_ID) x '
        f'JOIN noe p ON p.NOE_ID = x.POT JOIN noe d ON d.NOE_ID = x.DEST WHERE p.TYPE_KEY IN {POTEAUX}',
        QgsWkbTypes.LineString)

    def fleche(couleur, style='solid'):
        s = trait(couleur, '0.6', style)
        tete = QgsMarkerLineSymbolLayer(True)
        tete.setPlacements(Qgis.MarkerLinePlacement.LastVertex)
        tete.setSubSymbol(QgsMarkerSymbol.createSimple({'name': 'filled_arrowhead', 'color': couleur, 'size': '3',
                                                        'outline_style': 'no'}))
        s.appendSymbolLayer(tete)
        return s

    categories(rayons, 'coalesce("IMPL_KEY", -1)', [
        (0, 'Aérien télécom', fleche('#2CA02C')),
        (1, 'Aérien énergie (BT)', fleche('#E67E22')),
        (2, 'Façade', fleche('#2CA02C', 'dot')),
        (-1, 'Autre', fleche('#1F77B4'))])
    etiquettes(rayons, "format_number(\"ANGLE\", 0) || ' gr  ' || coalesce(\"DESTINATION\", '')", 7, ligne=True,
               echelle_max=ECHELLE_ROSACE)

    cercles = virtuelle('Rosaces — cercles', sources,
        f'SELECT p.NOE_ID, p.NOE_LIB, ExteriorRing(Buffer(p.geometry, {RAYON}, 100)) AS geometry FROM noe p '
        f'WHERE p.TYPE_KEY IN {POTEAUX} AND EXISTS (SELECT 1 FROM lin l WHERE p.NOE_ID IN (l.NOE1_KEY, l.NOE2_KEY))',
        QgsWkbTypes.LineString)
    cercle = trait('#555555', '0.3')
    graduation = QgsMarkerLineSymbolLayer(True, 2 * math.pi * RAYON / 40)   # un trait tous les 10 grades
    graduation.setIntervalUnit(Qgis.RenderUnit.MapUnits)
    graduation.setSubSymbol(QgsMarkerSymbol.createSimple({'name': 'line', 'color': '#555555', 'size': '1.6',
                                                          'outline_color': '#555555', 'outline_width': '0.25'}))
    cercle.appendSymbolLayer(graduation)
    categories(cercles, '1', [(1, 'Rosace', cercle)])

    # poteaux sélectionnés une fois puis croisés avec les repères : une union de quatre requêtes EXISTS sur les
    # tables virtuelles ne se termine pas
    reperes = virtuelle('Rosaces — repères', sources,
        f'SELECT p.NOE_ID, g.GRADES, MakePoint(X(p.geometry) + {RAYON + 2} * Sin(g.GRADES * PI() / 200), '
        f'Y(p.geometry) + {RAYON + 2} * Cos(g.GRADES * PI() / 200), 2154) AS geometry FROM ('
        f'  SELECT n.NOE_ID, n.geometry FROM noe n WHERE n.TYPE_KEY IN {POTEAUX} '
        '   AND EXISTS (SELECT 1 FROM lin l WHERE n.NOE_ID IN (l.NOE1_KEY, l.NOE2_KEY))) p '
        'CROSS JOIN (SELECT 0 AS GRADES UNION ALL SELECT 100 UNION ALL SELECT 200 UNION ALL SELECT 300) g',
        QgsWkbTypes.Point)
    categories(reperes, '1', [(1, 'Repère', QgsMarkerSymbol.createSimple({'name': 'circle', 'size': '0'}))])
    etiquettes(reperes, '"GRADES"', 7, echelle_max=ECHELLE_ROSACE)

    for couche in (rayons, cercles, reperes):
        couche.setScaleBasedVisibility(True)
        couche.setMinimumScale(ECHELLE_ROSACE)
        couche.setMaximumScale(0)
        ajouter(couche, 'Rosaces des poteaux')


def main():
    if not DOSSIER or not os.path.isfile(chemin('noyau.sqlite')):
        print(__doc__)
        sys.exit(1)
    app = QgsApplication([], False)
    app.initQgis()
    projet = QgsProject.instance()
    projet.setCrs(CRS)
    projet.setTitle('NgeEsPlorer — consultation du projet ' + os.path.basename(DOSSIER))
    racine = projet.layerTreeRoot()
    groupes = {g: racine.addGroup(g) for g in ('Rosaces des poteaux', 'Contrôles', 'Réseau', 'Tables noyau', 'Tables infra', 'Tables chambre',
                                                'Tables poteau', 'Référentiels', 'Fond de plan')}

    def ajouter(couche, groupe, visible=True):
        projet.addMapLayer(couche, False)
        noeud = groupes[groupe].addLayer(couche)
        noeud.setItemVisibilityChecked(visible)
        return couche

    # référentiels et tables
    ref = {
        'type': ajouter(table('noyau.sqlite', 'DEF_TYPE', 'Types'), 'Référentiels'),
        'vue': ajouter(table('noyau.sqlite', 'DEF_VUE', 'Vues photographiées'), 'Référentiels'),
        'impl': ajouter(table('noyau.sqlite', 'DEF_IMPLANTATION', 'Implantations (linéaires)'), 'Référentiels'),
        'gmod': ajouter(table('noyau.sqlite', 'DEF_GEOL_MODE', 'Modes de géolocalisation'), 'Référentiels'),
        'etat': ajouter(table('infra.sqlite', 'DEF_CD_ETAT', 'États des alvéoles'), 'Référentiels'),
        'imps': ajouter(table('infra.sqlite', 'DEF_SUPPORT_IMPLANT', 'Implantations (supports)'), 'Référentiels'),
        'matcab': ajouter(table('infra.sqlite', 'MAT_CABLE', 'Catalogue câbles'), 'Référentiels'),
        'matequ': ajouter(table('infra.sqlite', 'MAT_EQUIP', 'Catalogue équipements'), 'Référentiels'),
        'matchb': ajouter(table('chambre.sqlite', 'MAT_CHAMBRE', 'Catalogue chambres'), 'Référentiels'),
        'matpot': ajouter(table('poteau.sqlite', 'MAT_POTEAU', 'Catalogue poteaux'), 'Référentiels'),
        'potnat': ajouter(table('poteau.sqlite', 'DEF_POT_NAT', 'Natures de poteau'), 'Référentiels'),
    }
    for g in ('Référentiels',):
        groupes[g].setExpanded(False)
    t = {
        'fic': ajouter(table('noyau.sqlite', 'PRJ_FICHIER', 'Photos'), 'Tables noyau'),
        'int': ajouter(table('noyau.sqlite', 'PRJ_INTERVENTION', 'Interventions'), 'Tables noyau'),
        'cd': ajouter(table('infra.sqlite', 'INF_CONDUITE', 'Conduites'), 'Tables infra'),
        'cdc': ajouter(table('infra.sqlite', 'INF_CD_CABLE', 'Occupation des conduites'), 'Tables infra'),
        'prt': ajouter(table('infra.sqlite', 'INF_PORTEE', 'Portées'), 'Tables infra'),
        'pcb': ajouter(table('infra.sqlite', 'INF_PORTEE_CABLE', 'Câbles portés'), 'Tables infra'),
        'equ': ajouter(table('infra.sqlite', 'INF_EQUIPEMENT', 'Équipements sur support'), 'Tables infra'),
        'chb': ajouter(table('chambre.sqlite', 'CHB_CHAMBRE', 'Chambres'), 'Tables chambre'),
        'face': ajouter(table('chambre.sqlite', 'CHB_FACE', 'Faces'), 'Tables chambre'),
        'mlog': ajouter(table('chambre.sqlite', 'CHB_MASQUE_LOGIQUE', 'Masques logiques'), 'Tables chambre'),
        'pos': ajouter(table('chambre.sqlite', 'CHB_POSITION', 'Positions dans les masques'), 'Tables chambre'),
        'pot': ajouter(table('poteau.sqlite', 'POT_POTEAU', 'Poteaux'), 'Tables poteau'),
        'ctl': ajouter(table('poteau.sqlite', 'POT_CONTROLE', 'Contrôles de poteau'), 'Tables poteau'),
    }
    for g in ('Tables noyau', 'Tables infra', 'Tables chambre', 'Tables poteau'):
        groupes[g].setExpanded(False)

    # réseau
    zones = geo('PRJ_ZONE', 'Zones')
    zones.setRenderer(QgsCategorizedSymbolRenderer('1', [QgsRendererCategory(
        1, QgsFillSymbol.createSimple({'color': '0,0,0,0', 'outline_color': '#555555', 'outline_width': '0.6',
                                       'outline_style': 'dash'}), 'Zone')]))
    etiquettes(zones, '"ZONE_LIB"', 10, echelle_max=200000)
    lin = geo('PRJ_LINEAIRE', 'Linéaires')
    noe = geo('PRJ_NOE', 'Nœuds')
    categories(lin, '"TYPE_KEY"', [
        (1001, 'Parcours souterrain', trait('#1F77B4', '0.5')),
        (1002, 'Portée aérienne', trait('#2CA02C', '0.5', 'dash')),
        (1003, 'Parcours en façade', trait('#E67E22', '0.5', 'dot'))])
    categories(noe, "CASE WHEN \"TYPE_KEY\" IN (16,17,18) THEN 'CHB' WHEN \"TYPE_KEY\" IN (13,14,15) THEN 'POT' "
                    "WHEN \"TYPE_KEY\" = 30 THEN 'FAC' ELSE 'AUT' END", [
        ('CHB', 'Chambre', point('square', '#7E3FBF')),
        ('POT', 'Poteau', point('circle', '#2E8B57')),
        ('FAC', 'Ancrage façade', point('triangle', '#E67E22')),
        ('AUT', 'Autre point', point('diamond', '#7F8C8D', '2.2'))])
    etiquettes(noe, '"NOE_LIB"')
    noe.setDisplayExpression('coalesce("NOE_LIB", \'\') || \' — \' || "NOE_CODE_EXT"')
    lin.setDisplayExpression('"LIN_CODE_EXT"')
    ajouter(noe, 'Réseau')     # ordre de la légende = ordre de dessin : nœuds au-dessus
    ajouter(lin, 'Réseau')
    ajouter(zones, 'Réseau')

    # contrôles (couches virtuelles sur les couches du projet)
    portees = virtuelle('Rosace des portées', {'lin': lin, 'prt': t['prt'], 'noe': noe, 'pcb': t['pcb']},
        'SELECT l.LIN_ID, l.LIN_CODE_EXT, a.NOE_LIB AS NOE1, b.NOE_LIB AS NOE2, p.PRT_ANG1, p.PRT_ANG2, p.PRT_LNG, '
        '(SELECT COUNT(*) FROM pcb c WHERE c.PRT_KEY = p.PRT_ID) AS NB_CABLES, l.geometry '
        'FROM lin l JOIN prt p ON p.LIN_KEY = l.LIN_ID JOIN noe a ON a.NOE_ID = l.NOE1_KEY '
        'JOIN noe b ON b.NOE_ID = l.NOE2_KEY', QgsWkbTypes.LineString)
    categories(portees, '1', [(1, 'Portée', trait('#2CA02C', '0.9'))])
    # angle relevé à chaque extrémité (grades) et nombre de câbles portés
    etiquettes(portees, "format_number(\"PRT_ANG1\", 0) || ' gr ↔ ' || format_number(\"PRT_ANG2\", 0) || ' gr · ' "
                        "|| \"NB_CABLES\" || ' câble(s)'", 7, ligne=True, echelle_max=3000)
    chambres = virtuelle('Chambres — niveau de renseignement', {'noe': noe, 'chb': t['chb'], 'mat': ref['matchb'],
                                                                 'fic': t['fic']},
        'SELECT n.NOE_ID, n.NOE_LIB, n.NOE_CODE_EXT, c.CHB_NIVEAU, m.MAT_LIB AS TYPE_CHB, '
        '(SELECT COUNT(*) FROM fic f WHERE f.OBJ_KEY = n.NOE_ID) AS NB_PHOTOS, n.geometry '
        'FROM noe n JOIN chb c ON c.NOE_KEY = n.NOE_ID LEFT JOIN mat m ON m.MAT_ID = c.MAT_KEY', QgsWkbTypes.Point)
    categories(chambres, '"CHB_NIVEAU"', [
        (0, 'Non relevée', point('square', '#BDBDBD', '3')),
        (1, 'Renseignée en partie', point('square', '#F39C12', '3')),
        (2, 'Renseignée', point('square', '#27AE60', '3'))])
    a_placer = virtuelle('Miroirs à appliquer (conduites vues d\'un seul côté)',
        {'lin': lin, 'cd': t['cd'], 'pos': t['pos'], 'noe': noe},
        'SELECT l.LIN_ID, l.LIN_CODE_EXT, COUNT(*) AS NB_A_PLACER, l.geometry FROM lin l '
        'JOIN cd ON cd.LIN_KEY = l.LIN_ID JOIN noe a ON a.NOE_ID = l.NOE1_KEY JOIN noe b ON b.NOE_ID = l.NOE2_KEY '
        'WHERE a.TYPE_KEY IN (16,17,18) AND b.TYPE_KEY IN (16,17,18) '
        'AND (SELECT COUNT(*) FROM pos WHERE pos.CD_KEY = cd.CD_ID) = 1 GROUP BY l.LIN_ID', QgsWkbTypes.LineString)
    categories(a_placer, '1', [(1, 'Conduites à placer côté destination', trait('#E02424', '1.4'))])
    etiquettes(a_placer, '"NB_A_PLACER" || \' à placer\'', 7, ligne=True)
    indt = projet.mapLayersByName('Modes de géolocalisation')[0]
    code_indt = next(f['GMOD_ID'] for f in indt.getFeatures() if f['GMOD_CODE'] == 'INDT')
    a_localiser = geo('PRJ_NOE', 'Destinations à localiser', f'"GEOL_MOD_KEY" = {code_indt}')
    categories(a_localiser, '1', [(1, 'Position indéterminée', point('cross2', '#E02424', '4', '#E02424'))])
    etiquettes(a_localiser, '"NOE_LIB"', 7)
    rosaces(ajouter, noe, lin, t['prt'])
    ajouter(portees, 'Contrôles')
    ajouter(chambres, 'Contrôles', False)
    ajouter(a_placer, 'Contrôles', False)
    ajouter(a_localiser, 'Contrôles', False)

    # fond de plan
    osm = QgsRasterLayer('type=xyz&url=https://tile.openstreetmap.org/{z}/{x}/{y}.png&zmax=19&zmin=0',
                         'OpenStreetMap', 'wms')
    if osm.isValid():
        ajouter(osm, 'Fond de plan')

    # libellés des référentiels à la place des clés
    libelle(noe, 'TYPE_KEY', ref['type'], 'TYPE_ID', 'TYPE_LIB')
    libelle(noe, 'GEOL_MOD_KEY', ref['gmod'], 'GMOD_ID', 'GMOD_LIB')
    libelle(lin, 'TYPE_KEY', ref['type'], 'TYPE_ID', 'TYPE_LIB')
    libelle(lin, 'IMPL_KEY', ref['impl'], 'IMPL_ID', 'IMPL_LIB')
    libelle(t['chb'], 'MAT_KEY', ref['matchb'], 'MAT_ID', 'MAT_LIB')
    libelle(t['chb'], 'IMPS_KEY', ref['imps'], 'IMPS_ID', 'IMPS_LIB')
    libelle(t['pot'], 'MAT_KEY', ref['matpot'], 'MAT_ID', 'MAT_DESC')
    libelle(t['pot'], 'NAT_KEY', ref['potnat'], 'NAT_ID', 'NAT_LIB')
    libelle(t['pot'], 'IMPS_KEY', ref['imps'], 'IMPS_ID', 'IMPS_LIB')
    libelle(t['cd'], 'ETAT_KEY', ref['etat'], 'ETAT_ID', 'ETAT_LIB')
    libelle(t['cdc'], 'MAT_KEY', ref['matcab'], 'MAT_ID', 'MAT_LIB')
    libelle(t['pcb'], 'MAT_KEY', ref['matcab'], 'MAT_ID', 'MAT_LIB')
    libelle(t['equ'], 'MAT_KEY', ref['matequ'], 'MAT_ID', 'MAT_LIB')
    libelle(t['fic'], 'VUE_KEY', ref['vue'], 'VUE_ID', 'VUE_LIB')
    t['cd'].setDisplayExpression('"CD_CODE_EXT" || \' Ø\' || coalesce("CD_DIAM", \'?\')')
    t['fic'].setDisplayExpression('"FIC_NOM"')
    i = t['fic'].fields().indexOf('FIC_CHEMIN')
    t['fic'].setEditorWidgetSetup(i, QgsEditorWidgetSetup('ExternalResource', {
        'DocumentViewer': 1, 'DocumentViewerHeight': 320, 'RelativeStorage': 1, 'FileWidget': True,
        'FileWidgetButton': False, 'UseLink': False}))

    # relations : la fiche d'un parent montre ses enfants
    relation(projet, 'Chambre', noe, 'NOE_ID', t['chb'], 'NOE_KEY')
    relation(projet, 'Poteau', noe, 'NOE_ID', t['pot'], 'NOE_KEY')
    relation(projet, 'Photos', noe, 'NOE_ID', t['fic'], 'OBJ_KEY')
    relation(projet, 'Équipements', noe, 'NOE_ID', t['equ'], 'NOE_KEY')
    relation(projet, 'Faces', t['chb'], 'CHB_ID', t['face'], 'CHB_KEY')
    relation(projet, 'Masques logiques', t['chb'], 'CHB_ID', t['mlog'], 'CHB_KEY')
    relation(projet, 'Positions de la face', t['face'], 'FAC_ID', t['pos'], 'FAC_KEY')
    relation(projet, 'Conduites', lin, 'LIN_ID', t['cd'], 'LIN_KEY')
    relation(projet, 'Positions de la conduite', t['cd'], 'CD_ID', t['pos'], 'CD_KEY')
    relation(projet, 'Occupation', t['cd'], 'CD_ID', t['cdc'], 'CD_KEY')
    relation(projet, 'Sous-tubes', t['cd'], 'CD_ID', t['cd'], 'CD_PARENT_KEY')
    relation(projet, 'Portée', lin, 'LIN_ID', t['prt'], 'LIN_KEY')
    relation(projet, 'Câbles portés', t['prt'], 'PRT_ID', t['pcb'], 'PRT_KEY')
    relation(projet, 'Contrôles', t['pot'], 'POT_ID', t['ctl'], 'POT_KEY')

    # signets par zone, vue initiale sur la première
    premiere = None
    for f in zones.getFeatures():
        rect = QgsReferencedRectangle(f.geometry().boundingBox().buffered(100), CRS)
        b = QgsBookmark()
        b.setName(f['ZONE_LIB'])
        b.setExtent(rect)
        projet.bookmarkManager().addBookmark(b)
        premiere = premiere or rect
    if premiere:
        projet.viewSettings().setDefaultViewExtent(premiere)

    sortie = chemin(os.path.basename(DOSSIER) + '.qgs')
    projet.write(sortie)
    print(f'Projet QGIS : {sortie}')
    print(f'  {len(projet.mapLayers())} couches, {len(projet.relationManager().relations())} relations, '
          f'{len(projet.bookmarkManager().bookmarks())} signets ; fond OpenStreetMap : {"oui" if osm.isValid() else "non"}')
    print('  contrôles :', {c.name(): c.featureCount() for c in (portees, chambres, a_placer, a_localiser)})
    sys.stdout.flush()
    os._exit(0)   # exitQgis plante en mode autonome sous Windows ; le projet est déjà écrit


if __name__ == '__main__':
    main()
