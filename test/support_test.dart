import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/data/visuals.dart';
import 'package:nge_esplorer/modules/poteau/rosette_editor.dart';
import 'package:nge_esplorer/modules/poteau/rosette_screen.dart';
import 'package:nge_esplorer/modules/poteau/rosette_view.dart';
import 'package:nge_esplorer/modules/completion.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/visuals_screen.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
import 'package:nge_esplorer/widgets/bottom_bar.dart';
import 'package:nge_esplorer/widgets/fields.dart';
import 'package:nge_esplorer/widgets/linear_list.dart';
import 'package:nge_esplorer/widgets/photo.dart';
import 'package:provider/provider.dart';

/// Image PNG de 1 × 1 pixel.
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Map<String, dynamic> photo(String id, String view, int rank) => {
      'ENTITE': 'PRJ_NOE',
      'VUE_CODE': view,
      'FIC_CODE_EXT': id,
      'FIC_RANG': rank,
      'FIC_PRINCIPALE': rank == 1 ? 1 : 0,
      'FIC_NOM': '$id.jpg',
      'DATE_PRISE': '2021-03-25T09:30:00Z',
      'fichier': 'fichiers/$id.jpg',
    };

/// Paquet d'essai : un poteau et ses trois visuels (boîtier : 1 photo, ensemble : 2, tête : aucune).
Bundle bundle() => Bundle(
      header: {
        'format': Bundle.format,
        'version': Bundle.version,
        'date': '2026-11-02T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
        'modules': {'noyau': '0.1.0', 'poteau': '0.1.0'},
      },
      objects: [
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'P1',
          'geometry': {'type': 'Point', 'coordinates': [2.0, 45.0]},
          'properties': {
            'classe': 'NOE',
            'NOE_LIB': 'P922',
            'TYPE_KEY': 14,
            'fichiers': [photo('B1', 'BOITIER', 1), photo('E2', 'ENSEMBLE', 2), photo('E1', 'ENSEMBLE', 1)],
          },
        }),
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'P2',
          'geometry': {'type': 'Point', 'coordinates': [2.0005, 45.0]},
          'properties': {'classe': 'NOE', 'NOE_LIB': 'P923', 'TYPE_KEY': 14},
        }),
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'L1',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [2.0, 45.0],
              [2.0005, 45.0],
            ],
          },
          'properties': {
            'classe': 'LIN',
            'TYPE_KEY': 1002,
            'NOE1_KEY': 'P1',
            'NOE2_KEY': 'P2',
            'inf': {'portee': <String, dynamic>{}},
          },
        }),
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'C1',
          'geometry': {'type': 'Point', 'coordinates': [2.001, 45.0]},
          'properties': {'classe': 'NOE', 'NOE_LIB': 'C12', 'TYPE_KEY': 16},
        }),
      ],
      referenceData: ReferenceData({
        'noyau': {
          'DEF_TYPE': [
            {'TYPE_ID': 3, 'TYPE_CODE': 'INF', 'TYPE_LIB': 'Support'},
            {'TYPE_ID': 13, 'TYPE_CODE': 'POT', 'TYPE_LIB': 'Poteau', 'TYPE_PARENT_KEY': 3},
            {'TYPE_ID': 14, 'TYPE_CODE': 'POT-FT', 'TYPE_LIB': 'Poteau télécom', 'TYPE_PARENT_KEY': 13},
            {'TYPE_ID': 16, 'TYPE_CODE': 'CHB', 'TYPE_LIB': 'Chambre', 'TYPE_PARENT_KEY': 3},
          ],
          'DEF_VUE': [
            {'TYPE_KEY': 13, 'VUE_CODE': 'TETE', 'VUE_LIB': 'Vue tête de poteau', 'VUE_ORDRE': 3, 'VUE_OBLIGATOIRE': 'OUI'},
            {'TYPE_KEY': 13, 'VUE_CODE': 'BOITIER', 'VUE_LIB': 'Boîtier optique', 'VUE_ORDRE': 1, 'VUE_OBLIGATOIRE': 'NON'},
            {'TYPE_KEY': 13, 'VUE_CODE': 'ENSEMBLE', 'VUE_LIB': 'Vue d\'ensemble', 'VUE_ORDRE': 2, 'VUE_OBLIGATOIRE': 'OUI'},
            {'TYPE_KEY': 16, 'VUE_CODE': 'ENV', 'VUE_LIB': 'Environnement', 'VUE_ORDRE': 1, 'VUE_OBLIGATOIRE': 'OUI'},
            {'TYPE_KEY': 16, 'VUE_CODE': 'A', 'VUE_LIB': 'Vue A', 'VUE_ORDRE': 2, 'VUE_OBLIGATOIRE': 'SI_MASQUE'},
            {'TYPE_KEY': 16, 'VUE_CODE': 'B', 'VUE_LIB': 'Vue B', 'VUE_ORDRE': 3, 'VUE_OBLIGATOIRE': 'SI_MASQUE'},
          ],
        },
      }),
      files: {'fichiers/B1.jpg': png, 'fichiers/E1.jpg': png, 'fichiers/E2.jpg': png},
    );

final vOverall = Visual.expected({'VUE_CODE': 'ENSEMBLE'});
final vHead = Visual.expected({'VUE_CODE': 'TETE'});

/// Entrée [label] du menu ⋮ de l'écran (il remplace les pictos de la barre de titre).
Future<void> menu(WidgetTester t, String label) async {
  await t.tap(find.byTooltip('Plus d\'actions'));
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

/// Saisie du support : bouton de la barre basse (notes rep16 : retirée du menu ⋮).
Future<void> entry(WidgetTester t) async {
  await t.tap(find.widgetWithText(BarItem, 'Saisie'));
  await t.pumpAndSettle();
}

void main() {
  group('Visuels et photos', () {
    test('visuels du type et de ses parents, ordre de la galerie', () {
      final p = bundle();
      final o = p.objects.first;
      expect(Visual.of(o, p.referenceData).map((v) => v.code), ['BOITIER', 'ENSEMBLE', 'TETE']);
      expect(o.photos(vOverall).map((f) => f['FIC_CODE_EXT']), ['E1', 'E2']);
      expect(o.photos(vHead), isEmpty);
    });

    test('ajouter, réordonner, supprimer : référence et rangs', () {
      final o = bundle().objects.first;
      final n = o.addPhoto(vOverall, name: 'IMG_1.JPG', size: 3, author: 'essai');
      expect(n['fichier'], matches(RegExp(r'^fichiers/[0-9a-f-]{36}\.jpg$')));
      expect(n['FIC_TYPE'], 'image/jpeg');
      expect(o.photos(vOverall).map((f) => f['FIC_RANG']), [1, 2, 3]);

      final order = o.photos(vOverall);
      o.reorderPhotos([order[2], order[0], order[1]]);
      expect(o.photos(vOverall).first, same(n));
      expect(n['FIC_PRINCIPALE'], 1);
      expect(o.files.where((f) => f['FIC_PRINCIPALE'] == 1 && f['VUE_CODE'] == 'ENSEMBLE').length, 1);

      // photo venue du BE : abandonnée ; photo prise sur le terminal : retirée
      final e1 = o.photos(vOverall).firstWhere((f) => f['FIC_CODE_EXT'] == 'E1');
      o.deletePhoto(vOverall, e1, isNew: false, author: 'essai');
      expect(e1['DATE_ABD'], isNotNull);
      expect(o.files, contains(e1));
      o.deletePhoto(vOverall, n, isNew: true, author: 'essai');
      expect(o.files, isNot(contains(n)));
      final remaining = o.photos(vOverall).single;
      expect([remaining['FIC_CODE_EXT'], remaining['FIC_RANG'], remaining['FIC_PRINCIPALE']], ['E2', 1, 1]);
    });

    test('visuel libre : après les visuels attendus, titre porté par ses photos', () {
      final p = bundle();
      final o = p.objects.first;
      final free = Visual.free('Boîte aux lettres');
      final f = o.addPhoto(free, name: 'bal.jpg', size: 3, author: 'essai');
      expect([f['VIS_CODE'], f['VIS_LIB'], f.containsKey('VUE_CODE')], [free.code, 'Boîte aux lettres', false]);
      o.addPhoto(free, name: 'bal2.jpg', size: 3, author: 'essai');
      var vs = Visual.of(o, p.referenceData);
      expect(vs.map((v) => v.lib), ['Boîtier optique', "Vue d'ensemble", 'Vue tête de poteau', 'Boîte aux lettres']);
      expect(vs.last.free, isTrue);
      expect(o.photos(vs.last).map((f) => f['FIC_RANG']), [1, 2]);

      o.renameVisual(vs.last, 'BAL');
      vs = Visual.of(o, p.referenceData);
      expect(vs.last.lib, 'BAL');

      // sans photo, le visuel libre disparaît
      for (final f in o.photos(vs.last)) {
        o.deletePhoto(vs.last, f, isNew: true, author: 'essai');
      }
      expect(Visual.of(o, p.referenceData).length, 3);
    });

    test('paquet de retour : photos prises sur le terminal et toujours rattachées', () async {
      final repo = MemoryRepository();
      await repo.load(bundle());
      final app = AppProvider(repo);
      final o = (await repo.object('P1'))!.copy();
      await app.addPhoto(o, vHead, name: 'tete.png', bytes: png);
      await app.addPhoto(o, vHead, name: 'autre.png', bytes: png);
      final o2 = (await repo.object('P1'))!.copy();
      final removed = o2.photos(vHead).last;
      o2.deletePhoto(vHead, removed, isNew: true, author: 'essai');
      await app.save(o2);

      final (_, zip) = await app.returnBundle();
      final names = ZipDecoder().decodeBytes(zip).files.map((f) => f.name).toList();
      final kept = o2.photos(vHead).single['fichier'];
      expect(names, contains(kept));
      expect(names, isNot(contains(removed['fichier'])));
    });
  });

  group('Renseignement (principe FOA Explorer)', () {
    late MemoryRepository repo;
    late ReferenceData ref;
    setUp(() async {
      final p = bundle();
      ref = p.referenceData;
      repo = MemoryRepository();
      await repo.load(p);
    });

    test('poteau : partiel, complet, défaut ; niveau posé à l\'enregistrement', () async {
      final o = (await repo.object('P1'))!.copy();
      expect(await completionOf((await repo.object('P2'))!, ref, repo), Completion.toFill);
      expect(await completionOf(o, ref, repo), Completion.partial); // photos, mais tête manquante

      o.addPhoto(vHead, name: 't.jpg', size: 1, author: 'essai');
      o.namespace('pot', create: true)!
        ..['MAT_KEY'] = 7
        ..['controles'] = [
          {'DATE_CTL': '2026-11-02', 'SEC_UTILISABLE': 1},
        ];
      expect(await completionOf(o, ref, repo), Completion.partial); // portée L1 non orientée

      final l1 = (await repo.object('L1'))!.copy();
      (l1.namespace('inf')!['portee'] as Map)['PRT_ANG1'] = 100.0;
      await repo.save(l1, author: 'essai');
      expect(await completionOf(o, ref, repo), Completion.complete);

      await AppProvider(repo).save(o);
      expect((await repo.object('P1'))!.namespace('pot')!['POT_NIVEAU'], 2);

      (o.namespace('pot')!['controles'] as List).add({'DATE_CTL': '2026-11-03', 'SEC_UTILISABLE': 0});
      expect(await completionOf(o, ref, repo), Completion.defect);
    });

    test('chambre : face relevée et vue de chaque face relevée', () async {
      final c = (await repo.object('C1'))!.copy();
      expect(await completionOf(c, ref, repo), Completion.toFill);
      final visuals = Visual.of(c, ref);
      c.addPhoto(visuals.firstWhere((v) => v.code == 'ENV'), name: 'env.jpg', size: 1, author: 'essai');
      expect(await completionOf(c, ref, repo), Completion.partial); // aucune face relevée
      c.namespace('chb', create: true)!['faces'] = [
        {
          'FAC_CODE': 'A',
          'positions': [
            {'CD_KEY': 'X'},
          ],
        },
        {'FAC_CODE': 'B', 'positions': []},
      ];
      expect(await completionOf(c, ref, repo), Completion.partial); // vue A manquante (B : sans position)
      c.addPhoto(visuals.firstWhere((v) => v.code == 'A'), name: 'a.jpg', size: 1, author: 'essai');
      expect(await completionOf(c, ref, repo), Completion.complete);
    });
  });

  test('rosace : direction dictée par la destination connue, ajustable de ± 5 gr ; libre vers une destination à '
      'relever ou créée', () async {
    final repo = MemoryRepository();
    await repo.load(bundle());
    final editor = RosetteEditor(repo, (await repo.object('P1'))!, author: 'essai', intervention: () => 'i1');
    await editor.load();
    final p = editor.spans.single;
    expect(p.direction, closeTo(100, 0.5)); // P923, plein est
    expect([p.surveyedAngle, p.angle], [null, p.direction]);
    editor.orient(p, p.direction! + 3);
    expect([p.limited, p.deviation], [false, closeTo(3, 0.06)]);
    // au-delà de la marge : arrêtée à la butée, d'un côté comme de l'autre
    editor.orient(p, p.direction! + 40);
    expect([p.limited, p.deviation], [true, closeTo(directionMargin, 0.06)]);
    editor.orient(p, p.direction! - 12);
    expect([p.limited, p.deviation], [true, closeTo(-directionMargin, 0.06)]);

    // destination créée pendant la session : elle suit l'aiguille, sans contrainte
    final created = editor.add(newType: 14, newLabel: 'P999', angle: 0);
    expect(created.direction, isNull);
    editor.orient(created, 250);
    expect([created.limited, created.angle], [false, 250.0]);

    // destination à relever (position provisoire) : orientation libre
    final p2 = (await repo.object('P2'))!.copy()..props['GEOL_MOD_KEY'] = 8;
    await repo.save(p2, author: 'essai');
    await editor.load();
    expect(editor.spans.single.direction, isNull);
  });

  testWidgets('rosace : butée de la direction de la destination signalée sous l\'angle', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final pole = (await repo.object('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: RosetteScreen(pole: pole)),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('(destination)'), findsOneWidget);
    await t.tap(find.widgetWithText(ListTile, 'P923'));
    await t.pumpAndSettle();
    expect(find.textContaining('ajustable de ± 5.0 gr à l\'aiguille'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.text('+1'));
      await t.pump();
    }
    expect(find.textContaining('écart de l\'aiguille : +3.0 gr'), findsOneWidget);
    expect(find.textContaining('Écart limité'), findsNothing);
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('+1'));
      await t.pump();
    }
    expect(find.textContaining('écart de l\'aiguille : +5.0 gr'), findsOneWidget);
    expect(find.text('Écart limité à ± 5.0 gr : si la destination est mal placée, corrigez sa position.'), findsOneWidget);

    // recalée sur la carte : sur la direction de la destination, le bouton devient inactif
    final realign = find.ancestor(
        of: find.text('Recaler sur la carte (100.0 gr)', skipOffstage: false),
        matching: find.bySubtype<TextButton>(skipOffstage: false));
    await t.ensureVisible(realign);
    await t.pumpAndSettle();
    await t.tap(find.text('Recaler sur la carte (100.0 gr)'));
    await t.pump();
    // la note, juste au-dessus du bouton, peut être sortie du panneau au défilement
    expect(find.textContaining('ajustable de ± 5.0 gr à l\'aiguille', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Écart limité', skipOffstage: false), findsNothing);
    expect(t.widget<TextButton>(realign).onPressed, isNull);
    await t.ensureVisible(find.text('+1', skipOffstage: false));
    await t.pumpAndSettle();
    await t.tap(find.text('+1'));
    await t.pump();
    expect(t.widget<TextButton>(realign).onPressed, isNotNull);
  });

  test('rosace : recaler sur la carte, sur la géométrie vers une destination à relever, impossible vers une '
      'destination créée', () async {
    final repo = MemoryRepository();
    await repo.load(bundle());
    await repo.save((await repo.object('P2'))!.copy()..props['GEOL_MOD_KEY'] = 8, author: 'essai');
    final editor = RosetteEditor(repo, (await repo.object('P1'))!, author: 'essai', intervention: () => 'i1');
    await editor.load();
    final p = editor.spans.single;
    expect([p.direction, editor.mapDirection(p)], [null, p.mapAngle]);
    editor.orient(p, 250);
    editor.realign(p);
    expect(p.surveyedAngle, closeTo(p.mapAngle!, 0.06));
    final created = editor.add(newType: 14, newLabel: 'P999', angle: 30);
    expect(editor.mapDirection(created), isNull);
  });

  testWidgets('rosace : portée, câble en accordéon (modifier, supprimer, annuler), enregistrer', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo);
    final pole = (await repo.object('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RosetteScreen(pole: pole))),
              child: const Text('carte'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();
    expect(find.text('portées · 1 direction'), findsOneWidget);
    expect(find.text('Direction'), findsOneWidget);
    expect(find.text('Portées'), findsOneWidget);

    await t.tap(find.widgetWithText(ListTile, 'P923'));
    await t.pumpAndSettle();
    // le carton « Naviguer vers » de la portée choisie prend sa place sous le détail : on fait défiler jusqu'au bouton
    await t.scrollUntilVisible(find.text('Ajouter un câble'), 100, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Ajouter un câble'));
    await t.pumpAndSettle();
    expect(find.text('Câble n° 1 à identifier'), findsOneWidget);
    await t.ensureVisible(find.text('2'));
    await t.pumpAndSettle();
    await t.tap(find.text('2'));
    await t.pumpAndSettle();
    expect(find.text('nappe 2 · Standard agglomération'), findsOneWidget);

    await t.ensureVisible(find.text('Supprimer ce câble'));
    await t.pumpAndSettle();
    await t.tap(find.text('Supprimer ce câble'));
    await t.pumpAndSettle();
    expect(find.text('Câble n° 1 à identifier'), findsNothing);
    await t.tap(find.text('ANNULER'));
    await t.pumpAndSettle();
    expect(find.text('nappe 2 · Standard agglomération'), findsOneWidget);

    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final cables = ((await repo.object('L1'))!.namespace('inf')!['portee'] as Map)['cables'] as List;
    expect(cables.single, containsPair('PCB_NAPPE', 2));
    expect(find.text('Enregistrer'), findsNothing);
  });

  testWidgets('rosace : le carton paraît sans changer la taille de la rosace, l\'aiguille suit le doigt ; portée '
      'supprimée puis enregistrée : plus rien à enregistrer', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final pole = (await repo.object('P1'))!;
    // P923 à relever (position provisoire) : l'aiguille est libre, sans la butée de la direction de la destination
    await repo.save((await repo.object('P2'))!.copy()..props['GEOL_MOD_KEY'] = 8, author: 'essai');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RosetteScreen(pole: pole))),
              child: const Text('carte'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();
    final before = t.getRect(find.byType(RosetteView));
    expect(find.byType(RouteCard), findsNothing);

    // aiguille de P923 (100 gr, à l'est) glissée jusqu'au sud : le carton paraît dès le début du geste, au-dessus du
    // panneau, et la rosace ne bouge pas ; l'aiguille suit le doigt jusqu'à 200 gr
    final c = before.center, r = before.shortestSide / 2 * 0.6;
    Offset at(double grads) => c + Offset(math.sin(grads * math.pi / 200), -math.cos(grads * math.pi / 200)) * r;
    final drag = await t.startGesture(at(100));
    for (var g = 105.0; g <= 200; g += 5) {
      await drag.moveTo(at(g));
      await t.pump();
    }
    expect(find.byType(RouteCard), findsOneWidget);
    expect(t.getRect(find.byType(RosetteView)), before);
    expect(t.getRect(find.byType(RouteCard)).top, greaterThanOrEqualTo(before.bottom));
    await drag.up();
    await t.pumpAndSettle();
    expect(find.text('200.0 gr'), findsOneWidget);

    // portée supprimée, puis enregistrée : abandonnée dans le dépôt, l'écran n'a plus rien à enregistrer (au bout du
    // détail, au-dessus du bouton « Enregistrer »)
    await t.drag(find.byType(Scrollable).first, const Offset(0, -1000));
    await t.pumpAndSettle();
    await t.tap(find.text('Supprimer la portée'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect((await repo.object('L1'))!.abandoned, isTrue);
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.text('portées · 0 direction'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Enregistrer les modifications ?'), findsNothing);
    expect(find.text('carte'), findsOneWidget);
  });

  testWidgets('saisie du poteau : cartes Général, Contrôles, Commentaires ; portées et autres parcours dans '
      'l\'onglet Portées, portées enregistrées avant d\'ouvrir le support d\'en face', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    // parcours souterrain du poteau vers la chambre (hors rosace), sa conduite placée sur la face A de la chambre
    await repo.save(
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
            'NOE1_KEY': 'P1',
            'NOE2_KEY': 'C1',
            'inf': {
              'conduites': [
                {'CD_CODE_EXT': 'CD9', 'CD_NUM': 1, 'CD_DIAM': 45.0},
              ],
            },
          },
        }),
        author: 'essai');
    final c1 = (await repo.object('C1'))!.copy();
    c1.namespace('chb', create: true)!['faces'] = [
      {
        'FAC_CODE': 'A',
        'positions': [
          {'CD_KEY': 'CD9', 'POS_X': 0.2, 'POS_Y': 0.2},
        ],
      },
    ];
    await repo.save(c1, author: 'essai');
    final pole = (await repo.object('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        // carte simulée : le poteau s'ouvre sur ses visuels, puis sa saisie
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, pole), child: const Text('carte')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();
    await entry(t);
    List<String?> names() => [for (final r in screenStack.stack) r.settings.name];
    expect(names(), ['/', 'support:P1', 'onglet:P1:saisie']);
    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    Finder inSection(String title, Finder f) =>
        find.descendant(of: find.ancestor(of: find.text(title), matching: find.byType(Section)), matching: f);

    // cartes dépliables comme la chambre, sans carte Poteau ni linéaires ; caractéristiques dans Général
    expect(inSection('GÉNÉRAL', find.widgetWithText(TextField, 'Référence (catalogue)')), findsOneWidget);
    expect(inSection('GÉNÉRAL', find.widgetWithText(TextFormField, 'Numéro')), findsOneWidget);
    for (final title in ['GÉNÉRAL', 'CONTRÔLES', 'COMMENTAIRES']) {
      await t.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('POTEAU'), findsNothing);
    expect(find.text('LINÉAIRES'), findsNothing);
    expect(find.text('PORTÉES ET PARCOURS'), findsNothing);
    expect(find.textContaining('vers '), findsNothing);

    // contrôle du jour, sans commentaire (réunis dans le journal) ; la carte se replie
    final day = Bundle.timestamp().substring(0, 10).split('-').reversed.join('/');
    await t.scrollUntilVisible(find.text('Contrôle du $day'), -200, scrollable: find.byType(Scrollable).first);
    expect(inSection('CONTRÔLES', find.byType(TextFormField)), findsNothing);
    await tap(find.text('CONTRÔLES'));
    expect(find.text('Percussion'), findsNothing);
    await tap(find.text('CONTRÔLES'));
    expect(t.takeException(), isNull);
    await tap(find.descendant(of: find.widgetWithText(YesNoField, 'Contrôle visuel'), matching: find.text('Oui')));
    await tap(find.text('Enregistrer'));
    final ctl = ((await repo.object('P1'))!.namespace('pot')!['controles'] as List).single as Map;
    expect([ctl['DATE_CTL'], ctl['CTL_VISUEL']], [Bundle.timestamp().substring(0, 10), 1]);
    expect(ctl.keys, isNot(contains('CTL_COMMENT')));

    // onglet Portées : la portée vers P923, puis le parcours souterrain vers C12
    await tap(find.text('Portées'));
    expect(find.text('PORTÉES'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'P923'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('vers C12'), 100, scrollable: find.byType(Scrollable).first);
    expect(find.text('AUTRES PARCOURS'), findsOneWidget);
    // ni portée ni parcours ne se suit d'une touche : leur sélection montre le carton « Naviguer vers »
    expect(find.byTooltip('Ouvrir C12'), findsNothing);
    expect(find.byTooltip('Ouvrir P923'), findsNothing);
    expect(find.textContaining('Naviguer vers'), findsNothing);

    // portée choisie : son détail et son carton ; réorientée, elle est enregistrée avant de naviguer jusqu'à P923
    await tap(find.widgetWithText(ListTile, 'P923'));
    // le détail s'ouvre en haut, et non au défilement de la liste
    expect(find.descendant(of: find.byType(ListView), matching: find.text('P923')), findsOneWidget);
    expect(find.text('Naviguer vers P923'), findsOneWidget);
    await tap(find.text('+1'));
    await tap(find.text('Naviguer vers P923'));
    final ang1 = ((await repo.object('L1'))!.namespace('inf')!['portee'] as Map)['PRT_ANG1'];
    expect(ang1, isNotNull);
    // P923 remplace P922, un seul support ouvert au-dessus de la carte : ses portées, la portée commune ouverte (vue
    // de son côté, vers P922), carton du retour
    expect(names(), ['/', 'onglet:P2:portees']);
    expect(find.text('P923'), findsOneWidget);
    expect(find.text('portées · 1 direction'), findsOneWidget);
    expect(find.descendant(of: find.byType(ListView), matching: find.text('P922')), findsOneWidget);
    expect(find.text('Angle'), findsOneWidget);
    expect(find.text('Naviguer vers P922'), findsOneWidget);
    // l'angle relevé de ce côté-ci (PRT_ANG2), enregistré
    await tap(find.text('+1'));
    await tap(find.text('Enregistrer'));
    final ang2 = ((await repo.object('L1'))!.namespace('inf')!['portee'] as Map)['PRT_ANG2'];
    expect(ang2, isNotNull);
    // picto des visuels : ceux de P923 à la place de ses portées
    await menu(t, 'Visuels du support');
    expect(find.text('P923'), findsOneWidget);
    expect(find.textContaining('visuels'), findsOneWidget);
    expect(names(), ['/', 'support:P2']);
    // menu ⋮ : « Revenir à P922 » rouvre ses portées, relues dans le dépôt, la portée toujours choisie avec son carton
    await tap(find.byTooltip('Plus d\'actions'));
    expect(find.text('portées'), findsOneWidget);
    await tap(find.text('Revenir à P922'));
    expect(names(), ['/', 'onglet:P1:portees']);
    expect(find.text('Naviguer vers P923'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
    // modifiée de ce côté-ci, la portée garde l'angle relevé à P923 (plus de copie périmée qui l'écraserait)
    await tap(find.text('+1'));
    await tap(find.text('Enregistrer'));
    final both = (await repo.object('L1'))!.namespace('inf')!['portee'] as Map;
    expect([both['PRT_ANG2'], both['PRT_ANG1'] == ang1], [ang2, isFalse]);
    await tap(find.byTooltip('Portées', skipOffstage: false)); // retour à la liste, en haut du détail
    expect(find.text('PORTÉES'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.textContaining('Naviguer vers'), findsNothing);

    // parcours souterrain sélectionné : son carton mène à la chambre, sur son aperçu des masques (même écran), le
    // parcours mis en avant avec la pastille jaune du retour (notes rep11 : plus de carton sur l'aperçu)
    await t.scrollUntilVisible(find.textContaining('vers C12'), 100, scrollable: find.byType(Scrollable).first);
    await tap(find.textContaining('vers C12'));
    await tap(find.text('Naviguer vers C12'));
    expect(find.text('masques'), findsOneWidget);
    expect(names(), ['/', 'onglet:C1:masques']);
    // et la pastille de la chambre ramène au poteau, sur ses portées, le parcours sélectionné
    await t.scrollUntilVisible(find.byTooltip('Naviguer vers P922'), 100, scrollable: find.byType(Scrollable).first);
    await tap(find.byTooltip('Naviguer vers P922'));
    expect(find.text('PORTÉES'), findsOneWidget);
    expect(find.text('Naviguer vers C12'), findsOneWidget);
    // menu ⋮ : les supports quittés, du plus récent au plus ancien ; Carte : retour direct, quel que soit le chemin
    await tap(find.byTooltip('Plus d\'actions'));
    // visuels du support (la saisie est dans la barre basse, notes rep16), puis les supports quittés
    final items = find.byType(PopupMenuItem<VoidCallback>);
    expect(find.text('Saisie du support'), findsNothing);
    for (final (i, label) in ['Visuels du support', 'Revenir à C12', 'P923', 'Repérer sur la carte'].indexed) {
      expect(find.descendant(of: items.at(i), matching: find.text(label)), findsOneWidget, reason: label);
    }
    await t.tapAt(const Offset(10, 790)); // ferme le menu
    await t.pumpAndSettle();
    await tap(find.text('Carte'));
    expect(names(), ['/']);
  });

  testWidgets('picto des visuels : retour aux visuels du support, saisie enregistrée avant', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final pole = (await repo.object('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, pole), child: const Text('carte')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();
    await entry(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Numéro'), 'P922 bis');
    await t.pump();
    await menu(t, 'Visuels du support');
    // les visuels d'arrivée, et non un second écran des visuels
    expect(find.text('P922 bis'), findsOneWidget);
    expect(find.textContaining('visuels'), findsOneWidget);
    expect(screenStack.stack, hasLength(2));
    expect((await repo.object('P1'))!.lib, 'P922 bis');
  });

  testWidgets('visuels, galerie : état des visuels, suppression avec Annuler, référence', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo);
    final pole = (await repo.object('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, pole), child: const Text('carte')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();

    expect(find.text('visuels · 1 manquant'), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
    expect(find.text('Manquante'), findsOneWidget);
    expect(find.text('Portées'), findsOneWidget);

    await t.tap(find.text('Vue d\'ensemble *'));
    await t.pumpAndSettle();
    expect(find.text('Référence'), findsOneWidget);
    expect(find.byTooltip('Définir comme référence'), findsOneWidget);
    // photos entières au format 4:3 (notes rep10), une par rangée sur un téléphone
    final frames = find.descendant(of: find.byType(Card), matching: find.byType(AspectRatio));
    expect(frames, findsNWidgets(2));
    expect(t.getSize(frames.first).aspectRatio, closeTo(4 / 3, 0.01));
    expect(t.getRect(frames.at(1)).top, greaterThan(t.getRect(frames.first).bottom));
    // toucher une photo l'affiche en plein écran, agrandissable
    await t.tap(frames.first);
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    // supprimer la référence (E1) : E2 devient la référence ; Annuler la rétablit
    await t.tap(find.byTooltip('Supprimer la photo').first);
    await t.pumpAndSettle();
    expect(find.text('Photo supprimée'), findsOneWidget);
    var overall = (await repo.object('P1'))!.photos(vOverall);
    expect(overall.map((f) => f['FIC_CODE_EXT']), ['E2']);
    expect(overall.single['FIC_PRINCIPALE'], 1);
    expect(app.nbChanged, 1);

    await t.tap(find.text('ANNULER'));
    await t.pumpAndSettle();
    overall = (await repo.object('P1'))!.photos(vOverall);
    expect(overall.map((f) => f['FIC_CODE_EXT']), ['E1', 'E2']);

    // la seconde devient la référence
    await t.ensureVisible(find.byTooltip('Définir comme référence'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Définir comme référence'));
    await t.pumpAndSettle();
    overall = (await repo.object('P1'))!.photos(vOverall);
    expect(overall.map((f) => f['FIC_CODE_EXT']), ['E2', 'E1']);
    expect(overall.first['FIC_PRINCIPALE'], 1);

    // appui long sur la seconde, déposée sur la première : elles échangent leur place
    final second = await t.startGesture(t.getCenter(frames.at(1)));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await second.moveTo(t.getCenter(frames.first));
    await t.pump();
    await second.up();
    await t.pumpAndSettle();
    expect((await repo.object('P1'))!.photos(vOverall).map((f) => f['FIC_CODE_EXT']), ['E1', 'E2']);

    // tablette en paysage : les deux photos côte à côte
    t.view.physicalSize = const Size(1280, 800);
    await t.pumpAndSettle();
    expect(t.getRect(frames.at(1)).left, greaterThan(t.getRect(frames.first).right));
    expect(t.getRect(frames.at(1)).top, t.getRect(frames.first).top);
    t.view.physicalSize = const Size(360, 800);
    await t.pumpAndSettle();

    // le globe ramène à la carte
    await t.tap(find.text('Carte'));
    await t.pumpAndSettle();
    expect(find.text('carte'), findsOneWidget);
  });

  testWidgets('visuels et galerie relus : une copie périmée n’efface rien de ce qui a été enregistré entre-temps ; '
      '« Annuler » ne rétablit que la photo', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo);
    final pole = (await repo.object('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, pole), child: const Text('carte')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();

    // écriture faite ailleurs (onglet, autre écran) : les visuels se relisent
    await app.save((await repo.object('P1'))!.copy()..props['NOE_LIB'] = 'P922 bis');
    await t.pumpAndSettle();
    expect(find.text('P922 bis'), findsOneWidget);

    // galerie dont la copie a vieilli : ses gestes partent du support enregistré
    await t.tap(find.text('Vue d\'ensemble *'));
    await t.pumpAndSettle();
    await app.save((await repo.object('P1'))!.copy()..namespace('pot', create: true)!['POT_HAUT'] = 9.5);
    await t.ensureVisible(find.byTooltip('Définir comme référence'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Définir comme référence'));
    await t.pumpAndSettle();
    var p1 = (await repo.object('P1'))!;
    expect(p1.namespace('pot')!['POT_HAUT'], 9.5);
    expect(p1.photos(vOverall).map((f) => f['FIC_CODE_EXT']), ['E2', 'E1']);

    // supprimer la référence (commandes de nouveau actives un instant après le déplacement), écrire ailleurs, puis
    // « Annuler » : seule la photo revient, à sa place
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.byTooltip('Supprimer la photo').first);
    await t.pumpAndSettle();
    expect((await repo.object('P1'))!.photos(vOverall).map((f) => f['FIC_CODE_EXT']), ['E1']);
    await app.save((await repo.object('P1'))!.copy()..namespace('pot', create: true)!['POT_HAUT'] = 10.0);
    await t.tap(find.text('ANNULER'));
    await t.pumpAndSettle();
    p1 = (await repo.object('P1'))!;
    expect(p1.photos(vOverall).map((f) => f['FIC_CODE_EXT']), ['E2', 'E1']);
    expect(p1.photos(vOverall).first['FIC_PRINCIPALE'], 1);
    expect(p1.namespace('pot')!['POT_HAUT'], 10.0);
  });

  testWidgets('« Repérer sur la carte » depuis une saisie modifiée : enregistrée, sans question, retour à la carte',
      (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo);
    final pole = (await repo.object('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, pole), child: const Text('carte')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();
    await entry(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Numéro'), 'P922 bis');
    await t.pump();
    await menu(t, 'Repérer sur la carte');
    expect(find.text('Enregistrer les modifications ?'), findsNothing);
    expect(screenStack.stack, hasLength(1));
    expect((await repo.object('P1'))!.lib, 'P922 bis');
    expect(app.takeLocate(), 'P1');
  });

  testWidgets('menu ⋮ : intitulé à jour d’un support renommé ; un support supprimé n’est plus proposé', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final p1 = (await repo.object('P1'))!, p2 = (await repo.object('P2'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(children: [
              TextButton(onPressed: () => openSupport(context, p1), child: const Text('ouvrir P922')),
              TextButton(onPressed: () => openSupport(context, p2), child: const Text('ouvrir P923')),
            ]),
          ),
        ),
      ),
    ));
    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    Future<List<String>> menuTexts() async {
      await t.tap(find.byTooltip('Plus d\'actions'));
      await t.pumpAndSettle();
      final texts = [
        for (final e in find.descendant(of: find.byType(PopupMenuItem<VoidCallback>), matching: find.byType(Text)).evaluate())
          (e.widget as Text).data ?? '',
      ];
      await t.tapAt(const Offset(10, 790)); // ferme le menu
      await t.pumpAndSettle();
      return texts;
    }

    // P922 renommé dans sa saisie, puis quitté depuis ses visuels (ouverts avant le renommage) : le menu de P923
    // propose « Revenir à P922 bis »
    await tap(find.text('ouvrir P922'));
    await entry(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Numéro'), 'P922 bis');
    await t.pump();
    await tap(find.text('Enregistrer'));
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('P922 bis'), findsOneWidget);
    await tap(find.text('Carte'));
    await tap(find.text('ouvrir P923'));
    expect(await menuTexts(), contains('Revenir à P922 bis'));

    // numéro tapé puis abandonné (« Abandonner les modifications ») : l'intitulé reste celui qui est enregistré
    await tap(find.text('Carte'));
    await tap(find.text('ouvrir P922'));
    await entry(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Numéro'), 'P922 essai');
    await t.pump();
    await tap(find.text('Carte'));
    await tap(find.text('Abandonner les modifications'));
    await tap(find.text('ouvrir P923'));
    final texts = await menuTexts();
    expect(texts, contains('Revenir à P922 bis'));
    expect(texts.where((x) => x.contains('essai')), isEmpty);

    // P922 supprimé : il n'est plus proposé
    await tap(find.text('Carte'));
    await tap(find.text('ouvrir P922'));
    await entry(t);
    await t.scrollUntilVisible(find.text('Supprimer le support'), 200, scrollable: find.byType(Scrollable).first);
    await tap(find.text('Supprimer le support'));
    await tap(find.widgetWithText(FilledButton, 'Supprimer'));
    expect(find.text('ouvrir P923'), findsOneWidget);
    await tap(find.text('ouvrir P923'));
    expect((await menuTexts()).where((x) => x.contains('P922')), isEmpty);
  });

  testWidgets('visuels : même carte partout (notes rep9), photo 4:3 jamais étirée, commandes en icônes ; en tuiles '
      'sur les écrans larges, de même hauteur par rangée', (t) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo);
    final pole = (await repo.object('P1'))!;
    Future<void> show(Size size) async {
      t.view.physicalSize = size;
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(theme: ngeTheme(), home: VisualsScreen(object: pole)),
      ));
      await t.pumpAndSettle();
    }

    Finder card(String title) => find.ancestor(of: find.text(title), matching: find.byType(VisualCard));
    Rect at(String title) => t.getRect(card(title));
    Size photo(String title) => t.getSize(find.descendant(of: card(title), matching: find.byType(Photo)));
    const box = 'Boîtier optique', overall = 'Vue d\'ensemble *', head = 'Vue tête de poteau *';
    bool stacked(String a, String b) => at(b).top >= at(a).bottom && at(b).left == at(a).left;
    bool sideBySide(String a, String b) => at(b).top == at(a).top && at(b).left > at(a).right;

    // la liste ne construit que ce qui approche de l'écran : défiler jusqu'au dernier visuel
    Future<void> reveal(String title) =>
        t.scrollUntilVisible(find.text(title), 100, scrollable: find.byType(Scrollable).first);

    for (final size in const [Size(360, 800), Size(412, 915), Size(800, 360), Size(800, 1280), Size(1280, 800), Size(1920, 1080)]) {
      await show(size);
      for (final v in [box, overall, head]) {
        await reveal(v);
        // même carte partout : photo 4:3, commandes en icônes à sa droite
        expect(photo(v).aspectRatio, closeTo(4 / 3, 0.01), reason: '$size $v');
        expect(find.descendant(of: card(v), matching: find.byTooltip('Prendre une photo')), findsOneWidget,
            reason: '$size $v');
      }
      expect(find.widgetWithText(OutlinedButton, 'Prendre une photo'), findsNothing, reason: '$size');
      expect(t.takeException(), isNull, reason: '$size');
    }

    // téléphone en portrait : une colonne
    await show(const Size(360, 800));
    expect(stacked(box, overall), isTrue);
    await reveal(head);
    expect(stacked(overall, head), isTrue);
    // tablette en portrait, téléphone en paysage : deux tuiles par rangée, de même hauteur
    for (final size in const [Size(800, 1280), Size(800, 360)]) {
      await show(size);
      expect(sideBySide(box, overall), isTrue, reason: '$size');
      expect(at(box).height, at(overall).height, reason: '$size');
      await reveal(head);
      expect(stacked(box, head), isTrue, reason: '$size');
    }
    // tablette en paysage et écran très large : les trois sur une rangée
    for (final size in const [Size(1280, 800), Size(1920, 1080)]) {
      await show(size);
      expect([sideBySide(box, overall), sideBySide(overall, head)], [isTrue, isTrue], reason: '$size');
      expect({at(box).height, at(overall).height, at(head).height}, hasLength(1), reason: '$size');
    }
  });

  testWidgets('saisie d\'un autre support : portée sélectionnée, carton « Naviguer vers », rosace du poteau d\'en face',
      (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    // support générique (ancrage de façade…) relié à P923 par une portée
    await repo.save(
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'F1',
          'geometry': {'type': 'Point', 'coordinates': [2.0005, 45.0005]},
          'properties': {'classe': 'NOE', 'NOE_LIB': 'F1', 'TYPE_KEY': 3},
        }),
        author: 'essai');
    await repo.save(
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'L9',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [2.0005, 45.0005],
              [2.0005, 45.0],
            ],
          },
          'properties': {
            'classe': 'LIN',
            'TYPE_KEY': 1002,
            'NOE1_KEY': 'F1',
            'NOE2_KEY': 'P2',
            'inf': {'portee': <String, dynamic>{}},
          },
        }),
        author: 'essai');
    final f1 = (await repo.object('F1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        // carte simulée : le support s'ouvre sur ses visuels, puis sa saisie
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, f1), child: const Text('carte')),
          ),
        ),
      ),
    ));
    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await tap(find.text('carte'));
    await entry(t);
    List<String?> names() => [for (final r in screenStack.stack) r.settings.name];

    // la portée se sélectionne (pas de suivi d'une touche) et montre son carton
    await t.scrollUntilVisible(find.textContaining('vers P923'), 100, scrollable: find.byType(Scrollable).first);
    expect(find.byTooltip('Ouvrir P923'), findsNothing);
    expect(find.textContaining('Naviguer vers'), findsNothing);
    await tap(find.textContaining('vers P923'));
    // P923 s'ouvre à la place de F1 sur ses portées, la portée commune ouverte, avec le carton du retour
    await tap(find.text('Naviguer vers P923'));
    expect(find.text('P923'), findsOneWidget);
    expect(find.text('Angle'), findsOneWidget);
    expect(names(), ['/', 'onglet:P2:portees']);
    // le carton du retour ramène F1 sur sa saisie (son écran des parcours), la portée sélectionnée avec son carton
    await tap(find.text('Naviguer vers F1'));
    expect(names(), ['/', 'onglet:F1:saisie']);
    expect(find.textContaining('saisie du support'), findsOneWidget);
    expect(find.text('Naviguer vers P923'), findsOneWidget);
    await tap(find.byTooltip('Fermer'));
    expect(find.textContaining('Naviguer vers'), findsNothing);
  });

  testWidgets('galerie : un double toucher sur la corbeille n\'atteint pas la photo voisine ; « Annuler » rétablit '
      'les suppressions à la suite ; glisser une photo près du bord fait défiler la liste', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final p1 = (await repo.object('P1'))!.copy();
    p1.props['fichiers'] = [...p1.files, photo('E3', 'ENSEMBLE', 3), photo('E4', 'ENSEMBLE', 4)];
    await repo.save(p1, author: 'essai');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => openSupport(context, p1), child: const Text('carte')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('carte'));
    await t.pumpAndSettle();
    await t.tap(find.text('Vue d\'ensemble *'));
    await t.pumpAndSettle();
    Future<List<Object?>> order() async =>
        [for (final f in (await repo.object('P1'))!.photos(vOverall)) f['FIC_CODE_EXT']];
    expect(await order(), ['E1', 'E2', 'E3', 'E4']);

    // double toucher sur la corbeille de E1 : la seconde touche tombe sur E2, venue à sa place, sans effet
    final delete = find.byTooltip('Supprimer la photo');
    await t.tap(delete.first);
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(delete.first, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(await order(), ['E2', 'E3', 'E4']);

    // une seconde suppression, voulue, pendant que « Annuler » est offert : il rétablit les deux, à leur place
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(delete.first);
    await t.pumpAndSettle();
    expect(await order(), ['E3', 'E4']);
    expect(find.text('2 photos supprimées'), findsOneWidget);
    await t.tap(find.text('ANNULER'));
    await t.pumpAndSettle();
    expect(await order(), ['E1', 'E2', 'E3', 'E4']);

    // la liste défilée en bas, la dernière photo glissée et tenue contre le haut de la liste : elle défile
    await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await t.pumpAndSettle();
    final list = t.state<ScrollableState>(find.byType(Scrollable).first);
    final bottom = list.position.pixels;
    expect(bottom, greaterThan(0));
    final frames = find.descendant(of: find.byType(Card), matching: find.byType(AspectRatio));
    final drag = await t.startGesture(t.getCenter(frames.last));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await drag.moveTo(Offset(180, t.getTopLeft(find.byType(Scrollable).first).dy + 10));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(list.position.pixels, lessThan(bottom));
    await drag.up();
    await t.pumpAndSettle();
  });
}
