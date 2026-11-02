import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'objet.dart';
import 'referentiels.dart';

/// Paquet de zone (docs/paquet.md) : en-tête, objets GeoJSON, référentiels et fichiers joints.
class Paquet {
  Paquet({required this.entete, required this.objets, required this.referentiels, this.fichiers = const {}});

  static const format = 'nge-esplorer-paquet';
  static const version = '0.1.0';

  /// Versions majeures des modules que l'application sait lire.
  static const modulesConnus = {'noyau': 0, 'infra': 0, 'chambre': 0, 'poteau': 0};

  final Map<String, dynamic> entete;
  final List<Objet> objets;
  final Referentiels referentiels;
  final Map<String, Uint8List> fichiers;

  String get projet => (entete['projet'] as Map?)?['code'] as String? ?? '?';
  String get zone => (entete['zone'] as Map?)?['code'] as String? ?? '?';
  String get zoneLib => (entete['zone'] as Map?)?['lib'] as String? ?? zone;
  String get date => entete['date'] as String? ?? '';

  /// Emprise [minLon, minLat, maxLon, maxLat] de la zone.
  List<double>? get emprise =>
      ((entete['zone'] as Map?)?['emprise'] as List?)?.map((v) => (v as num).toDouble()).toList();

  /// Lit un paquet de publication ; lève [FormatException] si le paquet est illisible par cette application.
  static Paquet lire(Uint8List zip) {
    final archive = ZipDecoder().decodeBytes(zip);
    Map<String, dynamic> json(String nom) {
      final f = archive.findFile(nom);
      if (f == null) throw FormatException('$nom absent du paquet');
      return jsonDecode(utf8.decode(f.content)) as Map<String, dynamic>;
    }

    final entete = json('paquet.json');
    if (entete['format'] != format) throw FormatException('format inattendu : ${entete['format']}');
    if (_majeure(entete['version']) != _majeure(version)) {
      throw FormatException('version de format ${entete['version']} non prise en charge (attendue $version)');
    }
    final modules = (entete['modules'] as Map? ?? {}).cast<String, dynamic>();
    for (final m in modules.entries) {
      final connue = modulesConnus[m.key];
      if (connue == null) throw FormatException('module inconnu : ${m.key}');
      if (_majeure(m.value) != connue) throw FormatException('module ${m.key} en version ${m.value} non prise en charge');
    }
    final objets = [
      for (final f in (json('objets.geojson')['features'] as List)) Objet.depuisFeature((f as Map).cast()),
    ];
    final fichiers = <String, Uint8List>{
      for (final f in archive.files)
        if (f.isFile && f.name.startsWith('fichiers/')) f.name: f.content,
    };
    return Paquet(entete: entete, objets: objets, referentiels: Referentiels(json('referentiels.json')), fichiers: fichiers);
  }

  /// Paquet de retour : objets modifiés (statut posé), intervention et fichiers nouveaux.
  static Uint8List ecrireRetour({
    required Map<String, dynamic> base,
    required Map<String, dynamic> intervention,
    required List<Objet> objets,
    Map<String, Uint8List> fichiers = const {},
  }) {
    final entete = {
      'format': format,
      'version': version,
      'sens': 'RETOUR',
      'date': horodatage(),
      'base': base['date'],
      'projet': base['projet'],
      'zone': base['zone'],
      'modules': base['modules'],
      'intervention': intervention,
      'effectifs': {
        for (final c in Classe.values) c.code: objets.where((o) => o.classe == c).length,
        'fichiers': fichiers.length,
      },
    };
    final archive = Archive()
      ..addFile(ArchiveFile.string('paquet.json', const JsonEncoder.withIndent(' ').convert(entete)))
      ..addFile(ArchiveFile.string(
          'objets.geojson', jsonEncode({'type': 'FeatureCollection', 'features': [for (final o in objets) o.versFeature()]})));
    for (final f in fichiers.entries) {
      archive.addFile(ArchiveFile.bytes(f.key, f.value));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static int _majeure(Object? v) => int.tryParse('$v'.split('.').first) ?? -1;

  /// Date ISO 8601 UTC à la seconde, comme au BE.
  static String horodatage([DateTime? d]) => '${(d ?? DateTime.now()).toUtc().toIso8601String().split('.').first}Z';
}
