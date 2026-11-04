import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/data_repository.dart';
import '../../data/geo_object.dart';
import '../../data/bundle.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../poteau/rosette_editor.dart';
import '../completion.dart';

/// Faces d'une chambre (CHB_FACE.FAC_CODE).
const chamberFaces = ['A', 'B', 'C', 'D'];

/// Grille par défaut d'une face (celle des relevés FOA Explorer).
const defaultColumns = 9;
const defaultRows = 12;

/// Diamètres normalisés des alvéoles et sous-tubes (mm).
const standardDiameters = [28.0, 33.0, 45.0, 60.0, 80.0, 100.0, 150.0];

/// Diamètre affiché d'une alvéole, en cellules de grille (échelle des relevés FOA Explorer).
double diameterInCells(double? mm) => ((mm ?? 60) / 62).clamp(0.55, 2.6);

/// Une alvéole dans la face : la position (dans la copie de la chambre) et la conduite (dans la copie du linéaire,
/// ou de la chambre si sa destination n'est pas connue).
class MaskBore {
  MaskBore(this.position, {this.linear, this.duct});

  final Map<String, dynamic> position;

  /// Linéaire porteur de la conduite ; null pour une alvéole sans destination connue (sans miroir, autorisée).
  final GeoObject? linear;

  /// Conduite (INF_CONDUITE) ; null si elle n'est pas dans le paquet.
  final Map<String, dynamic>? duct;

  String get cd => position['CD_KEY'] as String;
  double get x => (position['POS_X'] as num?)?.toDouble() ?? 0;
  double get y => (position['POS_Y'] as num?)?.toDouble() ?? 0;
  int? get state => duct?['ETAT_KEY'] as int?;
  double? get diameter => (duct?['CD_DIAM'] as num?)?.toDouble();
  int? get number => duct?['CD_NUM'] as int?;
  bool get mirror => position['POS_MIROIR'] == 1;
  bool get noDestination => duct != null && linear == null;
  int get nbCables => (duct?['cables'] as List?)?.length ?? 0;
}

/// Session d'édition des masques d'une chambre : positions des conduites dans les faces (espace `chb`), état et
/// diamètre des conduites (espace `inf` des linéaires, ou de la chambre pour les conduites sans destination connue).
/// Rien n'est écrit dans le dépôt avant [validate].
class MaskEditor extends ChangeNotifier {
  MaskEditor(this.repo, GeoObject chamber, {required this.author, String? face})
      : chamber = chamber.copy(),
        face = face ?? _firstFace(chamber);

  final DataRepository repo;
  final GeoObject chamber;
  final String author;

  /// Face affichée.
  String face;

  /// Linéaires souterrains de la chambre (copies), porteurs des conduites.
  final List<GeoObject> linears = [];

  /// Extrémité opposée de chaque linéaire, par identifiant du linéaire.
  final Map<String, GeoObject> destinations = {};

  final Set<String> _changedLinears = {};
  bool _chamberChanged = false;

  /// Conduites créées pendant la session (retirées tout à fait si on les retire du masque).
  final Set<String> _newDucts = {};

  /// Conduite sélectionnée (CD_KEY).
  String? selection;
  bool loaded = false;

  bool get changed => _chamberChanged || _changedLinears.isNotEmpty;

  static String _firstFace(GeoObject chamber) {
    final faces = (chamber.namespace('chb')?['faces'] as List?) ?? const [];
    final surveyed = [
      for (final f in faces)
        if (((f as Map)['positions'] as List?)?.any((p) => (p as Map)['DATE_ABD'] == null) ?? false)
          '${f['FAC_CODE']}',
    ]..sort();
    return surveyed.firstOrNull ?? 'A';
  }

  Future<void> load() async {
    for (final l in await repo.linearsOf(chamber.id)) {
      if (l.typeKey == aerialSpanType || l.typeKey == facadeRunType) continue;
      final copy = l.copy();
      linears.add(copy);
      final dest = await repo.object((l.noe1 == chamber.id ? l.noe2 : l.noe1) ?? '');
      if (dest != null) destinations[l.id] = dest;
    }
    linears.sort((a, b) => linearLabel(a).compareTo(linearLabel(b)));
    loaded = true;
    notifyListeners();
  }

  /// Parcours d'une conduite ; [l] null : conduite sans destination connue, portée par la chambre.
  String linearLabel(GeoObject? l) =>
      l == null ? tr('Sans destination connue') : tr('Vers {0}', [destinations[l.id]?.lib ?? '?']);

  // -- faces et positions ----------------------------------------------------------------------

  Map<String, dynamic> get _chb => chamber.namespace('chb', create: true)!;

  List<Map<String, dynamic>> get _faces {
    final l = _chb.putIfAbsent('faces', () => <dynamic>[]) as List;
    for (var i = 0; i < l.length; i++) {
      if (l[i] is! Map<String, dynamic>) l[i] = (l[i] as Map).cast<String, dynamic>();
    }
    return l.cast<Map<String, dynamic>>();
  }

  Map<String, dynamic>? _existingFace(String code) => _faces.where((f) => f['FAC_CODE'] == code).firstOrNull;

  Map<String, dynamic> _faceOrCreate(String code) {
    final existing = _existingFace(code);
    if (existing != null) return existing;
    final f = <String, dynamic>{
      'FAC_CODE': code,
      'FAC_NB_COL': defaultColumns,
      'FAC_NB_LIG': defaultRows,
      'positions': <dynamic>[],
    };
    _faces
      ..add(f)
      ..sort((a, b) => '${a['FAC_CODE']}'.compareTo('${b['FAC_CODE']}'));
    return f;
  }

  List<Map<String, dynamic>> _positions(Map<String, dynamic> face) {
    final l = face.putIfAbsent('positions', () => <dynamic>[]) as List;
    for (var i = 0; i < l.length; i++) {
      if (l[i] is! Map<String, dynamic>) l[i] = (l[i] as Map).cast<String, dynamic>();
    }
    return l.cast<Map<String, dynamic>>();
  }

  int get columns => _existingFace(face)?['FAC_NB_COL'] as int? ?? defaultColumns;
  int get rows => _existingFace(face)?['FAC_NB_LIG'] as int? ?? defaultRows;

  (GeoObject?, Map<String, dynamic>)? _duct(String cd) {
    for (final l in linears) {
      for (final c in ductsOf(l)) {
        if (c['CD_CODE_EXT'] == cd) return (l, c);
      }
    }
    for (final c in ductsOf(chamber)) {
      if (c['CD_CODE_EXT'] == cd) return (null, c);
    }
    return null;
  }

  static List<Map<String, dynamic>> ductsOf(GeoObject l) {
    final inf = l.namespace('inf');
    final c = inf?['conduites'] as List?;
    if (c == null) return const [];
    for (var i = 0; i < c.length; i++) {
      if (c[i] is! Map<String, dynamic>) c[i] = (c[i] as Map).cast<String, dynamic>();
    }
    return c.cast<Map<String, dynamic>>();
  }

  /// Alvéoles de la face [code] (face affichée par défaut), positions abandonnées exclues.
  List<MaskBore> bores([String? code]) {
    final f = _existingFace(code ?? face);
    if (f == null) return const [];
    return [
      for (final p in _positions(f))
        if (p['DATE_ABD'] == null && p['CD_KEY'] is String)
          () {
            final c = _duct(p['CD_KEY'] as String);
            return MaskBore(p, linear: c?.$1, duct: c?.$2);
          }(),
    ];
  }

  MaskBore? get selectedBore => bores().where((a) => a.cd == selection).firstOrNull;

  void selectFace(String code) {
    face = code;
    selection = null;
    notifyListeners();
  }

  void select(String? cd) {
    selection = cd;
    notifyListeners();
  }

  // -- modifications ---------------------------------------------------------------------------

  void _positionChanged(Map<String, dynamic> p) {
    p['DATE_MODIF'] = Bundle.timestamp();
    p['SRC_MODIF'] = author;
    _chamberChanged = true;
  }

  void _ductChanged(MaskBore a) {
    final c = a.duct;
    if (c == null) return;
    c['DATE_MODIF'] = Bundle.timestamp();
    c['SRC_MODIF'] = author;
    final l = a.linear;
    l == null ? _chamberChanged = true : _changedLinears.add(l.id);
  }

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;

  /// Déplace l'alvéole (centre, en cellules), dans les limites de la grille.
  void move(MaskBore a, double x, double y) {
    a.position['POS_X'] = _round(x.clamp(0, columns.toDouble()));
    a.position['POS_Y'] = _round(y.clamp(0, rows.toDouble()));
    _positionChanged(a.position);
    notifyListeners();
  }

  void setDuctState(MaskBore a, int state) {
    if (a.duct == null) return;
    a.duct!['ETAT_KEY'] = state;
    _ductChanged(a);
    notifyListeners();
  }

  void setDiameter(MaskBore a, double mm) {
    if (a.duct == null) return;
    a.duct!['CD_DIAM'] = mm;
    _ductChanged(a);
    notifyListeners();
  }

  /// Nouvelle alvéole dans la face affichée : conduite créée dans [linear] (dans la chambre si null : destination
  /// inconnue), position au point ([x], [y]).
  String add({GeoObject? linear, required double x, required double y, double? diameter, int? state}) {
    final cd = const Uuid().v4();
    final date = Bundle.timestamp();
    final carrier = linear ?? chamber;
    final ducts = carrier.namespace('inf', create: true)!.putIfAbsent('conduites', () => <dynamic>[]) as List;
    final num = ductsOf(carrier).fold<int>(0, (m, c) => (c['CD_NUM'] as int? ?? 0) > m ? c['CD_NUM'] as int : m) + 1;
    ducts.add(<String, dynamic>{
      'CD_CODE_EXT': cd,
      'CD_NUM': num,
      'CD_DIAM': ?diameter,
      'ETAT_KEY': ?state,
      'DATE_CREA': date,
      'SRC_MODIF': author,
    });
    _newDucts.add(cd);
    if (linear != null) _changedLinears.add(linear.id);
    final f = _faceOrCreate(face);
    final p = <String, dynamic>{'CD_KEY': cd, 'POS_MIROIR': 0, 'DATE_CREA': date};
    _positions(f).add(p);
    p['POS_X'] = _round(x.clamp(0, columns.toDouble()));
    p['POS_Y'] = _round(y.clamp(0, rows.toDouble()));
    _positionChanged(p);
    selection = cd;
    notifyListeners();
    return cd;
  }

  /// Retire l'alvéole de la face : abandon de la position (pas de suppression) ; une conduite créée pendant la
  /// session disparaît tout à fait.
  void remove(MaskBore a) {
    final f = _existingFace(face)!;
    if (_newDucts.remove(a.cd)) {
      _positions(f).remove(a.position);
      if (a.duct != null) ((a.linear ?? chamber).namespace('inf')!['conduites'] as List).remove(a.duct);
    } else {
      a.position['DATE_ABD'] = Bundle.timestamp();
      a.position['SRC_ABD'] = author;
    }
    _chamberChanged = true;
    if (selection == a.cd) selection = null;
    notifyListeners();
  }

  /// Taille de la grille de la face affichée (grandes faces : plus de colonnes ou de lignes).
  void resize(int nbColumns, int nbRows) {
    final f = _faceOrCreate(face);
    f['FAC_NB_COL'] = nbColumns;
    f['FAC_NB_LIG'] = nbRows;
    f['DATE_MODIF'] = Bundle.timestamp();
    f['SRC_MODIF'] = author;
    _chamberChanged = true;
    notifyListeners();
  }

  /// Écrit la chambre (niveau de renseignement recalculé) et les linéaires modifiés dans le dépôt. Seuls les
  /// espaces `chb` et `inf.conduites` sont repris sur l'objet du dépôt : les photos prises entre-temps restent.
  Future<void> validate(ReferenceData referenceData) async {
    for (final l in linears.where((l) => _changedLinears.contains(l.id))) {
      final fresh = (await repo.object(l.id))?.copy() ?? l;
      fresh.namespace('inf', create: true)!['conduites'] = _clone(l.namespace('inf')?['conduites']);
      await repo.save(fresh, author: author);
    }
    if (_chamberChanged) {
      final fresh = (await repo.object(chamber.id))?.copy() ?? chamber;
      fresh.props['chb'] = _clone(_chb);
      final noDestination = chamber.namespace('inf')?['conduites'];
      if (noDestination != null) fresh.namespace('inf', create: true)!['conduites'] = _clone(noDestination);
      await saveLevel(fresh, referenceData, repo);
      await repo.save(fresh, author: author);
    }
    _changedLinears.clear();
    _chamberChanged = false;
    _newDucts.clear();
    notifyListeners();
  }

  static Object? _clone(Object? v) => v == null ? null : jsonDecode(jsonEncode(v));
}
