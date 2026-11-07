import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/data/data_repository.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/data/visuals.dart';
import 'package:nge_esplorer/map/symbols.dart';
import 'package:nge_esplorer/modules/optique/equipment_screen.dart';
import 'package:nge_esplorer/modules/optique/fibready_chart.dart';
import 'package:nge_esplorer/modules/optique/splice_screen.dart';
import 'package:nge_esplorer/modules/optique/optical.dart';
import 'package:nge_esplorer/modules/optique/route_panel.dart';
import 'package:nge_esplorer/modules/immeuble/building.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/address_screen.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
import 'package:nge_esplorer/widgets/bottom_bar.dart';
import 'package:nge_esplorer/widgets/support_bar.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> node(String id, String lib, double lon, [Map<String, dynamic> props = const {}]) => {
      'type': 'Feature',
      'id': id,
      'geometry': {'type': 'Point', 'coordinates': [lon, 45.0]},
      'properties': {'classe': 'NOE', 'NOE_LIB': lib, 'TYPE_KEY': 16, ...props},
    };

/// Fibre [num] d'un câble de 12 fibres par tube, couleurs du code Orange.
Map<String, dynamic> fibre(int num) => {
      'FIB_NUM': num,
      'FIB_TUBE': (num - 1) ~/ 12 + 1,
      'FIB_NUM_TUBE': (num - 1) % 12 + 1,
      'COUL_KEY': (num - 1) % 12 + 1,
      'TUBE_COUL_KEY': ((num - 1) ~/ 12) % 12 + 1,
    };

/// Photo [code] du support ou de l'équipement [equipment] : vue attendue [view] ou visuel libre [free].
Map<String, dynamic> photo(String code, {String? view, String? free, String? equipment, int rank = 1}) => {
      'ENTITE': equipment == null ? 'PRJ_NOE' : 'INF_EQUIPEMENT',
      'EQU_KEY': ?equipment,
      'VUE_CODE': ?view,
      if (free != null) ...{'VIS_CODE': free, 'VIS_LIB': 'Étiquettes'},
      'FIC_CODE_EXT': code,
      'FIC_NOM': '$code.jpg',
      'FIC_RANG': rank,
      'FIC_PRINCIPALE': rank == 1 ? 1 : 0,
    };

/// Paquet d'essai (format 0.4.0) : une chambre N1 portant le PBO E1, alimenté par le câble C1 depuis N2 et dont part
/// le câble C2 vers N3 ; ses cassettes (passages, attentes, épissures), deux mesures ; une seconde boîte E2, sans
/// contenu optique ; photos du support (environnement, et une photo d'équipement d'un paquet antérieur, sans
/// `EQU_KEY`) et du PBO (boîtier ouvert, visuel libre) ; l'adresse A1 et deux locaux desservis par le PBO.
Bundle opticalBundle() => Bundle(
      header: {
        'format': Bundle.format,
        'version': Bundle.version,
        'date': '2026-11-05T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
        'modules': {'noyau': '0.2.0', 'infra': '0.2.0', 'optique': '0.1.0', 'immeuble': '0.1.0'},
      },
      objects: [
        for (final f in [
          node('N1', 'CHA-2-0011', 2.0, {
            'ADR_KEY': 'A1',
            'inf': {
              'equipements': [
                {'EQU_CODE_EXT': 'E1', 'MAT_KEY': 10, 'EQU_QTE': 1},
                {'EQU_CODE_EXT': 'E2', 'MAT_KEY': 10, 'EQU_QTE': 1},
              ],
            },
            'fichiers': [
              photo('F1', view: 'ENV'),
              {...photo('F2', view: 'ENV', rank: 2), 'ENTITE': 'INF_EQUIPEMENT'},
              photo('F3', view: 'OUVERT', equipment: 'E1'),
              photo('F4', free: 'V1', equipment: 'E1'),
            ],
            'opt': {
              'equipements': [
                {
                  'EQU_KEY': 'E1',
                  'EQO_LIB': 'PBO-2-02HG-1015',
                  'OTYP_KEY': 2,
                  'EQO_CAPA': 36,
                  'cassettes': [
                    {
                      'CAS_NUM': 0,
                      'positions': [
                        {'POS_NUM': 1, 'CAB1_KEY': 'C1', 'FIB1_NUM': 1, 'CAB2_KEY': 'C2', 'FIB2_NUM': 1, 'PFON_KEY': 2,
                          'POS_AFFECT': 'PASSAGE'},
                      ],
                    },
                    {
                      'CAS_NUM': 1,
                      'CTYP_KEY': 2,
                      'positions': [
                        {'POS_NUM': 1, 'CAB1_KEY': 'C1', 'FIB1_NUM': 14, 'PFON_KEY': 3, 'POS_AFFECT': 'ABONNE'},
                        {'POS_NUM': 2, 'CAB1_KEY': 'C1', 'FIB1_NUM': 15, 'CAB2_KEY': 'C2', 'FIB2_NUM': 157,
                          'PFON_KEY': 1, 'POS_CONNECTEUR': 'SFU'},
                      ],
                    },
                  ],
                  'mesures': [
                    {'MES_CODE_EXT': 'M1', 'CAB_KEY': 'C1', 'FIB_NUM': 14, 'MES_CABLE': 'CDI-1015_MSB', 'MES_FIBRE': 55,
                      'MES_LAMBDA': 1550, 'MES_SENS': 'OE', 'MES_LNG': 1168.112, 'MES_PERTE': 0.572, 'MES_CONFORME': 1,
                      'MES_ORIGINE': 'SRO', 'MES_EXTREMITE': 'PBO', 'MES_DATE': '2026-04-06T10:39:45Z'},
                    {'MES_CODE_EXT': 'M2', 'CAB_KEY': 'C1', 'FIB_NUM': 15, 'MES_CABLE': 'CDI-1015_MSB', 'MES_FIBRE': 56,
                      'MES_LAMBDA': 1550, 'MES_SENS': 'OE', 'MES_LNG': 1168.1, 'MES_PERTE': 1.2, 'MES_CONFORME': 0},
                  ],
                },
              ],
            },
          }),
          node('N2', 'CHA-2-0010', 2.001),
          // PBO E3 au bout du câble C2 : la fibre 157 y est en attente
          node('N3', 'CHA-2-0012', 2.002, {
            'inf': {
              'equipements': [
                {'EQU_CODE_EXT': 'E3', 'MAT_KEY': 10, 'EQU_QTE': 1},
              ],
            },
            'opt': {
              'equipements': [
                {
                  'EQU_KEY': 'E3',
                  'EQO_LIB': 'PBO-2-02HG-1016',
                  'OTYP_KEY': 2,
                  'cassettes': [
                    {
                      'CAS_NUM': 2,
                      'positions': [
                        {'POS_NUM': 4, 'CAB1_KEY': 'C2', 'FIB1_NUM': 157, 'PFON_KEY': 3},
                      ],
                    },
                  ],
                },
              ],
            },
          }),
          {
            'type': 'Feature',
            'id': 'C1',
            'geometry': null,
            'properties': {
              'classe': 'CAB', 'CAB_LIB': 'CDI-2-02HG-1010', 'CAB_CAPA': 24, 'CFON_KEY': 7, 'NOE1_KEY': 'N2',
              'NOE2_KEY': 'N1', 'EQU2_KEY': 'E1',
              'passages': [
                {'LIN_KEY': 'L1', 'PAS_RANG': 1},
                {'LIN_KEY': 'L2', 'PAS_RANG': 2},
              ],
              'fibres': [for (var i = 1; i <= 24; i++) fibre(i)],
            },
          },
          {
            'type': 'Feature',
            'id': 'C2',
            'geometry': null,
            'properties': {
              'classe': 'CAB', 'CAB_LIB': 'CDI-2-02HG-1020', 'CAB_CAPA': 288, 'NOE1_KEY': 'N1', 'NOE2_KEY': 'N3',
              'EQU1_KEY': 'E1', 'EQU2_KEY': 'E3',
              'fibres': [fibre(1), fibre(157)],
            },
          },
          // raccordement final du PBO à l'adresse A1, à son tracé propre (format 0.5.0)
          {
            'type': 'Feature',
            'id': 'C3',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [2.0, 45.0],
                [2.0, 45.0001],
              ],
            },
            'properties': {
              'classe': 'CAB', 'CAB_LIB': 'RAC-1015-1', 'CAB_CAPA': 1, 'CFON_KEY': 8, 'NOE1_KEY': 'N1',
              'EQU1_KEY': 'E1', 'ADR2_KEY': 'A1',
            },
          },
          {
            'type': 'Feature',
            'id': 'A1',
            'geometry': {'type': 'Point', 'coordinates': [2.0, 45.0001]},
            'properties': {
              'classe': 'ADR', 'ADR_NUMERO': 1, 'ADR_VOIE': 'RUE VOLTAIRE', 'ADR_COMMUNE': 'HUSSIGNY-GODBRANGE',
              'imb': {
                'HAB_KEY': 2, 'IAD_NB_LOG': 7, 'IAD_NB_PRO': 1, 'IAD_NB_PRISE_LOG': 7, 'IAD_NB_PRISE_PRO': 1,
                'IAD_CONV_DATE': '2025-03-12',
                'locaux': [
                  {'LOC_CODE_EXT': 'L1', 'LTYP_KEY': 1, 'RACCO_KEY': 1, 'LOC_ESCALIER': '1', 'LOC_ETAGE': '2',
                    'LOC_LIB': '1', 'EQU_KEY': 'E1'},
                  {'LOC_CODE_EXT': 'L2', 'LTYP_KEY': 2, 'EQU_KEY': 'E1'},
                ],
              },
            },
          },
        ])
          GeoObject.fromFeature(f),
      ],
      referenceData: ReferenceData({
        'noyau': {
          'DEF_TYPE': [
            {'TYPE_ID': 3, 'TYPE_CODE': 'INF', 'TYPE_LIB': 'Support'},
            {'TYPE_ID': 16, 'TYPE_CODE': 'CHB', 'TYPE_LIB': 'Chambre', 'TYPE_PARENT_KEY': 3},
          ],
          'DEF_VUE': [
            {'TYPE_KEY': 16, 'VUE_CODE': 'ENV', 'VUE_LIB': 'Environnement', 'VUE_ORDRE': 1, 'VUE_OBLIGATOIRE': 'OUI'},
            for (final (i, (code, lib)) in const [
              ('FERME', 'Boîtier fermé'), ('OUVERT', 'Boîtier ouvert'), ('CASSETTES', 'Cassettes'),
              ('MESURES', 'Mesures photométriques'),
            ].indexed)
              {'VUE_ENTITE': 'INF_EQUIPEMENT', 'VUE_CODE': code, 'VUE_LIB': lib, 'VUE_ORDRE': i + 1,
                'VUE_OBLIGATOIRE': 'NON'},
          ],
        },
        'infra': {
          'MAT_EQUIP': [
            {'MAT_ID': 10, 'MAT_LIB': 'PBO - MICRO MANCHON 36 FO', 'MAT_CAPAEPIS': 36},
          ],
        },
        'optique': {
          'DEF_OPT_EQUIP_TYPE': [
            {'OTYP_ID': 2, 'OTYP_CODE': 'PBO', 'OTYP_LIB': 'Point de branchement optique'},
          ],
          'DEF_CAB_FONCTION': [
            {'CFON_ID': 7, 'CFON_CODE': 'DI', 'CFON_LIB': 'Distribution'},
            {'CFON_ID': 8, 'CFON_CODE': 'RA', 'CFON_LIB': 'Raccordement final'},
          ],
          'DEF_CASSETTE_TYPE': [
            {'CTYP_ID': 2, 'CTYP_CODE': 'E', 'CTYP_LIB': 'Épissures'},
          ],
          'DEF_POS_FONCTION': [
            {'PFON_ID': 1, 'PFON_CODE': 'EP', 'PFON_LIB': 'Épissure'},
            {'PFON_ID': 2, 'PFON_CODE': 'PA', 'PFON_LIB': 'Passage'},
            {'PFON_ID': 3, 'PFON_CODE': 'AT', 'PFON_LIB': 'Attente'},
          ],
          'DEF_FO_COULEUR': [
            for (final (i, (code, lib, rgb)) in const [
              ('R', 'Rouge', '#FF0000'), ('BL', 'Bleu', '#0070C0'), ('VE', 'Vert', '#92D050'), ('J', 'Jaune', '#FFFF00'),
              ('V', 'Violet', '#7638A3'), ('B', 'Blanc', '#FFFFFF'), ('OR', 'Orange', '#FFC000'), ('GR', 'Gris', '#C1C1C1'),
              ('BR', 'Marron', '#993300'), ('N', 'Noir', '#000000'), ('TU', 'Turquoise', '#00B0F0'),
              ('RS', 'Rose', '#FF65CC'),
            ].indexed)
              {'COUL_ID': i + 1, 'COUL_CODE': code, 'COUL_LIB': lib, 'COUL_RGB': rgb},
          ],
        },
        'immeuble': {
          'DEF_IMB_HABITAT': [
            {'HAB_ID': 1, 'HAB_CODE': 'P', 'HAB_LIB': 'Pavillon'},
            {'HAB_ID': 2, 'HAB_CODE': 'I', 'HAB_LIB': 'Immeuble'},
          ],
          'DEF_LOC_TYPE': [
            {'LTYP_ID': 1, 'LTYP_CODE': 'R', 'LTYP_LIB': 'Résidentiel'},
            {'LTYP_ID': 2, 'LTYP_CODE': 'P', 'LTYP_LIB': 'Professionnel'},
          ],
          'DEF_LOC_RACCO': [
            {'RACCO_ID': 1, 'RACCO_CODE': 'PR', 'RACCO_LIB': 'Programmé'},
          ],
        },
      }),
    );

Future<(MemoryRepository, AppProvider)> load() async {
  final repo = MemoryRepository();
  await repo.load(opticalBundle());
  return (repo, AppProvider(repo));
}

Future<void> pump(WidgetTester t, AppProvider app, Widget home, {Size size = const Size(360, 800)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: home),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('dépôt : câbles d\'un nœud, nœud d\'un équipement, adresses desservies, tenus à jour à l\'enregistrement',
      () async {
    final (repo, app) = await load();
    expect((await repo.cablesOf('N1')).map((c) => c.id), unorderedEquals(['C1', 'C2', 'C3']));
    expect((await repo.cablesOf('N2')).map((c) => c.id), ['C1']);
    // raccordement : extrémité aval à l'adresse, emprise de son tracé propre
    final r = (await repo.object('C3'))!;
    expect([r.noe2, r.adr2, r.bounds], [null, 'A1', [2.0, 45.0, 2.0, 45.0001]]);
    expect((await repo.objectsInBounds([1.9, 44.9, 2.1, 45.1], classes: {ObjectClass.cab})).map((c) => c.id), ['C3']);
    expect((await repo.nodeOfEquipment('E1'))?.id, 'N1');
    expect((await repo.addressesServedBy('E1')).map((a) => a.id), ['A1']);

    // locaux retirés de l'adresse, équipement retiré du nœud : les index suivent
    final a = (await repo.object('A1'))!.copy();
    a.namespace('imb')!.remove('locaux');
    await app.save(a);
    expect(await repo.addressesServedBy('E1'), isEmpty);
    final n = (await repo.object('N1'))!.copy();
    n.props.remove('inf');
    await app.save(n);
    expect(await repo.nodeOfEquipment('E1'), isNull);
    expect((await repo.cablesOf('N1')).map((c) => c.id), unorderedEquals(['C1', 'C2', 'C3']));
  });

  test('recherche : support par son étiquette, ses équipements, ses câbles, son adresse et celles que dessert son PBO',
      () async {
    final (repo, app) = await load();
    List<(String, SearchMatch, String)> found(List<SearchHit> l) => [for (final h in l) (h.support.id, h.match, h.text)];
    expect(found(await repo.search('cha-2-0011')), [('N1', SearchMatch.support, 'CHA-2-0011')]);
    expect(found(await repo.search('PBO-2')),
        unorderedEquals([('N1', SearchMatch.equipment, 'PBO-2-02HG-1015'), ('N3', SearchMatch.equipment, 'PBO-2-02HG-1016')]));
    expect((await repo.search('pbo-2-02hg-1015')).single.equipment, 'E1');
    // câble : un résultat par extrémité
    expect(found(await repo.search('cdi-2-02hg-1010')), unorderedEquals([
      ('N2', SearchMatch.cable, 'CDI-2-02HG-1010'),
      ('N1', SearchMatch.cable, 'CDI-2-02HG-1010'),
    ]));
    // adresse : le support qui la porte (ADR_KEY), le support du PBO qui dessert ses locaux ; espaces superflus ignorés
    expect(found(await repo.search('  1 rue   voltaire ')), [
      ('N1', SearchMatch.address, '1 RUE VOLTAIRE HUSSIGNY-GODBRANGE'),
      ('N1', SearchMatch.servedAddress, '1 RUE VOLTAIRE HUSSIGNY-GODBRANGE'),
    ]);
    // les textes trouvés les plus courts d'abord
    expect(found(await repo.search('2-0')).map((f) => f.$3).take(3), ['CHA-2-0010', 'CHA-2-0011', 'CHA-2-0012']);
    expect(await repo.search(' '), isEmpty);

    // équipement abandonné : plus trouvé ; support abandonné : ni lui ni ses entités
    final n = (await repo.object('N1'))!.copy();
    (n.namespace('inf')!['equipements'] as List).first['DATE_ABD'] = '2026-11-05T08:00:00Z';
    await app.save(n);
    expect(await repo.search('PBO-2-02HG-1015'), isEmpty);
    await app.save((await repo.object('N1'))!.copy(), abandon: true);
    expect(found(await repo.search('cdi-2-02hg-1010')), [('N2', SearchMatch.cable, 'CDI-2-02HG-1010')]);
    expect(await repo.search('voltaire'), isEmpty);
  });

  test('dépôt : câbles tirés sur chaque linéaire de leur parcours (couche Tirage), abandon compris', () async {
    final (repo, app) = await load();
    final on = await repo.cablesOnLinears(['L1', 'L2', 'L3']);
    expect(on.keys, ['L1', 'L2']);
    expect(on['L1']!.map((c) => c.id), ['C1']);
    // parcours modifié : l'index suit ; câble abandonné : plus tiré
    final c1 = (await repo.object('C1'))!.copy();
    (c1.props['passages'] as List).removeLast();
    await app.save(c1);
    expect((await repo.cablesOnLinears(['L1', 'L2'])).keys, ['L1']);
    await app.save((await repo.object('C1'))!.copy(), abandon: true);
    expect(await repo.cablesOnLinears(['L1', 'L2']), isEmpty);
  });

  test('route optique : de proche en proche par les positions, de l\'amont (hors du paquet) à l\'attente du PBO '
      'aval', () async {
    final (repo, app) = await load();
    final n = (await repo.object('N1'))!;
    final p = Optical.positions(Optical.cassettes(Optical.of(n, 'E1')).last).last;
    final route = await OpticalRoute.trace(repo, n, 'E1', p);
    expect([for (final h in route) h.node?.id], ['N2', 'N1', 'N3']);
    expect([for (final h in route) h.equipment], [null, 'E1', 'E3']);
    // amont : C1 sans équipement de départ, suite hors du paquet (fibre 15 du câble, vers N2)
    expect([route.first.position, route.first.fibreOut], [null, (cable: 'C1', num: 15)]);
    expect([route[1].fibreIn, route[1].fibreOut], [(cable: 'C1', num: 15), (cable: 'C2', num: 157)]);
    expect([route.last.position?['POS_NUM'], route.last.fibreIn, route.last.fibreOut], [4, (cable: 'C2', num: 157), null]);
    // liens à la légende FibReady : fusion au PBO E1, attente simple (sans affectation) au PBO E3
    expect([for (final h in route.skip(1)) FibreLink.ofPosition(h.position!, app.referenceData)?.symbol], ['-x-', '-o']);
    // attentes distinguées par leur affectation (connecteurs.csv de FibReady, liens du FBT d'Evicom)
    expect([
      for (final (f, a) in const [('CO', 'DEPART'), ('EP', null), ('PA', 'PASSAGE'), ('PA', 'SURCAPA'), ('AT', 'ABONNE'),
        ('AT', 'RESERVE'), ('AT', 'MORTE'), ('AT', 'SURCAPA'), ('AT', null), ('XX', null)])
        FibreLink.of(f, a)?.symbol,
    ], ['o-', '-x-', '<@>', '<@>', '-#', '-R', '-ø', '-o', '-o', null]);
    // prise abonné : seulement quand la fibre s'achève à la PTO du logement ; au PBO, attente abonné
    final abonne = {'CAB1_KEY': 'C2', 'FIB1_NUM': 3, 'PFON_KEY': 3, 'POS_AFFECT': 'ABONNE'};
    expect([
      FibreLink.ofPosition(abonne, app.referenceData, equipmentType: 'PBO'),
      FibreLink.ofPosition(abonne, app.referenceData, equipmentType: 'PTO'),
      FibreLink.ofPosition({'CAB1_KEY': 'C2', 'FIB1_NUM': 3, 'PFON_KEY': 4}, app.referenceData, equipmentType: 'PTO'),
      FibreLink.ofPosition({...abonne, 'CAB2_KEY': 'C3', 'FIB2_NUM': 1}, app.referenceData, equipmentType: 'PTO'),
    ].map((l) => l?.lib), ['Attente abonné', 'Prise abonné', 'Prise abonné', 'Attente abonné']);
  });

  test('route optique : un câble arrivé à une baie (SRO) remonte au connecteur de l\'un de ses tiroirs', () async {
    final repo = MemoryRepository();
    final b = opticalBundle();
    // C1 part de la baie B0 de N2, dont le tiroir T1 porte le connecteur de la fibre 15
    b.objects.firstWhere((o) => o.id == 'C1').props['EQU1_KEY'] = 'B0';
    b.objects.firstWhere((o) => o.id == 'N2').props
      ..['inf'] = {
        'equipements': [
          {'EQU_CODE_EXT': 'B0', 'MAT_KEY': 10},
          {'EQU_CODE_EXT': 'T1', 'MAT_KEY': 10},
        ],
      }
      ..['opt'] = {
        'equipements': [
          {'EQU_KEY': 'B0', 'EQO_LIB': 'BAIE-1'},
          {
            'EQU_KEY': 'T1',
            'EQO_LIB': 'TIROIR-1',
            'EQO_PARENT_KEY': 'B0',
            'cassettes': [
              {
                'CAS_NUM': 1,
                'positions': [
                  {'POS_NUM': 7, 'CAB2_KEY': 'C1', 'FIB2_NUM': 15, 'PFON_KEY': 4},
                ],
              },
            ],
          },
        ],
      };
    await repo.load(b);
    final n2 = (await repo.object('N2'))!;
    expect(Optical.descendants(n2, 'B0'), ['T1']);
    final n = (await repo.object('N1'))!;
    final p = Optical.positions(Optical.cassettes(Optical.of(n, 'E1')).last).last;
    final route = await OpticalRoute.trace(repo, n, 'E1', p);
    expect([for (final h in route) h.equipment], ['T1', 'E1', 'E3']);
    expect([route.first.position?['POS_NUM'], route.first.fibreIn, route.first.fibreOut], [7, null, (cable: 'C1', num: 15)]);
    // attente en amont (fibre de réserve) : notée #-
  });

  testWidgets('écran Optique : la route se déplie sous le connecteur touché ; une étape touchée bascule aussitôt sur '
      'son boîtier, sur son connecteur, la route toujours dépliée ; replier est volontaire', (t) async {
    // PBO d'arrivée E3 aux nombreux raccordements : la liste des câbles raccordés, chargée après la première image,
    // s'insère au-dessus des cassettes ; le connecteur doit rester à l'écran
    final bundle = opticalBundle();
    bundle.objects.addAll([
      for (var i = 1; i <= 12; i++)
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'R$i',
          'geometry': null,
          'properties': {'classe': 'CAB', 'CAB_LIB': 'RAC-1016-$i', 'CAB_CAPA': 1, 'CFON_KEY': 8, 'NOE1_KEY': 'N3',
            'EQU1_KEY': 'E3', 'ADR2_KEY': 'A1'},
        }),
    ]);
    final repo = MemoryRepository();
    await repo.load(bundle);
    // affichage simplifié (version précédente, conservée) ; la charte FibReady a son propre essai
    final app = AppProvider(repo)..setFibReadyChart(false);
    // ouvert comme depuis l'écran dédié de l'équipement (onglet liens:E1)
    await pump(
      t,
      app,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => openTab(
            context,
            (await repo.object('N1'))!,
            SpliceScreen.tab('E1'),
            (o) => SpliceScreen(node: o, equipment: 'E1'),
          ),
          child: const Text('ouvrir'),
        ),
      ),
    );
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    Finder inRoute(Finder f) => find.descendant(of: find.byType(RoutePanel), matching: f);
    Color? tileColor(String label) =>
        t.widget<Material>(find.ancestor(of: inRoute(find.text(label)), matching: find.byType(Material)).first).color;

    await t.ensureVisible(find.text('SFU'));
    await t.pumpAndSettle();
    await t.tap(find.text('SFU'));
    await t.pumpAndSettle();
    expect(find.byType(RoutePanel), findsOneWidget);
    expect(find.text('Route optique · 2 liens'), findsOneWidget);
    expect(inRoute(find.text('CHA-2-0010 · suite hors du paquet')), findsOneWidget);
    // adresse du support à la place de son étiquette (maquette), son picto à la place du type ; étiquette préfixée
    // du type si elle ne le porte pas
    expect(inRoute(find.text('1 RUE VOLTAIRE HUSSIGNY-GODBRANGE · K1 · P2')), findsOneWidget);
    expect(inRoute(find.text('CHA-2-0011 · K1 · P2')), findsNothing);
    expect(inRoute(find.byType(SupportSymbol)), findsNWidgets(3));
    expect(inRoute(find.text('PBO-2-02HG-1015')), findsOneWidget);
    expect(inRoute(find.text('PBO')), findsNothing);
    // une seule mention par lien, ni symbole ni légende : fusion au PBO, attente simple au PBO aval
    expect(inRoute(find.text('Fusion')), findsOneWidget);
    expect(inRoute(find.text('Attente')), findsOneWidget);
    expect(inRoute(find.text('-x-')), findsNothing);
    // étape du boîtier affiché en évidence
    expect(tileColor('PBO-2-02HG-1015'), Nge.yellow.withValues(alpha: 0.35));

    // toucher le connecteur à nouveau : la route se replie, sans changer d'écran
    await t.tap(find.text('SFU'));
    await t.pumpAndSettle();
    expect(find.byType(RoutePanel), findsNothing);
    expect(screenStack.shown?.tab, 'liens:E1');

    // une étape touchée : bascule aussitôt sur son boîtier, sur son connecteur, la route toujours dépliée dessous
    await t.tap(find.text('SFU'));
    await t.pumpAndSettle();
    await t.ensureVisible(inRoute(find.text('PBO-2-02HG-1016')));
    await t.pumpAndSettle();
    await t.tap(inRoute(find.text('PBO-2-02HG-1016')));
    await t.pumpAndSettle();
    expect([screenStack.shown?.id, screenStack.shown?.tab], ['N3', 'liens:E3']);
    expect(find.byType(RoutePanel), findsOneWidget);
    expect(tileColor('PBO-2-02HG-1016'), Nge.yellow.withValues(alpha: 0.35));
    expect(tileColor('PBO-2-02HG-1015'), Colors.transparent);
    // le connecteur concerné : sa cassette dépliée, lui à l'écran (dans la zone qui défile, au-dessus de la barre
    // basse), en évidence, une fois les câbles raccordés chargés
    expect(find.text('RAC-1016-12'), findsOneWidget);
    final row = find.ancestor(of: find.text('4'), matching: find.byType(Material)).first;
    expect(t.widget<Material>(row).color, Nge.yellow.withValues(alpha: 0.35));
    final body = t.getRect(find.byType(SingleChildScrollView));
    final shown = t.getRect(find.text('4'));
    expect(shown.top >= body.top && shown.bottom <= body.bottom, isTrue, reason: '$shown dans $body');

    // replier : volontaire, on reste sur ce boîtier
    await t.ensureVisible(find.text('Replier'));
    await t.pumpAndSettle();
    await t.tap(find.text('Replier'));
    await t.pumpAndSettle();
    expect(find.byType(RoutePanel), findsNothing);
    expect([screenStack.shown?.id, screenStack.shown?.tab], ['N3', 'liens:E3']);
  });

  test('écran Optique : seule la première cassette est dépliée par défaut, hors passages hors cassettes', () {
    expect(SpliceScreen.firstCassette([{'CAS_NUM': 0}, {'CAS_NUM': 1}, {'CAS_NUM': 2}]), 1);
    expect(SpliceScreen.firstCassette([{'CAS_NUM': 3}, {'CAS_NUM': 4}]), 3);
    expect(SpliceScreen.firstCassette([{'CAS_NUM': 0}]), 0);
    expect(SpliceScreen.firstCassette([]), isNull);
  });

  test('route optique : étiquette préfixée de la fonction de l\'équipement si elle ne la porte pas ; adresse complète',
      () async {
    final (repo, app) = await load();
    final n = (await repo.object('N1'))!.copy();
    (n.namespace('opt')!['equipements'] as List).first['EQO_LIB'] = '01B19X';
    RouteHop hop(GeoObject node) => (node: node, equipment: 'E1', position: null, fibreIn: null, cableIn: null,
        fibreOut: null, cableOut: null, address: null);
    expect(hopLabel(hop(n), app.referenceData), 'PBO 01B19X');
    expect(hopLabel(hop((await repo.object('N1'))!), app.referenceData), 'PBO-2-02HG-1015');
    final a = (await repo.object('A1'))!.copy()..props.addAll({'ADR_CP': '54860'});
    expect(fullAddressLabel(a), '1 RUE VOLTAIRE 54860 HUSSIGNY-GODBRANGE');
  });

  test('charte FibReady : devenir de la fibre (fond du connecteur), couleurs des fibres', () {
    const a = FibreLink.subscriberWait, x = FibreLink.splice, r = FibreLink.reserve, o = FibreLink.start;
    // vers une attente abonné : vert, le lien de l'attente compris
    expect([for (var i = 0; i < 3; i++) FibReadyChart.fateOf([o, x, a], i)], List.filled(3, FibreFate.outlet));
    // vers une réserve : violet ; au-delà d'une prise abonné : orange
    expect(FibReadyChart.fateOf([o, x, r], 1), FibreFate.reserve);
    expect(FibReadyChart.fateOf([o, a, x, FibreLink.wait], 2), FibreFate.beyondOutlet);
    // suite hors du paquet, attente simple : jaune pâle
    expect(FibReadyChart.fateOf([null, x, FibreLink.wait], 1), FibreFate.other);
    expect(FibReadyChart.fateOf([o, x, null], 1), FibreFate.other);
    // couleurs FibReady (param_fiber_colours.csv) : rouge, bleu, vert ; au-delà de 12, de nouveau
    expect([FibReadyChart.colorOfRank(1).$1, FibReadyChart.colorOfRank(3).$1, FibReadyChart.colorOfRank(13).$1],
        [const Color(0xFFFF0000), const Color(0xFFADFF2F), const Color(0xFFFF0000)]);
    expect(FibreFate.outlet.color, const Color(0xFF90EE90));
    // symbole retourné quand la fibre n'est que du côté sortant (règle de FibReady) : départ o-, fibre morte ø-
    String sym(FibreLink? l, bool i, bool o) => FibReadyChart.symbolOf(l, hasIn: i, hasOut: o);
    expect([
      sym(FibreLink.start, false, true),
      sym(FibreLink.wait, true, false),
      sym(FibreLink.wait, false, true),
      sym(FibreLink.dead, false, true),
      sym(FibreLink.dead, true, false),
      sym(FibreLink.reserve, false, true),
      sym(FibreLink.splice, true, true),
      sym(null, true, false),
    ], ['o-', '-o', 'o-', 'ø-', '-ø', 'R-', '-x-', '…']);
    // texte noir ou blanc selon la luminosité du fond (FibReady) : blanc sur violet
    expect([FibreRow.contrastOn(FibreFate.reserve.color), FibreRow.contrastOn(FibreFate.outlet.color)],
        [Colors.white, Colors.black]);
    expect(FibreFate.reserve.color, const Color(0xFF9370DB));
  });

  testWidgets('écran Optique à la charte FibReady (par défaut) : capacité, tube et fibre colorés, connecteur dessiné '
      'sur le fond de la destination de la fibre ; route optique de même', (t) async {
    final (repo, app) = await load();
    expect(app.fibReadyChart, isTrue);
    await pump(t, app, SpliceScreen(node: (await repo.object('N1'))!, equipment: 'E1'));
    // épissure P2 de la cassette 1 : 24Fo T2 F3 -x- F1 T14 288Fo ; attente simple au bout, fond jaune pâle
    expect(find.byType(FibreRow), findsWidgets);
    final splice = find.ancestor(of: find.text('288Fo'), matching: find.byType(FibreRow));
    expect(find.descendant(of: splice, matching: find.text('24Fo')), findsOneWidget);
    expect(find.descendant(of: splice, matching: find.text('T2')), findsOneWidget);
    expect(find.descendant(of: splice, matching: find.text('F3')), findsOneWidget);
    expect(find.descendant(of: splice, matching: find.text('T14')), findsOneWidget);
    expect(t.widget<FibreRow>(splice).link, FibreLink.splice);
    // connecteur par son symbole textuel de FibReady
    expect(find.descendant(of: splice, matching: find.text('-x-')), findsOneWidget);
    expect(t.widget<FibreRow>(splice).fate, FibreFate.other);
    // l'attente abonné : vers une prise ou attente abonné, fond vert
    final wait = find.byWidgetPredicate((w) => w is FibreRow && w.link == FibreLink.subscriberWait);
    expect(wait, findsOneWidget);
    expect(t.widget<FibreRow>(wait).fate, FibreFate.outlet);
    expect(find.text('Attente abonné'), findsNothing);
    expect(find.descendant(of: wait, matching: find.text('-#')), findsOneWidget);
    // route optique : mêmes lignes
    await t.ensureVisible(find.text('288Fo'));
    await t.pumpAndSettle();
    await t.tap(find.text('288Fo'));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(RoutePanel), matching: find.byType(FibreRow)), findsNWidgets(3));

    // variante en pastilles (notes equipements rep7) : badge du câble, ronds du tube et de la fibre, badge du connecteur
    // choisie depuis le menu ⋮ de l'écran Optique
    await t.tap(find.byTooltip('Plus d\'actions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Liens : Pastilles'));
    await t.pumpAndSettle();
    expect(app.linkDisplay, LinkDisplay.badges);
    final badgeRow = find.ancestor(of: find.text('288Fo'), matching: find.byType(FibreRow)).first;
    expect(t.widget<FibreRow>(badgeRow).badges, isTrue);
    expect(find.descendant(of: badgeRow, matching: find.text('14')), findsOneWidget);
    expect(find.descendant(of: badgeRow, matching: find.text('-x-')), findsOneWidget);
    expect(find.descendant(of: badgeRow, matching: find.text('T14')), findsNothing);

    // Paramètres : affichage simplifié (version précédente)
    app.setFibReadyChart(false);
    await t.pumpAndSettle();
    expect(find.byType(FibreRow), findsNothing);
    expect(find.text('Attente abonné'), findsOneWidget);
  });

  test('contenu optique : équipement, cassettes, fibres citées', () async {
    final (repo, _) = await load();
    final n = (await repo.object('N1'))!;
    final e = Optical.of(n, 'E1')!;
    expect(e['EQO_LIB'], 'PBO-2-02HG-1015');
    expect(Optical.of(n, 'E2'), isNull);
    expect(Optical.cassettes(e).map((c) => Optical.positions(c).length), [1, 2]);
    expect(Optical.citedCables(e), {'C1', 'C2'});
    final p = Optical.positions(Optical.cassettes(e).last).last;
    expect([Optical.fibre(p, '1'), Optical.fibre(p, '2')], [(cable: 'C1', num: 15), (cable: 'C2', num: 157)]);
    expect(Optical.fibre(Optical.measures(e).first), (cable: 'C1', num: 14));
    expect([decimal(1168.112), decimal(0.572, 3), decimal(2.0)], ['1168,1', '0,572', '2']);
  });

  test('visuels d\'un équipement, distincts de ceux du support ; photo prise pour un équipement', () async {
    final (repo, app) = await load();
    final n = (await repo.object('N1'))!;
    final support = Visual.of(n, app.referenceData);
    expect(support.map((v) => v.code), ['ENV']);
    // photo d'équipement d'un paquet antérieur (sans EQU_KEY) : restée au support
    expect(n.photos(support.single).map((f) => f['FIC_CODE_EXT']), ['F1', 'F2']);
    final pbo = Visual.ofEquipment(n, 'E1', app.referenceData);
    expect(pbo.map((v) => v.lib), ['Boîtier fermé', 'Boîtier ouvert', 'Cassettes', 'Mesures photométriques', 'Étiquettes']);
    expect([for (final v in pbo) n.photos(v).length], [0, 1, 0, 0, 1]);
    expect(pbo.every((v) => v.equipment == 'E1'), isTrue);
    expect(pbo.last.renamed('Plan').equipment, 'E1');
    final box = Visual.ofEquipment(n, 'E2', app.referenceData);
    expect(box.map((v) => v.code), ['FERME', 'OUVERT', 'CASSETTES', 'MESURES']);
    expect([for (final v in box) n.photos(v).length], [0, 0, 0, 0]);

    final f = n.copy().addPhoto(box.first, name: 'p.jpg', size: 3, author: 'essai');
    expect([f['ENTITE'], f['EQU_KEY'], f['VUE_CODE']], ['INF_EQUIPEMENT', 'E2', 'FERME']);
    final g = n.copy().addPhoto(support.single, name: 'p.jpg', size: 3, author: 'essai');
    expect([g['ENTITE'], g.containsKey('EQU_KEY')], ['PRJ_NOE', isFalse]);
  });

  testWidgets('écran dédié d\'un équipement : fiche, visuels de l\'équipement ; choix parmi les équipements du support',
      (t) async {
    final (repo, app) = await load();
    await pump(t, app, EquipmentScreen(node: (await repo.object('N1'))!, equipment: 'E1'));
    expect(find.text('PBO-2-02HG-1015'), findsOneWidget);
    expect(find.text('Point de branchement optique · CHA-2-0011'), findsOneWidget);
    expect(find.text('PBO - MICRO MANCHON 36 FO'), findsOneWidget);
    // visuels de l'équipement, sans ceux du support ; boîtier ouvert photographié, visuel libre
    for (final lib in ['Boîtier fermé', 'Boîtier ouvert', 'Étiquettes']) {
      await t.scrollUntilVisible(find.text(lib), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(lib), findsOneWidget);
    }
    expect(find.text('Environnement *'), findsNothing);
    expect(find.text('1 photo'), findsNWidgets(2));

    // deux équipements : « Autre équipement » du menu ⋮ propose le choix, l'équipement affiché marqué (la barre basse
    // porte la saisie, notes rep16)
    expect(find.widgetWithText(BarItem, 'Équipements'), findsNothing);
    await t.tap(find.byTooltip('Plus d\'actions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Autre équipement'));
    await t.pumpAndSettle();
    expect(find.text('Équipements de CHA-2-0011'), findsOneWidget);
    expect(find.descendant(of: find.widgetWithText(ListTile, 'PBO-2-02HG-1015'), matching: find.byIcon(Icons.check)),
        findsOneWidget);
    await t.tap(find.widgetWithText(ListTile, 'PBO - MICRO MANCHON 36 FO'));
    await t.pumpAndSettle();
    expect(find.text('équipement · CHA-2-0011'), findsOneWidget);
    expect(screenStack.shown?.tab, 'equipement:E2');
    // boîte d'épissure du catalogue sans contenu optique : écran Optique consultable
    expect(find.widgetWithText(OutlinedButton, 'Optique'), findsOneWidget);
  });

  testWidgets('liens fibres d\'un PBO : boîtier, câbles raccordés, cassettes et positions avec leurs couleurs, mesures, '
      'locaux desservis', (t) async {
    final (repo, app) = await load();
    app.setFibReadyChart(false);
    await pump(t, app, EquipmentScreen(node: (await repo.object('N1'))!, equipment: 'E1'));

    // écran dédié de l'équipement : Optique (liens fibres)
    await t.tap(find.widgetWithText(OutlinedButton, 'Optique'));
    await t.pumpAndSettle();
    expect(find.text('optique'), findsOneWidget);
    expect(screenStack.shown?.tab, 'liens:E1');
    expect(find.text('36 fibres'), findsOneWidget);

    // câbles : arrivée depuis N2, départ vers N3
    expect(find.text('24 FO · Distribution · depuis CHA-2-0010'), findsOneWidget);
    expect(find.text('288 FO · vers CHA-2-0012'), findsOneWidget);
    // raccordement final : vers l'adresse desservie
    expect(find.text('1 FO · Raccordement final · vers 1 RUE VOLTAIRE'), findsOneWidget);

    // cassette 1 dépliée : attente d'une fibre, épissure de deux ; tube 14 du câble de 288 : une bague noire
    expect(find.text('CASSETTE 1 — ÉPISSURES'), findsOneWidget);
    // une seule mention du lien : « Attente abonné » dit la fonction et l'affectation (ni symbole, ni « ABONNE ») ;
    // pas « prise abonné » : la prise (PTO) est dans le logement
    expect(find.text('Attente abonné'), findsOneWidget);
    expect(find.text('Prise abonné'), findsNothing);
    expect(find.text('ABONNE'), findsNothing);
    expect(find.text('Attente'), findsNothing);
    expect(find.text('-#'), findsNothing);
    expect(find.text('CDI-2-02HG-1010  T2 F2  (14)'), findsOneWidget);
    expect(find.text('CDI-2-02HG-1020  T14 F1  (157)'), findsOneWidget);
    expect(find.byTooltip('Tube 14 : Bleu, 1 bague noire'), findsOneWidget);
    expect(find.byTooltip('Fibre 2 : Bleu'), findsOneWidget);
    // passages hors cassettes : pliés
    expect(find.text('PASSAGES HORS CASSETTES'), findsOneWidget);
    expect(find.text('Passage lové'), findsNothing);
    await t.tap(find.text('PASSAGES HORS CASSETTES'));
    await t.pumpAndSettle();
    expect(find.text('Passage lové'), findsOneWidget);
    expect(find.text('PASSAGE'), findsNothing);

    // mesures : une hors seuils ; locaux desservis par le PBO
    await t.scrollUntilVisible(find.text('LOCAUX DESSERVIS'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('2 mesures · 1 hors seuils'), findsOneWidget);
    expect(find.text('CDI-1015_MSB · fibre 55 · 1550 nm · OE'), findsOneWidget);
    expect(find.text('1168,1 m · 0,572 dB · SRO → PBO · 06/04/2026'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('1 RUE VOLTAIRE'), findsOneWidget);
    expect(find.text('2 locaux (Résidentiel 1, Professionnel 1)'), findsOneWidget);
  });

  testWidgets('adresse d\'un support : immeuble, BAL et locaux de l\'adresse du paquet, avec leur PBO', (t) async {
    final (repo, app) = await load();
    final n = (await repo.object('N1'))!;
    // tablette : boutons Détacher, Annuler et Valider sur une ligne avec la police des essais
    await pump(t, app, AddressScreen(node: n, current: await repo.object('A1')), size: const Size(800, 1280));
    await t.scrollUntilVisible(find.text('LOCAUX'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('IMMEUBLE ET BAL'), findsOneWidget);
    expect(find.text('Immeuble'), findsOneWidget);
    expect(find.text('signée le 12/03/2025'), findsOneWidget);
    expect(find.text('2 locaux (Résidentiel 1, Professionnel 1)'), findsOneWidget);
    await t.scrollUntilVisible(find.text('esc. 1 · étage 2 · local 1'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Résidentiel · Programmé · PBO-2-02HG-1015'), findsOneWidget);
    expect(find.text('Professionnel · PBO-2-02HG-1015'), findsOneWidget);
  });
}
