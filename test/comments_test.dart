import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/bundle.dart';
import 'package:nge_esplorer/data/geo_object.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/data/reference_data.dart';
import 'package:nge_esplorer/modules/poteau/pole_sheet.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/map_screen.dart' show exportReturn;
import 'package:nge_esplorer/screens/object_screen.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
import 'package:nge_esplorer/widgets/comments.dart';
import 'package:nge_esplorer/widgets/fields.dart';
import 'package:provider/provider.dart';

/// Journal publié par le BE, du plus ancien au plus récent : texte repris d'un import FOA Explorer, puis alerte
/// d'un autre technicien.
List<Map<String, dynamic>> published() => [
      {
        'COM_CODE_EXT': 'K1',
        'COM_TYPE': 'standard',
        'COM_TEXTE': 'Appui commun ERDF',
        'COM_AUTEUR': 'FOA',
        'COM_ORIGINE': 'FOA',
        'DATE_CREA': '2024-05-02T08:00:00Z',
      },
      {
        'COM_CODE_EXT': 'K2',
        'COM_TYPE': 'alert',
        'COM_TEXTE': 'Poteau penché vers la chaussée',
        'COM_AUTEUR': 'Paul Martin',
        'INT_CODE_EXT': 'I0',
        'DATE_CREA': '2026-10-20T09:00:00Z',
      },
    ];

const tables = <String, dynamic>{
  'noyau': {
    'DEF_TYPE': [
      {'TYPE_ID': 3, 'TYPE_CODE': 'INF', 'TYPE_LIB': 'Support'},
      {'TYPE_ID': 13, 'TYPE_CODE': 'POT', 'TYPE_LIB': 'Poteau', 'TYPE_PARENT_KEY': 3},
      {'TYPE_ID': 14, 'TYPE_CODE': 'POT-FT', 'TYPE_LIB': 'Poteau télécom', 'TYPE_PARENT_KEY': 13},
    ],
  },
};

/// Paquet d'essai : un poteau et son journal.
Bundle bundle() => Bundle(
      header: {
        'format': Bundle.format,
        'version': Bundle.version,
        'sens': 'PUBLICATION',
        'date': '2026-11-04T08:00:00Z',
        'projet': {'code': 'TEST'},
        'zone': {'code': 'Z1', 'lib': 'Zone 1', 'emprise': [2.0, 45.0, 2.01, 45.01]},
        'modules': {'noyau': '0.2.0', 'poteau': '0.2.0'},
      },
      objects: [
        GeoObject.fromFeature({
          'type': 'Feature',
          'id': 'P1',
          'geometry': {'type': 'Point', 'coordinates': [2.0, 45.0]},
          'properties': {'classe': 'NOE', 'NOE_LIB': 'P922', 'TYPE_KEY': 14, 'commentaires': published()},
        }),
      ],
      referenceData: ReferenceData(tables),
    );

/// Le paquet d'essai en ZIP, comme le publie le BE.
Uint8List zip(Bundle b) => ZipEncoder().encodeBytes(Archive()
  ..addFile(ArchiveFile.string('paquet.json', jsonEncode(b.header)))
  ..addFile(ArchiveFile.string(
      'objets.geojson', jsonEncode({'type': 'FeatureCollection', 'features': [for (final o in b.objects) o.toFeature()]})))
  ..addFile(ArchiveFile.string('referentiels.json', jsonEncode(tables))));

List<Object?> codes(GeoObject o) => [for (final c in o.comments) c['COM_CODE_EXT']];

/// Date-heure locale affichée dans le journal.
String local(String iso) {
  final d = DateTime.parse(iso).toLocal();
  String n(int v) => v.toString().padLeft(2, '0');
  return '${n(d.day)}/${n(d.month)}/${d.year} ${n(d.hour)}:${n(d.minute)}';
}

/// Sélecteur de fichiers factice : l'enregistrement rend [saved], comme file_picker. Web : toujours null, le ZIP
/// étant téléchargé ; ailleurs, null quand le sélecteur est fermé sans enregistrer.
class SavePicker extends FilePickerPlatform {
  SavePicker(this.saved);

  final Uri? saved;

  /// Noms des fichiers enregistrés.
  final names = <String>[];

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    names.add(fileName);
    return saved;
  }
}

/// Exporte le retour depuis [context] par le sélecteur factice ; rend le nom du fichier.
Future<String> exportWith(WidgetTester t, BuildContext context, Uri? saved, {required bool web}) async {
  final picker = SavePicker(saved);
  FilePickerPlatform.instance = picker;
  await exportReturn(context, web: web);
  await t.pumpAndSettle();
  expect(picker.names, [matches(RegExp(r'^TEST_Z1_RETOUR_\d{8}T\d{4}\.zip$'))]);
  return picker.names.single;
}

void main() {
  test('types : codes de FibReady par gravité, Standard par défaut', () {
    expect(CommentType.values.map((t) => t.code), ['alert', 'minor', 'standard', 'great']);
    expect(CommentType.of({'COM_TYPE': 'great'}), CommentType.great);
    expect(CommentType.of({'COM_TYPE': 'inconnu'}), CommentType.standard);
    expect(CommentType.of({}), CommentType.standard);
  });

  test('journal : du plus ancien au plus récent, abandonnés exclus ; ajout, modification, retrait', () {
    final o = bundle().objects.single;
    o.props['commentaires'] = [
      ...published().reversed,
      {
        'COM_CODE_EXT': 'K0',
        'COM_TEXTE': 'Doublon',
        'COM_AUTEUR': 'BE',
        'DATE_CREA': '2025-01-01T00:00:00Z',
        'DATE_ABD': '2025-02-01T00:00:00Z',
        'SRC_ABD': 'BE',
      },
    ];
    expect(codes(o), ['K1', 'K2']);

    final c = o.addComment(type: CommentType.alert, text: '  Hauban à reprendre  ', author: 'Jean Dupont', intervention: 'I1');
    expect(c['COM_CODE_EXT'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(c['DATE_CREA'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')));
    expect([c['COM_TYPE'], c['COM_TEXTE'], c['COM_AUTEUR'], c['INT_CODE_EXT']],
        ['alert', 'Hauban à reprendre', 'Jean Dupont', 'I1']);
    expect(c.keys, isNot(anyOf(contains('COM_ORIGINE'), contains('DATE_MODIF'))));
    expect(o.comments.last, same(c));
    expect(o.copy().comments.last, c); // écrit dans l'objet GeoJSON

    o.editComment(c, text: 'Hauban à reprendre côté rue ', type: CommentType.minor, author: 'Jean Dupont');
    expect([c['COM_TYPE'], c['COM_TEXTE'], c['SRC_MODIF']], ['minor', 'Hauban à reprendre côté rue', 'Jean Dupont']);
    expect(c['DATE_MODIF'], isNotNull);

    // retiré : il disparaît du journal, les autres restent
    o.removeComment(c);
    expect(codes(o), ['K1', 'K2']);
    expect(o.props['commentaires'], hasLength(3)); // l'abandonné du BE reste dans l'objet

    // sans commentaire, pas de clé `commentaires`
    final n = GeoObject(id: 'N1', objectClass: ObjectClass.noe);
    expect(n.comments, isEmpty);
    final first = n.addComment(text: 'Regard cassé', author: 'Jean Dupont', intervention: 'I1');
    expect(first['COM_TYPE'], 'standard');
    n.removeComment(first);
    expect(n.props.keys, isNot(contains('commentaires')));
  });

  test('règle du journal : son auteur, l\'intervention en cours, tant que le retour qui le contient n\'est pas '
      'exporté', () async {
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo)..setAuthor('Jean Dupont');
    final o = (await repo.object('P1'))!.copy();
    // texte repris de FOA, commentaire d'un autre technicien : lecture seule
    expect(o.comments.map(app.canEditComment), [false, false]);

    final mine = o.addComment(type: CommentType.alert, text: 'Hauban à reprendre', author: app.author, intervention: app.intervention);
    expect(app.canEditComment(mine), isTrue);
    // un autre auteur, même pendant l'intervention en cours
    expect(app.canEditComment({...mine, 'COM_AUTEUR': 'Paul Martin'}), isFalse);
    await app.save(o);

    // paquet de retour : l'objet complet avec tout son journal, l'intervention signe les nouveaux commentaires
    final (_, bytes) = await app.returnBundle();
    final a = ZipDecoder().decodeBytes(bytes);
    final header = jsonDecode(utf8.decode(a.findFile('paquet.json')!.content)) as Map;
    expect(header['version'], Bundle.version);
    expect([header['intervention']['INT_CODE_EXT'], header['intervention']['INT_AUTEUR']],
        [mine['INT_CODE_EXT'], 'Jean Dupont']);
    final features = (jsonDecode(utf8.decode(a.findFile('objets.geojson')!.content)) as Map)['features'] as List;
    final returned = (features.single as Map)['properties']['commentaires'] as List;
    expect(returned.map((c) => c['COM_CODE_EXT']), ['K1', 'K2', mine['COM_CODE_EXT']]);

    // préparé mais pas exporté (export annulé) : toujours modifiable ; exporté : figé
    expect(app.canEditComment(mine), isTrue);
    // saisi depuis, absent du retour préparé : son export ne le fige pas
    final later = o.addComment(text: 'Hauban posé', author: app.author, intervention: app.intervention);
    app.markExported();
    expect(app.canEditComment(mine), isFalse);
    expect(app.canEditComment(later), isTrue);

    // horloge du terminal recalée : seul compte le contenu des retours exportés, pas la date de saisie
    expect(app.canEditComment({...mine, 'DATE_CREA': '2099-01-01T00:00:00Z'}), isFalse);
    later['DATE_CREA'] = '2020-01-01T00:00:00Z';
    expect(app.canEditComment(later), isTrue);
    await app.save(o);
    await app.returnBundle();
    expect(app.canEditComment(later), isTrue);
    app.markExported();
    expect(app.canEditComment(later), isFalse);

    // nouveau paquet : nouvelle intervention, rien d'exporté ; les commentaires de la précédente sont figés
    await app.loadBundle(zip(bundle()));
    expect(app.error, isNull);
    expect([app.canEditComment(mine), app.canEditComment(later)], [false, false]);
    expect(app.intervention, isNot(mine['INT_CODE_EXT']));
    expect(app.canEditComment({...later, 'INT_CODE_EXT': app.intervention}), isTrue);
  });

  testWidgets('export du retour : sur le web, le téléchargement vaut export ; ailleurs, sans fichier enregistré, '
      'export annulé', (t) async {
    final picker = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = picker);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo)..setAuthor('Jean Dupont');
    final o = (await repo.object('P1'))!.copy();
    final mine = o.addComment(text: 'Hauban à reprendre', author: app.author, intervention: app.intervention);
    await app.save(o);
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    ));
    final context = t.element(find.byType(Scaffold));

    // Android, Windows : sélecteur fermé sans enregistrer ; le retour reste à exporter, le commentaire modifiable
    await exportWith(t, context, null, web: false);
    expect(find.text('Export annulé'), findsOneWidget);
    expect([app.toExport, app.canEditComment(mine)], [true, true]);

    // web : le ZIP est téléchargé et aucun fichier n'est rendu ; c'est un export, le commentaire est figé
    var name = await exportWith(t, context, null, web: true);
    expect(find.text('Paquet de retour : $name (1 objet)'), findsOneWidget);
    expect([app.toExport, app.canEditComment(mine)], [false, false]);

    // Android, Windows : fichier enregistré
    final later = o.addComment(text: 'Hauban posé', author: app.author, intervention: app.intervention);
    await app.save(o);
    expect([app.toExport, app.canEditComment(later)], [true, true]);
    name = await exportWith(t, context, Uri.parse('content://downloads/retour.zip'), web: false);
    expect(find.text('Paquet de retour : $name (1 objet)'), findsOneWidget);
    expect([app.toExport, app.canEditComment(later)], [false, false]);
  });

  testWidgets('carte Commentaires du poteau : journal en lecture seule, ajout typé, modification, retrait confirmé, '
      'figé après export', (t) async {
    final picker = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = picker);
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MemoryRepository();
    await repo.load(bundle());
    final app = AppProvider(repo)..setAuthor('Jean Dupont');
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ngeTheme(),
        navigatorObservers: [screenStack],
        home: ObjectScreen(object: (await repo.object('P1'))!),
      ),
    ));
    await t.pumpAndSettle();
    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    final dialogText = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    FilledButton button(String label) => t.widget<FilledButton>(find.widgetWithText(FilledButton, label));
    ChoiceChip chip(String label) => t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
    Finder inSection(String title, Finder f) =>
        find.descendant(of: find.ancestor(of: find.text(title), matching: find.byType(Section)), matching: f);

    // plus de champ libre (Général, Contrôles) ; la carte Commentaires suit les contrôles
    expect(inSection('GÉNÉRAL', find.byType(TextFormField)), findsNWidgets(3)); // numéro, hauteur, effort
    expect(find.widgetWithText(TextFormField, 'Commentaire'), findsNothing);
    final cards = (t.widget<ListView>(find.byType(ListView).first).childrenDelegate as SliverChildListDelegate).children;
    expect(cards.indexWhere((w) => w is CommentsCard), cards.indexWhere((w) => w is PoleChecks) + 1);

    // le journal publié, en lecture seule
    await t.scrollUntilVisible(find.text('Ajouter un commentaire'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('COMMENTAIRES'), findsOneWidget);
    expect(find.text('Aucun commentaire'), findsNothing);
    expect(find.text('Appui commun ERDF'), findsOneWidget);
    expect(find.text('FOA · ${local('2024-05-02T08:00:00Z')}'), findsOneWidget);
    expect(find.text('Poteau penché vers la chaussée'), findsOneWidget);
    expect(find.text('Paul Martin · ${local('2026-10-20T09:00:00Z')}'), findsOneWidget);
    expect(find.byTooltip('Alerte'), findsOneWidget); // pastille du type
    expect(find.byTooltip('Modifier le commentaire'), findsNothing);
    expect(find.byTooltip('Retirer le commentaire'), findsNothing);

    // saisie : Standard par défaut, Ajouter inactif tant que le texte est vide ; Annuler n'ajoute rien
    await tap(find.text('Ajouter un commentaire'));
    expect(find.text('Nouveau commentaire'), findsOneWidget);
    expect(chip('Standard').selected, isTrue);
    expect(button('Ajouter').onPressed, isNull);
    await t.enterText(dialogText, '   ');
    await t.pump();
    expect(button('Ajouter').onPressed, isNull);
    await tap(find.text('Annuler'));
    expect(find.text('Nouveau commentaire'), findsNothing);
    expect(find.text('Enregistrer'), findsNothing);

    await tap(find.text('Ajouter un commentaire'));
    await tap(find.widgetWithText(ChoiceChip, 'Alerte'));
    expect([chip('Alerte').selected, chip('Standard').selected], [true, false]);
    await t.enterText(dialogText, 'Hauban à reprendre\nCâble BT trop bas');
    await t.pump();
    await tap(find.widgetWithText(FilledButton, 'Ajouter'));
    expect(find.text('Hauban à reprendre\nCâble BT trop bas'), findsOneWidget);
    expect(find.textContaining('Jean Dupont · '), findsOneWidget);
    expect(find.byTooltip('Alerte'), findsNWidgets(2));
    expect(find.byTooltip('Modifier le commentaire'), findsOneWidget);
    expect((await repo.object('P1'))!.comments, hasLength(2)); // pas encore enregistré

    await tap(find.text('Enregistrer'));
    var p1 = (await repo.object('P1'))!;
    final saved = p1.comments.last;
    expect([saved['COM_TYPE'], saved['COM_TEXTE'], saved['COM_AUTEUR'], saved['INT_CODE_EXT']],
        ['alert', 'Hauban à reprendre\nCâble BT trop bas', 'Jean Dupont', app.intervention]);
    expect(saved['DATE_CREA'], isNotNull);
    expect(p1.status, 'M');
    expect(find.text('Enregistrer'), findsNothing);

    // modification de son commentaire : type et texte repris dans la saisie
    await tap(find.byTooltip('Modifier le commentaire'));
    expect(find.text('Modifier le commentaire'), findsOneWidget);
    expect(chip('Alerte').selected, isTrue);
    expect(find.descendant(of: dialogText, matching: find.text('Hauban à reprendre\nCâble BT trop bas')), findsOneWidget);
    await tap(find.widgetWithText(ChoiceChip, 'Mineur'));
    await t.enterText(dialogText, 'Hauban à reprendre côté rue');
    await t.pump();
    await tap(find.widgetWithText(FilledButton, 'Valider'));
    expect(find.text('Hauban à reprendre côté rue'), findsOneWidget);
    await tap(find.text('Enregistrer'));
    p1 = (await repo.object('P1'))!;
    expect([p1.comments.last['COM_TYPE'], p1.comments.last['COM_TEXTE'], p1.comments.last['SRC_MODIF']],
        ['minor', 'Hauban à reprendre côté rue', 'Jean Dupont']);
    expect(p1.comments.last['DATE_MODIF'], isNotNull);

    // retrait : confirmation qui rappelle le texte ; Annuler ne retire rien
    await tap(find.byTooltip('Retirer le commentaire'));
    expect(find.text('Retirer ce commentaire ?'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Hauban à reprendre côté rue')), findsOneWidget);
    expect(button('Retirer').style?.backgroundColor?.resolve({}), Nge.red);
    await tap(find.text('Annuler'));
    expect(find.text('Retirer ce commentaire ?'), findsNothing);
    expect(find.text('Hauban à reprendre côté rue'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
    // Retirer : il disparaît aussitôt, sans message d'annulation ; retrait enregistré
    await tap(find.byTooltip('Retirer le commentaire'));
    await tap(find.widgetWithText(FilledButton, 'Retirer'));
    expect(find.text('Retirer ce commentaire ?'), findsNothing);
    expect(find.text('Hauban à reprendre côté rue'), findsNothing);
    expect(find.byType(SnackBarAction), findsNothing);
    await tap(find.text('Enregistrer'));
    expect(codes((await repo.object('P1'))!), ['K1', 'K2']);

    // commentaire exporté dans un paquet de retour (téléchargé sur le web) : figé
    await tap(find.text('Ajouter un commentaire'));
    await t.enterText(dialogText, 'Hauban posé');
    await t.pump();
    await tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tap(find.text('Enregistrer'));
    expect(find.byTooltip('Modifier le commentaire'), findsOneWidget);
    await exportWith(t, t.element(find.byType(ObjectScreen)), null, web: true);
    expect(app.toExport, isFalse);
    expect(find.text('Hauban posé'), findsOneWidget);
    expect(find.byTooltip('Modifier le commentaire'), findsNothing);
    expect(find.byTooltip('Retirer le commentaire'), findsNothing);
  });
}
