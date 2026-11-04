// Extraction des textes à traduire du terminal vers les catalogues assets/lang/<code>.json (lib/lng.dart), comme
// lng_extract.py de FibReady.
//
// Textes relevés dans lib/ :
//   - premier argument littéral de tr(…), deuxième et troisième de trn(…) (littéraux adjacents concaténés) ;
//   - lignes marquées `// tr` (énumérations, tables const) : les littéraux qui ressemblent à du texte (espace,
//     lettre accentuée ou majuscule suivie de minuscules), pas les codes ni les chemins.
//
// Les traductions déjà saisies sont conservées ; les nouveaux textes sont ajoutés avec une traduction vide (qui
// retombe sur le français). Les clés qui ne sont plus trouvées dans les sources sont signalées, et retirées avec
// --prune.
//
// Usage (depuis la racine du projet) :
//   o:\flutter\sdk\flutter\bin\dart.bat run tools/lang/lng_extract.dart [--lang en] [--prune] [--list-empty]
import 'dart:convert';
import 'dart:io';

/// Langues traduites (le français est la langue des sources, sans catalogue).
const targetLanguages = ['en', 'es', 'pt', 'de'];

const catalogDir = 'assets/lang';

const _comment = 'Catalogue {0} de NgeEsPlorer (lib/lng.dart) : clé = texte français du code source, valeur = '
    'traduction. Mis à jour par tools/lang/lng_extract.dart ; une valeur vide retombe sur le français.';

const _names = {'en': 'anglais', 'es': 'espagnol', 'pt': 'portugais', 'de': 'allemand'};

void main(List<String> args) {
  String? only;
  final prune = args.contains('--prune');
  final listEmpty = args.contains('--list-empty');
  final i = args.indexOf('--lang');
  if (i >= 0 && i + 1 < args.length) only = args[i + 1];

  final texts = extractTexts(Directory('lib'));
  stdout.writeln('${texts.length} textes dans les sources');
  for (final code in only == null ? targetLanguages : [only]) {
    final file = File('$catalogDir/$code.json');
    final catalog = file.existsSync() ? readCatalog(file) : <String, String>{};
    final added = texts.where((t) => !catalog.containsKey(t)).toList();
    final obsolete = catalog.keys.where((k) => !texts.contains(k)).toList();
    for (final t in added) {
      catalog[t] = '';
    }
    if (prune) {
      obsolete.forEach(catalog.remove);
    }
    writeCatalog(file, code, catalog);
    final empty = catalog.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
    stdout.writeln('$code : ${added.length} ajouté(s), ${obsolete.length} obsolète(s)${prune ? ' retiré(s)' : ''}, '
        '${empty.length} sans traduction');
    if (!prune) {
      for (final k in obsolete) {
        stdout.writeln('  obsolète : $k');
      }
    }
    if (listEmpty) {
      for (final k in empty) {
        stdout.writeln('  à traduire : $k');
      }
    }
  }
}

/// Lit un catalogue (sans les clés de commentaire `_…`).
Map<String, String> readCatalog(File file) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('_')) e.key: '${e.value}',
  };
}

void writeCatalog(File file, String code, Map<String, String> catalog) {
  final keys = catalog.keys.toList()..sort();
  final out = <String, String>{
    '_comment': _comment.replaceFirst('{0}', _names[code] ?? code),
    for (final k in keys) k: catalog[k]!,
  };
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
}

/// Textes à traduire des sources Dart d'un dossier, triés.
Set<String> extractTexts(Directory dir) {
  final texts = <String>{};
  for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    if (f.path.replaceAll('\\', '/').endsWith('lib/lng.dart')) continue;
    texts.addAll(extractFromSource(f.readAsStringSync()));
  }
  return texts;
}

final _call = RegExp(r'(?<![\w.$])(trn?)\(');
final _text = RegExp(r"\s|[À-ÿŒœ]|^[A-ZÀ-Ý][a-zà-ÿ]");

/// Textes d'une source : arguments littéraux de tr / trn et littéraux des lignes marquées `// tr`.
List<String> extractFromSource(String src) {
  final out = <String>[];
  for (final m in _call.allMatches(src)) {
    var pos = m.end;
    final count = m.group(1) == 'trn' ? 3 : 1;
    for (var arg = 0; arg < count; arg++) {
      final lit = _readArgument(src, pos);
      if (lit == null) break;
      if (m.group(1) == 'tr' || arg > 0) out.add(lit.$1);
      pos = lit.$2;
    }
  }
  for (final line in const LineSplitter().convert(src)) {
    if (!RegExp(r'//\s*tr\s*$').hasMatch(line)) continue;
    var pos = 0;
    final code = line.substring(0, line.lastIndexOf('//'));
    while (true) {
      final q = code.indexOf(RegExp("['\"]"), pos);
      if (q < 0) break;
      final lit = _readLiterals(code, q);
      if (lit == null) break;
      if (_text.hasMatch(lit.$1) && !lit.$1.contains('/')) out.add(lit.$1);
      pos = lit.$2;
    }
  }
  return out;
}

/// Argument à partir de [pos] : (texte, position après la virgule ou la parenthèse) s'il est fait de littéraux
/// sans interpolation, sinon null (argument calculé, à la charge du code appelant).
(String, int)? _readArgument(String src, int pos) {
  // trn : le premier argument est le nombre, sauter jusqu'à la virgule de premier niveau
  var i = _skipSpace(src, pos);
  if (i >= src.length) return null;
  if (src[i] != "'" && src[i] != '"') {
    var depth = 0;
    for (; i < src.length; i++) {
      final c = src[i];
      if ('([{'.contains(c)) depth++;
      if (')]}'.contains(c)) {
        if (depth == 0) return null;
        depth--;
      }
      if (c == ',' && depth == 0) return ('', i + 1);
      if (c == "'" || c == '"') {
        final l = _readLiterals(src, i);
        if (l == null) return null;
        i = l.$2 - 1;
      }
    }
    return null;
  }
  final lit = _readLiterals(src, i);
  if (lit == null) return null;
  final j = _skipSpace(src, lit.$2);
  return (lit.$1, j < src.length && src[j] == ',' ? j + 1 : j);
}

int _skipSpace(String s, int i) {
  while (i < s.length && ' \t\r\n'.contains(s[i])) {
    i++;
  }
  return i;
}

/// Littéraux adjacents à partir de [start] : (texte concaténé, position après), null s'il y a une interpolation.
(String, int)? _readLiterals(String src, int start) {
  final buf = StringBuffer();
  var i = start;
  var any = false;
  while (true) {
    i = _skipSpace(src, i);
    if (i >= src.length || (src[i] != "'" && src[i] != '"')) break;
    final q = src[i];
    i++;
    while (i < src.length && src[i] != q) {
      final c = src[i];
      if (c == r'$') return null;
      if (c == '\\' && i + 1 < src.length) {
        final n = src[i + 1];
        buf.write(switch (n) { 'n' => '\n', 't' => '\t', _ => n });
        i += 2;
        continue;
      }
      buf.write(c);
      i++;
    }
    i++;
    any = true;
  }
  return any ? (buf.toString(), i) : null;
}
