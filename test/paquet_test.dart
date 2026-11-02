import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nge_esplorer/carte/geo.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/objet.dart';
import 'package:nge_esplorer/data/paquet.dart';
import 'package:nge_esplorer/modules/infra/cables.dart';
import 'package:nge_esplorer/modules/poteau/rosace_edition.dart';

/// Petit paquet de publication : un poteau, un voisin à l'est (portée relevée) et un au nord (portée sans angle).
Uint8List paquetEssai({String version = '0.1.0'}) {
  final entete = {
    'format': 'nge-esplorer-paquet',
    'version': version,
    'sens': 'PUBLICATION',
    'date': '2026-10-31T08:00:00Z',
    'projet': {'code': 'TEST', 'lib': 'Test', 'modele': '0.1.0'},
    'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
    'modules': {'noyau': '0.1.0', 'infra': '0.1.0', 'poteau': '0.1.0'},
  };
  Map<String, dynamic> noeud(String id, String lib, double lon, double lat) => {
        'type': 'Feature',
        'id': id,
        'geometry': {'type': 'Point', 'coordinates': [lon, lat]},
        'properties': {'classe': 'NOE', 'NOE_LIB': lib, 'TYPE_KEY': 14, 'ZONE_KEY': 'Z1', 'pot': {'POT_NIVEAU': 0}},
      };
  final objets = {
    'type': 'FeatureCollection',
    'features': [
      noeud('P1', '100', 2.0, 45.0),
      noeud('P2', '101', 2.0005, 45.0),
      noeud('P3', '102', 2.0, 45.0003),
      {
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
          'inf': {
            'portee': {
              'PRT_ANG1': 101.5,
              'PRT_ANG2': 301.5,
              'cables': [
                {'PCB_RANG': 1, 'MAT_KEY': 200, 'PCB_NAPPE': 1, 'PCB_TENSION': 'STD_AGGLO'},
              ],
            },
          },
        },
      },
      {
        'type': 'Feature',
        'id': 'L2',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [2.0, 45.0003],
            [2.0, 45.0],
          ],
        },
        'properties': {'classe': 'LIN', 'TYPE_KEY': 1002, 'NOE1_KEY': 'P3', 'NOE2_KEY': 'P1'},
      },
    ],
  };
  final ref = {
    'noyau': {
      'DEF_TYPE': [
        {'TYPE_ID': 3, 'TYPE_CODE': 'INF', 'TYPE_LIB': 'Support'},
        {'TYPE_ID': 13, 'TYPE_CODE': 'POT', 'TYPE_LIB': 'Poteau', 'TYPE_PARENT_KEY': 3},
        {'TYPE_ID': 14, 'TYPE_CODE': 'POT-FT', 'TYPE_LIB': 'Poteau télécom', 'TYPE_PARENT_KEY': 13},
      ],
    },
    'infra': {
      'MAT_CABLE': [
        {'MAT_ID': 200, 'MAT_LIB': '98-14-6', 'CAB_TYPE': 'Telecom', 'CAB_USAGE': 'RESEAU'},
        {'MAT_ID': 223, 'MAT_LIB': '5/9', 'CAB_TYPE': 'Telecom', 'CAB_USAGE': 'BRANCHEMENT'},
        {'MAT_ID': 50, 'MAT_LIB': 'BT 2*16', 'CAB_TYPE': 'I', 'CAB_USAGE': 'BRANCHEMENT'},
      ],
    },
    'poteau': {},
  };
  final a = Archive()
    ..addFile(ArchiveFile.string('paquet.json', jsonEncode(entete)))
    ..addFile(ArchiveFile.string('objets.geojson', jsonEncode(objets)))
    ..addFile(ArchiveFile.string('referentiels.json', jsonEncode(ref)));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  group('Geo', () {
    test('azimut en grades, 0 = nord, sens horaire', () {
      const o = LatLng(45, 2);
      expect(Geo.azimutGrades(o, const LatLng(45.001, 2)), closeTo(0, 0.01));
      expect(Geo.azimutGrades(o, const LatLng(45, 2.001)), closeTo(100, 0.01));
      expect(Geo.azimutGrades(o, const LatLng(44.999, 2)), closeTo(200, 0.01));
      expect(Geo.azimutGrades(o, const LatLng(45, 1.999)), closeTo(300, 0.01));
    });

    test('destination puis azimut et distance', () {
      const o = LatLng(45, 2);
      final d = Geo.destination(o, 50, 30);
      expect(Geo.azimutGrades(o, d), closeTo(50, 0.05));
      expect(Geo.distance(o, d), closeTo(30, 0.05));
    });
  });

  group('Paquet', () {
    test('lecture', () {
      final p = Paquet.lire(paquetEssai());
      expect(p.zone, 'Z1');
      expect(p.objets, hasLength(5));
      expect(p.referentiels.codeFamille(14), 'POT');
      expect(p.referentiels.cable(223)?['MAT_LIB'], '5/9');
    });

    test('version majeure inconnue refusée', () {
      expect(() => Paquet.lire(paquetEssai(version: '1.0.0')), throwsFormatException);
    });
  });

  group('Dépôt et rosace', () {
    late MemoryRepository repo;
    setUp(() async {
      repo = MemoryRepository();
      await repo.charger(Paquet.lire(paquetEssai()));
    });

    test('emprise et linéaires d\'un nœud', () async {
      final vus = await repo.objetsDansEmprise([1.9999, 44.9999, 2.0001, 45.0001]);
      expect(vus.map((o) => o.id), containsAll(['P1', 'L1', 'L2']));
      expect((await repo.lineairesDe('P1')).map((o) => o.id), unorderedEquals(['L1', 'L2']));
    });

    test('recherche par étiquette : nœuds seulement, les plus courtes d\'abord', () async {
      expect((await repo.rechercher('10')).map((o) => o.lib), ['100', '101', '102']);
      expect((await repo.rechercher(' 101 ')).map((o) => o.id), ['P2']);
      expect(await repo.rechercher('L1'), isEmpty);
      expect(await repo.rechercher(''), isEmpty);
    });

    test('angles : relevé sinon géométrie, du bon côté du linéaire', () async {
      final ed = RosaceEdition(repo, (await repo.objet('P1'))!, auteur: 'essai');
      await ed.charger();
      final est = ed.portees.firstWhere((p) => p.id == 'L1');
      final nord = ed.portees.firstWhere((p) => p.id == 'L2');
      expect(est.premier, isTrue);
      expect(est.angle, 101.5);
      expect(nord.premier, isFalse);
      expect(nord.angleReleve, isNull);
      expect(nord.angle, closeTo(0, 0.01)); // P1 → P3 vers le nord
      expect(ed.portees.first.id, 'L2'); // triées par angle
    });

    test('orienter, ajouter, câbles, valider : statuts et paquet de retour', () async {
      final ed = RosaceEdition(repo, (await repo.objet('P1'))!, auteur: 'essai');
      await ed.charger();
      final nord = ed.portees.firstWhere((p) => p.id == 'L2');
      ed.orienter(nord, 398.04);
      expect(nord.portee['PRT_ANG2'], 398.0);
      ed.orienter(nord, 399.98);
      expect(nord.portee['PRT_ANG2'], 0.0);

      final nouvelle = ed.ajouter(typeNouveau: 30, libNouveau: 'Façade 12', angle: 250);
      ed.poserLongueur(nouvelle, 20);
      ed.poserCable(nouvelle, {'PCB_RANG': ed.rangSuivant(nouvelle), 'MAT_KEY': 223, 'PCB_TENSION': 'STD_AGGLO'});
      expect(nouvelle.cables.single['PCB_RANG'], 1);
      final dest = ed.nouveauxNoeuds.values.single;
      expect(Geo.distance(ed.poteau.point!, dest.point!), closeTo(20, 0.1));
      expect(Geo.azimutGrades(ed.poteau.point!, dest.point!), closeTo(250, 0.1));

      ed.abandonner(ed.portees.firstWhere((p) => p.id == 'L1'));
      await ed.valider();

      final modifies = {for (final o in await repo.modifies()) o.id: o.statut};
      expect(modifies['L2'], 'M');
      expect(modifies['L1'], 'A');
      expect(modifies[nouvelle.id], 'C');
      expect(modifies[dest.id], 'C');
      expect(modifies, hasLength(4));
      expect((await repo.lineairesDe('P1')).map((o) => o.id), unorderedEquals(['L2', nouvelle.id]));

      final zip = Paquet.ecrireRetour(
        base: repo.entete!,
        intervention: {'INT_CODE_EXT': 'i1', 'ACT_CODE': 'RELEVE_POT', 'INT_AUTEUR': 'essai', 'DATE_DEBUT': 'x'},
        objets: await repo.modifies(),
      );
      final a = ZipDecoder().decodeBytes(zip);
      final entete = jsonDecode(utf8.decode(a.findFile('paquet.json')!.content)) as Map;
      expect(entete['sens'], 'RETOUR');
      expect(entete['base'], '2026-10-31T08:00:00Z');
      final features = (jsonDecode(utf8.decode(a.findFile('objets.geojson')!.content)) as Map)['features'] as List;
      expect(features, hasLength(4));
      // Contrôle croisé avec l'implémentation de référence : RETOUR_SORTIE=<fichier.zip> flutter test
      final sortie = Platform.environment['RETOUR_SORTIE'];
      if (sortie != null) File(sortie).writeAsBytesSync(zip);
    });

    test('un objet créé puis abandonné ne remonte pas', () async {
      final o = Objet(id: 'N9', classe: Classe.noe, geometry: Objet.geoPoint(const LatLng(45, 2)));
      await repo.enregistrer(o, auteur: 'essai');
      expect((await repo.modifies()).map((o) => o.id), ['N9']);
      await repo.enregistrer(o, auteur: 'essai', abandon: true);
      expect(await repo.modifies(), isEmpty);
    });
  });

  // Paquet publié par tools/geojson/paquet.py, hors dépôt git : PAQUET_REEL=<paquet.zip> flutter test
  final reel = Platform.environment['PAQUET_REEL'];
  test('paquet réel : lecture et rosace de chaque poteau', () async {
    final p = Paquet.lire(File(reel!).readAsBytesSync());
    final repo = MemoryRepository();
    await repo.charger(p);
    var poteaux = 0, portees = 0, sansAngle = 0;
    for (final o in p.objets.where((o) => p.referentiels.codeFamille(o.typeKey) == 'POT')) {
      final ed = RosaceEdition(repo, o, auteur: 'essai');
      await ed.charger();
      poteaux++;
      portees += ed.portees.length;
      sansAngle += ed.portees.where((x) => x.angleReleve == null).length;
      for (final x in ed.portees) {
        expect(x.angle, inInclusiveRange(0, 400));
        if (x.angleReleve != null && x.angleCarto != null) {
          final ecart = (Geo.normaliser(x.angleReleve! - x.angleCarto! + 200) - 200).abs();
          expect(ecart, lessThan(1), reason: '${o.lib} → ${x.libelleDestination}');
        }
      }
    }
    // ignore: avoid_print
    print('${p.zone} : $poteaux poteaux, $portees portées vues depuis un poteau, $sansAngle sans angle relevé');
  }, skip: reel == null ? 'PAQUET_REEL non défini' : false);

  test('style des flèches (légende Hirondelle)', () {
    final ref = Paquet.lire(paquetEssai()).referentiels;
    final reseau = StyleCable.de(ref, 200), branchementFt = StyleCable.de(ref, 223), branchementBt = StyleCable.de(ref, 50);
    expect((reseau.reseau, reseau.branchement), (Reseau.telecom, false));
    expect((branchementFt.reseau, branchementFt.branchement), (Reseau.telecom, true));
    expect((branchementBt.reseau, branchementBt.branchement), (Reseau.energie, true));
    expect(StyleCable.de(ref, null).reseau, Reseau.inconnu);
  });
}
