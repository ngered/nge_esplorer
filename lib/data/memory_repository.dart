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
  final Map<String, Set<String>> _cablesByNode = {};
  final Map<String, Set<String>> _cablesByLinear = {};
  final Map<String, String> _nodeByEquipment = {};
  final Map<String, Set<String>> _addressesByEquipment = {};
  final Map<String, Set<String>> _nodesByAddress = {};
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

  /// Index des extrémités (linéaires, câbles), des linéaires du parcours des câbles, des équipements des nœuds, des PBO des locaux des adresses et des
  /// nœuds de chaque adresse.
  void _addToIndex(GeoObject o) {
    final former = _objects[o.id];
    if (former != null) _removeFromIndex(former);
    _objects[o.id] = o;
    final e = o.bounds;
    if (e == null) {
      _bounds.remove(o.id);
    } else {
      _bounds[o.id] = e;
    }
    final ends = switch (o.objectClass) {
      ObjectClass.lin => _linearsByNode,
      ObjectClass.cab => _cablesByNode,
      _ => null,
    };
    for (final n in [o.noe1, o.noe2]) {
      if (n != null) ends?.putIfAbsent(n, () => {}).add(o.id);
    }
    for (final l in _route(o)) {
      _cablesByLinear.putIfAbsent(l, () => {}).add(o.id);
    }
    for (final code in _equipmentCodes(o)) {
      _nodeByEquipment[code] = o.id;
    }
    for (final code in _servingEquipment(o)) {
      _addressesByEquipment.putIfAbsent(code, () => {}).add(o.id);
    }
    final adr = o.props['ADR_KEY'];
    if (o.objectClass == ObjectClass.noe && adr is String) _nodesByAddress.putIfAbsent(adr, () => {}).add(o.id);
  }

  void _removeFromIndex(GeoObject o) {
    for (final n in [o.noe1, o.noe2]) {
      _linearsByNode[n]?.remove(o.id);
      _cablesByNode[n]?.remove(o.id);
    }
    for (final l in _route(o)) {
      _cablesByLinear[l]?.remove(o.id);
    }
    for (final code in _equipmentCodes(o)) {
      if (_nodeByEquipment[code] == o.id) _nodeByEquipment.remove(code);
    }
    for (final code in _servingEquipment(o)) {
      _addressesByEquipment[code]?.remove(o.id);
    }
    _nodesByAddress[o.props['ADR_KEY']]?.remove(o.id);
  }

  /// Linéaires du parcours d'un câble (`passages[].LIN_KEY`).
  static Iterable<String> _route(GeoObject o) => [
        if (o.objectClass == ObjectClass.cab)
          for (final p in (o.props['passages'] as List?) ?? const [])
            if ((p as Map)['LIN_KEY'] is String) p['LIN_KEY'] as String,
      ];

  static Iterable<String> _equipmentCodes(GeoObject o) => [
        for (final e in (o.namespace('inf')?['equipements'] as List?) ?? const [])
          if ((e as Map)['EQU_CODE_EXT'] is String) e['EQU_CODE_EXT'] as String,
      ];

  static Iterable<String> _servingEquipment(GeoObject o) => [
        for (final l in (o.namespace('imb')?['locaux'] as List?) ?? const [])
          if ((l as Map)['EQU_KEY'] is String) l['EQU_KEY'] as String,
      ];

  @override
  Future<void> close() async {
    _bundle = null;
    _objects.clear();
    _bounds.clear();
    _linearsByNode.clear();
    _cablesByNode.clear();
    _cablesByLinear.clear();
    _nodeByEquipment.clear();
    _addressesByEquipment.clear();
    _nodesByAddress.clear();
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
  Future<List<SearchHit>> search(String text, {int max = 20}) async {
    final q = _normalized(text);
    if (q.isEmpty) return const [];
    bool found(Object? v) => v is String && _normalized(v).contains(q);
    GeoObject? present(String? id) {
      final o = _objects[id];
      return o == null || o.abandoned ? null : o;
    }

    final res = <SearchHit>[];
    for (final o in _objects.values) {
      if (o.abandoned) continue;
      switch (o.objectClass) {
        case ObjectClass.noe:
          if (found(o.lib)) res.add(SearchHit(o, SearchMatch.support, o.lib!));
          final abandoned = {
            for (final e in (o.namespace('inf')?['equipements'] as List?) ?? const [])
              if ((e as Map)['DATE_ABD'] != null) e['EQU_CODE_EXT'],
          };
          for (final e in (o.namespace('opt')?['equipements'] as List?) ?? const []) {
            final lib = (e as Map)['EQO_LIB'];
            if (found(lib) && !abandoned.contains(e['EQU_KEY'])) {
              res.add(SearchHit(o, SearchMatch.equipment, lib as String, equipment: e['EQU_KEY'] as String?));
            }
          }
        case ObjectClass.cab:
          if (!found(o.lib)) continue;
          for (final n in {o.noe1, o.noe2}) {
            final node = present(n);
            if (node != null) res.add(SearchHit(node, SearchMatch.cable, o.lib!));
          }
        case ObjectClass.adr:
          final label = _addressText(o);
          if (!found(label)) continue;
          for (final n in _nodesByAddress[o.id] ?? const <String>{}) {
            final node = present(n);
            if (node != null) res.add(SearchHit(node, SearchMatch.address, label));
          }
          for (final code in _servingEquipment(o).toSet()) {
            final node = present(_nodeByEquipment[code]);
            if (node != null) res.add(SearchHit(node, SearchMatch.servedAddress, label, equipment: code));
          }
        case ObjectClass.lin:
          break;
      }
    }
    res.sort((a, b) {
      final c = a.text.length.compareTo(b.text.length);
      if (c != 0) return c;
      final d = a.text.compareTo(b.text);
      return d != 0 ? d : a.match.index.compareTo(b.match.index);
    });
    return res.take(max).toList();
  }

  /// Minuscules, espaces simples, sans espace aux bouts.
  static String _normalized(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Numéro, complément, voie et commune d'une adresse, tels que cherchés et affichés (« 1 BIS RUE VOLTAIRE
  /// HUSSIGNY-GODBRANGE »).
  static String _addressText(GeoObject a) => [
        for (final k in ['ADR_NUMERO', 'ADR_REP', 'ADR_VOIE', 'ADR_COMMUNE'])
          if ('${a.props[k] ?? ''}'.trim().isNotEmpty) '${a.props[k]}'.trim(),
      ].join(' ');

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
  Future<List<GeoObject>> cablesOf(String nodeId) async => [
        for (final id in _cablesByNode[nodeId] ?? const <String>{})
          if (!_objects[id]!.abandoned) _objects[id]!,
      ];

  @override
  Future<Map<String, List<GeoObject>>> cablesOnLinears(Iterable<String> linearIds) async {
    final res = <String, List<GeoObject>>{};
    for (final l in linearIds) {
      final cables = [
        for (final id in _cablesByLinear[l] ?? const <String>{})
          if (!_objects[id]!.abandoned) _objects[id]!,
      ];
      if (cables.isNotEmpty) res[l] = cables;
    }
    return res;
  }

  @override
  Future<GeoObject?> nodeOfEquipment(String equipmentId) async => _objects[_nodeByEquipment[equipmentId]];

  @override
  Future<List<GeoObject>> addressesServedBy(String equipmentId) async => [
        for (final id in _addressesByEquipment[equipmentId] ?? const <String>{})
          if (!_objects[id]!.abandoned) _objects[id]!,
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
    } else if (existing != null && existing.abandoned) {
      // un objet abandonné le reste, même réécrit depuis une copie qui ne le savait pas : le retour le déclare
      // abandonné, pas modifié
      o.props['DATE_ABD'] = existing.props['DATE_ABD'];
      GeoObject.put(o.props, 'SRC_ABD', existing.props['SRC_ABD']);
      o.props['statut'] = existing.status;
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
