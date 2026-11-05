import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nge_esplorer/map/geo.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/modules/chambre/mask_editor.dart';
import 'package:nge_esplorer/modules/immeuble/building.dart';
import 'package:nge_esplorer/modules/infra/cables.dart';
import 'package:nge_esplorer/modules/optique/optical.dart';
import 'package:nge_esplorer/modules/poteau/rosette_editor.dart';

/// Petit paquet de publication : un poteau, un voisin à l'est (portée relevée) et un au nord (portée sans angle) ;
/// [features] : objets ajoutés.
Uint8List testBundle({String version = '0.1.0', Map<String, String>? modules, List<Map<String, dynamic>> features = const []}) {
  final header = {
    'format': 'nge-esplorer-paquet',
    'version': version,
    'sens': 'PUBLICATION',
    'date': '2026-10-31T08:00:00Z',
    'projet': {'code': 'TEST', 'lib': 'Test', 'modele': '0.1.0'},
    'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
    'modules': modules ?? {'noyau': '0.1.0', 'infra': '0.2.0', 'poteau': '0.1.0'},
  };
  Map<String, dynamic> node(String id, String lib, double lon, double lat) => {
        'type': 'Feature',
        'id': id,
        'geometry': {'type': 'Point', 'coordinates': [lon, lat]},
        'properties': {'classe': 'NOE', 'NOE_LIB': lib, 'TYPE_KEY': 14, 'ZONE_KEY': 'Z1', 'pot': {'POT_NIVEAU': 0}},
      };
  final objects = {
    'type': 'FeatureCollection',
    'features': [
      node('P1', '100', 2.0, 45.0),
      node('P2', '101', 2.0005, 45.0),
      node('P3', '102', 2.0, 45.0003),
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
      ...features,
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
    ..addFile(ArchiveFile.string('paquet.json', jsonEncode(header)))
    ..addFile(ArchiveFile.string('objets.geojson', jsonEncode(objects)))
    ..addFile(ArchiveFile.string('referentiels.json', jsonEncode(ref)));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  group('Geo', () {
    test('azimut en grades, 0 = nord, sens horaire', () {
      const o = LatLng(45, 2);
      expect(Geo.azimuthGrads(o, const LatLng(45.001, 2)), closeTo(0, 0.01));
      expect(Geo.azimuthGrads(o, const LatLng(45, 2.001)), closeTo(100, 0.01));
      expect(Geo.azimuthGrads(o, const LatLng(44.999, 2)), closeTo(200, 0.01));
      expect(Geo.azimuthGrads(o, const LatLng(45, 1.999)), closeTo(300, 0.01));
    });

    test('destination puis azimut et distance', () {
      const o = LatLng(45, 2);
      final d = Geo.destination(o, 50, 30);
      expect(Geo.azimuthGrads(o, d), closeTo(50, 0.05));
      expect(Geo.distance(o, d), closeTo(30, 0.05));
    });
  });

  group('Paquet', () {
    test('lecture', () {
      final p = Bundle.read(testBundle());
      expect(p.zone, 'Z1');
      expect(p.objects, hasLength(5));
      expect(p.referenceData.familyCode(14), 'POT');
      expect(p.referenceData.cable(223)?['MAT_LIB'], '5/9');
    });

    test('version majeure inconnue refusée', () {
      expect(() => Bundle.read(testBundle(version: '1.0.0')), throwsFormatException);
    });

    test('version mineure : un paquet 0.1.0 (sans commentaires), 0.2.0 (sans câbles), 0.3.0 (photos d\'équipement '
        'sans EQU_KEY) ou 0.4.0 (sans raccordements) reste lisible', () {
      expect(Bundle.version, '0.5.0');
      for (final v in ['0.1.0', '0.2.0', '0.3.0', '0.4.0', '0.5.0']) {
        expect(Bundle.read(testBundle(version: v)).objects, hasLength(5));
      }
    });

    test('modules optique et immeuble lus ; câble sans géométrie, compté au retour', () {
      final cable = {
        'type': 'Feature',
        'id': 'CB1',
        'geometry': null,
        'properties': {
          'classe': 'CAB',
          'CAB_LIB': 'CDI-1015',
          'NOE1_KEY': 'P1',
          'NOE2_KEY': 'P2',
          'fibres': [
            {'FIB_NUM': 1, 'FIB_TUBE': 1, 'FIB_NUM_TUBE': 1, 'COUL_KEY': 1, 'TUBE_COUL_KEY': 1},
          ],
        },
      };
      final p = Bundle.read(testBundle(
        version: '0.3.0',
        modules: {'noyau': '0.2.0', 'infra': '0.2.0', 'poteau': '0.2.0', 'optique': '0.1.0', 'immeuble': '0.1.0'},
        features: [cable],
      ));
      final c = p.objects.firstWhere((o) => o.id == 'CB1');
      expect([c.objectClass, c.geometry, c.lib, c.bounds], [ObjectClass.cab, null, 'CDI-1015', null]);
      expect(() => Bundle.read(testBundle(modules: {'noyau': '0.2.0', 'optique': '1.0.0'})), throwsFormatException);
      final zip = Bundle.writeReturn(base: p.header, intervention: {'INT_CODE_EXT': 'i1'}, objects: [c]);
      final header = jsonDecode(utf8.decode(ZipDecoder().decodeBytes(zip).findFile('paquet.json')!.content)) as Map;
      expect(header['effectifs'], {'NOE': 0, 'LIN': 0, 'ADR': 0, 'CAB': 1, 'fichiers': 0});
    });

    test('module chambre antérieur à 0.3.0 refusé : masques dans l\'ancien repère, paquet à republier', () {
      Bundle read(String chambre) =>
          Bundle.read(testBundle(modules: {'noyau': '0.2.0', 'infra': '0.2.0', 'chambre': chambre, 'poteau': '0.2.0'}));
      for (final v in ['0.1.0', '0.2.0', '0.2.9']) {
        expect(
          () => read(v),
          throwsA(isA<FormatException>().having((e) => e.message, 'message',
              'module chambre en version $v, antérieure à 0.3.0 (positions des masques dans l\'ancien repère) : '
                  'paquet à republier')),
        );
      }
      for (final v in ['0.3.0', '0.3.1', '0.4.0']) {
        expect(read(v).objects, hasLength(5));
      }
      expect(() => read('1.0.0'), throwsFormatException);
    });

    test('module infra antérieur à 0.2.0 refusé : câbles des conduites sans rang, paquet à republier (notes rep11)', () {
      Bundle read(String infra) =>
          Bundle.read(testBundle(modules: {'noyau': '0.2.0', 'infra': infra, 'chambre': '0.3.0', 'poteau': '0.2.0'}));
      expect(
        () => read('0.1.0'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            'module infra en version 0.1.0, antérieure à 0.2.0 (câbles des conduites sans rang) : paquet à republier')),
      );
      expect(read('0.2.0').objects, hasLength(5));
    });
  });

  group('Dépôt et rosace', () {
    late MemoryRepository repo;
    setUp(() async {
      repo = MemoryRepository();
      await repo.load(Bundle.read(testBundle()));
    });

    test('emprise et linéaires d\'un nœud', () async {
      final seen = await repo.objectsInBounds([1.9999, 44.9999, 2.0001, 45.0001]);
      expect(seen.map((o) => o.id), containsAll(['P1', 'L1', 'L2']));
      expect((await repo.linearsOf('P1')).map((o) => o.id), unorderedEquals(['L1', 'L2']));
    });

    test('recherche par étiquette : nœuds seulement, les plus courtes d\'abord', () async {
      expect((await repo.search('10')).map((h) => h.support.lib), ['100', '101', '102']);
      expect((await repo.search(' 101 ')).map((h) => h.support.id), ['P2']);
      expect(await repo.search('L1'), isEmpty);
      expect(await repo.search(''), isEmpty);
    });

    test('angles : relevé sinon géométrie, du bon côté du linéaire', () async {
      final ed = RosetteEditor(repo, (await repo.object('P1'))!, author: 'essai', intervention: () => 'i1');
      await ed.load();
      final east = ed.spans.firstWhere((p) => p.id == 'L1');
      final north = ed.spans.firstWhere((p) => p.id == 'L2');
      expect(east.isStart, isTrue);
      expect(east.angle, 101.5);
      expect(north.isStart, isFalse);
      expect(north.surveyedAngle, isNull);
      expect(north.angle, closeTo(0, 0.01)); // P1 → P3 vers le nord
      expect(ed.spans.first.id, 'L2'); // triées par angle
    });

    test('orienter, ajouter, câbles, valider : statuts et paquet de retour', () async {
      final ed = RosetteEditor(repo, (await repo.object('P1'))!, author: 'essai', intervention: () => 'i1');
      await ed.load();
      final north = ed.spans.firstWhere((p) => p.id == 'L2');
      ed.orient(north, 398.04);
      expect(north.span['PRT_ANG2'], 398.0);
      ed.orient(north, 399.98);
      expect(north.span['PRT_ANG2'], 0.0);

      final isNew = ed.add(newType: 30, newLabel: 'Façade 12', angle: 250);
      ed.setLength(isNew, 20);
      ed.setCable(isNew, {'PCB_RANG': ed.nextRank(isNew), 'MAT_KEY': 223, 'PCB_TENSION': 'STD_AGGLO'});
      expect(isNew.cables.single['PCB_RANG'], 1);
      final dest = ed.newNodes.values.single;
      expect(Geo.distance(ed.pole.point!, dest.point!), closeTo(20, 0.1));
      expect(Geo.azimuthGrads(ed.pole.point!, dest.point!), closeTo(250, 0.1));
      // texte automatique du nœud créé : commentaire signé de l'auteur et de l'intervention
      final note = dest.comments.single;
      expect([note['COM_TEXTE'], note['COM_TYPE'], note['COM_AUTEUR'], note['INT_CODE_EXT']],
          ['Créé depuis la rosace de 100 : position à relever', 'standard', 'essai', 'i1']);
      expect(dest.props.keys, isNot(contains('NOE_COMMENT')));

      ed.abandon(ed.spans.firstWhere((p) => p.id == 'L1'));
      await ed.validate();

      final modifies = {for (final o in await repo.modifies()) o.id: o.status};
      expect(modifies['L2'], 'M');
      expect(modifies['L1'], 'A');
      expect(modifies[isNew.id], 'C');
      expect(modifies[dest.id], 'C');
      expect(modifies, hasLength(4));
      expect((await repo.linearsOf('P1')).map((o) => o.id), unorderedEquals(['L2', isNew.id]));

      final zip = Bundle.writeReturn(
        base: repo.header!,
        intervention: {'INT_CODE_EXT': 'i1', 'ACT_CODE': 'RELEVE_POT', 'INT_AUTEUR': 'essai', 'DATE_DEBUT': 'x'},
        objects: await repo.modifies(),
      );
      final a = ZipDecoder().decodeBytes(zip);
      final header = jsonDecode(utf8.decode(a.findFile('paquet.json')!.content)) as Map;
      expect(header['sens'], 'RETOUR');
      expect(header['base'], '2026-10-31T08:00:00Z');
      final features = (jsonDecode(utf8.decode(a.findFile('objets.geojson')!.content)) as Map)['features'] as List;
      expect(features, hasLength(4));
      // Contrôle croisé avec l'implémentation de référence : RETOUR_SORTIE=<fichier.zip> flutter test
      final output = Platform.environment['RETOUR_SORTIE'];
      if (output != null) File(output).writeAsBytesSync(zip);
    });

    test('un objet créé puis abandonné ne remonte pas', () async {
      final o = GeoObject(id: 'N9', objectClass: ObjectClass.noe, geometry: GeoObject.geoPoint(const LatLng(45, 2)));
      await repo.save(o, author: 'essai');
      expect((await repo.modifies()).map((o) => o.id), ['N9']);
      await repo.save(o, author: 'essai', abandon: true);
      expect(await repo.modifies(), isEmpty);
    });
  });

  // Paquet publié par tools/geojson/paquet.py, hors dépôt git : PAQUET_REEL=<paquet.zip> flutter test
  final realBundle = Platform.environment['PAQUET_REEL'];
  test('paquet réel : lecture et rosace de chaque poteau', () async {
    final p = Bundle.read(File(realBundle!).readAsBytesSync());
    final repo = MemoryRepository();
    await repo.load(p);
    var poles = 0, spans = 0, withoutAngle = 0;
    for (final o in p.objects.where((o) => p.referenceData.familyCode(o.typeKey) == 'POT')) {
      final ed = RosetteEditor(repo, o, author: 'essai', intervention: () => 'i1');
      await ed.load();
      poles++;
      spans += ed.spans.length;
      withoutAngle += ed.spans.where((x) => x.surveyedAngle == null).length;
      for (final x in ed.spans) {
        expect(x.angle, inInclusiveRange(0, 400));
        if (x.surveyedAngle != null && x.mapAngle != null) {
          final deviation = (Geo.normalize(x.surveyedAngle! - x.mapAngle! + 200) - 200).abs();
          expect(deviation, lessThan(1), reason: '${o.lib} → ${x.destinationLabel}');
        }
      }
    }
    // ignore: avoid_print
    print('${p.zone} : $poles poteaux, $spans portées vues depuis un poteau, $withoutAngle sans angle relevé');
  }, skip: realBundle == null ? 'PAQUET_REEL non défini' : false);

  test('paquet réel : masques de chaque chambre', () async {
    final p = Bundle.read(File(realBundle!).readAsBytesSync());
    final repo = MemoryRepository();
    await repo.load(p);
    var chambers = 0, bores = 0;
    final withoutDuct = <String>[], outside = <String>[];
    final sizes = <String, int>{};
    for (final o in p.objects.where((o) => p.referenceData.familyCode(o.typeKey) == 'CHB')) {
      if ((o.namespace('chb')?['faces'] as List?)?.isEmpty ?? true) continue;
      final ed = MaskEditor(repo, o, author: 'essai');
      await ed.load();
      chambers++;
      for (final f in chamberFaces) {
        ed.selectFace(f);
        if (ed.bores().isNotEmpty) sizes.update(faceSizeLabel(ed.width, ed.height), (n) => n + 1, ifAbsent: () => 1);
        for (final a in ed.bores()) {
          bores++;
          if (a.duct == null) withoutDuct.add('${o.lib} ${a.cd}');
          // repère métrique : centre dans la face (m)
          if (a.x < 0 || a.x > ed.width || a.y < 0 || a.y > ed.height) outside.add('${o.lib} $f ${a.cd} (${a.x}, ${a.y})');
        }
      }
    }
    // ignore: avoid_print
    print('${p.zone} : $chambers chambres relevées, $bores alvéoles, ${withoutDuct.length} sans conduite ; faces : $sizes');
    expect(withoutDuct.length, lessThan(bores / 100 + 1), reason: withoutDuct.take(10).join(', '));
    expect(outside, isEmpty, reason: outside.take(10).join(', '));
  }, skip: realBundle == null ? 'PAQUET_REEL non défini' : false);

  test('paquet réel : liens fibres des équipements optiques et locaux des adresses', () async {
    final p = Bundle.read(File(realBundle!).readAsBytesSync());
    final repo = MemoryRepository();
    await repo.load(p);
    var boxes = 0, positions = 0, measures = 0, premises = 0;
    final unknown = <String>[], unserved = <String>[];
    for (final n in p.objects.where((o) => o.objectClass == ObjectClass.noe)) {
      for (final e in (n.namespace('opt')?['equipements'] as List?)?.cast<Map<String, dynamic>>() ?? const []) {
        boxes++;
        expect((await repo.nodeOfEquipment(e['EQU_KEY'] as String))?.id, n.id);
        for (final c in Optical.cassettes(e)) {
          for (final pos in Optical.positions(c)) {
            positions++;
            for (final f in [?Optical.fibre(pos, '1'), ?Optical.fibre(pos, '2')]) {
              final cable = await repo.object(f.cable);
              if (cable == null || !Optical.fibres(cable).any((x) => x['FIB_NUM'] == f.num)) {
                unknown.add('${e['EQO_LIB']} ${f.cable} F${f.num}');
              }
            }
          }
        }
        measures += Optical.measures(e).length;
      }
    }
    for (final a in await repo.addresses()) {
      for (final l in Building.premises(a)) {
        premises++;
        final equ = l['EQU_KEY'] as String?;
        if (equ != null && !(await repo.addressesServedBy(equ)).contains(a)) unserved.add('${a.id} $equ');
      }
    }
    // ignore: avoid_print
    print('${p.zone} : $boxes équipements optiques, $positions positions, $measures mesures, '
        '${p.objects.where((o) => o.objectClass == ObjectClass.cab).length} câbles, $premises locaux');
    expect(unknown, isEmpty, reason: unknown.take(10).join(', '));
    expect(unserved, isEmpty, reason: unserved.take(10).join(', '));
  }, skip: realBundle == null ? 'PAQUET_REEL non défini' : false);

  test('paquet réel : photos embarquées, chacune citée par son objet', () {
    final watch = Stopwatch()..start();
    final p = Bundle.read(File(realBundle!).readAsBytesSync());
    final cited = [
      for (final o in p.objects)
        for (final f in (o.props['fichiers'] as List?) ?? const [])
          if ((f as Map)['fichier'] is String) f['fichier'] as String,
    ];
    final missing = cited.where((c) => !p.files.containsKey(c)).toList();
    final size = p.files.values.fold<int>(0, (s, b) => s + b.length);
    // ignore: avoid_print
    print('${p.zone} : ${p.files.length} fichiers embarqués (${size ~/ 1000000} Mo), ${cited.length} cités, '
        'lu en ${watch.elapsedMilliseconds} ms');
    expect(missing, isEmpty, reason: missing.take(10).join(', '));
    expect(p.files.keys.toSet().difference(cited.toSet()), isEmpty);
  }, skip: realBundle == null ? 'PAQUET_REEL non défini' : false);

  test('style des flèches (légende Hirondelle)', () {
    final ref = Bundle.read(testBundle()).referenceData;
    final network = CableStyle.of(ref, 200), dropFt = CableStyle.of(ref, 223), dropBt = CableStyle.of(ref, 50);
    expect((network.network, network.drop), (Network.telecom, false));
    expect((dropFt.network, dropFt.drop), (Network.telecom, true));
    expect((dropBt.network, dropBt.drop), (Network.energy, true));
    expect(CableStyle.of(ref, null).network, Network.unknown);
  });
}
