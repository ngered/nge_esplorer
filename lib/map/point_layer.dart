import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Support dessiné en point : disque [fill] cerclé de [stroke].
class MapPoint {
  const MapPoint(this.point, {required this.fill, required this.stroke});

  final LatLng point;
  final Color fill;
  final Color stroke;
}

/// Supports en points aux petites échelles, pour des milliers de points (Nancy : 8 600). Chaque point est projeté
/// une fois, en coordonnées de carte à l'échelle 1 ; à chaque image il ne reste qu'une multiplication-addition par
/// point et un dessin par couleur (bords d'abord, puis disques). CircleLayer refait la projection de Mercator et
/// regroupe les points dans des listes recréées, pour chaque point à chaque image.
class PointLayer extends StatefulWidget {
  const PointLayer({super.key, required this.points, this.radius = 5, this.stroke = 1});

  final List<MapPoint> points;
  final double radius;
  final double stroke;

  @override
  State<PointLayer> createState() => _PointLayerState();
}

/// Points d'une couleur : coordonnées à l'échelle 1 (x, y alternés) et tampon des positions à l'écran.
class _Group {
  _Group(this.color, List<double> xy)
      : mapXy = Float64List.fromList(xy),
        screenXy = Float32List(xy.length);

  final Color color;
  final Float64List mapXy;
  final Float32List screenXy;
}

class _PointLayerState extends State<PointLayer> {
  List<MapPoint>? _source;
  Crs? _crs;
  List<_Group> _strokes = [], _fills = [];

  void _project(Crs crs) {
    final strokes = <Color, List<double>>{}, fills = <Color, List<double>>{};
    for (final p in widget.points) {
      final (x, y) = crs.latLngToXY(p.point, 1);
      (strokes[p.stroke] ??= []).addAll([x, y]);
      (fills[p.fill] ??= []).addAll([x, y]);
    }
    _strokes = [for (final e in strokes.entries) _Group(e.key, e.value)];
    _fills = [for (final e in fills.entries) _Group(e.key, e.value)];
    _source = widget.points;
    _crs = crs;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (!identical(_source, widget.points) || _crs != camera.crs) _project(camera.crs);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _Painter(camera, _strokes, _fills, widget.radius, widget.stroke),
        size: camera.size,
        isComplex: true,
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.camera, this.strokes, this.fills, this.radius, this.stroke);

  final MapCamera camera;
  final List<_Group> strokes, fills;
  final double radius, stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final s = camera.crs.scale(camera.zoom);
    final o = camera.pixelOrigin;
    final brush = Paint()..strokeCap = StrokeCap.round;
    void draw(List<_Group> groups, double diameter) {
      brush.strokeWidth = diameter;
      for (final g in groups) {
        final c = g.mapXy, e = g.screenXy;
        for (var i = 0; i < c.length; i += 2) {
          e[i] = c[i] * s - o.dx;
          e[i + 1] = c[i + 1] * s - o.dy;
        }
        canvas.drawRawPoints(ui.PointMode.points, e, brush..color = g.color);
      }
    }

    draw(strokes, 2 * (radius + stroke));
    draw(fills, 2 * radius);
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.camera != camera || !identical(old.strokes, strokes) || old.radius != radius || old.stroke != stroke;
}
