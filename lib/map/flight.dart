import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Zoom à partir duquel les supports sont dessinés en pictos (en points en deçà).
const symbolsZoom = 16.0;

/// Circonférence de la Terre à l'équateur (m), pour l'échelle des tuiles Web Mercator.
const _earthCircumference = 40075016.686;

/// Zoom (tuiles de 256 px) auquel [pixels] pixels couvrent [meters] m à la latitude [latitude].
double zoomForWidth(double meters, double pixels, double latitude) =>
    math.log(_earthCircumference * math.cos(latitude * math.pi / 180) * pixels / (256 * meters)) / math.ln2;

/// Zoom d'arrivée d'un repérage, comme « Repérer » de FibReady : la vue montre au plus [radius] m autour de [point]
/// sur son plus petit côté (de plus loin, la carte zoome jusque-là ; de plus près, elle garde son zoom), les supports
/// en pictos au moins ; borné aux zooms de la carte.
double locateZoom(MapCamera camera, LatLng point, double radius) {
  final side = math.min(camera.nonRotatedSize.width, camera.nonRotatedSize.height);
  final zoom = side > 0 ? zoomForWidth(2 * radius, side, point.latitude) : camera.zoom;
  return camera.clampZoom(math.max(camera.zoom, math.max(zoom, symbolsZoom)));
}

double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _tanh(double x) => _sinh(x) / _cosh(x);

/// Vol de la vue jusqu'à un point (« Repérer » de FibReady, `flyTo` de MapLibre, d'après van Wijk et Nuij, « Smooth
/// and efficient zooming and panning », 2003) : la vue s'élève, survole et redescend sur l'arrivée, d'autant plus
/// haut que le trajet est long. Courbure [curve] et vitesse [speed] de FibReady ; un vol qui durerait plus de
/// [maxDuration] devient un saut ([duration] nulle), comme un trajet trop court.
class Flight {
  Flight(MapCamera camera, this.center, this.zoom,
      {double curve = 1.6, double speed = 1.1, Duration maxDuration = const Duration(seconds: 4)})
      : _camera = camera,
        _startZoom = camera.zoom,
        _rho = curve {
    _from = camera.projectAtZoom(camera.center, _startZoom);
    _delta = camera.projectAtZoom(center, _startZoom) - _from;
    final u1 = _delta.distance;
    // largeur vue au départ et à l'arrivée (px à l'échelle du départ)
    final w0 = math.max(camera.nonRotatedSize.width, camera.nonRotatedSize.height);
    final w1 = w0 / math.pow(2, zoom - _startZoom);
    final rho2 = _rho * _rho;
    // facteur d'élévation à la montée (descente : à l'arrivée)
    double rise(bool descent) {
      final b = (w1 * w1 - w0 * w0 + (descent ? -1 : 1) * rho2 * rho2 * u1 * u1) / (2 * (descent ? w1 : w0) * rho2 * u1);
      return math.log(math.sqrt(b * b + 1) - b);
    }

    final r0 = rise(false);
    _width = (s) => _cosh(r0) / _cosh(r0 + _rho * s);
    _progress = (s) => w0 * ((_cosh(r0) * _tanh(r0 + _rho * s) - _sinh(r0)) / rho2) / u1;
    var length = (rise(true) - r0) / _rho;
    if (u1 < 1e-6 || !length.isFinite) {
      // sur place : zoom seul, ou rien à faire
      if ((w0 - w1).abs() < 1e-6 || w0 <= 0 || w1 <= 0) {
        length = 0;
      } else {
        final k = w1 < w0 ? -1 : 1;
        length = (math.log(w1 / w0)).abs() / _rho;
        _progress = (_) => 0;
        _width = (s) => math.exp(k * _rho * s);
      }
    }
    _length = length;
    final ms = 1000 * length / speed;
    duration = !ms.isFinite || ms > maxDuration.inMilliseconds ? Duration.zero : Duration(milliseconds: ms.round());
  }

  final MapCamera _camera;
  final double _startZoom;
  final double _rho;
  late final Offset _from;
  late final Offset _delta;

  /// Largeur vue (relative au départ) et avancement sur le trajet au sol, à l'abscisse de vol s.
  late double Function(double s) _width;
  late double Function(double s) _progress;

  /// Longueur du vol (en largeurs de vue).
  late final double _length;

  /// Arrivée.
  final LatLng center;
  final double zoom;

  /// Durée du vol ; nulle : saut direct à l'arrivée.
  late final Duration duration;

  /// Centre et zoom de la vue à l'avancement [t] (0 à 1, adouci par l'appelant).
  (LatLng, double) at(double t) {
    if (t >= 1 || _length == 0) return (center, zoom);
    final s = t * _length;
    final scale = 1 / _width(s);
    return (
      _camera.unprojectAtZoom(_from + _delta * _progress(s), _startZoom),
      _startZoom + math.log(scale) / math.ln2,
    );
  }
}
