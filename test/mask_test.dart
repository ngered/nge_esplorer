import 'dart:typed_data';

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
import 'package:provider/provider.dart';

GeoObject node(String id, String lib, double lon, [Map<String, dynamic>? chb]) => GeoObject.fromFeature({
      'type': 'Feature',
      'id': id,
      'geometry': {'type': 'Point', 'coordinates': [lon, 45.0]},
      'properties': {'classe': 'NOE', 'NOE_LIB': lib, 'TYPE_KEY': 16, 'chb': ?chb},
    });

/// Deux chambres reliées par un parcours souterrain portant une conduite, placée dans la face A de C1.
Bundle bundle() => Bundle(
      header: {
        'format': Bundle.format,
        'version': Bundle.version,
        'date': '2026-11-02T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
        'modules': {'noyau': '0.1.0', 'infra': '0.1.0', 'chambre': '0.1.0'},
      },
      objects: [
        node('C1', 'C597', 2.0, {
          'faces': [
            {
              'FAC_CODE': 'A',
              'FAC_NB_COL': 9,
              'FAC_NB_LIG': 12,
              'positions': [
                {'CD_KEY': 'CD1', 'POS_X': 4.5, 'POS_Y': 6.0, 'POS_MIROIR': 0},
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
    e.move(a, 20, -1); // borné à la grille
    expect([a.x, a.y], [9.0, 0.0]);

    e.selectFace('B');
    final cd = e.add(linear: e.linears.single, x: 2, y: 3, diameter: 80, state: 0);
    expect([e.columns, e.rows], [defaultColumns, defaultRows]);
    expect(e.bores().single.number, 2);

    // une alvéole créée puis retirée disparaît ; une alvéole venue du BE est abandonnée
    final other = e.add(linear: e.linears.single, x: 5, y: 5);
    e.remove(e.bores().firstWhere((a) => a.cd == other));
    expect(MaskEditor.ductsOf(e.linears.single).map((c) => c['CD_CODE_EXT']), ['CD1', cd]);

    // photo de la face B prise pendant l'édition des masques
    final app = AppProvider(repo);
    final vB = Visual.of((await repo.object('C1'))!, ref).firstWhere((v) => v.code == 'B');
    await app.addPhoto((await repo.object('C1'))!.copy(), vB, name: 'b.jpg', bytes: Uint8List.fromList([1, 2, 3]));

    await e.validate(ref);
    final c1 = (await repo.object('C1'))!;
    final faces = (c1.namespace('chb')!['faces'] as List).cast<Map>();
    expect(faces.map((f) => f['FAC_CODE']), ['A', 'B']);
    expect(((faces.first['positions'] as List).single as Map)['POS_X'], 9.0);
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
    await e2.validate(ref);
    final pos = ((await repo.object('C1'))!.namespace('chb')!['faces'] as List).first['positions'] as List;
    expect((pos.single as Map)['DATE_ABD'], isNotNull);
    expect(MaskEditor(repo, (await repo.object('C1'))!, author: 'essai').face, 'B');
  });

  test('alvéole sans destination connue (sans miroir) : conduite portée par la chambre', () async {
    final e = MaskEditor(repo, (await repo.object('C2'))!, author: 'essai');
    await e.load();
    final cd = e.add(x: 4, y: 4, diameter: 45, state: 0);
    final a = e.bores().single;
    expect([a.noDestination, a.number, e.linearLabel(a.linear)], [true, 1, 'Sans destination connue']);
    e.setDuctState(a, 2);
    await e.validate(ref);
    final c2 = (await repo.object('C2'))!;
    expect(MaskEditor.ductsOf(c2).single, containsPair('CD_CODE_EXT', cd));
    expect(MaskEditor.ductsOf(c2).single['ETAT_KEY'], 2);
    expect(MaskEditor.ductsOf((await repo.object('L2'))!).map((c) => c['CD_CODE_EXT']), ['CD1']);

    // relue depuis le dépôt
    final e2 = MaskEditor(repo, c2, author: 'essai');
    await e2.load();
    expect(e2.bores().single.duct?['ETAT_KEY'], 2);
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

    await t.tap(find.descendant(of: find.byType(BoreTile), matching: find.text('1')));
    await t.pumpAndSettle();
    expect(find.textContaining('Alvéole 1 · Vers C598'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'M'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Fermer'));
    await t.pumpAndSettle();

    // toucher la grille hors alvéole : nouvelle alvéole
    await t.tapAt(t.getTopLeft(find.byType(MaskGrid)) + const Offset(40, 40));
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
  });

  testWidgets('fiche chambre (FOA Explorer) : cartes, type, référence, dimensions, équipement, adresse', (t) async {
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
    // cartes dépliables, sans titre « Chambre » répété ni masques (barre basse)
    for (final title in ['GÉNÉRAL', 'DIMENSIONS', 'ÉQUIPEMENTS', 'COMMENTAIRES']) {
      await t.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('CHAMBRE'), findsNothing);
    expect(find.text('CONDUITES'), findsNothing);
    expect(find.text('Face non relevée'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Commentaire'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Commentaire chambre (FOA)'), findsNothing);
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
    // une ligne par dimension : dimension relevée, référence du catalogue en aide sous le champ
    for (final (label, reference) in [('Largeur', '0,38 m'), ('Longueur', '1,16 m'), ('Hauteur', '0,60 m')]) {
      final field = find.widgetWithText(TextField, label);
      expect(find.descendant(of: field, matching: find.text('référence : $reference')), findsOneWidget);
    }
    final width = find.widgetWithText(TextField, 'Largeur');
    await t.ensureVisible(width);
    await t.enterText(width, '0,4');

    await t.ensureVisible(find.text('Ajouter un équipement'));
    await t.pumpAndSettle();
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
    final c1 = (await repo.object('C1'))!;
    expect(c1.typeKey, 17);
    expect([c1.namespace('chb')!['MAT_KEY'], c1.namespace('chb')!['IMPS_KEY'], c1.namespace('chb')!['CHB_LARG']], [5, 2, 0.4]);
    final equ = (c1.namespace('inf')!['equipements'] as List).single as Map;
    expect([equ['MAT_KEY'], equ['EQU_QTE']], [1, 1]);
    expect(equ.keys, isNot(contains('nouveau')));

    // barre basse : Équipements (à la place des connecteurs), liens fibres de la boîte d'épissure
    await t.tap(find.text('Équipements').last);
    await t.pumpAndSettle();
    expect(find.text('équipements'), findsOneWidget);
    await t.tap(find.byTooltip('Liens fibres'));
    await t.pumpAndSettle();
    expect(find.text('Liens fibres de la boîte : à venir'), findsOneWidget);

    // barre basse : Masques ouvre l'aperçu (une ligne par face, puis les conduites), une face ouvre sa grille
    await t.tap(find.text('Masques'));
    await t.pumpAndSettle();
    expect(find.text('masques'), findsOneWidget);
    expect(find.text('1 alvéole'), findsOneWidget);
    expect(find.text('Grille 9 × 12'), findsOneWidget);
    expect(find.text('Face non relevée'), findsNWidgets(3));
    await t.scrollUntilVisible(find.textContaining('vers C598'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('CONDUITES'), findsOneWidget);
    expect(find.text('1 conduite'), findsOneWidget);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await t.pumpAndSettle();
    await t.tap(find.text('1 alvéole'));
    await t.pumpAndSettle();
    expect(find.text('masque A · 1 alvéole'), findsOneWidget);
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
    await tap(find.byTooltip('Saisie du support'));
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
}
