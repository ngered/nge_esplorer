import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../lng.dart';
import 'geo_object.dart';
import 'reference_data.dart';

/// Paquet de zone (docs/paquet.md) : en-tête, objets GeoJSON, référentiels et fichiers joints.
class Bundle {
  Bundle({required this.header, required this.objects, required this.referenceData, this.files = const {}});

  static const format = 'nge-esplorer-paquet';
  static const version = '0.1.0';

  /// Versions majeures des modules que l'application sait lire.
  static const knownModules = {'noyau': 0, 'infra': 0, 'chambre': 0, 'poteau': 0};

  final Map<String, dynamic> header;
  final List<GeoObject> objects;
  final ReferenceData referenceData;
  final Map<String, Uint8List> files;

  String get project => (header['projet'] as Map?)?['code'] as String? ?? '?';
  String get zone => (header['zone'] as Map?)?['code'] as String? ?? '?';
  String get zoneLib => (header['zone'] as Map?)?['lib'] as String? ?? zone;
  String get date => header['date'] as String? ?? '';

  /// Emprise [minLon, minLat, maxLon, maxLat] de la zone.
  List<double>? get bounds =>
      ((header['zone'] as Map?)?['emprise'] as List?)?.map((v) => (v as num).toDouble()).toList();

  /// Lit un paquet de publication ; lève [FormatException] si le paquet est illisible par cette application.
  static Bundle read(Uint8List zip) {
    final archive = ZipDecoder().decodeBytes(zip);
    Map<String, dynamic> json(String name) {
      final f = archive.findFile(name);
      if (f == null) throw FormatException(tr('{0} absent du paquet', [name]));
      return jsonDecode(utf8.decode(f.content)) as Map<String, dynamic>;
    }

    final header = json('paquet.json');
    if (header['format'] != format) throw FormatException(tr('format inattendu : {0}', [header['format']]));
    if (_major(header['version']) != _major(version)) {
      throw FormatException(tr('version de format {0} non prise en charge (attendue {1})', [header['version'], version]));
    }
    final modules = (header['modules'] as Map? ?? {}).cast<String, dynamic>();
    for (final m in modules.entries) {
      final known = knownModules[m.key];
      if (known == null) throw FormatException(tr('module inconnu : {0}', [m.key]));
      if (_major(m.value) != known) throw FormatException(tr('module {0} en version {1} non prise en charge', [m.key, m.value]));
    }
    final objects = [
      for (final f in (json('objets.geojson')['features'] as List)) GeoObject.fromFeature((f as Map).cast()),
    ];
    final files = <String, Uint8List>{
      for (final f in archive.files)
        if (f.isFile && f.name.startsWith('fichiers/')) f.name: f.content,
    };
    return Bundle(header: header, objects: objects, referenceData: ReferenceData(json('referentiels.json')), files: files);
  }

  /// Paquet de retour : objets modifiés (statut posé), intervention et fichiers nouveaux.
  static Uint8List writeReturn({
    required Map<String, dynamic> base,
    required Map<String, dynamic> intervention,
    required List<GeoObject> objects,
    Map<String, Uint8List> files = const {},
  }) {
    final header = {
      'format': format,
      'version': version,
      'sens': 'RETOUR',
      'date': timestamp(),
      'base': base['date'],
      'projet': base['projet'],
      'zone': base['zone'],
      'modules': base['modules'],
      'intervention': intervention,
      'effectifs': {
        for (final c in ObjectClass.values) c.code: objects.where((o) => o.objectClass == c).length,
        'fichiers': files.length,
      },
    };
    final archive = Archive()
      ..addFile(ArchiveFile.string('paquet.json', const JsonEncoder.withIndent(' ').convert(header)))
      ..addFile(ArchiveFile.string(
          'objets.geojson', jsonEncode({'type': 'FeatureCollection', 'features': [for (final o in objects) o.toFeature()]})));
    for (final f in files.entries) {
      archive.addFile(ArchiveFile.bytes(f.key, f.value));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static int _major(Object? v) => int.tryParse('$v'.split('.').first) ?? -1;

  /// Date ISO 8601 UTC à la seconde, comme au BE.
  static String timestamp([DateTime? d]) => '${(d ?? DateTime.now()).toUtc().toIso8601String().split('.').first}Z';
}
