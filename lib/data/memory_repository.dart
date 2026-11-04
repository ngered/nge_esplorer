import 'dart:typed_data';

import 'data_repository.dart';
import 'geo_object.dart';
import 'bundle.dart';
import 'reference_data.dart';

/// Dépôt en mémoire (web) : les données disparaissent au rechargement de la page.
class MemoryRepository implements DataRepository {
  Bundle? _bundle;
  final Map<String, GeoObject> _objects = {};
  final Map<String, List<double>> _bounds = {};
  final Map<String, Set<String>> _linearsByNode = {};
  final Map<String, Uint8List> _added = {};

  @override
  bool get isOpen => _bundle != null;

  @override
  Map<String, dynamic>? get header => _bundle?.header;

  @override
  ReferenceData get referenceData => _bundle?.referenceData ?? ReferenceData.empty();

  @override
  Future<void> load(Bundle bundle) async {
    await close();
    _bundle = bundle;
    for (final o in bundle.objects) {
      _addToIndex(o);
    }
  }

  void _addToIndex(GeoObject o) {
    final former = _objects[o.id];
    if (former != null && former.objectClass == ObjectClass.lin) {
      for (final n in [former.noe1, former.noe2]) {
        _linearsByNode[n]?.remove(o.id);
      }
    }
    _objects[o.id] = o;
    final e = o.bounds;
    if (e == null) {
      _bounds.remove(o.id);
    } else {
      _bounds[o.id] = e;
    }
    if (o.objectClass == ObjectClass.lin) {
      for (final n in [o.noe1, o.noe2]) {
        if (n != null) _linearsByNode.putIfAbsent(n, () => {}).add(o.id);
      }
    }
  }

  @override
  Future<void> close() async {
    _bundle = null;
    _objects.clear();
    _bounds.clear();
    _linearsByNode.clear();
    _added.clear();
  }

  @override
  Future<List<GeoObject>> objectsInBounds(List<double> bounds, {Set<ObjectClass> classes = const {ObjectClass.noe, ObjectClass.lin}}) async {
    final res = <GeoObject>[];
    _bounds.forEach((id, e) {
      if (e[0] > bounds[2] || e[2] < bounds[0] || e[1] > bounds[3] || e[3] < bounds[1]) return;
      final o = _objects[id]!;
      if (classes.contains(o.objectClass) && !o.abandoned) res.add(o);
    });
    return res;
  }

  @override
  Future<GeoObject?> object(String id) async => _objects[id];

  @override
  Future<List<GeoObject>> search(String text, {int max = 20}) async {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final res = [
      for (final o in _objects.values)
        if (o.objectClass == ObjectClass.noe && !o.abandoned && (o.lib?.toLowerCase().contains(q) ?? false)) o,
    ]..sort((a, b) {
        final c = a.lib!.length.compareTo(b.lib!.length);
        return c != 0 ? c : a.lib!.compareTo(b.lib!);
      });
    return res.take(max).toList();
  }

  @override
  Future<List<GeoObject>> linearsOf(String nodeId) async => [
        for (final id in _linearsByNode[nodeId] ?? const <String>{})
          if (!_objects[id]!.abandoned) _objects[id]!,
      ];

  @override
  Future<List<GeoObject>> addresses() async => [
        for (final o in _objects.values)
          if (o.objectClass == ObjectClass.adr && !o.abandoned) o,
      ];

  @override
  Future<void> save(GeoObject object, {required String author, bool abandon = false}) async {
    final o = object.copy();
    final date = Bundle.timestamp();
    final existing = _objects[o.id];
    if (abandon) {
      o.props['DATE_ABD'] = date;
      o.props['SRC_ABD'] = author;
      // un objet créé puis abandonné avant tout retour n'a pas à remonter au BE
      o.props['statut'] = existing?.status == 'C' ? 'C' : 'A';
    } else {
      o.props['statut'] = existing == null || existing.status == 'C' ? 'C' : 'M';
    }
    if (o.props['statut'] == 'C' && existing == null) o.props['DATE_CREA'] = date;
    o.props['DATE_MODIF'] = date;
    o.props['SRC_MODIF'] = author;
    _addToIndex(o);
  }

  @override
  Future<List<GeoObject>> modifies() async => [
        for (final o in _objects.values)
          if (o.status != null && !(o.status == 'C' && o.abandoned)) o,
      ];

  @override
  Uint8List? file(String path) => _added[path] ?? _bundle?.files[path];

  @override
  Future<void> addFile(String path, Uint8List bytes) async => _added[path] = bytes;

  @override
  Map<String, Uint8List> get newFiles => Map.unmodifiable(_added);
}
