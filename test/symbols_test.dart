import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/map/symbols.dart';
import 'package:nge_esplorer/modules/completion.dart';
import 'package:nge_esplorer/modules/immeuble/building.dart';

/// Chambre portant des équipements optiques des fonctions [functions] (OTYP_KEY) ; [abandoned] : rangs abandonnés.
GeoObject chamber(List<int> functions, [Set<int> abandoned = const {}]) => GeoObject.fromFeature({
      'type': 'Feature',
      'id': 'N1',
      'geometry': {'type': 'Point', 'coordinates': [2.0, 45.0]},
      'properties': {
        'classe': 'NOE',
        'TYPE_KEY': 16,
        'inf': {
          'equipements': [
            for (var i = 0; i < functions.length; i++)
              {'EQU_CODE_EXT': 'E$i', if (abandoned.contains(i)) 'DATE_ABD': '2026-11-05T08:00:00Z'},
          ],
        },
        'opt': {
          'equipements': [
            for (var i = 0; i < functions.length; i++) {'EQU_KEY': 'E$i', 'OTYP_KEY': functions[i]},
          ],
        },
      },
    });

void main() {
  testWidgets('pictos FibReady : chargés et recolorés pour chaque statut, point pour un type sans picto', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Wrap(children: [
        for (final family in ['POT', 'CHB', 'FAC', 'IMM', 'SIT', 'SIT-NRO'])
          for (final r in [null, ...Completion.values])
            SupportSymbol(family: family, fill: r?.color, energy: family == 'POT' && r == Completion.complete),
        const SupportSymbol(family: 'INCONNU'),
      ]),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(30));
    expect(find.byType(SupportPoint), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('équipement optique porté : marque au coin du picto, avec ou sans statut', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Wrap(children: [
        for (final m in OpticalMark.values) ...[
          SupportSymbol(family: 'POT', mark: m),
          SupportSymbol(family: 'CHB', fill: Completion.partial.color, mark: m),
        ],
        const SupportSymbol(family: 'FAC', fill: Color(0xFF00FFFF)),
      ]),
    ));
    await t.pumpAndSettle();
    expect(find.byType(OpticalBadge), findsNWidgets(2 * OpticalMark.values.length));
    expect(find.byType(StatusSquare), findsNWidgets(OpticalMark.values.length + 1));
    expect(t.takeException(), isNull);
  });

  test('marque : BPE avant PBO, autre équipement optique, rien sans équipement présent', () {
    final ref = ReferenceData({
      'optique': {
        'DEF_OPT_EQUIP_TYPE': [
          {'OTYP_ID': 1, 'OTYP_CODE': 'BPE'},
          {'OTYP_ID': 2, 'OTYP_CODE': 'PBO'},
          {'OTYP_ID': 4, 'OTYP_CODE': 'DTI'},
        ],
      },
    });
    expect(OpticalMark.of(chamber([2]), ref), OpticalMark.pbo);
    expect(OpticalMark.of(chamber([2, 1]), ref), OpticalMark.bpe);
    expect(OpticalMark.of(chamber([4]), ref), OpticalMark.other);
    expect(OpticalMark.of(chamber([1], {0}), ref), isNull);
    expect(OpticalMark.of(chamber([]), ref), isNull);
  });
  /// Adresse d'habitat [hab] (1 pavillon, 2 immeuble) et de locaux des types [premises] (1 R, 2 P, 3 O, 4 T).
  GeoObject address({int? hab, List<int> premises = const [], int? nbLog, int? nbPro}) => GeoObject.fromFeature({
        'type': 'Feature',
        'id': 'A1',
        'geometry': {'type': 'Point', 'coordinates': [2.0, 45.0]},
        'properties': {
          'classe': 'ADR',
          'imb': {
            'HAB_KEY': ?hab,
            'IAD_NB_LOG': ?nbLog,
            'IAD_NB_PRO': ?nbPro,
            'locaux': [for (final t in premises) {'LTYP_KEY': t}],
          },
        },
      });

  test('NRO : shelter, pas armoire de rue comme les autres sites techniques', () {
    final ref = ReferenceData({
      'noyau': {
        'DEF_TYPE': [
          {'TYPE_ID': 3, 'TYPE_CODE': 'INF'},
          {'TYPE_ID': 40, 'TYPE_CODE': 'SIT', 'TYPE_PARENT_KEY': 3},
          {'TYPE_ID': 41, 'TYPE_CODE': 'SIT-NRO', 'TYPE_PARENT_KEY': 40},
          {'TYPE_ID': 42, 'TYPE_CODE': 'SIT-SRO', 'TYPE_PARENT_KEY': 40},
        ],
      },
    });
    expect([for (final k in [40, 41, 42]) SupportSymbol.assetFile(SupportSymbol.familyOf(k, ref))],
        ['NOE_ADR', 'NOE_SHELTER', 'NOE_ADR']);
  });

  test('usage d\'une adresse (codes FibReady) : individuel ou collectif, logement, pro ou FTTE', () {
    final ref = ReferenceData({
      'immeuble': {
        'DEF_IMB_HABITAT': [
          {'HAB_ID': 1, 'HAB_CODE': 'P'},
          {'HAB_ID': 2, 'HAB_CODE': 'I'},
        ],
        'DEF_LOC_TYPE': [
          {'LTYP_ID': 1, 'LTYP_CODE': 'R'},
          {'LTYP_ID': 2, 'LTYP_CODE': 'P'},
          {'LTYP_ID': 3, 'LTYP_CODE': 'O'},
          {'LTYP_ID': 4, 'LTYP_CODE': 'T'},
        ],
      },
    });
    String usage(GeoObject a) => AddressUsage.of(a, ref).code;
    expect(usage(address(hab: 1, premises: [1])), 'IND-HAB');
    // pavillon de plusieurs logements : individuel (Evicom)
    expect(usage(address(hab: 1, premises: [1, 1, 1])), 'IND-HAB');
    expect(usage(address(hab: 2, premises: [1, 1, 2])), 'COL-HAB', reason: 'mixte : logement');
    expect(usage(address(hab: 1, premises: [2])), 'IND-PRO');
    expect(usage(address(hab: 2, premises: [2, 2])), 'COL-PRO');
    expect(usage(address(hab: 1, premises: [4])), 'IND-FTTE');
    expect(usage(address(hab: 2, premises: [3, 4])), 'COL-FTTE');
    // sans habitat : collectif au-delà d'un local ; sans local : nombres de l'adresse
    expect(usage(address(premises: [1, 1])), 'COL-HAB');
    expect(usage(address(hab: 1, nbLog: 0, nbPro: 2)), 'IND-PRO');
    expect(usage(address()), 'IND-HAB');
  });

  testWidgets('pictos des adresses : un par usage', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Wrap(children: [for (final u in AddressUsage.values) AddressSymbol(usage: u)]),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(AddressUsage.values.length));
    expect(t.takeException(), isNull);
  });
}
