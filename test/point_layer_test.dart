import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nge_esplorer/map/point_layer.dart';

void main() {
  test('projection une fois à l\'échelle 1, puis affine : même position que flutter_map', () {
    const crs = Epsg3857();
    final camera = MapCamera(
        crs: crs, center: const LatLng(48.69, 6.18), zoom: 14.3, rotation: 0, nonRotatedSize: const Size(360, 700));
    for (final p in const [LatLng(48.69, 6.18), LatLng(48.7093, 6.1342), LatLng(48.6661, 6.2078)]) {
      final (x, y) = crs.latLngToXY(p, 1);
      final s = crs.scale(camera.zoom);
      final expected = camera.getOffsetFromOrigin(p);
      expect(x * s - camera.pixelOrigin.dx, closeTo(expected.dx, 1e-6));
      expect(y * s - camera.pixelOrigin.dy, closeTo(expected.dy, 1e-6));
    }
  });

  testWidgets('couche de points dans la carte', (tester) async {
    final points = [
      for (var i = 0; i < 2000; i++)
        MapPoint(LatLng(48.66 + i % 50 * 0.001, 6.13 + i ~/ 50 * 0.002),
            fill: i.isEven ? Colors.white : Colors.green, stroke: Colors.black),
    ];
    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        options: const MapOptions(initialCenter: LatLng(48.69, 6.18), initialZoom: 13),
        children: [PointLayer(points: points)],
      ),
    ));
    await tester.drag(find.byType(FlutterMap), const Offset(-120, 40));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(PointLayer), findsOneWidget);
  });
}
