import '../lng.dart';

/// Référentiels du paquet (`referentiels.json`) : tables `DEF_*` et `MAT_*` par module, gérées au BE seul.
class ReferenceData {
  ReferenceData(this._tables);

  ReferenceData.empty() : _tables = const {};

  final Map<String, dynamic> _tables;
  final Map<String, Map<Object?, Map<String, dynamic>>> _index = {};

  List<Map<String, dynamic>> table(String module, String name) =>
      [for (final l in (_tables[module]?[name] as List?) ?? const []) (l as Map).cast<String, dynamic>()];

  /// Ligne d'une table par sa clé (`TYPE_ID`, `MAT_ID`…).
  Map<String, dynamic>? row(String module, String name, String column, Object? value) {
    if (value == null) return null;
    final index = _index.putIfAbsent('$module.$name.$column', () => {for (final l in table(module, name)) l[column]: l});
    return index[value];
  }

  // -- accès courants ----------------------------------------------------------------------------

  Map<String, dynamic>? type(int? id) => row('noyau', 'DEF_TYPE', 'TYPE_ID', id);

  String typeLabel(int? id) => type(id)?['TYPE_LIB'] as String? ?? tr('Type {0}', [id]);

  /// Code du type racine sous « INF » ou du type lui-même (POT, CHB, FAC…), pour choisir le module.
  String? familyCode(int? id) {
    var t = type(id);
    while (t != null) {
      final parent = type(t['TYPE_PARENT_KEY'] as int?);
      if (parent == null || parent['TYPE_CODE'] == 'INF' || parent['TYPE_CODE'] == 'LIN') {
        return t['TYPE_CODE'] as String?;
      }
      t = parent;
    }
    return null;
  }

  Map<String, dynamic>? cable(int? matId) => row('infra', 'MAT_CABLE', 'MAT_ID', matId);

  Map<String, dynamic>? poleMat(int? matId) => row('poteau', 'MAT_POTEAU', 'MAT_ID', matId);

  String? lib(String module, String name, String column, String colLabel, Object? value) =>
      row(module, name, column, value)?[colLabel] as String?;
}
