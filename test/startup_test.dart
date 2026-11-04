import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/main.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/theme.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('démarrage : bleu nuit, logo NGE, compte modifiable, ouverture d\'un paquet', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppProvider(MemoryRepository()),
      child: const NgeEsPlorerApp(),
    ));
    await t.pumpAndSettle();

    expect(t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, Nge.navyBlue);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Ouvrir un paquet de zone'), findsOneWidget);
    expect(t.takeException(), isNull); // rien ne déborde sur un écran de téléphone

    await t.tap(find.text('terrain'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Redha Martinez');
    await t.tap(find.text('Valider'));
    await t.pumpAndSettle();
    expect(find.text('RM'), findsOneWidget);
  });
}
