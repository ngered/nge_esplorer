import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/lng.dart';
import 'package:nge_esplorer/main.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/screens/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../tools/lang/lng_extract.dart' as lng;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // version et build de la section « À propos » des Paramètres (pas de plateforme dans les tests)
  PackageInfo.setMockInitialValues(appName: 'NgeEsPlorer', packageName: 'fr.nge.esplorer', version: '1.0.0',
      buildNumber: '100', buildSignature: '');
  tearDown(() => Lng.load(Lng.sourceLanguage));

  test('catalogues : chaque texte des sources est traduit, avec les mêmes {n}', () {
    final texts = lng.extractTexts(Directory('lib'));
    expect(texts, isNotEmpty);
    final placeholders = RegExp(r'\{\d+\}');
    for (final code in lng.targetLanguages) {
      final catalog = lng.readCatalog(File('assets/lang/$code.json'));
      final missing = [for (final t in texts) if ((catalog[t] ?? '').isEmpty) t];
      expect(missing, isEmpty, reason: '$code : textes sans traduction (tools/lang/lng_extract.dart)');
      expect([for (final k in catalog.keys) if (!texts.contains(k)) k], isEmpty, reason: '$code : clés obsolètes');
      for (final t in texts) {
        Set<String> marks(String s) => placeholders.allMatches(s).map((m) => m.group(0)!).toSet();
        expect(marks(catalog[t]!), marks(t), reason: '$code : $t');
      }
    }
    expect(Lng.languages.keys.toSet(), {Lng.sourceLanguage, ...lng.targetLanguages});
  });

  test('tr et trn : traduction, repli sur le français, pluriel selon la langue', () async {
    expect(tr('Annuler'), 'Annuler');
    expect(trn(0, '{0} photo', '{0} photos'), '0 photo');
    expect(tr('Zone : {0}', ['Z1']), 'Zone : Z1');

    await Lng.load('en');
    expect(Lng.language, 'en');
    expect(tr('Annuler'), 'Cancel');
    expect(tr('Zone : {0}', ['Z1']), 'Zone: Z1');
    expect(tr('texte absent du catalogue'), 'texte absent du catalogue');
    expect(trn(0, '{0} photo', '{0} photos'), '0 photos');
    expect(trn(1, '{0} photo', '{0} photos'), '1 photo');
    expect(trn(2, 'masque {1} · {0} alvéole', 'masque {1} · {0} alvéoles', ['A']), 'duct layout A · 2 duct ways');

    await Lng.load('ar');
    expect(Lng.language, Lng.sourceLanguage);
  });

  testWidgets('changement de langue dans les Paramètres : tous les écrans traduits sans redémarrage', (t) async {
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppProvider(MemoryRepository());
    await t.pumpWidget(ChangeNotifierProvider.value(value: app, child: const NgeEsPlorerApp()));
    await t.pumpAndSettle();
    expect(find.text('Ouvrir un paquet de zone'), findsOneWidget);

    t.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await t.pumpAndSettle();
    await t.tap(find.text('Français'));
    await t.pumpAndSettle();
    await t.tap(find.text('English').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // lecture du catalogue
    await t.pumpAndSettle();

    expect(app.language, 'en');
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Base maps'), findsOneWidget);
    expect(t.widget<MaterialApp>(find.byType(MaterialApp)).locale, const Locale('en'));

    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    expect(find.text('Open a zone package'), findsOneWidget);
  });

  test('catalogues : JSON plats, commentaire en tête', () {
    for (final code in lng.targetLanguages) {
      final json = jsonDecode(File('assets/lang/$code.json').readAsStringSync()) as Map<String, dynamic>;
      expect(json.keys.first, '_comment');
      expect(json.values.every((v) => v is String), isTrue);
    }
  });
}
