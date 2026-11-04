import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/data/visuals.dart';
import 'package:nge_esplorer/modules/poteau/rosette_screen.dart';
import 'package:nge_esplorer/modules/completion.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/visuals_screen.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
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
    await t.ensureVisible(find.text('Ajouter un câble'));
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
    await t.tap(find.byTooltip('Définir comme référence'));
    await t.pumpAndSettle();
    overall = (await repo.object('P1'))!.photos(vOverall);
    expect(overall.map((f) => f['FIC_CODE_EXT']), ['E2', 'E1']);
    expect(overall.first['FIC_PRINCIPALE'], 1);

    // le globe ramène à la carte
    await t.tap(find.text('Carte'));
    await t.pumpAndSettle();
    expect(find.text('carte'), findsOneWidget);
  });
}
