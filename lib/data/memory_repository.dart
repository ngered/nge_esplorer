import 'dart:typed_data';

import 'data_repository.dart';
import 'objet.dart';
import 'paquet.dart';
import 'referentiels.dart';

/// Dépôt en mémoire (web) : les données disparaissent au rechargement de la page.
class MemoryRepository implements DataRepository {
  Paquet? _paquet;
  final Map<String, Objet> _objets = {};
  final Map<String, List<double>> _emprises = {};
  final Map<String, Set<String>> _lineairesParNoeud = {};
  final Map<String, Uint8List> _nouveaux = {};

  @override
  bool get ouvert => _paquet != null;

  @override
  Map<String, dynamic>? get entete => _paquet?.entete;

  @override
  Referentiels get referentiels => _paquet?.referentiels ?? Referentiels.vide();

  @override
  Future<void> charger(Paquet paquet) async {
    await fermer();
    _paquet = paquet;
    for (final o in paquet.objets) {
      _indexer(o);
    }
  }

  void _indexer(Objet o) {
    final ancien = _objets[o.id];
    if (ancien != null && ancien.classe == Classe.lin) {
      for (final n in [ancien.noe1, ancien.noe2]) {
        _lineairesParNoeud[n]?.remove(o.id);
      }
    }
    _objets[o.id] = o;
    final e = o.emprise;
    if (e == null) {
      _emprises.remove(o.id);
    } else {
      _emprises[o.id] = e;
    }
    if (o.classe == Classe.lin) {
      for (final n in [o.noe1, o.noe2]) {
        if (n != null) _lineairesParNoeud.putIfAbsent(n, () => {}).add(o.id);
      }
    }
  }

  @override
  Future<void> fermer() async {
    _paquet = null;
    _objets.clear();
    _emprises.clear();
    _lineairesParNoeud.clear();
    _nouveaux.clear();
  }

  @override
  Future<List<Objet>> objetsDansEmprise(List<double> emprise, {Set<Classe> classes = const {Classe.noe, Classe.lin}}) async {
    final res = <Objet>[];
    _emprises.forEach((id, e) {
      if (e[0] > emprise[2] || e[2] < emprise[0] || e[1] > emprise[3] || e[3] < emprise[1]) return;
      final o = _objets[id]!;
      if (classes.contains(o.classe) && !o.abandonne) res.add(o);
    });
    return res;
  }

  @override
  Future<Objet?> objet(String id) async => _objets[id];

  @override
  Future<List<Objet>> rechercher(String texte, {int max = 20}) async {
    final q = texte.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final res = [
      for (final o in _objets.values)
        if (o.classe == Classe.noe && !o.abandonne && (o.lib?.toLowerCase().contains(q) ?? false)) o,
    ]..sort((a, b) {
        final c = a.lib!.length.compareTo(b.lib!.length);
        return c != 0 ? c : a.lib!.compareTo(b.lib!);
      });
    return res.take(max).toList();
  }

  @override
  Future<List<Objet>> lineairesDe(String noeudId) async => [
        for (final id in _lineairesParNoeud[noeudId] ?? const <String>{})
          if (!_objets[id]!.abandonne) _objets[id]!,
      ];

  @override
  Future<void> enregistrer(Objet objet, {required String auteur, bool abandon = false}) async {
    final o = objet.copie();
    final date = Paquet.horodatage();
    final existant = _objets[o.id];
    if (abandon) {
      o.props['DATE_ABD'] = date;
      o.props['SRC_ABD'] = auteur;
      // un objet créé puis abandonné avant tout retour n'a pas à remonter au BE
      o.props['statut'] = existant?.statut == 'C' ? 'C' : 'A';
    } else {
      o.props['statut'] = existant == null || existant.statut == 'C' ? 'C' : 'M';
    }
    if (o.props['statut'] == 'C' && existant == null) o.props['DATE_CREA'] = date;
    o.props['DATE_MODIF'] = date;
    o.props['SRC_MODIF'] = auteur;
    _indexer(o);
  }

  @override
  Future<List<Objet>> modifies() async => [
        for (final o in _objets.values)
          if (o.statut != null && !(o.statut == 'C' && o.abandonne)) o,
      ];

  @override
  Uint8List? fichier(String chemin) => _nouveaux[chemin] ?? _paquet?.fichiers[chemin];

  @override
  Future<void> ajouterFichier(String chemin, Uint8List octets) async => _nouveaux[chemin] = octets;

  @override
  Map<String, Uint8List> get fichiersNouveaux => Map.unmodifiable(_nouveaux);
}
