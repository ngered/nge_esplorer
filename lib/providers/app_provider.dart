import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/data_repository.dart';
import '../data/objet.dart';
import '../data/paquet.dart';
import '../data/referentiels.dart';
import '../data/reglages.dart';
import '../data/visuels.dart';
import '../modules/renseignement.dart';
import 'sortie_page.dart' if (dart.library.js_interop) 'sortie_page_web.dart';

/// État de la session terrain : paquet chargé, compte, intervention en cours.
class AppProvider extends ChangeNotifier {
  AppProvider(this.repo, {this.reglages});

  final DataRepository repo;

  /// Paramètres conservés sur le terminal (absents dans les tests).
  final Reglages? reglages;

  /// Compte abonné (provisoire : saisi tant que la connexion par jeton n'existe pas).
  String auteur = 'terrain';
  String? erreur;
  bool chargement = false;

  /// Option : annuler le téléchargement des tuiles qui ne seront plus affichées (désactivée par défaut).
  bool annulerTuilesObsoletes = false;

  /// Clé Google Map Tiles renseignée par l'utilisateur, sous sa responsabilité (vide : pas de fonds Google).
  String cleGoogle = '';
  int nbModifies = 0;

  /// Le retour a été exporté depuis la dernière modification.
  bool _exporte = false;

  /// Modifications qui seraient perdues sans export (web : données en mémoire seulement).
  bool get aExporter => nbModifies > 0 && !_exporte;

  /// Incrémenté à chaque écriture : la carte recharge les objets visibles.
  int revision = 0;

  /// Incrémenté à chaque paquet chargé : la carte se cadre sur l'emprise de la zone.
  int paquets = 0;

  String? _intervention;
  String? _debut;

  bool get ouvert => repo.ouvert;
  Map<String, dynamic>? get entete => repo.entete;
  Referentiels get referentiels => repo.referentiels;

  String get titre {
    final e = entete;
    if (e == null) return 'NgeEsPlorer';
    return '${(e['zone'] as Map?)?['lib'] ?? (e['zone'] as Map?)?['code']}';
  }

  /// Emprise de la zone [minLon, minLat, maxLon, maxLat].
  List<double>? get emprise =>
      ((entete?['zone'] as Map?)?['emprise'] as List?)?.map((v) => (v as num).toDouble()).toList();

  Future<void> chargerPaquet(Uint8List zip) async {
    chargement = true;
    erreur = null;
    notifyListeners();
    try {
      await repo.charger(Paquet.lire(zip));
      _intervention = null;
      _debut = null;
      nbModifies = 0;
      _exporte = false;
      avertirAvantSortie(aExporter);
      revision++;
      paquets++;
    } on FormatException catch (e) {
      erreur = 'Paquet illisible : ${e.message}';
    } catch (e) {
      erreur = 'Paquet illisible : $e';
    } finally {
      chargement = false;
      notifyListeners();
    }
  }

  void definirAuteur(String nom) {
    auteur = nom.trim().isEmpty ? 'terrain' : nom.trim();
    notifyListeners();
  }

  Future<void> chargerReglages() async {
    final r = reglages;
    if (r == null) return;
    cleGoogle = await r.lire(Reglages.cleGoogle) ?? '';
    annulerTuilesObsoletes = await r.lire(Reglages.annulerTuiles) == 'oui';
    notifyListeners();
  }

  void definirAnnulationTuiles(bool active) {
    annulerTuilesObsoletes = active;
    reglages?.ecrire(Reglages.annulerTuiles, active ? 'oui' : null);
    notifyListeners();
  }

  void definirCleGoogle(String cle) {
    cleGoogle = cle.trim();
    reglages?.ecrire(Reglages.cleGoogle, cleGoogle);
    notifyListeners();
  }

  /// À appeler après toute écriture dans le dépôt (l'intervention commence à la première).
  Future<void> apresEcriture() async {
    _intervention ??= const Uuid().v4();
    _debut ??= Paquet.horodatage();
    nbModifies = (await repo.modifies()).length;
    _exporte = false;
    avertirAvantSortie(aExporter);
    revision++;
    notifyListeners();
  }

  /// À appeler une fois le paquet de retour enregistré.
  void marquerExporte() {
    _exporte = true;
    avertirAvantSortie(aExporter);
    notifyListeners();
  }

  Future<void> enregistrer(Objet o, {bool abandon = false}) async {
    if (!abandon) await poserNiveau(o, referentiels, repo);
    await repo.enregistrer(o, auteur: auteur, abandon: abandon);
    await apresEcriture();
  }

  /// Ajoute une photo prise sur le terminal au visuel [v] de [o] (copie de travail) et enregistre l'objet.
  Future<void> ajouterPhoto(Objet o, Visuel v, {required String nom, required Uint8List octets}) async {
    final f = o.ajouterPhoto(v, nom: nom, taille: octets.length, auteur: auteur);
    await repo.ajouterFichier(f['fichier'] as String, octets);
    await enregistrer(o);
  }

  /// Paquet de retour (objets modifiés, intervention, photos prises sur le terminal) et son nom de fichier.
  Future<(String, Uint8List)> paquetRetour() async {
    final e = entete!;
    final objets = await repo.modifies();
    final activites = <String>{
      for (final o in objets) ...[
        if (o.props.containsKey('pot') || o.espace('inf')?['portee'] != null) 'RELEVE_POT',
        if (o.props.containsKey('chb') || o.espace('inf')?['conduites'] != null) 'RELEVE_CHB',
      ],
    };
    final date = Paquet.horodatage();
    final intervention = {
      'INT_CODE_EXT': _intervention ?? const Uuid().v4(),
      'ACT_CODE': activites.isEmpty ? 'RELEVE' : (activites.toList()..sort()).join(','),
      'INT_AUTEUR': auteur,
      'INT_TERMINAL': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'DATE_DEBUT': _debut ?? date,
      'DATE_FIN': date,
    };
    // photos prises sur le terminal et toujours rattachées à un objet du retour
    final references = {
      for (final o in objets)
        for (final f in o.fichiers)
          if (f['DATE_ABD'] == null) f['fichier'],
    };
    final fichiers = {
      for (final f in repo.fichiersNouveaux.entries)
        if (references.contains(f.key)) f.key: f.value,
    };
    final zip = Paquet.ecrireRetour(base: e, intervention: intervention, objets: objets, fichiers: fichiers);
    final nom = '${(e['projet'] as Map?)?['code']}_${(e['zone'] as Map?)?['code']}_RETOUR_'
        '${date.replaceAll(RegExp(r'[-:]'), '').substring(0, 13)}.zip';
    return (nom, zip);
  }
}
