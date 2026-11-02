import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../carte/geo.dart';
import '../../data/data_repository.dart';
import '../../data/objet.dart';

/// Types de linéaires portés par la rosace (manifeste infra).
const typePorteeAerienne = 1002;
const typeParcoursFacade = 1003;

/// Types de nœuds proposés pour une destination nouvelle.
const typesDestination = {14: 'Poteau télécom', 15: 'Poteau BT', 30: 'Ancrage façade', 999: 'Autre point'};

/// Une portée vue depuis le poteau : le linéaire (copie en cours d'édition) et le côté du poteau.
class PorteeAuPoteau {
  PorteeAuPoteau(this.lineaire, {required this.premier, this.destination});

  final Objet lineaire;

  /// Le poteau est l'extrémité `NOE1_KEY` du linéaire.
  final bool premier;
  Objet? destination;
  bool modifiee = false;
  bool abandonnee = false;

  String get id => lineaire.id;
  String? get destinationId => premier ? lineaire.noe2 : lineaire.noe1;
  String get colAngle => premier ? 'PRT_ANG1' : 'PRT_ANG2';
  String get colAngleOppose => premier ? 'PRT_ANG2' : 'PRT_ANG1';

  Map<String, dynamic> get portee => lineaire.espace('inf', creer: true)!.putIfAbsent('portee', () => <String, dynamic>{})
      as Map<String, dynamic>;

  /// Angle relevé au poteau (grades) ; à défaut, azimut du premier segment de la géométrie.
  double? get angleReleve => (portee[colAngle] as num?)?.toDouble();

  double get angle => angleReleve ?? angleCarto ?? 0;

  double? get angleCarto {
    final pts = lineaire.ligne;
    if (pts.length < 2) return null;
    return premier ? Geo.azimutGrades(pts[0], pts[1]) : Geo.azimutGrades(pts.last, pts[pts.length - 2]);
  }

  List<Map<String, dynamic>> get cables {
    final l = portee.putIfAbsent('cables', () => <dynamic>[]) as List;
    for (var i = 0; i < l.length; i++) {
      if (l[i] is! Map<String, dynamic>) l[i] = (l[i] as Map).cast<String, dynamic>();
    }
    return l.cast<Map<String, dynamic>>();
  }

  String get libelleDestination => destination?.lib ?? destinationId ?? '?';
}

/// Session d'édition de la rosace d'un poteau : rien n'est écrit dans le dépôt avant [valider].
class RosaceEdition extends ChangeNotifier {
  RosaceEdition(this.repo, this.poteau, {required this.auteur});

  final DataRepository repo;
  final Objet poteau;
  final String auteur;
  final List<PorteeAuPoteau> portees = [];

  /// Nœuds de destination créés pendant la session (position provisoire, à relever).
  final Map<String, Objet> nouveauxNoeuds = {};
  PorteeAuPoteau? selection;
  bool charge = false;

  bool get modifiee => portees.any((p) => p.modifiee || p.abandonnee);

  Iterable<PorteeAuPoteau> get visibles => portees.where((p) => !p.abandonnee);

  Future<void> charger() async {
    for (final l in await repo.lineairesDe(poteau.id)) {
      if (l.typeKey != typePorteeAerienne && l.typeKey != typeParcoursFacade) continue;
      final p = PorteeAuPoteau(l.copie(), premier: l.noe1 == poteau.id);
      p.destination = await repo.objet(p.destinationId ?? '');
      portees.add(p);
    }
    portees.sort((a, b) => a.angle.compareTo(b.angle));
    charge = true;
    notifyListeners();
  }

  void selectionner(PorteeAuPoteau? p) {
    selection = p;
    notifyListeners();
  }

  /// Oriente la portée ; une destination créée pendant la session suit l'aiguille.
  void orienter(PorteeAuPoteau p, double grades) {
    final a = (Geo.normaliser(grades) * 10).roundToDouble() / 10;
    p.portee[p.colAngle] = a >= 400 ? 0.0 : a;
    p.modifiee = true;
    final dest = nouveauxNoeuds[p.destinationId];
    final origine = poteau.point;
    if (dest != null && origine != null) {
      final lng = (p.portee['PRT_LNG'] as num?)?.toDouble() ?? 30;
      final pos = Geo.destination(origine, a, lng);
      dest.geometry = Objet.geoPoint(pos);
      p.lineaire.geometry = Objet.geoLigne(p.premier ? [origine, pos] : [pos, origine]);
      p.portee[p.colAngleOppose] = Geo.normaliser(a + 200);
    }
    notifyListeners();
  }

  void poserLongueur(PorteeAuPoteau p, double? metres) {
    Objet.poser(p.portee, 'PRT_LNG', metres);
    p.modifiee = true;
    if (nouveauxNoeuds.containsKey(p.destinationId)) orienter(p, p.angle);
    notifyListeners();
  }

  /// Nœuds proches non encore reliés au poteau, triés par distance, pour choisir une destination.
  Future<List<(Objet, double)>> destinationsProches({double rayon = 150}) async {
    final c = poteau.point;
    if (c == null) return [];
    final hautBas = rayon / 111320;
    final gaucheDroite = hautBas / 0.7;
    final dejaReliees = {for (final p in visibles) p.destinationId};
    final res = <(Objet, double)>[];
    for (final o in await repo.objetsDansEmprise(
        [c.longitude - gaucheDroite, c.latitude - hautBas, c.longitude + gaucheDroite, c.latitude + hautBas],
        classes: {Classe.noe})) {
      if (o.id == poteau.id || dejaReliees.contains(o.id) || o.point == null) continue;
      final d = Geo.distance(c, o.point!);
      if (d <= rayon) res.add((o, d));
    }
    res.sort((a, b) => a.$2.compareTo(b.$2));
    return res;
  }

  /// Ajoute une portée vers un nœud existant (angle prérempli par la géométrie) ou vers un nœud nouveau.
  PorteeAuPoteau ajouter({Objet? existant, int? typeNouveau, String? libNouveau, double angle = 0}) {
    final origine = poteau.point!;
    Objet dest;
    if (existant != null) {
      dest = existant;
    } else {
      dest = Objet(id: const Uuid().v4(), classe: Classe.noe, geometry: Objet.geoPoint(Geo.destination(origine, angle, 30)));
      dest.props.addAll({
        'TYPE_KEY': typeNouveau ?? 999,
        if (poteau.props['ZONE_KEY'] != null) 'ZONE_KEY': poteau.props['ZONE_KEY'],
        'GEOL_MOD_KEY': 8, // indéterminé : position à relever
        'NOE_COMMENT': 'Créé depuis la rosace de ${poteau.lib ?? poteau.id} : position à relever',
      });
      Objet.poser(dest.props, 'NOE_LIB', libNouveau);
      nouveauxNoeuds[dest.id] = dest;
    }
    final fin = dest.point!;
    final lin = Objet(id: const Uuid().v4(), classe: Classe.lin, geometry: Objet.geoLigne([origine, fin]));
    final az = existant != null ? Geo.azimutGrades(origine, fin) : angle;
    lin.props.addAll({
      'TYPE_KEY': typePorteeAerienne,
      'IMPL_KEY': poteau.typeKey == 15 ? 1 : 0, // aérien énergie depuis un poteau BT, sinon aérien télécom
      'NOE1_KEY': poteau.id,
      'NOE2_KEY': dest.id,
      if (poteau.props['ZONE_KEY'] != null) 'ZONE_KEY': poteau.props['ZONE_KEY'],
      'inf': <String, dynamic>{
        'portee': <String, dynamic>{
          'PRT_ANG1': (az * 10).roundToDouble() / 10,
          'PRT_ANG2': Geo.normaliser(az + 200),
          'cables': <dynamic>[],
        },
      },
    });
    final p = PorteeAuPoteau(lin, premier: true, destination: dest)..modifiee = true;
    portees.add(p);
    selection = p;
    notifyListeners();
    return p;
  }

  void abandonner(PorteeAuPoteau p) {
    p.abandonnee = true;
    if (selection == p) selection = null;
    notifyListeners();
  }

  /// Ajoute ou remplace un câble porté (identifié par son rang).
  void poserCable(PorteeAuPoteau p, Map<String, dynamic> cable) {
    final l = p.cables;
    final i = l.indexWhere((c) => c['PCB_RANG'] == cable['PCB_RANG']);
    if (i >= 0) {
      l[i] = cable;
    } else {
      l.add(cable);
    }
    p.modifiee = true;
    notifyListeners();
  }

  void retirerCable(PorteeAuPoteau p, int rang) {
    p.cables.removeWhere((c) => c['PCB_RANG'] == rang);
    p.modifiee = true;
    notifyListeners();
  }

  int rangSuivant(PorteeAuPoteau p) =>
      p.cables.fold<int>(0, (m, c) => (c['PCB_RANG'] as int? ?? 0) > m ? c['PCB_RANG'] as int : m) + 1;

  /// Écrit les linéaires modifiés et les nœuds créés dans le dépôt.
  Future<void> valider() async {
    for (final p in portees) {
      final nouveau = nouveauxNoeuds[p.destinationId];
      if (p.abandonnee) {
        if (await repo.objet(p.id) != null) await repo.enregistrer(p.lineaire, auteur: auteur, abandon: true);
        continue;
      }
      if (!p.modifiee) continue;
      if (nouveau != null) await repo.enregistrer(nouveau, auteur: auteur);
      await repo.enregistrer(p.lineaire, auteur: auteur);
    }
    for (final p in portees) {
      p.modifiee = false;
    }
    notifyListeners();
  }
}
