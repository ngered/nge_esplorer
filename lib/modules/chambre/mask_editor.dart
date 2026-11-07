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

/// Diamètres normalisés des alvéoles (mm).
const standardDiameters = [28.0, 33.0, 45.0, 60.0, 80.0, 100.0, 150.0];

/// Diamètre de conduite (DEF_CD_DIAM, module infra 0.2.0) : nominal et intérieur (mm), proposé pour le sous-tubage.
typedef DuctDiameter = ({double nominal, double inner, bool subduct});

/// Diamètres à défaut du référentiel (paquet du module infra 0.1.0) : Ø intérieurs de l'abaque d'occupation de FOA
/// Explorer (cab_occupation.csv), ceux des sous-tubes de 20 et 24 mm à confirmer.
const _defaultDiameters = <DuctDiameter>[
  (nominal: 20, inner: 16, subduct: true),
  (nominal: 24, inner: 20, subduct: true),
  (nominal: 28, inner: 22, subduct: true),
  (nominal: 33, inner: 27, subduct: true),
  (nominal: 45, inner: 38, subduct: false),
  (nominal: 60, inner: 50, subduct: false),
  (nominal: 80, inner: 70, subduct: false),
  (nominal: 100, inner: 90, subduct: false),
  (nominal: 150, inner: 140, subduct: false),
];

/// Diamètres de conduite du paquet (DEF_CD_DIAM), du plus petit au plus grand ; ceux de FOA Explorer à défaut.
List<DuctDiameter> ductDiameters(ReferenceData ref) {
  final rows = [
    for (final r in ref.table('infra', 'DEF_CD_DIAM'))
      if (r['DIAM_NOMINAL'] is num && r['DIAM_INT'] is num)
        (
          nominal: (r['DIAM_NOMINAL'] as num).toDouble(),
          inner: (r['DIAM_INT'] as num).toDouble(),
          subduct: r['DIAM_SOUS_TUBE'] == 1,
        ),
  ]..sort((a, b) => a.nominal.compareTo(b.nominal));
  return rows.isEmpty ? _defaultDiameters : rows;
}

/// Diamètres proposés pour le sous-tubage (mm).
List<double> subductDiameters(ReferenceData ref) => [
      for (final d in ductDiameters(ref))
        if (d.subduct) d.nominal,
    ];

/// Diamètre intérieur (mm) d'une conduite de diamètre nominal [nominal], celui du référentiel ; null pour un
/// diamètre qui n'y est pas (comme au BE, le taux n'est alors pas calculable).
double? innerDiameter(ReferenceData ref, double nominal) =>
    ductDiameters(ref).where((d) => d.nominal == nominal).firstOrNull?.inner;

/// Diamètres de câble proposés (mm), ceux de l'écran « Occupation alvéole » de FOA Explorer.
const cableDiameters = [6.0, 8.0, 9.0, 10.0, 11.0, 13.0, 15.0, 20.0, 27.0, 30.0, 35.0, 40.0, 50.0];

/// Nature d'un câble constaté (INF_CD_CABLE.CDC_NATURE) : fibre ou cuivre.
const cableNatures = ['FO', 'CU'];

/// Libellé court d'une nature de câble : « Fo », « Cu » (FOA Explorer).
String natureLabel(Object? nature) => switch (nature) { 'FO' => 'Fo', 'CU' => 'Cu', _ => '?' };

/// Câbles constatés d'une conduite (INF_CD_CABLE), abandonnés exclus : les lignes elles-mêmes, modifiables.
List<Map<String, dynamic>> cablesOf(Map<String, dynamic>? duct) => [
      for (final c in (duct?['cables'] as List?) ?? const [])
        if ((c as Map)['DATE_ABD'] == null) c is Map<String, dynamic> ? c : c.cast<String, dynamic>(),
    ];

/// Nombre de câbles d'une conduite (somme des CDC_NB).
int cableCount(Map<String, dynamic>? duct) =>
    cablesOf(duct).fold(0, (n, c) => n + ((c['CDC_NB'] as num?)?.toInt() ?? 1));

/// Taux d'occupation d'une conduite (%), calculé comme au BE (`recalculer_occupation`) : sans câble, 100 % pour une
/// conduite mauvaise (M, XM), 0 sinon ; avec câbles, Σ CDC_NB × (CDC_DIAM / Ø intérieur)², la formule des sections
/// dont l'abaque de FOA Explorer donne les valeurs ; null si ce n'est pas calculable (diamètre de la conduite absent du
/// référentiel, câble sans diamètre).
double? occupancyOf(Map<String, dynamic>? duct, ReferenceData ref) {
  final cables = cablesOf(duct);
  if (cables.isEmpty) {
    final state = ref.row('infra', 'DEF_CD_ETAT', 'ETAT_ID', duct?['ETAT_KEY'])?['ETAT_CODE'];
    return state == 'M' || state == 'XM' ? 100 : 0;
  }
  final diameter = (duct?['CD_DIAM'] as num?)?.toDouble();
  final inner = diameter == null ? null : innerDiameter(ref, diameter);
  if (inner == null || cables.any((c) => c['CDC_DIAM'] is! num)) return null;
  return cables.fold<double>(0, (s, c) {
    final d = (c['CDC_DIAM'] as num).toDouble();
    return s + ((c['CDC_NB'] as num?)?.toInt() ?? 1) * (d / inner) * (d / inner) * 100;
  });
}

/// Face d'en face par défaut pour le miroir (règle de 84 % des paires de Nancy) : A et B s'échangent, C et D restent.
String mirrorFace(String code) => switch (code) { 'A' => 'B', 'B' => 'A', _ => code };

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
  MaskBore(this.position, {this.linear, this.duct, this.parentNumber});

  final Map<String, dynamic> position;

  /// Linéaire porteur de la conduite ; null pour une alvéole sans destination connue (sans miroir, autorisée).
  final GeoObject? linear;

  /// Conduite (INF_CONDUITE) ; null si elle n'est pas dans le paquet.
  final Map<String, dynamic>? duct;

  /// Numéro de l'alvéole parente d'un sous-tube.
  final int? parentNumber;

  String get cd => position['CD_KEY'] as String;

  /// Centre de l'alvéole, en m depuis la gauche et depuis le haut de la face.
  double get x => (position['POS_X'] as num?)?.toDouble() ?? 0;
  double get y => (position['POS_Y'] as num?)?.toDouble() ?? 0;
  int? get state => duct?['ETAT_KEY'] as int?;
  double? get diameter => (duct?['CD_DIAM'] as num?)?.toDouble();
  int? get number => duct?['CD_NUM'] as int?;
  bool get mirror => position['POS_MIROIR'] == 1;
  bool get noDestination => duct != null && linear == null;
  int get nbCables => cableCount(duct);

  /// Alvéole parente d'un sous-tube (CD_PARENT_KEY, CD_CODE_EXT de sa conduite) ; null pour une alvéole.
  String? get parent => duct?['CD_PARENT_KEY'] as String?;
  bool get subduct => parent != null;

  /// Numéro affiché : « 3 » pour une alvéole, « 3.2 » pour le deuxième sous-tube de l'alvéole 3 (FOA Explorer).
  String get label => number == null ? '?' : subduct ? '${parentNumber ?? '?'}.$number' : '$number';
}

/// Source du miroir : face [face] (A à D) de la chambre d'en face [chamber] (identifiant).
typedef MirrorSource = ({String chamber, String face});

/// Position active d'une conduite dans une chambre : face, centre et dimensions de la face (m).
typedef _Placed = ({String face, double x, double y, double width, double height});

/// Conduite à placer en miroir : linéaire, conduite, chambre d'en face, sa position là-bas, les positions de cette
/// chambre, alvéole parente d'un sous-tube.
typedef _Pending = ({
  String cd,
  GeoObject linear,
  Map<String, dynamic> duct,
  GeoObject other,
  _Placed there,
  Map<String, _Placed> otherPlaced,
  String? parent,
});

/// Conduite d'un linéaire de la chambre placée dans la chambre d'en face et pas dans celle-ci : alvéole à placer en
/// miroir dans la face [face], au point ([x], [y]) (m), avec ses sous-tubes ([children]).
class MirrorBore {
  MirrorBore({
    required this.cd,
    required this.linear,
    required this.duct,
    required this.face,
    required this.x,
    required this.y,
    this.parentNumber,
    this.children = const [],
  });

  final String cd;
  final GeoObject linear;
  final Map<String, dynamic> duct;
  final String face;
  final double x;
  final double y;

  /// Numéro de l'alvéole parente, déjà placée, d'un sous-tube à placer seul.
  final int? parentNumber;

  /// Sous-tubes placés avec l'alvéole : conduite et centre (m).
  final List<({String cd, double x, double y})> children;

  int? get state => duct['ETAT_KEY'] as int?;
  double? get diameter => (duct['CD_DIAM'] as num?)?.toDouble();
  int? get number => duct['CD_NUM'] as int?;
  bool get subduct => duct['CD_PARENT_KEY'] != null;
  String get label => number == null ? '?' : subduct ? '${parentNumber ?? '?'}.$number' : '$number';
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

  /// Positions créées pendant la session (miroir d'une conduite existante) : retirées tout à fait, comme les
  /// conduites nouvelles.
  final Set<Map<String, dynamic>> _newPositions = Set.identity();

  /// Lignes de câbles créées pendant la session (retirées tout à fait ; une ligne venue du BE est abandonnée).
  final Set<Map<String, dynamic>> _newCables = Set.identity();

  /// État d'une alvéole avant son sous-tubage dans la session (CD_KEY) : rétabli si ses sous-tubes sont retirés.
  final Map<String, int?> _stateBeforeSubduct = {};

  /// Conduite sélectionnée (CD_KEY).
  String? selection;

  /// Alvéole à placer en miroir mise en évidence (CD_KEY) : arrivée d'un « Vers … » sur une conduite que cette
  /// chambre n'a pas encore placée.
  String? focus;

  /// Face de la chambre d'en face dont les alvéoles à placer sont affichées en pointillé (bouton Miroir) ; null :
  /// miroir fermé.
  MirrorSource? mirrorSource;

  /// Nature du prochain câble ajouté (FO, CU), retenue pour la saisie en série.
  String cableNature = 'FO';
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

  /// Alvéoles de la face [code] (face affichée par défaut), positions abandonnées exclues ; les sous-tubes après les
  /// alvéoles, dessinés au-dessus de leur parent.
  List<MaskBore> bores([String? code]) {
    final f = _existingFace(code ?? face);
    if (f == null) return const [];
    final all = [
      for (final p in _positions(f))
        if (p['DATE_ABD'] == null && p['CD_KEY'] is String)
          () {
            final c = _duct(p['CD_KEY'] as String);
            final parent = c?.$2['CD_PARENT_KEY'];
            return MaskBore(p,
                linear: c?.$1,
                duct: c?.$2,
                parentNumber: parent is String ? _duct(parent)?.$2['CD_NUM'] as int? : null);
          }(),
    ];
    return [...all.where((a) => !a.subduct), ...all.where((a) => a.subduct)];
  }

  MaskBore? get selectedBore => bores().where((a) => a.cd == selection).firstOrNull;

  /// Sous-tubes de l'alvéole [a] (conduites de son porteur dont elle est le parent), placés ici ou non : ils font
  /// l'alvéole occupée et interdisent un second sous-tubage.
  List<Map<String, dynamic>> subductsOf(MaskBore a) => a.duct == null
      ? const []
      : ductsOf(a.linear ?? chamber).where((c) => c['CD_PARENT_KEY'] == a.cd && c['DATE_ABD'] == null).toList();

  /// Sous-tubes de l'alvéole [a] placés dans la face affichée, dans l'ordre de leur numéro.
  List<MaskBore> children(MaskBore a) =>
      bores().where((b) => b.parent == a.cd).toList()..sort((x, y) => (x.number ?? 0).compareTo(y.number ?? 0));

  // -- miroir ----------------------------------------------------------------------------------

  /// Positions actives d'une chambre par conduite : face, centre et dimensions de la face (m).
  static Map<String, _Placed> _placed(GeoObject chamber) => {
        for (final f in (chamber.namespace('chb')?['faces'] as List?) ?? const [])
          for (final p in ((f as Map)['positions'] as List?) ?? const [])
            if ((p as Map)['DATE_ABD'] == null && p['CD_KEY'] is String)
              p['CD_KEY'] as String: (
                face: '${f['FAC_CODE']}',
                x: (p['POS_X'] as num?)?.toDouble() ?? 0,
                y: (p['POS_Y'] as num?)?.toDouble() ?? 0,
                width: _positive(f['FAC_LARG']) ?? foaFaceWidth,
                height: _positive(f['FAC_HAUT']) ?? foaFaceHeight,
              ),
      };

  ({double width, double height}) _sizeOf(String code) => (
        width: _positive(_existingFace(code)?['FAC_LARG']) ?? defaultSize(code).width,
        height: _positive(_existingFace(code)?['FAC_HAUT']) ?? defaultSize(code).height,
      );

  /// Conduites des linéaires de la chambre placées dans la chambre d'en face et pas dans celle-ci : la matière du
  /// miroir.
  List<_Pending> _pending() {
    final here = _placed(chamber);
    final result = <_Pending>[];
    for (final l in linears) {
      final other = destinations[l.id];
      if (other == null || other.abandoned || other.id == chamber.id) continue;
      final there = _placed(other);
      for (final c in ductsOf(l)) {
        final cd = c['CD_CODE_EXT'];
        final t = cd is String && !here.containsKey(cd) ? there[cd] : null;
        if (t == null) continue;
        result.add((
          cd: cd as String,
          linear: l,
          duct: c,
          other: other,
          there: t,
          otherPlaced: there,
          parent: c['CD_PARENT_KEY'] as String?,
        ));
      }
    }
    return result;
  }

  /// Faces de la chambre d'en face d'où le miroir peut être appliqué, avec le nombre d'alvéoles qu'elles ont à
  /// placer ici (un sous-tube compte s'il est à placer seul, son alvéole l'étant déjà), par chambre puis par face.
  List<({MirrorSource source, GeoObject chamber, int count})> mirrorSources() {
    final here = _placed(chamber);
    final counts = <MirrorSource, int>{};
    final chambers = <String, GeoObject>{};
    for (final p in _pending()) {
      final parent = p.parent;
      final f = parent == null ? p.there.face : (here.containsKey(parent) ? p.otherPlaced[parent]?.face : null);
      if (f == null) continue;
      final key = (chamber: p.other.id, face: f);
      counts[key] = (counts[key] ?? 0) + 1;
      chambers[p.other.id] = p.other;
    }
    return [
      for (final e in counts.entries) (source: e.key, chamber: chambers[e.key.chamber]!, count: e.value),
    ]..sort((a, b) {
        final byLib = (a.chamber.lib ?? '').compareTo(b.chamber.lib ?? '');
        return byLib != 0 ? byLib : a.source.face.compareTo(b.source.face);
      });
  }

  /// Nombre d'alvéoles à placer en miroir, toutes faces d'en face confondues (pastille du bouton Miroir).
  int get pendingMirrors => mirrorSources().fold(0, (n, s) => n + s.count);

  /// Face proposée pour appliquer le miroir de [source] : celle où arrive déjà une conduite d'un linéaire vers cette
  /// chambre, sinon la face d'en face ([mirrorFace]) ; le miroir peut s'appliquer sur toute autre face.
  String suggestedFace(MirrorSource source) {
    final here = _placed(chamber);
    final codes = {
      for (final l in linears)
        if (destinations[l.id]?.id == source.chamber)
          for (final c in ductsOf(l)) c['CD_CODE_EXT'],
    };
    return chamberFaces.where((f) => here.entries.any((e) => e.value.face == f && codes.contains(e.key))).firstOrNull ??
        mirrorFace(source.face);
  }

  /// Affiche, en pointillé sur la face affichée, les alvéoles à placer de la face [source] de la chambre d'en face
  /// (bouton Miroir, notes rep15) ; null : plus rien d'affiché.
  void showMirror(MirrorSource? source) {
    mirrorSource = source;
    focus = null;
    notifyListeners();
  }

  /// Alvéoles à placer en miroir ([mirrorSource]) dans la face [code] (toutes faces si null) : celles de la face
  /// source sur la face affichée, quelle qu'elle soit ; centre retourné gauche-droite à la même proportion de la
  /// largeur, X' = W'·(1 − X/W), à la même profondeur depuis le haut, borné à la face ; les sous-tubes gardent leur
  /// écart au centre de l'alvéole, retourné. Un sous-tube dont l'alvéole est déjà placée ici est à placer seul, à
  /// côté d'elle. Aucune sans miroir affiché.
  List<MirrorBore> mirrors([String? code]) {
    final s = mirrorSource;
    if (s == null) return const [];
    final here = _placed(chamber);
    final pending = [for (final p in _pending()) if (p.other.id == s.chamber) p];
    final size = _sizeOf(face);
    final result = <MirrorBore>[];
    for (final p in pending) {
      final t = p.there;
      final parent = p.parent;
      if (parent != null) {
        // sous-tube : placé avec son alvéole, ou seul si elle est déjà placée ici
        final (ph, pt) = (here[parent], p.otherPlaced[parent]);
        if (ph == null || pt == null || pt.face != s.face) continue;
        final parentSize = _sizeOf(ph.face);
        result.add(MirrorBore(
          cd: p.cd,
          linear: p.linear,
          duct: p.duct,
          face: ph.face,
          x: (ph.x - (t.x - pt.x)).clamp(0.0, parentSize.width),
          y: (ph.y + (t.y - pt.y)).clamp(0.0, parentSize.height),
          parentNumber: _duct(parent)?.$2['CD_NUM'] as int?,
        ));
        continue;
      }
      if (t.face != s.face) continue;
      final x = _round((size.width * (1 - t.x / t.width)).clamp(0.0, size.width));
      final y = _round(math.min(t.y, size.height));
      result.add(MirrorBore(cd: p.cd, linear: p.linear, duct: p.duct, face: face, x: x, y: y, children: [
        for (final c in pending)
          if (c.parent == p.cd)
            (
              cd: c.cd,
              x: (x - (c.there.x - t.x)).clamp(0.0, size.width),
              y: (y + (c.there.y - t.y)).clamp(0.0, size.height),
            ),
      ]));
    }
    return code == null ? result : result.where((m) => m.face == code).toList();
  }

  /// Position de la conduite [cd] dans la face [f] en ([x], [y]), créée en appliquant le miroir ; une position
  /// abandonnée de la même conduite dans cette face est reprise (une seule position par conduite et par face).
  void _mirrorPosition(Map<String, dynamic> f, String cd, double x, double y) {
    final size = _sizeOf('${f['FAC_CODE']}');
    final positions = _positions(f);
    var p = positions.where((p) => p['CD_KEY'] == cd).firstOrNull;
    if (p == null) {
      p = <String, dynamic>{'CD_KEY': cd, 'DATE_CREA': Bundle.timestamp()};
      positions.add(p);
      _newPositions.add(p);
    } else {
      p
        ..remove('DATE_ABD')
        ..remove('SRC_ABD');
    }
    p['POS_MIROIR'] = 1;
    p['POS_X'] = _round(x.clamp(0.0, size.width));
    p['POS_Y'] = _round(y.clamp(0.0, size.height));
    _positionChanged(p);
  }

  /// Place l'alvéole [m] en miroir, avec ses sous-tubes, sur sa face, qui devient la face affichée ; [select] : elle
  /// devient l'alvéole choisie. Le miroir se referme quand il n'a plus rien à placer.
  void placeMirror(MirrorBore m, {bool select = true}) {
    final f = _faceOrCreate(m.face);
    _mirrorPosition(f, m.cd, m.x, m.y);
    for (final c in m.children) {
      _mirrorPosition(f, c.cd, c.x, c.y);
    }
    if (focus == m.cd) focus = null;
    if (select) {
      face = m.face;
      selection = m.cd;
    }
    if (mirrors().isEmpty) mirrorSource = null;
    notifyListeners();
  }

  /// Sous-tubes de l'alvéole [a] que la chambre d'en face a placés et pas celle-ci.
  int pendingSubducts(MaskBore a) => _pending().where((p) => p.parent == a.cd && p.otherPlaced.containsKey(a.cd)).length;

  /// Place, à côté de l'alvéole [a] déjà placée ici, ses sous-tubes que la chambre d'en face a placés et pas
  /// celle-ci ; rend leur nombre.
  int placeSubductMirrors(MaskBore a) {
    final ph = _placed(chamber)[a.cd];
    if (ph == null) return 0;
    var n = 0;
    for (final p in _pending().where((p) => p.parent == a.cd)) {
      final pt = p.otherPlaced[a.cd];
      if (pt == null) continue;
      _mirrorPosition(_faceOrCreate(ph.face), p.cd, ph.x - (p.there.x - pt.x), ph.y + (p.there.y - pt.y));
      n++;
    }
    notifyListeners();
    return n;
  }

  /// « Tout placer » : place toutes les alvéoles à placer de la face affichée ; rend leur nombre.
  int placeMirrors() {
    final all = mirrors(face);
    for (final m in all) {
      placeMirror(m, select: false);
    }
    return all.length;
  }

  /// Arrivée d'un « Vers … » sur la conduite [cd] que cette chambre n'a pas encore placée : le miroir de sa face
  /// s'ouvre sur la face proposée ([suggestedFace]), son alvéole (celle d'un sous-tube qui n'y est pas encore)
  /// mise en évidence ; faux si cette conduite n'est pas à placer.
  bool focusMirror(String cd) {
    final pending = _pending();
    final here = _placed(chamber);
    final p = pending.where((p) => p.cd == cd).firstOrNull;
    if (p == null) return false;
    final parent = p.parent;
    final top = parent != null && !here.containsKey(parent) ? pending.where((q) => q.cd == parent).firstOrNull : p;
    if (top == null) return false;
    final topParent = top.parent;
    if (topParent == null) {
      mirrorSource = (chamber: top.other.id, face: top.there.face);
      face = suggestedFace(mirrorSource!);
    } else {
      // sous-tube à placer seul : la face de son alvéole, ici et en face
      final pt = top.otherPlaced[topParent];
      if (pt == null) return false;
      mirrorSource = (chamber: top.other.id, face: pt.face);
      face = here[topParent]!.face;
    }
    selection = null;
    focus = top.cd;
    notifyListeners();
    return true;
  }

  // -- imbrication (sous-tubage par glisser-déposer) -------------------------------------------

  /// Alvéole où l'alvéole [a], déposée, est sous-tube (glisser-déposer d'InfraExplorer, `ClsChbMask.MajTubage`,
  /// notes rep15 et rep17) : la plus petite alvéole strictement plus grande dont le carré englobant contient son
  /// centre ; pour un sous-tube, son alvéole s'il y est resté. Null s'il n'y en a pas (un sous-tube déposé hors de son
  /// alvéole en est détaché), ou si [a] ne peut pas être un sous-tube (sous-tubée elle-même, conduite absente,
  /// diamètre inconnu).
  MaskBore? nestTarget(MaskBore a) {
    final d = a.diameter;
    if (a.duct == null || d == null || subductsOf(a).isNotEmpty) return null;
    final hosts = [
      for (final b in bores())
        if (b.cd != a.cd && !b.subduct && b.duct != null && (b.diameter ?? 0) > d)
          if ((b.x - a.x).abs() < boreDiameter(b.diameter) / 2 && (b.y - a.y).abs() < boreDiameter(b.diameter) / 2) b,
    ]..sort((x, y) => x.diameter!.compareTo(y.diameter!));
    return hosts.firstOrNull;
  }

  /// [a] peut devenir sous-tube de [parent] : même porteur (le sous-tube hérite de la destination de son alvéole),
  /// ou conduite créée pendant la session, qui en change.
  bool canNest(MaskBore a, MaskBore parent) => a.linear?.id == parent.linear?.id || _newDucts.contains(a.cd);

  /// L'alvéole [a] devient sous-tube de [parent] ([canNest]) : CD_PARENT_KEY, numéro suivant dans l'alvéole, porteur
  /// de l'alvéole pour une conduite créée pendant la session ; l'alvéole devient occupée. Un sous-tube change ainsi
  /// d'alvéole (son ancienne alvéole garde son état, comme dans InfraExplorer). Rend l'annulation.
  VoidCallback nest(MaskBore a, MaskBore parent) {
    final duct = a.duct!;
    final (number, previous, parentState, from) = (duct['CD_NUM'], duct['CD_PARENT_KEY'], parent.state, a.linear);
    final to = parent.linear;
    if (from?.id != to?.id) _moveDuct(duct, from, to);
    duct['CD_PARENT_KEY'] = parent.cd;
    duct['CD_NUM'] = subductsOf(parent).where((c) => !identical(c, duct)).fold<int>(0, (m, c) => math.max(m, c['CD_NUM'] as int? ?? 0)) + 1;
    _ductChanged(MaskBore(a.position, linear: to, duct: duct));
    _occupy(parent);
    _refreshOccupancy(parent);
    _ductChanged(parent);
    notifyListeners();
    return () {
      previous == null ? duct.remove('CD_PARENT_KEY') : duct['CD_PARENT_KEY'] = previous;
      duct['CD_NUM'] = number;
      if (from?.id != to?.id) _moveDuct(duct, to, from);
      _ductChanged(MaskBore(a.position, linear: from, duct: duct));
      parentState == null ? parent.duct!.remove('ETAT_KEY') : parent.duct!['ETAT_KEY'] = parentState;
      _refreshOccupancy(parent);
      _ductChanged(parent);
      notifyListeners();
    };
  }

  /// Le sous-tube [a] redevient une alvéole, au numéro suivant parmi les alvéoles de son porteur ; son ancienne
  /// alvéole garde son état (comme dans InfraExplorer). Rend l'annulation.
  VoidCallback unnest(MaskBore a) {
    if (!a.subduct) return () {};
    final duct = a.duct!;
    final (parent, number) = (duct['CD_PARENT_KEY'], duct['CD_NUM']);
    final carrier = a.linear ?? chamber;
    duct
      ..remove('CD_PARENT_KEY')
      ..['CD_NUM'] = ductsOf(carrier)
              .where((c) => c['CD_PARENT_KEY'] == null && !identical(c, duct))
              .fold<int>(0, (m, c) => math.max(m, c['CD_NUM'] as int? ?? 0)) +
          1;
    _ductChanged(a);
    notifyListeners();
    return () {
      duct
        ..['CD_PARENT_KEY'] = parent
        ..['CD_NUM'] = number;
      _ductChanged(a);
      notifyListeners();
    };
  }

  /// Change la conduite [duct] de porteur (linéaire, ou chambre si null).
  void _moveDuct(Map<String, dynamic> duct, GeoObject? from, GeoObject? to) {
    ((from ?? chamber).namespace('inf')?['conduites'] as List?)?.removeWhere((c) => identical(c, duct));
    ((to ?? chamber).namespace('inf', create: true)!.putIfAbsent('conduites', () => <dynamic>[]) as List).add(duct);
    for (final l in [from, to]) {
      l == null ? _chamberChanged = true : _changedLinears.add(l.id);
    }
  }

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

  /// Déplace l'alvéole (centre, en m depuis la gauche et le haut), dans les limites de la face ; ses sous-tubes la
  /// suivent.
  void move(MaskBore a, double x, double y) {
    final (x0, y0) = (a.x, a.y);
    final followers = children(a);
    _place(a.position, x, y);
    _positionChanged(a.position);
    final (dx, dy) = (a.x - x0, a.y - y0);
    for (final c in followers) {
      _place(c.position, c.x + dx, c.y + dy);
      _positionChanged(c.position);
    }
    notifyListeners();
  }

  // -- état et occupation ----------------------------------------------------------------------

  /// État occupé correspondant (règle de FOA Explorer) : vide → occupée, réservée → occupée et réservée, mauvaise →
  /// occupée et mauvaise.
  static const _occupiedCodes = {'V': 'X', 'R': 'XR', 'M': 'XM'};

  int? _stateId(String code) =>
      referenceData.table('infra', 'DEF_CD_ETAT').where((e) => e['ETAT_CODE'] == code).firstOrNull?['ETAT_ID'] as int?;

  /// Code de l'état [id] (DEF_CD_ETAT.ETAT_CODE).
  String? stateCode(int? id) => referenceData.row('infra', 'DEF_CD_ETAT', 'ETAT_ID', id)?['ETAT_CODE'] as String?;

  /// Alvéole occupée d'office : elle porte des câbles ou des sous-tubes.
  bool occupied(MaskBore a) => a.nbCables > 0 || subductsOf(a).isNotEmpty;

  /// Passe l'état de la conduite à l'état occupé correspondant (sans effet s'il l'est déjà, ou si le paquet ne connaît
  /// pas cet état : XM manque au module infra 0.1.0).
  void _occupy(MaskBore a) {
    final to = _occupiedCodes[stateCode(a.state) ?? 'V'];
    final id = to == null ? null : _stateId(to);
    if (id != null) a.duct!['ETAT_KEY'] = id;
  }

  /// Taux d'occupation de la conduite (CD_OCCUP, %), au dixième, recalculé à chaque changement des câbles, de l'état
  /// ou du diamètre.
  void _refreshOccupancy(MaskBore a) => _setOccupancy(a.duct!);

  void _setOccupancy(Map<String, dynamic> duct) {
    final o = occupancyOf(duct, referenceData);
    if (o == null) {
      duct.remove('CD_OCCUP');
    } else {
      duct['CD_OCCUP'] = (o * 10).roundToDouble() / 10;
    }
  }

  /// État de la conduite ; une alvéole qui porte des câbles ou des sous-tubes reste occupée ([occupied]).
  void setDuctState(MaskBore a, int state) {
    if (a.duct == null) return;
    a.duct!['ETAT_KEY'] = state;
    if (occupied(a)) _occupy(a);
    _refreshOccupancy(a);
    _ductChanged(a);
    notifyListeners();
  }

  void setDiameter(MaskBore a, double mm) {
    if (a.duct == null) return;
    a.duct!['CD_DIAM'] = mm;
    _refreshOccupancy(a);
    _ductChanged(a);
    notifyListeners();
  }

  /// Ajoute un câble constaté de [mm] mm et de nature [nature] (FO, CU) à la conduite de [a] : une ligne de même
  /// diamètre et de même nature, sans référence ni commentaire, compte un câble de plus (CDC_NB) ; sinon une ligne
  /// nouvelle, au rang suivant (CDC_RANG). L'alvéole devient occupée.
  void addCable(MaskBore a, double mm, String nature) {
    final duct = a.duct;
    if (duct == null) return;
    final list = duct.putIfAbsent('cables', () => <dynamic>[]) as List;
    _rankCables(list);
    final cables = cablesOf(duct);
    final same = cables
        .where((c) => c['CDC_DIAM'] == mm && c['CDC_NATURE'] == nature && c['MAT_KEY'] == null && c['CDC_COMMENT'] == null)
        .firstOrNull;
    final date = Bundle.timestamp();
    if (same != null) {
      same['CDC_NB'] = ((same['CDC_NB'] as num?)?.toInt() ?? 1) + 1;
      same['DATE_MODIF'] = date;
      same['SRC_MODIF'] = author;
    } else {
      final rank = [for (final c in list) ((c as Map)['CDC_RANG'] as num?)?.toInt() ?? 0].fold(0, math.max) + 1;
      final row = <String, dynamic>{
        'CDC_RANG': rank,
        'CDC_NB': 1,
        'CDC_DIAM': mm,
        'CDC_NATURE': nature,
        'DATE_CREA': date,
        'SRC_MODIF': author,
      };
      list.add(row);
      _newCables.add(row);
    }
    cableNature = nature;
    _occupy(a);
    _refreshOccupancy(a);
    _ductChanged(a);
    notifyListeners();
  }

  /// Numérote les lignes de câbles sans rang (paquet antérieur au module infra 0.2.0) à la suite des autres :
  /// CDC_RANG est la clé du câble dans sa conduite, exigée au retour.
  static void _rankCables(List list) {
    var rank = [for (final c in list) ((c as Map)['CDC_RANG'] as num?)?.toInt() ?? 0].fold(0, math.max);
    for (final c in list) {
      if ((c as Map)['CDC_RANG'] is! int) c['CDC_RANG'] = ++rank;
    }
  }

  void setCableNature(String nature) {
    cableNature = nature;
    notifyListeners();
  }

  /// Retire un câble de la ligne [cable] : un de moins, ou la ligne entière s'il n'y en avait qu'un, retirée tout à
  /// fait si elle a été créée pendant la session, sinon abandonnée (son rang, clé du câble au BE, n'est jamais
  /// réattribué). L'état reste celui de la conduite.
  void removeCable(MaskBore a, Map<String, dynamic> cable) {
    final duct = a.duct;
    if (duct == null) return;
    _rankCables(duct['cables'] as List);
    final n = (cable['CDC_NB'] as num?)?.toInt() ?? 1;
    if (n > 1) {
      cable['CDC_NB'] = n - 1;
      cable['DATE_MODIF'] = Bundle.timestamp();
      cable['SRC_MODIF'] = author;
    } else if (_newCables.remove(cable)) {
      (duct['cables'] as List).removeWhere((c) => identical(c, cable));
    } else {
      cable['DATE_ABD'] = Bundle.timestamp();
      cable['SRC_ABD'] = author;
    }
    _refreshOccupancy(a);
    _ductChanged(a);
    notifyListeners();
  }

  // -- sous-tubage -----------------------------------------------------------------------------

  /// Les [count] sous-tubes de [mm] mm tiennent dans une alvéole de [parentMm] mm, disposés comme dans FOA Explorer
  /// (en carré pour 4, en triangle pour 3), à 5 % près.
  static bool subductFits(double? parentMm, int count, double mm) {
    if (parentMm == null) return false;
    final extent = count == 4 ? mm / 2 * (1 + math.sqrt2) : mm / 2 * 2.15;
    return extent <= parentMm / 2 * 1.05;
  }

  /// Centres des sous-tubes de rayon [r] (m) par rapport au centre de l'alvéole, dans l'ordre de leur numéro (rangées
  /// de haut en bas, puis de gauche à droite) : gabarits 3X et 4X de FOA Explorer.
  static List<(double, double)> subductOffsets(int count, double r) => count == 4
      ? [(-r, -r), (r, -r), (-r, r), (r, r)]
      : [(0, -1.15 * r), (-r, 0.55 * r), (r, 0.55 * r)];

  /// Sous-tube l'alvéole [a] : [count] sous-tubes de [mm] mm (conduites du même porteur, CD_PARENT_KEY = conduite de
  /// l'alvéole, numérotés 1 à [count], vides), placés dans la face selon [subductOffsets] ; l'alvéole devient
  /// occupée. Sans effet sur un sous-tube ou une alvéole déjà sous-tubée.
  void subduct(MaskBore a, int count, double mm) {
    if (a.duct == null || a.subduct || subductsOf(a).isNotEmpty) return;
    _stateBeforeSubduct[a.cd] = a.state;
    final carrier = a.linear ?? chamber;
    final ducts = carrier.namespace('inf', create: true)!.putIfAbsent('conduites', () => <dynamic>[]) as List;
    final f = _existingFace(face)!;
    final date = Bundle.timestamp();
    final empty = _stateId('V');
    final offsets = subductOffsets(count, mm / 2000);
    for (var i = 0; i < offsets.length; i++) {
      final cd = const Uuid().v4();
      final duct = <String, dynamic>{
        'CD_CODE_EXT': cd,
        'CD_PARENT_KEY': a.cd,
        'CD_NUM': i + 1,
        'CD_DIAM': mm,
        'ETAT_KEY': ?empty,
        'DATE_CREA': date,
        'SRC_MODIF': author,
      };
      _setOccupancy(duct);
      ducts.add(duct);
      _newDucts.add(cd);
      final p = <String, dynamic>{'CD_KEY': cd, 'POS_MIROIR': 0, 'DATE_CREA': date};
      _positions(f).add(p);
      _place(p, a.x + offsets[i].$1, a.y + offsets[i].$2);
      _positionChanged(p);
    }
    _occupy(a);
    _refreshOccupancy(a);
    _ductChanged(a);
    if (a.linear != null) _changedLinears.add(a.linear!.id);
    notifyListeners();
  }

  /// Nouvelle alvéole dans la face affichée : conduite créée dans [linear] (dans la chambre si null : destination
  /// inconnue), centre au point ([x], [y]) en m, borné à la face.
  String add({GeoObject? linear, required double x, required double y, double? diameter, int? state}) {
    final cd = const Uuid().v4();
    final date = Bundle.timestamp();
    final carrier = linear ?? chamber;
    final ducts = carrier.namespace('inf', create: true)!.putIfAbsent('conduites', () => <dynamic>[]) as List;
    // numéro suivant parmi les alvéoles (un sous-tube est numéroté dans son alvéole)
    final num = ductsOf(carrier)
            .where((c) => c['CD_PARENT_KEY'] == null)
            .fold<int>(0, (m, c) => (c['CD_NUM'] as int? ?? 0) > m ? c['CD_NUM'] as int : m) +
        1;
    final duct = <String, dynamic>{
      'CD_CODE_EXT': cd,
      'CD_NUM': num,
      'CD_DIAM': ?diameter,
      'ETAT_KEY': ?state,
      'DATE_CREA': date,
      'SRC_MODIF': author,
    };
    _setOccupancy(duct);
    ducts.add(duct);
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

  /// Retire l'alvéole de la face, avec ses sous-tubes : abandon de la position (pas de suppression) ; une conduite
  /// créée pendant la session disparaît tout à fait, comme une position créée en appliquant le miroir. La conduite
  /// existante reste, et sa position dans la chambre d'en face.
  void remove(MaskBore a) {
    final f = _existingFace(face)!;
    for (final b in [...children(a), a]) {
      if (_newDucts.remove(b.cd)) {
        _positions(f).remove(b.position);
        if (b.duct != null) ((b.linear ?? chamber).namespace('inf')!['conduites'] as List).remove(b.duct);
        if (b.linear != null) _changedLinears.add(b.linear!.id);
      } else if (_newPositions.remove(b.position)) {
        _positions(f).remove(b.position);
      } else {
        b.position['DATE_ABD'] = Bundle.timestamp();
        b.position['SRC_ABD'] = author;
      }
      if (selection == b.cd) selection = null;
    }
    // alvéole sous-tubée pendant la session, dont les sous-tubes sont tous retirés : son état d'avant
    final parent = a.subduct ? bores().where((b) => b.cd == a.parent).firstOrNull : null;
    if (parent != null && _stateBeforeSubduct.containsKey(parent.cd) && !occupied(parent)) {
      final before = _stateBeforeSubduct.remove(parent.cd);
      before == null ? parent.duct!.remove('ETAT_KEY') : parent.duct!['ETAT_KEY'] = before;
      _refreshOccupancy(parent);
      _ductChanged(parent);
    }
    _chamberChanged = true;
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
    // câbles d'un paquet antérieur au module infra 0.2.0 : numérotés dans tout objet réécrit (retour vérifié)
    for (final carrier in [...linears.where((l) => _changedLinears.contains(l.id)), if (_chamberChanged) chamber]) {
      for (final c in ductsOf(carrier)) {
        if (c['cables'] is List) _rankCables(c['cables'] as List);
      }
    }
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
    _newPositions.clear();
    _newCables.clear();
    _stateBeforeSubduct.clear();
    notifyListeners();
  }

  static Object? _clone(Object? v) => v == null ? null : jsonDecode(jsonEncode(v));
}
