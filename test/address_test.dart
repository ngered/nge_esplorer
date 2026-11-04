import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/geocoding.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/address_screen.dart';
import 'package:nge_esplorer/screens/object_screen.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:provider/provider.dart';

/// Réponse de la Géoplateforme (extrait réel, Nancy).
const banResponse = {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [6.180784, 48.675083]},
      'properties': {'type': 'street', 'street': 'Rue Maréchal Oudinot', 'postcode': '54000', 'citycode': '54395', 'city': 'Nancy'},
    },
    {
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [6.180712, 48.675038]},
      'properties': {
        'type': 'housenumber',
        'street': 'Rue Maréchal Oudinot',
        'housenumber': '68bis',
        'postcode': '54000',
        'citycode': '54395',
        'city': 'Nancy',
        'id': '54395_3440_00068_bis',
        'banId': 'c72faffb-3558-4e60-800c-c0ddab3e1050',
      },
    },
  ],
};

/// Réponse de Photon (extrait réel, Casablanca).
const photonResponse = {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'geometry': {'type': 'Point', 'coordinates': [-7.6005824, 33.5797293]},
      'properties': {'type': 'street', 'name': 'Rue Faline', 'city': 'Casablanca', 'postcode': '20504', 'countrycode': 'MA'},
    },
  ],
};

/// Géocodeur d'essai : adresse fixe, ou échec réseau si null.
class FakeGeocoder extends Geocoder {
  FakeGeocoder(this.result);

  final FoundAddress? result;

  @override
  Future<FoundAddress?> reverse(LatLng p) async => result ?? (throw http.ClientException('hors ligne'));
}

FoundAddress found({int? numero, String? rep, required String voie}) => (
      numero: numero,
      rep: rep,
      voie: voie,
      cp: '54600',
      insee: '54578',
      commune: 'Villers-lès-Nancy',
      banId: 'ban-1',
      point: const LatLng(48.6731, 6.1521),
    );

Bundle bundle() => Bundle(
      header: {
        'format': Bundle.format,
        'version': Bundle.version,
        'date': '2026-11-04T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [6.1, 48.6, 6.2, 48.7]},
        'modules': {'noyau': '0.1.0'},
      },
      objects: [
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'C1',
          'geometry': {'type': 'Point', 'coordinates': [6.1521, 48.6731]},
          'properties': {'classe': 'NOE', 'NOE_LIB': 'C597', 'TYPE_KEY': 16},
        }),
        for (final (id, n) in [('A12', 12), ('A14', 14)])
          GeoObject.fromFeature({
            'type': 'Feature',
            'id': id,
            'geometry': null,
            'properties': {
              'classe': 'ADR',
              'ADR_NUMERO': n,
              'ADR_VOIE': 'RUE DES LILAS',
              'ADR_CP': '54600',
              'ADR_INSEE': '54578',
              'ADR_COMMUNE': 'VILLERS-LES-NANCY',
            },
          }),
      ],
      referenceData: ReferenceData({
        'noyau': {
          'DEF_TYPE': [
            {'TYPE_ID': 3, 'TYPE_CODE': 'INF', 'TYPE_LIB': 'Support'},
            {'TYPE_ID': 16, 'TYPE_CODE': 'CHB', 'TYPE_LIB': 'Chambre', 'TYPE_PARENT_KEY': 3},
          ],
        },
      }),
    );

void main() {
  group('géocodage inversé', () {
    test('BAN : meilleure adresse, numéro et indice de répétition, identifiant BAN', () async {
      final g = Geocoder(client: MockClient((r) async {
        expect(r.url.host, 'data.geopf.fr');
        return http.Response(jsonEncode(banResponse), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      final a = (await g.reverse(const LatLng(48.675037, 6.180743)))!;
      expect([a.numero, a.rep, a.voie, a.cp, a.insee, a.commune, a.banId],
          [68, 'bis', 'Rue Maréchal Oudinot', '54000', '54395', 'Nancy', 'c72faffb-3558-4e60-800c-c0ddab3e1050']);
      expect(a.point!.longitude, 6.180712);
    });

    test('hors de France : Photon seul (Maroc)', () async {
      final hosts = <String>[];
      final g = Geocoder(client: MockClient((r) async {
        hosts.add(r.url.host);
        return http.Response(jsonEncode(photonResponse), 200);
      }));
      final a = (await g.reverse(const LatLng(33.58, -7.6)))!;
      expect(hosts, ['photon.komoot.io']);
      expect([a.numero, a.voie, a.commune, a.insee], [null, 'Rue Faline', 'Casablanca', null]);
    });

    test('numéros de voie', () {
      expect(Geocoder.splitNumber('12'), (12, null));
      expect(Geocoder.splitNumber('12 B'), (12, 'B'));
      expect(Geocoder.splitNumber('5ter'), (5, 'ter'));
      expect(Geocoder.splitNumber('lieu-dit'), (null, null));
    });
  });

  group('écran de l\'adresse', () {
    late MemoryRepository repo;
    setUp(() async {
      repo = MemoryRepository();
      await repo.load(bundle());
    });

    Future<void> open(WidgetTester t, FakeGeocoder geocoder) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: AppProvider(repo),
        child: MaterialApp(
          theme: ngeTheme(),
          home: ObjectScreen(object: (await repo.object('C1'))!, geocoder: geocoder),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('Aucune adresse rattachée'));
      await t.pumpAndSettle();
      expect(find.byType(AddressScreen), findsOneWidget);
    }

    Future<void> detect(WidgetTester t) async {
      await t.tap(find.text('Détecter l\'adresse à la position du support'));
      await t.pumpAndSettle();
    }

    Future<void> validateAndSave(WidgetTester t) async {
      await t.tap(find.text('Valider'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
    }

    testWidgets('détection : adresse du paquet reconnue (casse et accents ignorés), rattachée', (t) async {
      await open(t, FakeGeocoder(found(numero: 14, voie: 'Rue des Lilas')));
      await detect(t);
      expect(find.text('Adresse du paquet : 14 Rue des Lilas, 54600 Villers-lès-Nancy'), findsOneWidget);
      expect(find.widgetWithText(DropdownButtonFormField<String?>, '14'), findsOneWidget);

      await validateAndSave(t);
      expect(find.text('14 RUE DES LILAS, 54600 VILLERS-LES-NANCY'), findsOneWidget);
      expect((await repo.object('C1'))!.props['ADR_KEY'], 'A14');
      expect((await repo.object('A14'))!.status, isNull); // inchangée : pas réécrite
    });

    testWidgets('détection : nouvelle adresse sur une voie du paquet, créée avec le support', (t) async {
      await open(t, FakeGeocoder(found(numero: 16, rep: 'bis', voie: 'Rue des Lilas')));
      await detect(t);
      expect(find.text('Nouvelle adresse : 16 bis Rue des Lilas, 54600 Villers-lès-Nancy'), findsOneWidget);
      expect(find.widgetWithText(TextField, '16'), findsOneWidget);

      await validateAndSave(t);
      final adrKey = (await repo.object('C1'))!.props['ADR_KEY'] as String;
      final a = (await repo.object(adrKey))!;
      // commune et voie sous leur libellé du paquet
      expect([a.objectClass, a.status, a.props['ADR_NUMERO'], a.props['ADR_REP'], a.props['ADR_VOIE'], a.props['ADR_COMMUNE']],
          [ObjectClass.adr, 'C', 16, 'bis', 'RUE DES LILAS', 'VILLERS-LES-NANCY']);
      expect([a.props['ADR_INSEE'], a.props['ADR_BAN_ID'], a.point], ['54578', 'ban-1', const LatLng(48.6731, 6.1521)]);
    });

    testWidgets('sans connexion : message, saisie à la main', (t) async {
      await open(t, FakeGeocoder(null));
      await detect(t);
      expect(find.text('Détection impossible : pas de connexion ou service indisponible.'), findsOneWidget);

      // suggestions tirées des adresses du paquet, accents ignorés
      await t.enterText(find.widgetWithText(TextField, 'Commune'), 'villers lès');
      await t.pumpAndSettle();
      await t.tap(find.text('VILLERS-LES-NANCY'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Voie'), 'lilas');
      await t.pumpAndSettle();
      await t.tap(find.text('RUE DES LILAS'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'Nouvelle adresse'));
      await t.pumpAndSettle();
      await t.tap(find.text('12').last);
      await t.pumpAndSettle();
      await validateAndSave(t);
      expect((await repo.object('C1'))!.props['ADR_KEY'], 'A12');
    });
  });
}
