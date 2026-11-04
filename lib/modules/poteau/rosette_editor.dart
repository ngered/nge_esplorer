import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../map/geo.dart';
import '../../data/data_repository.dart';
import '../../data/geo_object.dart';

/// Types de linéaires portés par la rosace (manifeste infra).
const aerialSpanType = 1002;
const facadeRunType = 1003;

/// Types de nœuds proposés pour une destination nouvelle.
const destinationTypes = {14: 'Poteau télécom', 15: 'Poteau BT', 30: 'Ancrage façade', 999: 'Autre point'}; // tr

/// Une portée vue depuis le poteau : le linéaire (copie en cours d'édition) et le côté du poteau.
class PoleSpan {
  PoleSpan(this.linear, {required this.isStart, this.destination});

  final GeoObject linear;

  /// Le poteau est l'extrémité `NOE1_KEY` du linéaire.
  final bool isStart;
  GeoObject? destination;
  bool changed = false;
  bool abandoned = false;

  String get id => linear.id;
  String? get destinationId => isStart ? linear.noe2 : linear.noe1;
  String get colAngle => isStart ? 'PRT_ANG1' : 'PRT_ANG2';
  String get colAngleOpposite => isStart ? 'PRT_ANG2' : 'PRT_ANG1';

  Map<String, dynamic> get span => linear.namespace('inf', create: true)!.putIfAbsent('portee', () => <String, dynamic>{})
      as Map<String, dynamic>;

  /// Angle relevé au poteau (grades) ; à défaut, azimut du premier segment de la géométrie.
  double? get surveyedAngle => (span[colAngle] as num?)?.toDouble();

  double get angle => surveyedAngle ?? mapAngle ?? 0;

  double? get mapAngle {
    final pts = linear.line;
    if (pts.length < 2) return null;
    return isStart ? Geo.azimuthGrads(pts[0], pts[1]) : Geo.azimuthGrads(pts.last, pts[pts.length - 2]);
  }

  List<Map<String, dynamic>> get cables {
    final l = span.putIfAbsent('cables', () => <dynamic>[]) as List;
    for (var i = 0; i < l.length; i++) {
      if (l[i] is! Map<String, dynamic>) l[i] = (l[i] as Map).cast<String, dynamic>();
    }
    return l.cast<Map<String, dynamic>>();
  }

  String get destinationLabel => destination?.lib ?? destinationId ?? '?';
}

/// Session d'édition de la rosace d'un poteau : rien n'est écrit dans le dépôt avant [validate].
class RosetteEditor extends ChangeNotifier {
  RosetteEditor(this.repo, this.pole, {required this.author});

  final DataRepository repo;
  final GeoObject pole;
  final String author;
  final List<PoleSpan> spans = [];

  /// Nœuds de destination créés pendant la session (position provisoire, à relever).
  final Map<String, GeoObject> newNodes = {};
  PoleSpan? selection;
  bool loaded = false;

  bool get changed => spans.any((p) => p.changed || p.abandoned);

  Iterable<PoleSpan> get activeSpans => spans.where((p) => !p.abandoned);

  Future<void> load() async {
    for (final l in await repo.linearsOf(pole.id)) {
      if (l.typeKey != aerialSpanType && l.typeKey != facadeRunType) continue;
      final p = PoleSpan(l.copy(), isStart: l.noe1 == pole.id);
      p.destination = await repo.object(p.destinationId ?? '');
      spans.add(p);
    }
    spans.sort((a, b) => a.angle.compareTo(b.angle));
    loaded = true;
    notifyListeners();
  }

  void select(PoleSpan? p) {
    selection = p;
    notifyListeners();
  }

  /// Oriente la portée ; une destination créée pendant la session suit l'aiguille.
  void orient(PoleSpan p, double grads) {
    final a = (Geo.normalize(grads) * 10).roundToDouble() / 10;
    p.span[p.colAngle] = a >= 400 ? 0.0 : a;
    p.changed = true;
    final dest = newNodes[p.destinationId];
    final origin = pole.point;
    if (dest != null && origin != null) {
      final lng = (p.span['PRT_LNG'] as num?)?.toDouble() ?? 30;
      final pos = Geo.destination(origin, a, lng);
      dest.geometry = GeoObject.geoPoint(pos);
      p.linear.geometry = GeoObject.geoLine(p.isStart ? [origin, pos] : [pos, origin]);
      p.span[p.colAngleOpposite] = Geo.normalize(a + 200);
    }
    notifyListeners();
  }

  void setLength(PoleSpan p, double? meters) {
    GeoObject.put(p.span, 'PRT_LNG', meters);
    p.changed = true;
    if (newNodes.containsKey(p.destinationId)) orient(p, p.angle);
    notifyListeners();
  }

  /// Nœuds proches non encore reliés au poteau, triés par distance, pour choisir une destination.
  Future<List<(GeoObject, double)>> nearbyDestinations({double radius = 150}) async {
    final c = pole.point;
    if (c == null) return [];
    final latSpan = radius / 111320;
    final lonSpan = latSpan / 0.7;
    final alreadyLinked = {for (final p in activeSpans) p.destinationId};
    final res = <(GeoObject, double)>[];
    for (final o in await repo.objectsInBounds(
        [c.longitude - lonSpan, c.latitude - latSpan, c.longitude + lonSpan, c.latitude + latSpan],
        classes: {ObjectClass.noe})) {
      if (o.id == pole.id || alreadyLinked.contains(o.id) || o.point == null) continue;
      final d = Geo.distance(c, o.point!);
      if (d <= radius) res.add((o, d));
    }
    res.sort((a, b) => a.$2.compareTo(b.$2));
    return res;
  }

  /// Ajoute une portée vers un nœud existant (angle prérempli par la géométrie) ou vers un nœud nouveau.
  PoleSpan add({GeoObject? existing, int? newType, String? newLabel, double angle = 0}) {
    final origin = pole.point!;
    GeoObject dest;
    if (existing != null) {
      dest = existing;
    } else {
      dest = GeoObject(id: const Uuid().v4(), objectClass: ObjectClass.noe, geometry: GeoObject.geoPoint(Geo.destination(origin, angle, 30)));
      dest.props.addAll({
        'TYPE_KEY': newType ?? 999,
        if (pole.props['ZONE_KEY'] != null) 'ZONE_KEY': pole.props['ZONE_KEY'],
        'GEOL_MOD_KEY': 8, // indéterminé : position à relever
        'NOE_COMMENT': 'Créé depuis la rosace de ${pole.lib ?? pole.id} : position à relever',
      });
      GeoObject.put(dest.props, 'NOE_LIB', newLabel);
      newNodes[dest.id] = dest;
    }
    final end = dest.point!;
    final lin = GeoObject(id: const Uuid().v4(), objectClass: ObjectClass.lin, geometry: GeoObject.geoLine([origin, end]));
    final az = existing != null ? Geo.azimuthGrads(origin, end) : angle;
    lin.props.addAll({
      'TYPE_KEY': aerialSpanType,
      'IMPL_KEY': pole.typeKey == 15 ? 1 : 0, // aérien énergie depuis un poteau BT, sinon aérien télécom
      'NOE1_KEY': pole.id,
      'NOE2_KEY': dest.id,
      if (pole.props['ZONE_KEY'] != null) 'ZONE_KEY': pole.props['ZONE_KEY'],
      'inf': <String, dynamic>{
        'portee': <String, dynamic>{
          'PRT_ANG1': (az * 10).roundToDouble() / 10,
          'PRT_ANG2': Geo.normalize(az + 200),
          'cables': <dynamic>[],
        },
      },
    });
    final p = PoleSpan(lin, isStart: true, destination: dest)..changed = true;
    spans.add(p);
    selection = p;
    notifyListeners();
    return p;
  }

  void abandon(PoleSpan p) {
    p.abandoned = true;
    if (selection == p) selection = null;
    notifyListeners();
  }

  /// Ajoute ou remplace un câble porté (identifié par son rang).
  void setCable(PoleSpan p, Map<String, dynamic> cable) {
    final l = p.cables;
    final i = l.indexWhere((c) => c['PCB_RANG'] == cable['PCB_RANG']);
    if (i >= 0) {
      l[i] = cable;
    } else {
      l.add(cable);
    }
    p.changed = true;
    notifyListeners();
  }

  void removeCable(PoleSpan p, int rank) {
    p.cables.removeWhere((c) => c['PCB_RANG'] == rank);
    p.changed = true;
    notifyListeners();
  }

  int nextRank(PoleSpan p) =>
      p.cables.fold<int>(0, (m, c) => (c['PCB_RANG'] as int? ?? 0) > m ? c['PCB_RANG'] as int : m) + 1;

  /// Écrit les linéaires modifiés et les nœuds créés dans le dépôt.
  Future<void> validate() async {
    for (final p in spans) {
      final created = newNodes[p.destinationId];
      if (p.abandoned) {
        if (await repo.object(p.id) != null) await repo.save(p.linear, author: author, abandon: true);
        continue;
      }
      if (!p.changed) continue;
      if (created != null) await repo.save(created, author: author);
      await repo.save(p.linear, author: author);
    }
    for (final p in spans) {
      p.changed = false;
    }
    notifyListeners();
  }
}
