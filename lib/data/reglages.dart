import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Paramètres de l'application conservés sur le terminal. Android : chiffrés par une clé de l'Android Keystore ;
/// web (provisoire, données de test uniquement) : stockage du navigateur. Un échec de lecture ou d'écriture laisse
/// les valeurs par défaut.
class Reglages {
  static const _stockage = FlutterSecureStorage();

  static const cleGoogle = 'cle_google_map_tiles';
  static const annulerTuiles = 'annuler_tuiles_obsoletes';

  Future<String?> lire(String nom) async {
    try {
      return await _stockage.read(key: nom);
    } catch (_) {
      return null;
    }
  }

  /// Valeur vide ou nulle : le paramètre est retiré.
  Future<void> ecrire(String nom, String? valeur) async {
    try {
      if (valeur == null || valeur.isEmpty) {
        await _stockage.delete(key: nom);
      } else {
        await _stockage.write(key: nom, value: valeur);
      }
    } catch (_) {
      // paramètre non conservé : il vaut pour la session en cours
    }
  }
}
