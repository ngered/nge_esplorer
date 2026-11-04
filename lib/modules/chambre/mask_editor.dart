import 'dart:convert';
import 'dart:math' as math;

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

/// Fenêtre d'une face dans FOA Explorer (9 × 12 cellules de 6,3 × 4,5 cm), en m : dimensions d'une nouvelle face
/// quand celles de la chambre ne sont pas connues (chambre OHN, catalogue vide).
const foaFaceWidth = 0.567;
const foaFaceHeight = 0.54;

/// Côté des cellules carrées de la grille dessinée (m) : constante d'affichage, pas une donnée.
const gridCell = 0.05;

/// Bornes des dimensions d'une face (m).
const minFaceSize = 0.05;
const maxFaceSize = 10.0;

/// Diamètres normalisés des alvéoles et sous-tubes (mm).
const standardDiameters = [28.0, 33.0, 45.0, 60.0, 80.0, 100.0, 150.0];

/// Diamètre d'une alvéole en m (vraie grandeur), à partir de celui de la conduite en mm ; 60 mm s'il n'est pas connu.
double boreDiameter(double? mm) => (mm ?? 60) / 1000;

/// Longueur en m écrite en centimètres, au millimètre près (« 56,7 », « 38 »).
String centimeters(double meters) {
  final mm = (meters * 1000).round();
  return mm % 10 == 0 ? '${mm ~/ 10}' : (mm / 10).toStringAsFixed(1).replaceAll('.', ',');
}

/// Dimensions d'une face (m), écrites en centimètres : « 56,7 × 54 cm ».
String faceSizeLabel(double width, double height) => '${centimeters(width)} × ${centimeters(height)} cm';

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

  /// Centre de l'alvéole, en m depuis la gauche et depuis le haut de la face.
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
/// Repère métrique : dimensions des faces (`FAC_LARG`, `FAC_HAUT`) et positions (`POS_X`, `POS_Y`, centre de
/// l'alvéole depuis la gauche et le haut de la face) en m. Rien n'est écrit dans le dépôt avant [validate].
class MaskEditor extends ChangeNotifier {
  MaskEditor(this.repo, GeoObject chamber, {required this.author, String? face, ReferenceData? referenceData})
      : chamber = chamber.copy(),
        referenceData = referenceData ?? repo.referenceData,
        face = face ?? firstFace(chamber);

  final DataRepository repo;

  /// Copie de travail de la chambre, relue dans le dépôt au chargement ([load]).
  GeoObject chamber;
  final String author;

  /// Référentiels du paquet : catalogue des chambres (MAT_CHAMBRE) pour les dimensions d'une nouvelle face, vues
  /// pour le niveau de renseignement.
  final ReferenceData referenceData;

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

  /// Face ouverte par défaut : la première où une alvéole est placée, sinon A.
  static String firstFace(GeoObject chamber) {
    final faces = (chamber.namespace('chb')?['faces'] as List?) ?? const [];
    final surveyed = [
      for (final f in faces)
        if (((f as Map)['positions'] as List?)?.any((p) => (p as Map)['DATE_ABD'] == null) ?? false)
          '${f['FAC_CODE']}',
    ]..sort();
    return surveyed.firstOrNull ?? 'A';
  }

  /// Charge les linéaires de la chambre, et la chambre elle-même telle qu'elle est dans le dépôt : l'objet donné a pu
  /// vieillir depuis l'ouverture de l'écran qui l'a passé.
  Future<void> load() async {
    final stored = await repo.object(chamber.id);
    if (stored != null) chamber = stored.copy();
    for (final l in await repo.linearsOf(chamber.id)) {
      if (isSpan(l)) continue;
      final copy = l.copy();
      linears.add(copy);
      final dest = await repo.object((l.noe1 == chamber.id ? l.noe2 : l.noe1) ?? '');
      if (dest != null) destinations[l.id] = dest;
    }
    linears.sort((a, b) => linearLabel(a).compareTo(linearLabel(b)));
    loaded = true;
    notifyListeners();
  }

  /// Parcours d'une conduite ; [l] null : conduite sans destination connue, portée par la chambre ; « ? » : support
  /// d'en face absent du paquet.
  String linearLabel(GeoObject? l) {
    if (l == null) return tr('Sans destination connue');
    final d = destinations[l.id];
    return tr('Vers {0}', [d == null ? '?' : d.lib ?? tr('Sans étiquette')]);
  }

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

  /// Dimensions connues de la chambre pour la face [code] (face affichée par défaut), en m : largeur de la chambre
  /// pour les faces A et B, longueur pour C et D ; hauteur (profondeur) de la chambre. Dimension relevée, sinon
  /// celle du catalogue (intérieur) ; null si elle n'est pas connue (chambre OHN, catalogue vide).
  ({double? width, double? height}) chamberSize([String? code]) => chamberSizeOf(chamber, referenceData, code ?? face);

  /// [chamberSize] de la chambre [chamber], sans session d'édition (aperçu des masques).
  static ({double? width, double? height}) chamberSizeOf(GeoObject chamber, ReferenceData referenceData, String code) {
    final chb = chamber.namespace('chb');
    final mat = referenceData.row('chambre', 'MAT_CHAMBRE', 'MAT_ID', chb?['MAT_KEY']);
    double? dimension(String column) {
      for (final v in [chb?[column], mat?['${column}_INT']]) {
        if (v is num && v > 0) return _round(v.toDouble());
      }
      return null;
    }

    return (width: dimension(code == 'A' || code == 'B' ? 'CHB_LARG' : 'CHB_LNG'), height: dimension('CHB_HAUT'));
  }

  /// Dimensions de la face [code] de [chamber] (m), sans session d'édition : celles de la face relevée, sinon celles
  /// d'une nouvelle face (dimensions de la chambre, sinon fenêtre FOA).
  static ({double width, double height}) faceSizeOf(GeoObject chamber, ReferenceData referenceData, String code) {
    final faces = (chamber.namespace('chb')?['faces'] as List?) ?? const [];
    final f = faces.where((f) => (f as Map)['FAC_CODE'] == code).firstOrNull as Map?;
    final s = chamberSizeOf(chamber, referenceData, code);
    return (
      width: _positive(f?['FAC_LARG']) ?? s.width ?? foaFaceWidth,
      height: _positive(f?['FAC_HAUT']) ?? s.height ?? foaFaceHeight,
    );
  }

  /// Dimensions d'une nouvelle face [code] (m) : celles de la chambre, sinon celles de la fenêtre FOA.
  ({double width, double height}) defaultSize([String? code]) {
    final s = chamberSize(code);
    return (width: s.width ?? foaFaceWidth, height: s.height ?? foaFaceHeight);
  }

  static double? _positive(Object? v) => v is num && v > 0 ? v.toDouble() : null;

  /// Largeur et hauteur de la face affichée (m) : celles de la face relevée, sinon celles d'une nouvelle face.
  double get width => _positive(_existingFace(face)?['FAC_LARG']) ?? defaultSize().width;
  double get height => _positive(_existingFace(face)?['FAC_HAUT']) ?? defaultSize().height;

  Map<String, dynamic> _faceOrCreate(String code) {
    final existing = _existingFace(code);
    if (existing != null) return existing;
    final size = defaultSize(code);
    final f = <String, dynamic>{
      'FAC_CODE': code,
      'FAC_LARG': size.width,
      'FAC_HAUT': size.height,
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

  /// Arrivée dans [chamber] de la conduite [cd] du linéaire [linear] (alvéole suivie depuis l'autre extrémité) : la
  /// face (A à D) où elle est placée, et cette conduite ; si elle ne l'est pas, la première face où une autre conduite
  /// du linéaire l'est, sans conduite choisie (aucune autre ne doit l'être à sa place) ; null si aucune ne l'est.
  static ({String face, String? cd})? arrival(GeoObject chamber, GeoObject linear, {required String cd}) {
    final ducts = {for (final c in ductsOf(linear)) c['CD_CODE_EXT']};
    final faces = [for (final f in (chamber.namespace('chb')?['faces'] as List?) ?? const []) f as Map];
    String? first;
    for (final code in chamberFaces) {
      for (final f in faces.where((f) => f['FAC_CODE'] == code)) {
        for (final p in (f['positions'] as List?) ?? const []) {
          if ((p as Map)['DATE_ABD'] != null || p['CD_KEY'] is! String) continue;
          if (p['CD_KEY'] == cd) return (face: code, cd: cd);
          if (ducts.contains(p['CD_KEY'])) first ??= code;
        }
      }
    }
    return first == null ? null : (face: first, cd: null);
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

  /// Place d'une nouvelle alvéole de [diameter] mm dans la face affichée (m) : le centre de la face, sinon le
  /// premier point qui ne chevauche aucune alvéole, vers la droite puis sur les rangées suivantes, d'un pas égal au
  /// diamètre (une cellule de grille au moins) ; le centre si la face est pleine.
  (double, double) freePlace([double? diameter]) {
    final d = boreDiameter(diameter);
    final step = math.max(gridCell, d);
    final w = width, h = height;
    final others = bores();
    bool free(double x, double y) => others.every((a) {
          final dx = a.x - x, dy = a.y - y;
          return math.sqrt(dx * dx + dy * dy) >= (boreDiameter(a.diameter) + d) / 2;
        });
    var (x, y) = (w / 2, h / 2);
    for (var i = 0; i < 2000; i++) {
      if (free(x, y)) return (_round(x), _round(y));
      x += step;
      if (x > w - d / 2) {
        x = d / 2;
        y += step;
        if (y > h - d / 2) y = d / 2;
      }
    }
    return (_round(w / 2), _round(h / 2));
  }

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

  /// Arrondi au millimètre (valeurs en m).
  static double _round(double v) => (v * 1000).roundToDouble() / 1000;

  /// Centre de la position en ([x], [y]), borné à la face affichée.
  void _place(Map<String, dynamic> p, double x, double y) {
    p['POS_X'] = _round(x.clamp(0.0, width));
    p['POS_Y'] = _round(y.clamp(0.0, height));
  }

  /// Déplace l'alvéole (centre, en m depuis la gauche et le haut), dans les limites de la face.
  void move(MaskBore a, double x, double y) {
    _place(a.position, x, y);
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
  /// inconnue), centre au point ([x], [y]) en m, borné à la face.
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
    _place(p, x, y);
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

  /// Dimensions de la face affichée (m), à la demande de l'utilisateur (une face relevée n'est jamais agrandie
  /// d'office). Ses alvéoles restent centrées : décalées de la moitié de l'écart de largeur et de hauteur, puis
  /// bornées à la nouvelle face.
  void resize(double newWidth, double newHeight) {
    final f = _faceOrCreate(face);
    final w = _round(newWidth.clamp(minFaceSize, maxFaceSize)), h = _round(newHeight.clamp(minFaceSize, maxFaceSize));
    final dx = (w - width) / 2, dy = (h - height) / 2;
    f['FAC_LARG'] = w;
    f['FAC_HAUT'] = h;
    for (final a in bores()) {
      final (x, y) = (a.x, a.y);
      _place(a.position, x + dx, y + dy);
      if (a.x != x || a.y != y) _positionChanged(a.position);
    }
    f['DATE_MODIF'] = Bundle.timestamp();
    f['SRC_MODIF'] = author;
    _chamberChanged = true;
    notifyListeners();
  }

  /// Écrit la chambre (niveau de renseignement recalculé) et les linéaires modifiés dans le dépôt. Seuls les
  /// espaces `chb` et `inf.conduites` sont repris sur l'objet du dépôt : les photos prises entre-temps restent.
  Future<void> validate() async {
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
