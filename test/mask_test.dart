import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/data/visuals.dart';
import 'package:nge_esplorer/modules/chambre/mask_editor.dart';
import 'package:nge_esplorer/modules/chambre/mask_screen.dart';
import 'package:nge_esplorer/screens/object_screen.dart';
import 'package:nge_esplorer/screens/visuals_screen.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
import 'package:nge_esplorer/widgets/fields.dart';
import 'package:nge_esplorer/widgets/svg_icon.dart';
import 'package:nge_esplorer/widgets/support_link.dart';
import 'package:nge_esplorer/map/symbols.dart';
import 'package:nge_esplorer/modules/chambre/mask_overview_screen.dart';
import 'package:nge_esplorer/widgets/bottom_bar.dart';
import 'package:provider/provider.dart';

GeoObject node(String id, String lib, double lon, [Map<String, dynamic>? chb]) => GeoObject.fromFeature({
      'type': 'Feature',
      'id': id,
      'geometry': {'type': 'Point', 'coordinates': [lon, 45.0]},
      'properties': {'classe': 'NOE', 'NOE_LIB': lib, 'TYPE_KEY': 16, 'chb': ?chb},
    });

/// Deux chambres reliées par un parcours souterrain portant une conduite, placée au centre de la face A de C1,
/// relevée dans FOA Explorer (fenêtre de 0,567 × 0,54 m ; repère métrique du module chambre 0.3.0).
Bundle bundle() => Bundle(
      header: {
        'format': Bundle.format,
        'version': Bundle.version,
        'date': '2026-11-02T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
        'modules': {'noyau': '0.2.0', 'infra': '0.1.0', 'chambre': '0.3.0'},
      },
      objects: [
        node('C1', 'C597', 2.0, {
          'faces': [
            {
              'FAC_CODE': 'A',
              'FAC_LARG': 0.567,
              'FAC_HAUT': 0.54,
              'positions': [
                {'CD_KEY': 'CD1', 'POS_X': 0.2835, 'POS_Y': 0.27, 'POS_MIROIR': 0},
              ],
            },
          ],
        })
          ..props['ADR_KEY'] = 'A1',
        node('C2', 'C598', 2.001),
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'A1',
          'geometry': null,
          'properties': {'classe': 'ADR', 'ADR_NUMERO': 12, 'ADR_VOIE': 'rue des Lilas', 'ADR_CP': '54600', 'ADR_COMMUNE': 'Villers'},
        }),
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'L2',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [2.0, 45.0],
              [2.001, 45.0],
            ],
          },
          'properties': {
            'classe': 'LIN',
            'TYPE_KEY': 1001,
            'NOE1_KEY': 'C1',
            'NOE2_KEY': 'C2',
            'inf': {
              'conduites': [
                {'CD_CODE_EXT': 'CD1', 'CD_NUM': 1, 'CD_DIAM': 45.0, 'ETAT_KEY': 2},
              ],
            },
          },
        }),
      ],
      referenceData: ReferenceData({
        'noyau': {
          'DEF_TYPE': [
            {'TYPE_ID': 3, 'TYPE_CODE': 'INF', 'TYPE_LIB': 'Support'},
            {'TYPE_ID': 16, 'TYPE_CODE': 'CHB', 'TYPE_LIB': 'Chambre', 'TYPE_PARENT_KEY': 3},
            {'TYPE_ID': 17, 'TYPE_CODE': 'CHB-FT', 'TYPE_LIB': 'Chambre FT', 'TYPE_PARENT_KEY': 16},
          ],
          'DEF_VUE': [
            {'TYPE_KEY': 16, 'VUE_CODE': 'A', 'VUE_LIB': 'Vue A', 'VUE_ORDRE': 1, 'VUE_OBLIGATOIRE': 'SI_MASQUE', 'VUE_ACTION': 'MASQUE'},
            {'TYPE_KEY': 16, 'VUE_CODE': 'B', 'VUE_LIB': 'Vue B', 'VUE_ORDRE': 2, 'VUE_OBLIGATOIRE': 'SI_MASQUE', 'VUE_ACTION': 'MASQUE'},
          ],
        },
        'chambre': {
          'MAT_CHAMBRE': [
            {'MAT_ID': 36, 'MAT_LIB': 'OHN', 'CHB_LNG_INT': 0.0, 'CHB_LARG_INT': 0.0, 'CHB_HAUT_INT': 0.0},
            {'MAT_ID': 5, 'MAT_LIB': 'L2C', 'CHB_LNG_INT': 1.16, 'CHB_LARG_INT': 0.38, 'CHB_HAUT_INT': 0.6},
          ],
        },
        'infra': {
          'DEF_SUPPORT_IMPLANT': [
            {'IMPS_ID': 1, 'IMPS_CODE': 'CHS', 'IMPS_LIB': 'Chaussée'},
            {'IMPS_ID': 2, 'IMPS_CODE': 'TRT', 'IMPS_LIB': 'Trottoir'},
          ],
          'MAT_EQUIP': [
            {'MAT_ID': 1, 'MAT_LIB': 'Boîte Epissures 144x', 'MAT_REF': 'FIST-GCO2-BC6', 'MAT_CAPAEPIS': 144},
            {'MAT_ID': 2, 'MAT_LIB': 'Manchon', 'MAT_REF': 'MCH-1'},
          ],
          'DEF_CD_ETAT': [
            {'ETAT_ID': 0, 'ETAT_CODE': 'V', 'ETAT_LIB': 'Vide', 'ETAT_COULEUR': '#FFFFFF'},
            {'ETAT_ID': 1, 'ETAT_CODE': 'R', 'ETAT_LIB': 'Réservée', 'ETAT_COULEUR': '#1E6FD9'},
            {'ETAT_ID': 2, 'ETAT_CODE': 'X', 'ETAT_LIB': 'Occupée', 'ETAT_COULEUR': '#F39C12'},
            {'ETAT_ID': 4, 'ETAT_CODE': 'M', 'ETAT_LIB': 'Mauvaise (casse)', 'ETAT_COULEUR': '#E02424'},
          ],
        },
      }),
    );

/// Entrée [label] du menu ⋮ de l'écran (il remplace les pictos de la barre de titre).
Future<void> menu(WidgetTester t, String label) async {
  await t.tap(find.byTooltip('Plus d\'actions'));
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

/// Lien « Vers … » de l'alvéole choisie vers le support d'en face (bouton avec son type et son pictogramme).
Finder vers(String lib) => find.ancestor(of: find.textContaining('Vers $lib'), matching: find.byType(SupportLink));

void main() {
  late MemoryRepository repo;
  late ReferenceData ref;
  setUp(() async {
    final p = bundle();
    ref = p.referenceData;
    repo = MemoryRepository();
    await repo.load(p);
  });

  test('masque : état, déplacement, nouvelle alvéole, retrait ; photos prises entre-temps conservées', () async {
    final e = MaskEditor(repo, (await repo.object('C1'))!, author: 'essai');
    await e.load();
    expect(e.face, 'A');
    expect(e.linearLabel(e.linears.single), 'Vers C598');
    final a = e.bores().single;
    expect([a.number, a.state, a.diameter], [1, 2, 45.0]);

    e.setDuctState(a, 4);
    e.move(a, 20, -1); // borné à la face (m)
    expect([a.x, a.y], [0.567, 0.0]);
    e.move(a, 0.12345, 0.2); // au millimètre
    expect([a.x, a.y], [0.123, 0.2]);
    e.move(a, 0.567, 0.0);

    // nouvelle face d'une chambre sans référence ni dimension relevée : fenêtre FOA
    e.selectFace('B');
    expect([e.width, e.height], [foaFaceWidth, foaFaceHeight]);
    final cd = e.add(linear: e.linears.single, x: 0.1, y: 0.15, diameter: 80, state: 0);
    expect(e.bores().single.number, 2);
    expect([e.bores().single.x, e.bores().single.y], [0.1, 0.15]);

    // une alvéole créée puis retirée disparaît ; une alvéole venue du BE est abandonnée
    final other = e.add(linear: e.linears.single, x: 0.3, y: 0.3);
    e.remove(e.bores().firstWhere((a) => a.cd == other));
    expect(MaskEditor.ductsOf(e.linears.single).map((c) => c['CD_CODE_EXT']), ['CD1', cd]);

    // photo de la face B prise pendant l'édition des masques
    final app = AppProvider(repo);
    final vB = Visual.of((await repo.object('C1'))!, ref).firstWhere((v) => v.code == 'B');
    await app.addPhoto((await repo.object('C1'))!.copy(), vB, name: 'b.jpg', bytes: Uint8List.fromList([1, 2, 3]));

    await e.validate();
    final c1 = (await repo.object('C1'))!;
    final faces = (c1.namespace('chb')!['faces'] as List).cast<Map>();
    expect(faces.map((f) => f['FAC_CODE']), ['A', 'B']);
    expect(((faces.first['positions'] as List).single as Map)['POS_X'], 0.567);
    expect([faces.last['FAC_LARG'], faces.last['FAC_HAUT']], [0.567, 0.54]);
    expect(faces.last.keys, isNot(contains('FAC_NB_COL')));
    expect(((faces.last['positions'] as List).single as Map)['CD_KEY'], cd);
    expect(c1.photos(vB), hasLength(1));
    expect(c1.namespace('chb')!['CHB_NIVEAU'], 1); // vue A manquante
    final ducts = MaskEditor.ductsOf((await repo.object('L2'))!);
    expect(ducts.first['ETAT_KEY'], 4);
    expect(ducts.last, containsPair('CD_DIAM', 80.0));
    expect(e.changed, isFalse);

    // retrait d'une position venue du BE : abandon, la face n'est plus relevée
    final e2 = MaskEditor(repo, c1, author: 'essai', face: 'A');
    await e2.load();
    e2.remove(e2.bores().single);
    await e2.validate();
    final pos = ((await repo.object('C1'))!.namespace('chb')!['faces'] as List).first['positions'] as List;
    expect((pos.single as Map)['DATE_ABD'], isNotNull);
    expect(MaskEditor(repo, (await repo.object('C1'))!, author: 'essai').face, 'B');
  });

  test('alvéole sans destination connue (sans miroir) : conduite portée par la chambre', () async {
    final e = MaskEditor(repo, (await repo.object('C2'))!, author: 'essai');
    await e.load();
    final cd = e.add(x: 0.2, y: 0.2, diameter: 45, state: 0);
    final a = e.bores().single;
    expect([a.noDestination, a.number, e.linearLabel(a.linear)], [true, 1, 'Sans destination connue']);
    e.setDuctState(a, 2);
    await e.validate();
    final c2 = (await repo.object('C2'))!;
    expect(MaskEditor.ductsOf(c2).single, containsPair('CD_CODE_EXT', cd));
    expect(MaskEditor.ductsOf(c2).single['ETAT_KEY'], 2);
    expect(MaskEditor.ductsOf((await repo.object('L2'))!).map((c) => c['CD_CODE_EXT']), ['CD1']);

    // relue depuis le dépôt
    final e2 = MaskEditor(repo, c2, author: 'essai');
    await e2.load();
    expect(e2.bores().single.duct?['ETAT_KEY'], 2);
  });

  test('nouvelle face aux dimensions de la chambre : largeur (A, B) ou longueur (C, D), hauteur ; relevées, sinon '
      'catalogue, sinon fenêtre FOA', () async {
    MaskEditor editor(Map<String, dynamic> chb) => MaskEditor(repo, node('C9', 'C9', 2.0, chb), author: 'essai');

    // ni référence ni dimension relevée : fenêtre FOA (0,567 × 0,54 m)
    var e = editor({});
    expect(e.chamberSize('A'), (width: null, height: null));
    expect(e.defaultSize('A'), (width: foaFaceWidth, height: foaFaceHeight));

    // L2C du catalogue (intérieur : longueur 1,16, largeur 0,38, hauteur 0,60 m)
    e = editor({'MAT_KEY': 5});
    expect([for (final f in chamberFaces) e.defaultSize(f)], [
      (width: 0.38, height: 0.6),
      (width: 0.38, height: 0.6),
      (width: 1.16, height: 0.6),
      (width: 1.16, height: 0.6),
    ]);

    // dimensions relevées d'abord, catalogue pour les autres
    e = editor({'MAT_KEY': 5, 'CHB_LARG': 0.4, 'CHB_HAUT': 0.7});
    expect([e.defaultSize('B'), e.defaultSize('D')], [(width: 0.4, height: 0.7), (width: 1.16, height: 0.7)]);

    // OHN (dimensions nulles au catalogue) : fenêtre FOA pour chaque dimension inconnue
    e = editor({'MAT_KEY': 36, 'CHB_HAUT': 0.65});
    expect(e.chamberSize('C'), (width: null, height: 0.65));
    expect(e.defaultSize('C'), (width: foaFaceWidth, height: 0.65));

    // la première alvéole crée la face à ces dimensions ; ajout borné à la face
    e = editor({'MAT_KEY': 5})..selectFace('C');
    expect([e.width, e.height], [1.16, 0.6]);
    e.add(x: 2, y: -1);
    final face = (e.chamber.namespace('chb')!['faces'] as List).single as Map;
    expect([face['FAC_CODE'], face['FAC_LARG'], face['FAC_HAUT']], ['C', 1.16, 0.6]);
    expect([e.bores().single.x, e.bores().single.y], [1.16, 0.0]);
  });

  test('arrivée d\'une alvéole suivie : sa face et elle-même si elle est placée ; sinon la face du parcours, rien de '
      'choisi à sa place ; sinon aucune', () async {
    final c1 = (await repo.object('C1'))!, l2 = (await repo.object('L2'))!;
    expect(MaskEditor.arrival(c1, l2, cd: 'CD1'), (face: 'A', cd: 'CD1'));
    // une autre conduite du parcours, non placée : la face où le parcours arrive, sans alvéole choisie
    expect(MaskEditor.arrival(c1, l2, cd: 'CD2'), (face: 'A', cd: null));
    expect(MaskEditor.arrival((await repo.object('C2'))!, l2, cd: 'CD1'), isNull);
    expect(MaskEditor.firstFace((await repo.object('C2'))!), 'A');
  });

  test('la session des masques repart de la chambre du dépôt (objet passé périmé)', () async {
    final stale = (await repo.object('C1'))!.copy();
    final fresh = stale.copy()..namespace('chb')!['CHB_HAUT'] = 0.9;
    await repo.save(fresh, author: 'essai');
    final e = MaskEditor(repo, stale, author: 'essai');
    await e.load();
    e.move(e.bores().single, 0.1, 0.1);
    await e.validate();
    expect((await repo.object('C1'))!.namespace('chb')!['CHB_HAUT'], 0.9);
  });

  test('face relevée redimensionnée à la demande seulement : alvéoles centrées, puis bornées à la face', () async {
    final c1 = (await repo.object('C1'))!.copy();
    c1.namespace('chb')!['MAT_KEY'] = 5; // L2C : face A de 0,38 × 0,60 m
    // la session repart de la chambre du dépôt
    await repo.save(c1, author: 'essai');
    final e = MaskEditor(repo, c1, author: 'essai');
    await e.load();
    // relevée dans la fenêtre FOA : gardée telle quelle à l'ouverture
    expect([e.width, e.height], [foaFaceWidth, foaFaceHeight]);
    expect(e.chamberSize(), (width: 0.38, height: 0.6));
    final added = e.add(linear: e.linears.single, x: 0.55, y: 0.05);
    final [center, corner] = e.bores();
    expect([center.cd, corner.cd], ['CD1', added]);

    // x += (0,38 − 0,567) / 2, y += (0,60 − 0,54) / 2
    e.resize(0.38, 0.6);
    expect([e.width, e.height], [0.38, 0.6]);
    expect([center.x, center.y], [0.19, 0.3]);
    expect([corner.x, corner.y], [0.38, 0.08]); // 0,4565 borné à la largeur
    // agrandie : toujours centrées
    e.resize(1.16, 0.6);
    expect([center.x, center.y], [0.58, 0.3]);
    expect([corner.x, corner.y], [0.77, 0.08]);

    await e.validate();
    final face = ((await repo.object('C1'))!.namespace('chb')!['faces'] as List).single as Map;
    expect([face['FAC_LARG'], face['FAC_HAUT'], face['SRC_MODIF']], [1.16, 0.6, 'essai']);
    final positions = (face['positions'] as List).cast<Map>();
    expect([for (final p in positions) (p['POS_X'], p['POS_Y'])], [(0.58, 0.3), (0.77, 0.08)]);
    expect(positions.first['DATE_MODIF'], isNotNull);
  });

  test('ajout au centre de la face, décalé (en m) pour ne chevaucher aucune alvéole', () async {
    final c2 = (await repo.object('C2'))!.copy();
    c2.namespace('chb', create: true)!['MAT_KEY'] = 5; // face A de 0,38 × 0,60 m
    await repo.save(c2, author: 'essai');
    final e = MaskEditor(repo, c2, author: 'essai');
    await e.load();
    expect(e.freePlace(45), (0.19, 0.3));
    e.add(linear: e.linears.single, x: 0.19, y: 0.3, diameter: 100);
    // 100 mm au centre : une 45 mm deux pas (5 cm) plus à droite
    expect(e.freePlace(45), (0.29, 0.3));
    e.add(linear: e.linears.single, x: 0.29, y: 0.3, diameter: 45);
    e.add(linear: e.linears.single, x: 0.34, y: 0.3, diameter: 45);
    // rangée pleine jusqu'au bord droit : rangée suivante, depuis la gauche
    final (x, y) = e.freePlace(45);
    expect([x < 0.19, y], [true, 0.35]);
  });

  testWidgets('grille du masque : choisir une alvéole, changer son état, en placer une, enregistrer', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppProvider(repo);
    final chamber = (await repo.object('C1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MaskScreen(chamber: chamber))),
              child: const Text('carte'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();
    expect(find.text('masque A · 1 alvéole'), findsOneWidget);
    expect(find.text('Masques'), findsOneWidget);

    // face aux proportions réelles (0,567 × 0,54 m), centrée dans la vue ; alvéole en vraie grandeur (45 mm)
    final grid = find.descendant(of: find.byType(MaskGrid), matching: find.byType(CustomPaint));
    final face = t.getSize(grid);
    expect(face.width / face.height, closeTo(0.567 / 0.54, 0.001));
    expect(t.getCenter(grid).dy, closeTo(t.getCenter(find.byType(MaskGrid)).dy, 0.5));
    expect(t.getSize(find.byType(BoreTile)).width, closeTo(face.width * 0.045 / 0.567, 0.01));

    await t.tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
    await t.pumpAndSettle();
    // « Vers C598 » : lien bien visible vers la chambre d'en face, sur sa ligne, avec son type et son pictogramme
    // (notes rep10)
    expect(find.text('Alvéole 1'), findsOneWidget);
    expect(vers('C598'), findsOneWidget);
    expect(find.descendant(of: vers('C598'), matching: find.textContaining('Chambre')), findsOneWidget);
    expect(find.descendant(of: vers('C598'), matching: find.byType(SupportSymbol)), findsOneWidget);
    expect(t.getSize(vers('C598')).width, greaterThan(300));
    await t.tap(find.widgetWithText(ChoiceChip, 'M'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Fermer'));
    await t.pumpAndSettle();

    // toucher la grille hors alvéole : nouvelle alvéole
    await t.tapAt(t.getTopLeft(grid) + const Offset(30, 30));
    await t.pumpAndSettle();
    expect(find.text('Nouvelle alvéole · face A'), findsOneWidget);
    await t.tap(find.text('Placer l\'alvéole'));
    await t.pumpAndSettle();
    expect(find.text('masque A · 2 alvéoles'), findsOneWidget);
    await t.tap(find.byTooltip('Fermer'));
    await t.pumpAndSettle();

    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final ducts = MaskEditor.ductsOf((await repo.object('L2'))!);
    expect(ducts.map((c) => c['ETAT_KEY']), [4, 0]);
    expect(ducts.last['CD_DIAM'], 45.0);
    expect(find.text('Enregistrer'), findsNothing);
    // position du toucher, en m depuis le coin haut gauche de la face
    final positions = (((await repo.object('C1'))!.namespace('chb')!['faces'] as List).single as Map)['positions'] as List;
    final scale = face.width / 0.567; // px par m
    expect([(positions.last as Map)['POS_X'], positions.last['POS_Y']],
        [closeTo(30 / scale, 0.001), closeTo(30 / scale, 0.001)]);
  });

  testWidgets('dimensions de la face : centimètres, dimensions de la chambre, alvéoles recentrées', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final chamber = (await repo.object('C1'))!.copy();
    chamber.namespace('chb')!['MAT_KEY'] = 5; // L2C : face A de 0,38 × 0,60 m
    await repo.save(chamber, author: 'essai');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), home: MaskScreen(chamber: chamber)),
    ));
    await t.pumpAndSettle();
    Size face() => t.getSize(find.descendant(of: find.byType(MaskGrid), matching: find.byType(CustomPaint)));
    expect(face().aspectRatio, closeTo(0.567 / 0.54, 0.001));
    // actions de la face dans le menu ⋮ : la barre de titre ne garde que les visuels et le menu
    Future<void> faceSize() async {
      await t.tap(find.byTooltip('Plus d\'actions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Dimensions de la face'));
      await t.pumpAndSettle();
    }

    expect(find.byTooltip('Dimensions de la face'), findsNothing);
    await faceSize();
    expect(find.text('Dimensions de la face A'), findsOneWidget);
    final width = find.widgetWithText(TextField, 'Largeur'), height = find.widgetWithText(TextField, 'Hauteur');
    expect([t.widget<TextField>(width).controller!.text, t.widget<TextField>(height).controller!.text], ['56,7', '54']);
    expect(find.text('Les alvéoles restent centrées dans la face.'), findsOneWidget);
    // dimension hors bornes : Valider inactif
    await t.enterText(height, '0');
    await t.pump();
    expect(find.text('De 5 à 1000 cm'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Valider')).onPressed, isNull);
    // dimensions de la chambre (catalogue)
    await t.tap(find.text('Dimensions de la chambre (38 × 60 cm)'));
    await t.pump();
    expect([t.widget<TextField>(width).controller!.text, t.widget<TextField>(height).controller!.text], ['38', '60']);
    expect(find.text('De 5 à 1000 cm'), findsNothing);
    await t.tap(find.widgetWithText(FilledButton, 'Valider'));
    await t.pumpAndSettle();
    expect(face().aspectRatio, closeTo(0.38 / 0.6, 0.001));

    // saisie en centimètres, au millimètre
    await faceSize();
    await t.enterText(width, '46,2');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Valider'));
    await t.pumpAndSettle();

    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final f = ((await repo.object('C1'))!.namespace('chb')!['faces'] as List).single as Map;
    expect([f['FAC_LARG'], f['FAC_HAUT']], [0.462, 0.6]);
    // alvéole recentrée : 0,2835 + (0,38 − 0,567) / 2 + (0,462 − 0,38) / 2, 0,27 + (0,60 − 0,54) / 2
    final p = (f['positions'] as List).single as Map;
    expect([p['POS_X'], p['POS_Y']], [0.231, 0.3]);

    // face C non relevée : longueur de la chambre (1,16 m), trop large pour la vue : toute sa hauteur, parcourue en
    // largeur
    await t.tap(find.text('C'));
    await t.pumpAndSettle();
    expect(face().aspectRatio, closeTo(1.16 / 0.6, 0.001));
    expect(face().height, closeTo(t.getSize(find.byType(MaskGrid)).height - 24, 0.5));
    expect(face().width, greaterThan(t.getSize(find.byType(MaskGrid)).width));
  });

  testWidgets('paysage : faces au-dessus de la grille, à gauche ; légende et panneau de l\'alvéole à droite ; '
      'nouvelle alvéole dans un volet qui se déplie depuis la droite', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final chamber = (await repo.object('C1'))!.copy();
    chamber.namespace('chb')!['MAT_KEY'] = 5; // L2C : nouvelle face de 0,38 × 0,60 m
    await repo.save(chamber, author: 'essai');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: MaskScreen(chamber: chamber)),
    ));
    await t.pumpAndSettle();
    Future<void> tap(Finder f) async {
      await t.tap(f);
      await t.pumpAndSettle();
    }

    Rect face() => t.getRect(find.descendant(of: find.byType(MaskGrid), matching: find.byType(CustomPaint)));
    final faces = find.byType(SegmentedButton<String>);
    // corps entre la barre de titre et la barre basse : à gauche, les noms des faces au-dessus de la grille (notes
    // rep9), centrés ; la colonne de droite pour la légende ; la face A relevée, centrée dans la grille
    final top = t.getRect(find.byType(AppBar)).bottom, bottom = t.getRect(find.byType(BottomBar)).top;
    final grid = t.getRect(find.byType(MaskGrid));
    expect([grid.left, grid.right, grid.bottom], [0, 1280 - maskSideWidth - 1, bottom]);
    expect(t.getRect(faces).top, lessThan(top + 16));
    expect(grid.top, greaterThanOrEqualTo(t.getRect(faces).bottom));
    expect(t.getRect(faces).center.dx, closeTo(grid.center.dx, 0.5));
    expect(t.getRect(find.text('M Mauvaise (casse)')).left, greaterThanOrEqualTo(grid.right));
    expect(t.getRect(find.text('V Vide')).top, lessThan(top + 40));
    expect(face().center, offsetMoreOrLessEquals(grid.center, epsilon: 0.5));
    // notes rep8 : la place de la tablette sert à la lisibilité, la légende en grand, un état par ligne
    expect(t.getSize(find.text('M Mauvaise (casse)')).height, greaterThanOrEqualTo(20));
    expect(t.getRect(find.text('V Vide')).bottom, lessThanOrEqualTo(t.getRect(find.text('R Réservée')).top));
    // barre de titre : le seul menu ⋮, plus de pictos
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)), findsOneWidget);
    expect(find.byTooltip('Plus d\'actions'), findsOneWidget);

    // alvéole choisie : son panneau dans la colonne ; état enregistré par le bouton du panneau, « Vers C598 » mène
    // d'une touche à la grille de l'autre chambre, sans carton (sa conduite n'y est pas placée : face A, rien de
    // choisi) ; la grille de départ, premier écran de l'essai, reste dessous
    await tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
    expect(t.getRect(find.text('Alvéole 1')).left, greaterThanOrEqualTo(grid.right));
    // état et diamètre en grandes cases, libellés entiers : les sept diamètres sur deux rangées de quatre, chaque case
    // facile à toucher
    expect(find.byType(ChoiceChip), findsNothing);
    final d28 = t.getRect(find.text('28')), d150 = t.getRect(find.text('150'));
    expect(d150.top, greaterThan(d28.bottom));
    expect(t.getSize(find.ancestor(of: find.text('28'), matching: find.byType(InkWell)).first).height,
        greaterThanOrEqualTo(48));
    await tap(find.text('150'));
    await tap(find.text('M Mauvaise (casse)'));
    await tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    expect(MaskEditor.ductsOf((await repo.object('L2'))!).single['CD_DIAM'], 150);
    expect(MaskEditor.ductsOf((await repo.object('L2'))!).single['ETAT_KEY'], 4);
    await tap(vers('C598'));
    expect(find.text('C598'), findsOneWidget);
    expect(find.text('masque A · 0 alvéole'), findsOneWidget);
    expect(find.textContaining('Naviguer vers'), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(t.getRect(find.text('Alvéole 1')).left, greaterThanOrEqualTo(grid.right));

    // face B, nouvelle, aux dimensions de la chambre L2C : toute la hauteur de la vue ; toucher la face y place une
    // alvéole
    await tap(find.text('B'));
    expect(face().height, closeTo(grid.height - 24, 0.5));
    expect(face().width / face().height, closeTo(0.38 / 0.6, 0.001));
    await t.tapAt(face().center + const Offset(40, 40));
    await t.pumpAndSettle();
    // le volet se déplie depuis la droite sur la colonne latérale, la grille reste visible ; diamètre et état en
    // grandes cases
    expect(t.getRect(find.text('Nouvelle alvéole · face B')).left, greaterThanOrEqualTo(grid.right));
    expect(find.byType(ChoiceChip), findsNothing);
    await tap(find.text('60'));
    await tap(find.text('Placer l\'alvéole'));
    expect(find.text('masque B · 1 alvéole'), findsOneWidget);
    expect(MaskEditor.ductsOf((await repo.object('L2'))!), hasLength(1)); // pas encore enregistrée
    expect(t.getRect(find.text('Alvéole 2')).left, greaterThanOrEqualTo(grid.right));

    // zoom à la molette (Windows) ; l'appui long amène l'alvéole sous le doigt, le glissement déplace la vue
    final before = face();
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(mouse.hover(grid.center));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await t.pumpAndSettle();
    final zoomed = face();
    expect(zoomed.height, greaterThan(before.height * 2));
    final start = t.getCenter(find.byType(BoreTile));
    final press = await t.startGesture(start);
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await press.moveBy(const Offset(60, 40));
    await t.pump();
    await press.up();
    await t.pumpAndSettle();
    // au millimètre près (3 px à ce zoom)
    expect(t.getCenter(find.byType(BoreTile)), offsetMoreOrLessEquals(start + const Offset(60, 40), epsilon: 3));
    await t.dragFrom(grid.center - const Offset(150, 150), const Offset(-100, 150));
    await t.pumpAndSettle();
    expect(face().top, greaterThan(zoomed.top + 100));

    // tablette en portrait : comme sur un téléphone, le choix de la face au-dessus de la grille, le panneau dessous,
    // l'alvéole toujours choisie
    t.view.physicalSize = const Size(800, 1280);
    await t.pumpAndSettle();
    final portrait = t.getRect(find.byType(MaskGrid));
    expect(portrait.width, 800);
    expect(t.getRect(faces).bottom, lessThanOrEqualTo(portrait.top));
    expect(t.getRect(find.text('Alvéole 2')).top, greaterThanOrEqualTo(portrait.bottom));
  });

  testWidgets('fiche chambre (FOA Explorer) : cartes, type, référence, dimensions, adresse ; onglets Équipements et Masques', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppProvider(repo);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: ObjectScreen(object: (await repo.object('C1'))!),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('12 rue des Lilas, 54600 Villers'), findsOneWidget);
    // cartes dépliables, sans titre « Chambre » répété ; équipements et masques dans leurs onglets (barre basse)
    for (final title in ['GÉNÉRAL', 'DIMENSIONS', 'COMMENTAIRES']) {
      await t.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('CHAMBRE'), findsNothing);
    expect(find.text('ÉQUIPEMENTS'), findsNothing);
    expect(find.text('Ajouter un équipement'), findsNothing);
    expect(find.text('CONDUITES'), findsNothing);
    expect(find.text('Face vide'), findsNothing);
    // commentaires : journal daté et signé (widgets/comments.dart), plus de champ libre
    expect(find.text('Aucun commentaire'), findsOneWidget);
    expect(find.text('Ajouter un commentaire'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Commentaire'), findsNothing);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await t.pumpAndSettle();

    // replier puis déplier une carte : les champs de texte se reconstruisent sans erreur
    await t.tap(find.text('GÉNÉRAL'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Numéro'), findsNothing);
    await t.tap(find.text('GÉNÉRAL'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.widgetWithText(TextFormField, 'C597'), findsOneWidget);

    Future<void> choose(String field, String value) async {
      final f = find.widgetWithText(DropdownButtonFormField<Object?>, field);
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
      await t.tap(find.text(value).last);
      await t.pumpAndSettle();
    }

    await choose('Type', 'Chambre FT');
    await choose('Référence (catalogue)', 'L2C');
    await choose('Implantation', 'Trottoir');
    // une ligne par dimension : dimension relevée, référence du catalogue en petit dans le cadre du champ
    for (final (label, reference) in [('Largeur', '0,38 m'), ('Longueur', '1,16 m'), ('Hauteur', '0,60 m')]) {
      final field = find.widgetWithText(NumberField, label);
      expect(find.descendant(of: field, matching: find.text('référence : $reference')), findsOneWidget);
    }
    final width = find.widgetWithText(TextField, 'Largeur');
    await t.ensureVisible(width);
    await t.enterText(width, '0,4');

    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final c1 = (await repo.object('C1'))!;
    expect(c1.typeKey, 17);
    expect([c1.namespace('chb')!['MAT_KEY'], c1.namespace('chb')!['IMPS_KEY'], c1.namespace('chb')!['CHB_LARG']], [5, 2, 0.4]);

    // barre basse : onglet Équipements (à la place des connecteurs), seul endroit où on les modifie
    await t.tap(find.text('Équipements').last);
    await t.pumpAndSettle();
    expect(find.text('équipements'), findsOneWidget);
    expect(find.text('Aucun équipement'), findsOneWidget);
    await t.tap(find.text('Ajouter un équipement'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'boîte');
    await t.pumpAndSettle();
    await t.tap(find.text('Boîte Epissures 144x — FIST-GCO2-BC6').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await t.pumpAndSettle();
    expect(find.text('Boîte Epissures 144x — FIST-GCO2-BC6'), findsOneWidget);
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final equ = ((await repo.object('C1'))!.namespace('inf')!['equipements'] as List).single as Map;
    expect([equ['MAT_KEY'], equ['EQU_QTE']], [1, 1]);
    expect(equ.keys, isNot(contains('nouveau')));
    // nombre d'équipements sur le bouton de la barre basse, icône dessinée (boîtier sur câble) ; onglet actif : pastille
    // inversée, lisible sur le fond jaune
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);
    final equipmentItem = find.widgetWithText(BarItem, 'Équipements');
    expect(find.descendant(of: equipmentItem, matching: find.byType(SvgIcon)), findsOneWidget);
    final badge = t.widget<Badge>(find.descendant(of: equipmentItem, matching: find.byType(Badge)));
    expect([badge.backgroundColor, badge.textColor], [Nge.slateDark, Nge.yellow]);

    // liens fibres de la boîte d'épissure
    await t.tap(find.byTooltip('Liens fibres'));
    await t.pumpAndSettle();
    expect(find.text('Liens fibres de la boîte : à venir'), findsOneWidget);

    // barre basse : Masques ouvre l'aperçu (une ligne par face, puis les conduites), une face ouvre sa grille
    await t.tap(find.text('Masques'));
    await t.pumpAndSettle();
    expect(find.text('masques'), findsOneWidget);
    expect(find.text('1 alvéole'), findsOneWidget);
    // dimensions de la face relevée (fenêtre FOA), pas celles de la chambre L2C choisie entre-temps
    expect(find.text('56,7 × 54 cm'), findsOneWidget);
    expect(find.text('Face vide'), findsNWidgets(3));
    await t.scrollUntilVisible(find.textContaining('vers C598'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('CONDUITES'), findsOneWidget);
    expect(find.text('1 conduite'), findsOneWidget);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await t.pumpAndSettle();
    await t.tap(find.text('1 alvéole'));
    await t.pumpAndSettle();
    expect(find.text('masque A · 1 alvéole'), findsOneWidget);

    // alvéole : « Vers C598 » mène d'une touche à C598, qui remplace C597 : directement sa grille (la conduite n'y
    // est pas placée : face A, rien de choisi), sans carton ; un seul support ouvert, la grille et l'aperçu de C597
    // sont fermés (la saisie, premier écran de l'essai, reste dessous)
    List<String?> names() => [for (final r in screenStack.stack) r.settings.name];
    await t.tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
    await t.pumpAndSettle();
    await t.tap(vers('C598'));
    await t.pumpAndSettle();
    expect(find.text('C598'), findsOneWidget);
    expect(find.text('masque A · 0 alvéole'), findsOneWidget);
    expect(find.textContaining('Naviguer vers'), findsNothing);
    expect(names(), ['/', 'onglet:C2:masques:A']);

    // menu ⋮ : « Revenir à C597 » rouvre sa grille sur la face et l'alvéole où on l'avait laissée
    await t.tap(find.byTooltip('Plus d\'actions'));
    await t.pumpAndSettle();
    expect(find.text('masque A'), findsOneWidget);
    expect(find.text('Repérer sur la carte'), findsOneWidget);
    await t.tap(find.text('Revenir à C597'));
    await t.pumpAndSettle();
    expect(find.text('masque A · 1 alvéole'), findsOneWidget);
    expect(find.text('Alvéole 1'), findsOneWidget);
    expect(names(), ['/', 'onglet:C1:masques:A']);

    // aperçu (Masques de la barre basse) : toucher le parcours le sélectionne et montre son carton ; « Naviguer vers »
    // ouvre l'autre extrémité à la place de C597, sur le même écran, avec le carton du retour, qui ramène ici
    await t.tap(find.text('Masques'));
    await t.pumpAndSettle();
    expect(find.text('Naviguer vers C598'), findsNothing);
    await t.scrollUntilVisible(find.textContaining('vers C598'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.textContaining('vers C598'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Ouvrir C598'), findsNothing); // en sélection, c'est le carton qui y mène
    await t.tap(find.text('Naviguer vers C598'));
    await t.pumpAndSettle();
    expect(find.text('C598'), findsOneWidget);
    expect(names(), ['/', 'onglet:C2:masques']);
    await t.tap(find.text('Naviguer vers C597'));
    await t.pumpAndSettle();
    expect(find.text('C597'), findsOneWidget);
    expect(find.text('Naviguer vers C598'), findsOneWidget);
    await t.tap(find.byTooltip('Fermer'));
    await t.pumpAndSettle();
    expect(find.text('Naviguer vers C598'), findsNothing);
  });

  testWidgets('onglets du support : remplacés et non empilés, saisie enregistrée, confirmation sur une grille', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final chamber = (await repo.object('C1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, chamber), child: const Text('carte')),
          ),
        ),
      ),
    ));
    List<String?> names() => [for (final r in screenStack.stack) r.settings.name];
    Future<void> tap(Finder f) async {
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await tap(find.text('carte'));
    await menu(t, 'Saisie du support');
    expect(names().skip(1), ['support:C1', 'onglet:C1:saisie']);

    // saisie en cours enregistrée avant de passer à l'onglet suivant, qui la remplace
    await t.enterText(find.widgetWithText(TextFormField, 'Numéro'), 'C597b');
    await tap(find.text('Équipements'));
    expect(find.text('équipements'), findsOneWidget);
    expect((await repo.object('C1'))!.lib, 'C597b');
    expect(names().skip(1), ['support:C1', 'onglet:C1:equipements']);

    await tap(find.text('Masques'));
    expect(names().skip(1), ['support:C1', 'onglet:C1:masques']);
    await tap(find.text('1 alvéole'));
    expect(names().length, 4);

    // grille modifiée : quitter demande confirmation ; « Rester » garde la grille
    await tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
    await tap(find.widgetWithText(ChoiceChip, 'M'));
    await tap(find.byTooltip('Fermer'));
    await tap(find.text('Équipements'));
    expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
    await tap(find.text('Rester'));
    expect(find.text('masque A · 1 alvéole'), findsOneWidget);
    expect(names().length, 4);

    // depuis une grille, Masques ramène à l'aperçu
    await tap(find.text('Masques'));
    await tap(find.text('Quitter'));
    expect(find.text('masques'), findsOneWidget);
    expect(names().skip(1), ['support:C1', 'onglet:C1:masques']);

    // retour : les visuels du support, puis la carte
    await tap(find.byType(BackButton));
    expect(find.textContaining('visuels'), findsOneWidget);
    expect(names().length, 2);
  });

  testWidgets('chambre d\'en face supprimée : ni « Vers … » ni « Naviguer vers » n\'y mènent ; réécrite depuis une '
      'copie qui l\'ignorait, elle reste abandonnée', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppProvider(repo);
    await app.save((await repo.object('C2'))!, abandon: true);
    // copie d'avant la suppression, renommée et réécrite : le dépôt garde l'abandon (le retour la déclare abandonnée)
    final stale = (await repo.object('C2'))!.copy()
      ..props.remove('DATE_ABD')
      ..props['NOE_LIB'] = 'C598b';
    await repo.save(stale, author: 'essai');
    final c2 = (await repo.object('C2'))!;
    expect([c2.status, c2.abandoned, c2.lib], ['A', isTrue, 'C598b']);

    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: MaskScreen(chamber: (await repo.object('C1'))!)),
    ));
    await t.pumpAndSettle();
    Future<void> tap(Finder f) async {
      await t.tap(f);
      await t.pumpAndSettle();
    }

    // alvéole : la destination supprimée n'est plus un lien, et le panneau le dit
    await tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
    expect(find.textContaining('Vers C598b'), findsOneWidget);
    expect(find.textContaining('support supprimé'), findsOneWidget);
    expect(vers('C598b'), findsNothing);
    // aperçu : le carton du parcours le dit, sans « Naviguer vers »
    await tap(find.text('Masques'));
    await t.scrollUntilVisible(find.textContaining('vers C598b'), 200, scrollable: find.byType(Scrollable).first);
    await tap(find.textContaining('vers C598b'));
    expect(find.text('Support d\'en face supprimé'), findsOneWidget);
    expect(find.textContaining('Naviguer vers'), findsNothing);
  });

  testWidgets('paysage peu haut (tablette 1024 × 600, téléphone 800 × 360) : présentation compacte, « Retirer du '
      'masque » et « Enregistrer » épinglés en bas de la colonne', (t) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // alvéole en haut à gauche de la face : visible sans faire glisser la grille, plus haute que la vue sur un
    // téléphone en paysage
    final c1 = (await repo.object('C1'))!.copy();
    ((((c1.namespace('chb')!['faces'] as List).single as Map)['positions'] as List).single as Map)
      ..['POS_X'] = 0.05
      ..['POS_Y'] = 0.05;
    await repo.save(c1, author: 'essai');
    for (final (size, state, key) in const [(Size(1024, 600), 'M', 4), (Size(800, 360), 'R', 1)]) {
      t.view.physicalSize = size;
      await t.pumpWidget(ChangeNotifierProvider.value(
        key: UniqueKey(),
        value: AppProvider(repo),
        child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: MaskScreen(chamber: (await repo.object('C1'))!)),
      ));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
      await t.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsWidgets, reason: '$size : présentation compacte');
      final chip = find.widgetWithText(ChoiceChip, state);
      await t.ensureVisible(chip);
      await t.pumpAndSettle();
      await t.tap(chip);
      await t.pumpAndSettle();
      final bottom = t.getRect(find.byType(BottomBar)).top;
      final save = find.widgetWithText(FilledButton, 'Enregistrer');
      expect(t.getRect(save).bottom, lessThanOrEqualTo(bottom), reason: '$size');
      expect(t.getRect(find.text('Retirer du masque')).bottom, lessThanOrEqualTo(bottom), reason: '$size');
      await t.tap(save);
      await t.pumpAndSettle();
      expect(MaskEditor.ductsOf((await repo.object('L2'))!).single['ETAT_KEY'], key, reason: '$size');
    }
  });

  testWidgets('aperçu des masques en paysage : les faces à gauche, en tuiles avec la miniature de leur masque, les '
      'conduites à droite (notes rep10)', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: MaskOverviewScreen(chamber: (await repo.object('C1'))!),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byType(MaskPreview), findsNWidgets(4));
    final masks = t.getRect(find.text('MASQUES')), conduits = t.getRect(find.text('CONDUITES'));
    expect(conduits.left, greaterThan(640));
    expect(masks.right, lessThan(640));
    expect(conduits.top, closeTo(masks.top, 1));
    // deux tuiles par rangée : A et B côte à côte, C et D dessous ; la miniature de A aux proportions de la face
    final a = t.getRect(find.byType(MaskPreview).at(0)), b = t.getRect(find.byType(MaskPreview).at(1));
    final c = t.getRect(find.byType(MaskPreview).at(2));
    expect([b.left > a.right, c.top > a.bottom], [isTrue, isTrue]);
    expect(a.width / a.height, closeTo(0.567 / 0.54, 0.01));
    expect(find.text('1 alvéole'), findsOneWidget);
    expect(find.text('Face vide'), findsNWidgets(3));
    // toucher la tuile de A ouvre sa grille ; le parcours de la liste porte le pictogramme du support d'en face
    expect(find.descendant(of: find.byType(ListTile), matching: find.byType(SupportSymbol)), findsOneWidget);
    await t.tap(find.text('1 alvéole'));
    await t.pumpAndSettle();
    expect(find.text('masque A · 1 alvéole'), findsOneWidget);
  });

  testWidgets('support sans étiquette : « Sans étiquette » plutôt que son identifiant', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c1 = (await repo.object('C1'))!.copy()..props.remove('NOE_LIB');
    await repo.save(c1, author: 'essai');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: MaskScreen(chamber: c1)),
    ));
    await t.pumpAndSettle();
    expect(find.text('Sans étiquette'), findsOneWidget);
    expect(find.text('C1'), findsNothing);
  });

  testWidgets('grille rouverte sur une alvéole disparue (jamais enregistrée) : rien de choisi, le premier toucher '
      'place une alvéole', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: MaskScreen(chamber: (await repo.object('C1'))!, face: 'A', selection: 'alvéole-disparue'),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Alvéole 1'), findsNothing);
    final grid = find.descendant(of: find.byType(MaskGrid), matching: find.byType(CustomPaint));
    await t.tapAt(t.getTopLeft(grid) + const Offset(30, 30));
    await t.pumpAndSettle();
    expect(find.text('Nouvelle alvéole · face A'), findsOneWidget);
  });

  testWidgets('volet de création sur un écran peu haut (1024 × 600) : puces aux libellés entiers, « Placer '
      'l\'alvéole » visible', (t) async {
    t.view.physicalSize = const Size(1024, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: MaskScreen(chamber: (await repo.object('C1'))!)),
    ));
    await t.pumpAndSettle();
    final grid = find.descendant(of: find.byType(MaskGrid), matching: find.byType(CustomPaint));
    await t.tapAt(t.getTopLeft(grid) + const Offset(30, 30));
    await t.pumpAndSettle();
    expect(find.text('Nouvelle alvéole · face A'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Mauvaise (casse)'), findsOneWidget);
    expect(t.getRect(find.text('Placer l\'alvéole')).bottom, lessThanOrEqualTo(600));
    await t.tap(find.text('Placer l\'alvéole'));
    await t.pumpAndSettle();
    expect(find.text('masque A · 2 alvéoles'), findsOneWidget);
  });

  testWidgets('grille en portrait, texte à 200 % sur un petit téléphone : la grille garde sa place, le panneau défile, '
      'aucune erreur', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    // alvéole en haut à gauche de la face, visible dans la grille réduite
    final c1 = (await repo.object('C1'))!.copy();
    ((((c1.namespace('chb')!['faces'] as List).single as Map)['positions'] as List).single as Map)
      ..['POS_X'] = 0.05
      ..['POS_Y'] = 0.05;
    await repo.save(c1, author: 'essai');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: MaskScreen(chamber: c1)),
    ));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // grille réduite mais présente (elle tombait à zéro), panneau borné à 45 % du corps
    expect(t.getSize(find.byType(MaskGrid)).height, greaterThan(60));
    expect(find.widgetWithText(FilledButton, 'Enregistrer'), findsNothing);
    expect(find.text('Retirer du masque'), findsOneWidget);
  });

  testWidgets('aperçu des masques sur un téléphone en paysage : une ligne par face, les quatre visibles', (t) async {
    t.view.physicalSize = const Size(800, 360);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: MaskOverviewScreen(chamber: (await repo.object('C1'))!)),
    ));
    await t.pumpAndSettle();
    expect(find.byType(MaskPreview), findsNothing);
    expect(find.text('Face vide'), findsNWidgets(3));
    expect(t.getRect(find.text('CONDUITES')).left, greaterThan(400));
  });
}
