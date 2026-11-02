/// Référentiels du paquet (`referentiels.json`) : tables `DEF_*` et `MAT_*` par module, gérées au BE seul.
class Referentiels {
  Referentiels(this._tables);

  Referentiels.vide() : _tables = const {};

  final Map<String, dynamic> _tables;
  final Map<String, Map<Object?, Map<String, dynamic>>> _index = {};

  List<Map<String, dynamic>> table(String module, String nom) =>
      [for (final l in (_tables[module]?[nom] as List?) ?? const []) (l as Map).cast<String, dynamic>()];

  /// Ligne d'une table par sa clé (`TYPE_ID`, `MAT_ID`…).
  Map<String, dynamic>? ligne(String module, String nom, String cle, Object? valeur) {
    if (valeur == null) return null;
    final index = _index.putIfAbsent('$module.$nom.$cle', () => {for (final l in table(module, nom)) l[cle]: l});
    return index[valeur];
  }

  // -- accès courants ----------------------------------------------------------------------------

  Map<String, dynamic>? type(int? id) => ligne('noyau', 'DEF_TYPE', 'TYPE_ID', id);

  String libType(int? id) => type(id)?['TYPE_LIB'] as String? ?? 'Type $id';

  /// Code du type racine sous « INF » ou du type lui-même (POT, CHB, FAC…), pour choisir le module.
  String? codeFamille(int? id) {
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

  Map<String, dynamic>? cable(int? matId) => ligne('infra', 'MAT_CABLE', 'MAT_ID', matId);

  Map<String, dynamic>? matPoteau(int? matId) => ligne('poteau', 'MAT_POTEAU', 'MAT_ID', matId);

  String? lib(String module, String nom, String cle, String colLib, Object? valeur) =>
      ligne(module, nom, cle, valeur)?[colLib] as String?;
}
