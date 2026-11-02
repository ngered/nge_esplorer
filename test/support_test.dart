import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/objet.dart';
import 'package:nge_esplorer/data/paquet.dart';
import 'package:nge_esplorer/data/referentiels.dart';
import 'package:nge_esplorer/data/visuels.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/visuels_screen.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:nge_esplorer/widgets/retour_carte.dart';
import 'package:provider/provider.dart';

/// Image PNG de 1 × 1 pixel.
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Map<String, dynamic> photo(String id, String vue, int rang) => {
      'ENTITE': 'PRJ_NOE',
      'VUE_CODE': vue,
      'FIC_CODE_EXT': id,
      'FIC_RANG': rang,
      'FIC_PRINCIPALE': rang == 1 ? 1 : 0,
      'FIC_NOM': '$id.jpg',
      'DATE_PRISE': '2021-03-25T09:30:00Z',
      'fichier': 'fichiers/$id.jpg',
    };

/// Paquet d'essai : un poteau et ses trois visuels (boîtier : 1 photo, ensemble : 2, tête : aucune).
Paquet paquet() => Paquet(
      entete: {
        'format': Paquet.format,
        'version': Paquet.version,
        'date': '2026-11-02T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
        'modules': {'noyau': '0.1.0', 'poteau': '0.1.0'},
      },
      objets: [
        Objet.depuisFeature({
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
      ],
      referentiels: Referentiels({
        'noyau': {
          'DEF_TYPE': [
            {'TYPE_ID': 3, 'TYPE_CODE': 'INF', 'TYPE_LIB': 'Support'},
            {'TYPE_ID': 13, 'TYPE_CODE': 'POT', 'TYPE_LIB': 'Poteau', 'TYPE_PARENT_KEY': 3},
            {'TYPE_ID': 14, 'TYPE_CODE': 'POT-FT', 'TYPE_LIB': 'Poteau télécom', 'TYPE_PARENT_KEY': 13},
          ],
          'DEF_VUE': [
            {'TYPE_KEY': 13, 'VUE_CODE': 'TETE', 'VUE_LIB': 'Vue tête de poteau', 'VUE_ORDRE': 3, 'VUE_OBLIGATOIRE': 'OUI'},
            {'TYPE_KEY': 13, 'VUE_CODE': 'BOITIER', 'VUE_LIB': 'Boîtier optique', 'VUE_ORDRE': 1, 'VUE_OBLIGATOIRE': 'NON'},
            {'TYPE_KEY': 13, 'VUE_CODE': 'ENSEMBLE', 'VUE_LIB': 'Vue d\'ensemble', 'VUE_ORDRE': 2, 'VUE_OBLIGATOIRE': 'OUI'},
          ],
        },
      }),
      fichiers: {'fichiers/B1.jpg': png, 'fichiers/E1.jpg': png, 'fichiers/E2.jpg': png},
    );

final vEnsemble = Visuel.attendu({'VUE_CODE': 'ENSEMBLE'});
final vTete = Visuel.attendu({'VUE_CODE': 'TETE'});

void main() {
  group('Visuels et photos', () {
    test('visuels du type et de ses parents, ordre de la galerie', () {
      final p = paquet();
      final o = p.objets.single;
      expect(Visuel.de(o, p.referentiels).map((v) => v.code), ['BOITIER', 'ENSEMBLE', 'TETE']);
      expect(o.photos(vEnsemble).map((f) => f['FIC_CODE_EXT']), ['E1', 'E2']);
      expect(o.photos(vTete), isEmpty);
    });

    test('ajouter, réordonner, supprimer : référence et rangs', () {
      final o = paquet().objets.single;
      final n = o.ajouterPhoto(vEnsemble, nom: 'IMG_1.JPG', taille: 3, auteur: 'essai');
      expect(n['fichier'], matches(RegExp(r'^fichiers/[0-9a-f-]{36}\.jpg$')));
      expect(n['FIC_TYPE'], 'image/jpeg');
      expect(o.photos(vEnsemble).map((f) => f['FIC_RANG']), [1, 2, 3]);

      final ordre = o.photos(vEnsemble);
      o.ordonnerPhotos([ordre[2], ordre[0], ordre[1]]);
      expect(o.photos(vEnsemble).first, same(n));
      expect(n['FIC_PRINCIPALE'], 1);
      expect(o.fichiers.where((f) => f['FIC_PRINCIPALE'] == 1 && f['VUE_CODE'] == 'ENSEMBLE').length, 1);

      // photo venue du BE : abandonnée ; photo prise sur le terminal : retirée
      final e1 = o.photos(vEnsemble).firstWhere((f) => f['FIC_CODE_EXT'] == 'E1');
      o.supprimerPhoto(vEnsemble, e1, nouvelle: false, auteur: 'essai');
      expect(e1['DATE_ABD'], isNotNull);
      expect(o.fichiers, contains(e1));
      o.supprimerPhoto(vEnsemble, n, nouvelle: true, auteur: 'essai');
      expect(o.fichiers, isNot(contains(n)));
      final reste = o.photos(vEnsemble).single;
      expect([reste['FIC_CODE_EXT'], reste['FIC_RANG'], reste['FIC_PRINCIPALE']], ['E2', 1, 1]);
    });

    test('visuel libre : après les visuels attendus, titre porté par ses photos', () {
      final p = paquet();
      final o = p.objets.single;
      final libre = Visuel.libre('Boîte aux lettres');
      final f = o.ajouterPhoto(libre, nom: 'bal.jpg', taille: 3, auteur: 'essai');
      expect([f['VIS_CODE'], f['VIS_LIB'], f.containsKey('VUE_CODE')], [libre.code, 'Boîte aux lettres', false]);
      o.ajouterPhoto(libre, nom: 'bal2.jpg', taille: 3, auteur: 'essai');
      var vs = Visuel.de(o, p.referentiels);
      expect(vs.map((v) => v.lib), ['Boîtier optique', "Vue d'ensemble", 'Vue tête de poteau', 'Boîte aux lettres']);
      expect(vs.last.libre, isTrue);
      expect(o.photos(vs.last).map((f) => f['FIC_RANG']), [1, 2]);

      o.renommerVisuel(vs.last, 'BAL');
      vs = Visuel.de(o, p.referentiels);
      expect(vs.last.lib, 'BAL');

      // sans photo, le visuel libre disparaît
      for (final f in o.photos(vs.last)) {
        o.supprimerPhoto(vs.last, f, nouvelle: true, auteur: 'essai');
      }
      expect(Visuel.de(o, p.referentiels).length, 3);
    });

    test('paquet de retour : photos prises sur le terminal et toujours rattachées', () async {
      final repo = MemoryRepository();
      await repo.charger(paquet());
      final app = AppProvider(repo);
      final o = (await repo.objet('P1'))!.copie();
      await app.ajouterPhoto(o, vTete, nom: 'tete.png', octets: png);
      await app.ajouterPhoto(o, vTete, nom: 'autre.png', octets: png);
      final o2 = (await repo.objet('P1'))!.copie();
      final retiree = o2.photos(vTete).last;
      o2.supprimerPhoto(vTete, retiree, nouvelle: true, auteur: 'essai');
      await app.enregistrer(o2);

      final (_, zip) = await app.paquetRetour();
      final noms = ZipDecoder().decodeBytes(zip).files.map((f) => f.name).toList();
      final gardee = o2.photos(vTete).single['fichier'];
      expect(noms, contains(gardee));
      expect(noms, isNot(contains(retiree['fichier'])));
    });
  });

  testWidgets('visuels, galerie : état des visuels, suppression avec Annuler, référence', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.charger(paquet());
    final app = AppProvider(repo);
    final poteau = (await repo.objet('P1'))!;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: themeNge(),
        navigatorObservers: [pileEcrans],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => ouvrirSupport(context, poteau), child: const Text('carte')),
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
    var ensemble = (await repo.objet('P1'))!.photos(vEnsemble);
    expect(ensemble.map((f) => f['FIC_CODE_EXT']), ['E2']);
    expect(ensemble.single['FIC_PRINCIPALE'], 1);
    expect(app.nbModifies, 1);

    await t.tap(find.text('ANNULER'));
    await t.pumpAndSettle();
    ensemble = (await repo.objet('P1'))!.photos(vEnsemble);
    expect(ensemble.map((f) => f['FIC_CODE_EXT']), ['E1', 'E2']);

    // la seconde devient la référence
    await t.tap(find.byTooltip('Définir comme référence'));
    await t.pumpAndSettle();
    ensemble = (await repo.objet('P1'))!.photos(vEnsemble);
    expect(ensemble.map((f) => f['FIC_CODE_EXT']), ['E2', 'E1']);
    expect(ensemble.first['FIC_PRINCIPALE'], 1);

    // le globe ramène à la carte
    await t.tap(find.text('Carte'));
    await t.pumpAndSettle();
    expect(find.text('carte'), findsOneWidget);
  });
}
