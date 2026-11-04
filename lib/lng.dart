import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Traduction de l'interface, comme CommonTools.Lng de FibReady. Le texte français du code source sert de clé :
/// [tr] le cherche dans le catalogue de la langue active et le rend tel quel s'il n'y figure pas (le français est la
/// langue d'origine, sans catalogue). Les catalogues sont des fichiers JSON plats « français : traduction » rangés
/// dans `assets/lang/` et tenus à jour par `tools/lang/lng_extract.dart`.
///
/// Ne passent pas par [tr] : les textes écrits dans les données ou le paquet de retour (restent en français, comme
/// les exports de FibReady), les libellés des référentiels (fournis par le BE), les noms propres et les clés.
/// Un texte constant (énumération, table `const`) porte la marque `// tr` en fin de ligne pour l'extraction et
/// n'est traduit qu'à l'affichage.
abstract final class Lng {
  /// Langue d'origine des textes du code source.
  static const sourceLanguage = 'fr';

  /// Langues proposées, avec leur nom dans leur langue (pas d'arabe : écriture de droite à gauche, comme FibReady).
  static const languages = {
    'fr': 'Français',
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
    'de': 'Deutsch',
  };

  static String _language = sourceLanguage;
  static Map<String, String> _catalog = const {};

  /// Langue active (code ISO à deux lettres).
  static String get language => _language;

  /// Charge le catalogue d'une langue. Une langue inconnue ou sans catalogue retombe sur la langue d'origine.
  static Future<void> load(String? language, {AssetBundle? bundle}) async {
    final code = language?.trim().toLowerCase() ?? sourceLanguage;
    var catalog = const <String, String>{};
    var active = sourceLanguage;
    if (code != sourceLanguage && languages.containsKey(code)) {
      try {
        final json = jsonDecode(await (bundle ?? rootBundle).loadString('assets/lang/$code.json')) as Map;
        catalog = {
          for (final e in json.entries)
            if (!'${e.key}'.startsWith('_') && '${e.value}'.isNotEmpty) '${e.key}': '${e.value}',
        };
        active = code;
      } catch (_) {
        // catalogue absent ou illisible : interface en français
      }
    }
    _catalog = catalog;
    _language = active;
  }

  /// Fait reconstruire tous les écrans après un changement de langue (les textes sont traduits au build).
  static void rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }

  static String _translate(String text) => _catalog[text] ?? text;
}

/// Traduit un texte français ; `{0}`, `{1}`… sont remplacés par [args].
String tr(String text, [List<Object?> args = const []]) => _format(Lng._translate(text), args);

/// Traduit selon le nombre [n] : le singulier [one] (traduit comme clé) vaut en français pour 0 et 1, dans les
/// autres langues pour 1 seulement ; le pluriel [many] sinon. `{0}` vaut [n], `{1}`… [args].
String trn(num n, String one, String many, [List<Object?> args = const []]) {
  final singular = Lng._language == Lng.sourceLanguage ? n.abs() < 2 : n == 1;
  return _format(Lng._translate(singular ? one : many), [n, ...args]);
}

String _format(String text, List<Object?> args) {
  if (args.isEmpty) return text;
  return text.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
    final i = int.parse(m.group(1)!);
    return i < args.length ? '${args[i] ?? ''}' : m.group(0)!;
  });
}
