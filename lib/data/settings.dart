import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Paramètres de l'application conservés sur le terminal. Android : chiffrés par une clé de l'Android Keystore ;
/// web (provisoire, données de test uniquement) : stockage du navigateur. Un échec de lecture ou d'écriture laisse
/// les valeurs par défaut.
class Settings {
  static const _storage = FlutterSecureStorage();

  static const googleKey = 'cle_google_map_tiles';
  static const cancelStaleTiles = 'annuler_tuiles_obsoletes';
  static const useLocalPhotoServer = 'photos_serveur_local';
  static const language = 'langue';
  static const animateLocate = 'reperage_anime';
  static const locateRadius = 'rayon_reperage';

  Future<String?> read(String name) async {
    try {
      return await _storage.read(key: name);
    } catch (_) {
      return null;
    }
  }

  /// Valeur vide ou nulle : le paramètre est retiré.
  Future<void> write(String name, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: name);
      } else {
        await _storage.write(key: name, value: value);
      }
    } catch (_) {
      // paramètre non conservé : il vaut pour la session en cours
    }
  }
}
