import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/map/colors.dart';
import 'package:nge_esplorer/map/flight.dart';
import 'package:nge_esplorer/map/offset_line.dart';
import 'package:nge_esplorer/modules/chambre/mask_screen.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/map_screen.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
import 'package:provider/provider.dart';

/// Paquet d'essai (Heillecourt : fond OpenStreetMap) : une chambre et un poteau ; [linked] : reliés par un parcours
/// souterrain ; [equipments] : nombre d'équipements de la chambre (boîtes du catalogue, B1, B2…).
Bundle bundle({bool linked = false, int equipments = 0}) => Bundle(
      header: {
        'format': Bundle.format,
        'version': Bundle.version,
        'date': '2026-11-04T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [6.190, 48.650, 6.194, 48.652]},
        'modules': {'noyau': '0.2.0'},
      },
      objects: [
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'C1',
          'geometry': {'type': 'Point', 'coordinates': [6.191, 48.651]},
          'properties': {
            'classe': 'NOE',
            'NOE_LIB': '5011',
            'TYPE_KEY': 16,
            if (equipments > 0)
              'inf': {
                'equipements': [
                  for (var i = 1; i <= equipments; i++) {'EQU_CODE_EXT': 'E$i', 'MAT_KEY': i},
                ],
              },
          },
        }),
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'P1',
          'geometry': {'type': 'Point', 'coordinates': [6.193, 48.651]},
          'properties': {'classe': 'NOE', 'NOE_LIB': 'P922', 'TYPE_KEY': 14},
        }),
        if (linked)
          GeoObject.fromFeature({
            'type': 'Feature',
            'id': 'L1',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [6.191, 48.651],
                [6.193, 48.651],
              ],
            },
            'properties': {'classe': 'LIN', 'TYPE_KEY': 1001, 'NOE1_KEY': 'C1', 'NOE2_KEY': 'P1'},
          }),
        // raccordement à son tracé propre, de C1 vers une adresse (couche Tirage)
        if (linked)
          GeoObject.fromFeature({
            'type': 'Feature',
            'id': 'K2',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [6.191, 48.651],
                [6.1912, 48.6512],
                [6.1915, 48.6513],
              ],
            },
            'properties': {'classe': 'CAB', 'CAB_LIB': 'RAC-1', 'CFON_KEY': 8, 'NOE1_KEY': 'C1', 'ADR2_KEY': 'A9'},
          }),
        // câble tiré sur le parcours L1 (couche Tirage)
        if (linked)
          GeoObject.fromFeature({
            'type': 'Feature',
            'id': 'K1',
            'geometry': null,
            'properties': {
              'classe': 'CAB', 'CAB_LIB': 'CDI-1', 'CAB_CAPA': 144, 'NOE1_KEY': 'C1', 'NOE2_KEY': 'P1',
              'passages': [
                {'LIN_KEY': 'L1', 'PAS_RANG': 1},
              ],
            },
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
        },
        'infra': {
          'MAT_EQUIP': [
            for (var i = 1; i <= 4; i++) {'MAT_ID': i, 'MAT_LIB': 'B$i'},
          ],
        },
      }),
    );

/// Services Google simulés : session de tuiles et mention de copyright de la vue ; aucune tuile.
final googleServices = MockClient((r) async {
  const json = {'content-type': 'application/json; charset=utf-8'};
  final expiry = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
  return switch (r.url.path) {
    '/v1/createSession' => http.Response(jsonEncode({'session': 'essai', 'expiry': '$expiry'}), 200, headers: json),
    '/tile/v1/viewport' =>
      http.Response(jsonEncode({'copyright': 'Données cartographiques ©2026 Google'}), 200, headers: json),
    _ => http.Response('', 404),
  };
});

/// Carte de [size] (points logiques, comme le cadre de terminal du web), [label] choisi par la recherche du bandeau ;
/// avec [googleKey], fond Google Plan choisi d'abord dans le panneau Couches.
Future<void> showSelected(WidgetTester t, Size size, String label, {String? googleKey, int equipments = 0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  final repo = MemoryRepository();
  await repo.load(bundle(equipments: equipments));
  final app = AppProvider(repo);
  if (googleKey != null) app.setGoogleKey(googleKey);
  // nouvel arbre à chaque appel : rien de l'essai précédent (sélection, recherche) n'est gardé
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(key: UniqueKey(), theme: ngeTheme(), navigatorObservers: [screenStack], home: const MapScreen()),
  ));
  await t.pumpAndSettle();
  if (googleKey != null) {
    await t.tap(find.text('Couches'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Google Plan'));
    await t.pumpAndSettle();
    await t.tap(find.text('Google Plan'));
    await t.pumpAndSettle();
    await closeLayers(t);
    await t.pumpAndSettle();
  }
  await t.enterText(find.byType(TextField), label);
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(ListTile, label));
  await t.pumpAndSettle();
}

/// Ferme le panneau Couches (il peut couvrir toute la hauteur de la carte : pas de toucher à côté).
Future<void> closeLayers(WidgetTester t) async {
  Navigator.of(t.element(find.text('Fond de plan'))).pop();
  await t.pumpAndSettle();
}

/// Carton d'aperçu du support sélectionné, à l'écran.
Rect card(WidgetTester t) => t.getRect(find.ancestor(of: find.text('Ouvrir'), matching: find.byType(Card)));

/// Bouton [label] du carton, à l'écran.
Rect button(WidgetTester t, String label) =>
    t.getRect(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()));

void main() {
  testWidgets('carte large (paysage, tablette) : carton compact dans le coin bas droit, Ouvrir à sa taille '
      'naturelle, mention du fond (OpenStreetMap) visible sous le carton', (t) async {
    addTearDown(t.view.reset);
    for (final size in const [Size(1280, 800), Size(800, 1280)]) {
      await showSelected(t, size, '5011');
      final map = t.getRect(find.byType(FlutterMap)), c = card(t), open = button(t, 'Ouvrir');
      final credit = t.getRect(find.text('© contributeurs OpenStreetMap'));
      expect(c.width, lessThanOrEqualTo(360), reason: '$size : largeur bornée');
      expect(c.right, map.right - 12, reason: '$size : coin droit (notes rep9)');
      expect(c.bottom, greaterThan(map.bottom - 24), reason: '$size : en bas, juste au-dessus de l\'attribution');
      expect(open.width, lessThan(c.width / 2), reason: '$size : Ouvrir à sa taille naturelle');
      expect(open.right, greaterThan(c.right - 24), reason: '$size : Ouvrir à droite du carton');
      expect(credit.top, greaterThanOrEqualTo(c.bottom), reason: '$size : mention jamais masquée par le carton');
      expect(map.contains(credit.topLeft) && map.contains(credit.bottomRight - const Offset(1, 1)), isTrue);
    }

    // poteau : Ajouter une destination puis Ouvrir, côte à côte à droite du carton ; pas de bouton Portées
    await showSelected(t, const Size(1280, 800), 'P922');
    final c = card(t), destination = t.getRect(find.byTooltip('Ajouter une destination')), open = button(t, 'Ouvrir');
    expect(find.text('Portées'), findsNothing);
    expect(destination.right, lessThan(open.left));
    expect(destination.left, greaterThanOrEqualTo(c.left));
    expect(open.right, greaterThan(c.right - 24));
  });

  testWidgets('équipements du support sur le carton : une pastille par équipement, qui ouvre son écran dédié ; au-delà '
      'de trois, une pastille propose le choix', (t) async {
    addTearDown(t.view.reset);
    await showSelected(t, const Size(360, 800), '5011', equipments: 2);
    expect(find.widgetWithText(ActionChip, 'B1'), findsOneWidget);
    await t.tap(find.widgetWithText(ActionChip, 'B2'));
    await t.pumpAndSettle();
    expect(find.text('équipement · 5011'), findsOneWidget);
    expect(screenStack.shown?.tab, 'equipement:E2');
    // retour : la carte, le carton toujours là
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'B1'), findsOneWidget);

    await showSelected(t, const Size(360, 800), '5011', equipments: 4);
    expect(find.byType(ActionChip), findsOneWidget);
    await t.tap(find.widgetWithText(ActionChip, '4 équipements'));
    await t.pumpAndSettle();
    expect(find.text('Équipements de 5011'), findsOneWidget);
    await t.tap(find.widgetWithText(ListTile, 'B3'));
    await t.pumpAndSettle();
    expect(screenStack.shown?.tab, 'equipement:E3');

    // poteau sans équipement : pas de pastille
    await showSelected(t, const Size(360, 800), 'P922');
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('fond Google en paysage : logo et mention de la vue visibles sous le carton compact', (t) async {
    addTearDown(t.view.reset);
    await http.runWithClient(
        () => showSelected(t, const Size(1280, 800), '5011', googleKey: 'cle-essai'), () => googleServices);
    final map = t.getRect(find.byType(FlutterMap)), c = card(t);
    expect(c.width, lessThanOrEqualTo(360));
    for (final f in [find.bySemanticsLabel('Google Maps'), find.text('Données cartographiques ©2026 Google')]) {
      final r = t.getRect(f);
      expect(r.top, greaterThanOrEqualTo(c.bottom), reason: '$f sous le carton');
      expect(r.bottom, lessThanOrEqualTo(map.bottom), reason: '$f dans la carte');
    }
  });

  testWidgets('téléphone en portrait : carton sur toute la largeur, boutons étirés (inchangé)', (t) async {
    addTearDown(t.view.reset);
    await showSelected(t, const Size(360, 800), '5011');
    var c = card(t);
    expect([c.left, c.right], [12, 348]);
    expect(button(t, 'Ouvrir').width, greaterThan(c.width * 0.8));
    // statut de renseignement aligné à droite du carton (notes rep12)
    final status = t.getRect(find.textContaining(RegExp(r'^(À renseigner|Partiel|Complet|Défaut)$')));
    expect(status.right, greaterThan(c.right - 40));

    await showSelected(t, const Size(360, 800), 'P922');
    c = card(t);
    final open = button(t, 'Ouvrir');
    final destination = t.getRect(find.byTooltip('Ajouter une destination'));
    expect(find.text('Portées'), findsNothing, reason: 'rosace par la barre basse du poteau ouvert');
    // « Ajouter une destination » à sa taille d'icône, devant ; Ouvrir prend le reste de la largeur
    expect(destination.right, lessThan(open.left));
    expect(destination.width + open.width, greaterThan(c.width * 0.8));
  });

  /// Carte de téléphone (360 × 800) sur [repo], pile des écrans suivie.
  Future<AppProvider> showMap(WidgetTester t, MemoryRepository repo) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    final app = AppProvider(repo);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: const MapScreen()),
    ));
    await t.pumpAndSettle();
    return app;
  }

  MapCamera camera(WidgetTester t) => t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;

  /// Recherche de [label] dans le bandeau, résultat choisi (sans attendre la fin du repérage).
  Future<void> search(WidgetTester t, String label) async {
    await t.enterText(find.byType(TextField), '');
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), label);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, label));
  }

  testWidgets('glissement de la carte : le réseau se dessine pendant le geste, sans attendre qu\'il finisse', (t) async {
    addTearDown(t.view.reset);
    // support à une vue et demie à l'est du centre : hors de la vue et de sa marge chargée au départ
    const far = LatLng(48.651, 6.199);
    final b = bundle()
      ..objects.add(GeoObject.fromFeature({
        'type': 'Feature',
        'id': 'F1',
        'geometry': {'type': 'Point', 'coordinates': [far.longitude, far.latitude]},
        'properties': {'classe': 'NOE', 'NOE_LIB': 'LOIN', 'TYPE_KEY': 16},
      }));
    final repo = MemoryRepository();
    await repo.load(b);
    await showMap(t, repo);
    bool drawn() => t
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .any((l) => l.markers.any((m) => m.point == far));
    expect(drawn(), isFalse);
    expect(camera(t).visibleBounds.contains(far), isFalse);

    final gesture = await t.startGesture(t.getCenter(find.byType(FlutterMap)));
    for (var i = 0; i < 40 && !camera(t).visibleBounds.contains(far); i++) {
      await gesture.moveBy(const Offset(-25, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(camera(t).visibleBounds.contains(far), isTrue);
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 16));
    expect(drawn(), isTrue, reason: 'dessiné le doigt encore posé');
    await gesture.up();
    await t.pumpAndSettle();
  });

  testWidgets('« Ajouter une destination » : on touche le support de destination sur la carte, la rosace s\'ouvre '
      'avec la portée vers lui, à enregistrer', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    await showMap(t, repo);
    Future<void> tapOn(LatLng p) async {
      await t.tapAt(t.getTopLeft(find.byType(FlutterMap)) + camera(t).latLngToScreenOffset(p));
      await t.pump(const Duration(milliseconds: 500)); // la carte attend un éventuel double toucher
      await t.pumpAndSettle();
    }

    // poteau touché sur la carte, cadrée sur toute la zone : la chambre reste en vue
    await tapOn(const LatLng(48.651, 6.193));
    expect(find.descendant(of: find.byType(Card), matching: find.text('P922')), findsOneWidget);

    await t.tap(find.byTooltip('Ajouter une destination'));
    await t.pumpAndSettle();
    expect(find.text('Nouvelle portée depuis P922'), findsOneWidget);
    expect(find.text('Ouvrir'), findsNothing);
    // le poteau lui-même n'est pas une destination ; la consigne reste
    await tapOn(const LatLng(48.651, 6.193));
    expect(find.text('Touchez un autre support que P922'), findsOneWidget);
    expect(find.text('Nouvelle portée depuis P922'), findsOneWidget);
    // Annuler rend l'aperçu
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);

    await t.tap(find.byTooltip('Ajouter une destination'));
    await t.pumpAndSettle();
    await tapOn(const LatLng(48.651, 6.191));
    // rosace du poteau, la portée vers la chambre 5011 ajoutée et choisie, orientée sur elle (plein ouest)
    expect(find.text('portées · 1 direction'), findsOneWidget);
    expect(find.textContaining('Direction de la destination : 300.0 gr'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final spans = await repo.linearsOf('P1');
    expect([spans.single.typeKey, spans.single.noe1, spans.single.noe2], [1002, 'P1', 'C1']);
  });

  testWidgets('recherche : support repéré comme « Repérer » de FibReady (vol, zoom d\'arrivée borné par le rayon, '
      'pulsations) ; sans animation et rayon de repérage choisis dans les Paramètres', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = await showMap(t, repo);
    double halo() => t.widget<Transform>(find.byKey(const ValueKey('halo'))).transform.getMaxScaleOnAxis();

    // vol : la vue passe par des positions intermédiaires, puis arrive sur le poteau, au zoom qui montre 50 m autour
    // de lui sur la largeur de la carte (elle était plus loin)
    final start = camera(t);
    final expected = locateZoom(start, const LatLng(48.651, 6.193), 50);
    expect(expected, closeTo(zoomForWidth(100, start.nonRotatedSize.width, 48.651), 1e-9));
    expect(expected, greaterThan(start.zoom));
    await search(t, 'P922');
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    final midway = camera(t).center.longitude;
    expect(midway, greaterThan(start.center.longitude));
    expect(midway, lessThan(6.193 - 1e-6));
    // à l'arrivée, le halo de la sélection pulse trois fois en s'amortissant
    var peak = 1.0;
    for (var i = 0; i < 160 && t.binding.hasScheduledFrame; i++) {
      await t.pump(const Duration(milliseconds: 50));
      if (find.byKey(const ValueKey('halo')).evaluate().isNotEmpty) peak = math.max(peak, halo());
    }
    expect(camera(t).center.longitude, closeTo(6.193, 1e-6));
    expect(camera(t).zoom, closeTo(expected, 1e-6));
    expect(peak, greaterThan(1.5));
    expect(halo(), closeTo(1, 1e-6));

    // Paramètres : repérage sans animation, rayon de 200 m
    await t.tap(find.text('Paramètres'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Repérage animé'), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.text('Repérage animé'));
    await t.pumpAndSettle();
    await t.tap(find.text('Repérage animé'));
    await t.pumpAndSettle();
    expect(app.animateLocate, isFalse);
    await t.scrollUntilVisible(find.text('50 m'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('50 m'));
    await t.pumpAndSettle();
    await t.tap(find.text('200 m').last);
    await t.pumpAndSettle();
    expect(app.locateRadius, 200);
    await t.pageBack();
    await t.pumpAndSettle();

    // sans animation, la vue se place d'emblée ; de plus près que 200 m, elle garde son zoom
    await search(t, '5011');
    await t.pump();
    expect(camera(t).center.longitude, closeTo(6.191, 1e-6));
    expect(camera(t).zoom, closeTo(expected, 1e-6));
    await t.pumpAndSettle();
    // de plus loin, elle zoome jusqu'à montrer 200 m autour du support
    t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.move(const LatLng(48.66, 6.2), 13);
    await t.pumpAndSettle();
    await search(t, 'P922');
    await t.pumpAndSettle();
    expect(camera(t).center.longitude, closeTo(6.193, 1e-6));
    expect(camera(t).zoom, closeTo(zoomForWidth(400, 360, 48.651), 1e-6));
  });

  testWidgets('couche Tirage (masquée au départ) : bande des câbles sous les linéaires de leur parcours ; '
      'raccordements à leur tracé propre avec les adresses (couche Administratif)', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle(linked: true));
    await showMap(t, repo);
    List<Polyline> bands() => [
          for (final layer in t.widgetList<PolylineLayer>(find.byType(PolylineLayer)))
            for (final p in layer.polylines)
              if (p.color.toARGB32() & 0xFFFFFF == cableColor.toARGB32() & 0xFFFFFF) p,
        ];
    expect(bands(), isEmpty);
    await t.tap(find.text('Couches'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tirage'));
    await t.pumpAndSettle();
    await closeLayers(t);
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    // bande sur L1 (deux points), pas le raccordement K2 (trois), de la couche Administratif
    expect(bands().map((p) => p.points.length), [2]);
    await t.tap(find.text('Couches'));
    await t.pumpAndSettle();
    await t.tap(find.text('Administratif'));
    await t.pumpAndSettle();
    await closeLayers(t);
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    expect(bands().map((p) => p.points.length), unorderedEquals([2, 3]));

    // câbles en parallèle (option de FibReady) : un trait par câble, à la couleur de sa capacité (144 FO : vert),
    // cerné de blanc, au-dessus des linéaires
    List<Polyline> all() => [
          for (final layer in t.widgetList<PolylineLayer>(find.byType(PolylineLayer))) ...layer.polylines,
        ];
    expect(all().where((p) => p.color == cableCapacityColor(144)), isEmpty);
    await t.tap(find.text('Couches'));
    await t.pumpAndSettle();
    await t.tap(find.text('Câbles en parallèle'));
    await t.pumpAndSettle();
    expect(find.text('≤ 144 FO'), findsOneWidget);
    await closeLayers(t);
    await t.pumpAndSettle();
    final parallel = all().where((p) => p.color == cableCapacityColor(144)).toList();
    expect(parallel, hasLength(1));
    expect([parallel.single.borderColor, parallel.single.borderStrokeWidth > 0], [Colors.white, isTrue]);
    final layers = t.widgetList<PolylineLayer>(find.byType(PolylineLayer)).toList();
    int layerOf(Polyline p) => layers.indexWhere((l) => l.polylines.contains(p));
    final linear = all().firstWhere((p) => p.points.length == 2 && p.color != cableCapacityColor(144));
    expect(layerOf(parallel.single), greaterThan(layerOf(linear)));
    expect(all().where((p) => p.color == cableColor.withValues(alpha: 0.55)), isEmpty);

    // parcours d'infra : sa propre couche ; masquée, le linéaire L1 disparaît, pas les supports
    final lines = all().where((p) => p.points.length == 2 && p.color != cableCapacityColor(144)).length;
    await t.tap(find.text('Couches'));
    await t.pumpAndSettle();
    await t.tap(find.text('Parcours d\'infra'));
    await t.pumpAndSettle();
    await closeLayers(t);
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    expect(all().where((p) => p.points.length == 2 && p.color != cableCapacityColor(144)).length, lines - 1);
  });

  test('tracé décalé : de côté au zoom donné, sommets en onglet', () {
    const crs = Epsg3857();
    const zoom = 18.0;
    final line = [const LatLng(48.651, 6.191), const LatLng(48.651, 6.192), const LatLng(48.652, 6.192)];
    final o = offsetLine(line, 5, zoom);
    final a = crs.latLngToOffset(line[0], zoom), b = crs.latLngToOffset(o[0], zoom);
    // vers l'est, la gauche est au nord (écran : y vers le haut)
    expect((b - a).dx, closeTo(0, 1e-6));
    expect((b - a).dy, closeTo(-5, 1e-6));
    // coin à angle droit : onglet de 5·√2
    expect((crs.latLngToOffset(o[1], zoom) - crs.latLngToOffset(line[1], zoom)).distance, closeTo(5 * math.sqrt2, 1e-6));
    expect(offsetLine(line, 0, zoom), same(line));
  });

  testWidgets('la sélection suit le support affiché : parcours suivi, puis Carte, la carte vole jusqu\'au support '
      'atteint ; « Repérer sur la carte » du menu ⋮', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle(linked: true));
    final app = await showMap(t, repo);
    Future<void> tap(Finder f) async {
      await t.tap(f);
      await t.pumpAndSettle();
    }

    Finder preview(String label) => find.descendant(of: find.byType(Card), matching: find.text(label));

    await search(t, '5011');
    await t.pumpAndSettle();
    expect(preview('5011'), findsOneWidget);

    // 5011 ouvert, son parcours suivi jusqu'à P922 : la sélection de la carte suit le support affiché
    await tap(find.text('Ouvrir'));
    expect(app.selectedSupport, 'C1');
    await tap(find.text('Masques'));
    await t.scrollUntilVisible(find.textContaining('vers P922'), 200, scrollable: find.byType(Scrollable).first);
    await tap(find.textContaining('vers P922'));
    expect(app.selectedSupport, 'P1');
    expect(find.text('Naviguer vers 5011'), findsOneWidget);

    // Carte : P922 sélectionné et repéré
    await tap(find.text('Carte'));
    expect(screenStack.stack, hasLength(1));
    expect(preview('P922'), findsOneWidget);
    expect(camera(t).center.longitude, closeTo(6.193, 1e-6));

    // carte déplacée à la main, puis « Repérer sur la carte » depuis les visuels de P922 : la carte y revient, bien
    // que la sélection n'ait pas changé
    await t.drag(find.byType(FlutterMap), const Offset(200, 0));
    await t.pumpAndSettle();
    expect(camera(t).center.longitude, lessThan(6.193 - 1e-5));
    await tap(find.text('Ouvrir'));
    await tap(find.byTooltip('Plus d\'actions'));
    expect(find.text('Revenir à 5011'), findsOneWidget);
    await tap(find.text('Repérer sur la carte'));
    expect(screenStack.stack, hasLength(1));
    expect(preview('P922'), findsOneWidget);
    expect(camera(t).center.longitude, closeTo(6.193, 1e-6));
  });

  testWidgets('support ouvert pendant le vol de repérage : au retour, la carte est à l\'arrivée', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    await showMap(t, repo);
    t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.move(const LatLng(48.62, 6.13), 12);
    await t.pumpAndSettle();
    final expected = locateZoom(camera(t), const LatLng(48.651, 6.193), 50);
    await search(t, 'P922');
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(camera(t).center.longitude, lessThan(6.19));
    await t.tap(find.text('Ouvrir'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(camera(t).center.longitude, closeTo(6.193, 1e-6));
    expect(camera(t).zoom, closeTo(expected, 1e-6));
  });

  testWidgets('couche masquée : le support repéré reste dessiné, avec son halo', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    await showMap(t, repo);
    // tablette : le panneau Couches laisse voir la carte au-dessus de lui, qu'on touche pour le fermer
    t.view.physicalSize = const Size(800, 1280);
    await t.pumpAndSettle();
    await t.tap(find.text('Couches'));
    await t.pumpAndSettle();
    await t.tap(find.text('Souterrain'));
    await t.pumpAndSettle();
    await closeLayers(t);
    await t.pumpAndSettle();
    await search(t, '5011');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('halo')), findsOneWidget);
    // le toucher, désormais dessiné, le laisse sélectionné
    final at = camera(t).latLngToScreenOffset(const LatLng(48.651, 6.191));
    await t.tapAt(t.getTopLeft(find.byType(FlutterMap)) + at);
    // la carte attend un éventuel double toucher avant de traiter le toucher
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('halo')), findsOneWidget);
    expect(find.descendant(of: find.byType(Card), matching: find.text('5011')), findsOneWidget);
  });

  testWidgets('clavier ouvert pendant la recherche : le zoom d\'arrivée vaut pour la carte entière', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: const MapScreen()),
    ));
    await t.pumpAndSettle();
    final full = camera(t).nonRotatedSize;
    t.view.viewInsets = const FakeViewPadding(bottom: 420);
    await t.pumpAndSettle();
    await search(t, 'P922');
    t.view.resetViewInsets();
    await t.pumpAndSettle();
    expect(camera(t).nonRotatedSize, full);
    expect(camera(t).zoom, closeTo(zoomForWidth(100, full.shortestSide, 48.651), 1e-6));
  });

  testWidgets('tablette, rayon de 10 m : la vue montre bien 10 m autour du support (zoom jusqu\'à 22)', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    t.view.physicalSize = const Size(800, 1280);
    t.view.devicePixelRatio = 1;
    final app = AppProvider(repo)..setLocateRadius(10);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: const MapScreen()),
    ));
    await t.pumpAndSettle();
    await search(t, 'P922');
    await t.pumpAndSettle();
    final expected = zoomForWidth(20, camera(t).nonRotatedSize.shortestSide, 48.651);
    expect(expected, lessThan(22));
    expect(camera(t).zoom, closeTo(expected, 1e-6));
  });

  testWidgets('carte démontée sans repérage ni sélection : aucune erreur', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    await showMap(t, repo);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });

  testWidgets('« Repérer sur la carte » puis « Rester » : la demande de repérage est retirée', (t) async {
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle(linked: true));
    final app = await showMap(t, repo);
    Future<void> tap(Finder f) async {
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await search(t, '5011');
    await t.pumpAndSettle();
    await tap(find.text('Ouvrir'));
    await tap(find.text('Masques'));
    await tap(find.text('Face vide').first);
    // une alvéole placée, non enregistrée
    final grid = find.descendant(of: find.byType(MaskGrid), matching: find.byType(CustomPaint));
    await t.tapAt(t.getTopLeft(grid) + const Offset(30, 30));
    await t.pumpAndSettle();
    await tap(find.text('Placer l\'alvéole'));
    await tap(find.byTooltip('Plus d\'actions'));
    await tap(find.text('Repérer sur la carte'));
    expect(find.text('Enregistrer les modifications ?'), findsOneWidget);
    await t.tapAt(const Offset(4, 4)); // à côté du dialogue : on reste
    await t.pumpAndSettle();
    expect(find.text('masque A · 1 alvéole'), findsOneWidget);
    expect(app.takeLocate(), isNull);
  });

  testWidgets('texte à 200 % sur un téléphone en paysage : le carton compact reste dans la carte, la barre basse ne '
      'déborde pas', (t) async {
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = MemoryRepository();
    await repo.load(bundle());
    t.view.physicalSize = const Size(800, 360);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: AppProvider(repo),
      child: MaterialApp(theme: ngeTheme(), navigatorObservers: [screenStack], home: const MapScreen()),
    ));
    await t.pumpAndSettle();
    await search(t, 'P922');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final map = t.getRect(find.byType(FlutterMap));
    final card = t.getRect(find.ancestor(of: find.text('Ouvrir'), matching: find.byType(Card)));
    expect(card.top, greaterThanOrEqualTo(map.top));
  });
}
