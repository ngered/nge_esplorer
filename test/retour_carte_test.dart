import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/widgets/retour_carte.dart';
import 'package:nge_esplorer/widgets/saisie.dart';

/// Écran d'essai ; [protege] : saisie non enregistrée, confirmation avant de le quitter (comme la fiche).
class _Ecran extends StatelessWidget {
  const _Ecran(this.nom, {this.suivant, this.protege = false});

  final String nom;
  final Widget? suivant;
  final bool protege;

  @override
  Widget build(BuildContext context) => EcranSaisie(
        modifie: protege,
        child: Scaffold(
          appBar: AppBar(title: Text(nom), actions: const [BoutonCarte()]),
          body: suivant == null
              ? null
              : TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => suivant!)),
                  child: const Text('suivant'),
                ),
        ),
      );
}

void main() {
  testWidgets('retour à la carte : écran par écran, arrêté si l\'utilisateur reste sur une saisie', (t) async {
    await t.pumpWidget(MaterialApp(
      navigatorObservers: [pileEcrans],
      home: const _Ecran('carte',
          suivant: _Ecran('A', suivant: _Ecran('B', protege: true, suivant: _Ecran('C')))),
    ));
    for (var i = 0; i < 3; i++) {
      await t.tap(find.text('suivant'));
      await t.pumpAndSettle();
    }
    expect(find.text('C'), findsOneWidget);

    // C se ferme, B demande confirmation : on reste sur B
    await t.tap(find.byTooltip('Revenir à la carte'));
    await t.pumpAndSettle();
    await t.tap(find.text('Rester'));
    await t.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(pileEcrans.pile.length, 3);

    // cette fois on quitte B : A se ferme aussi, retour à la carte
    await t.tap(find.byTooltip('Revenir à la carte'));
    await t.pumpAndSettle();
    await t.tap(find.text('Quitter'));
    await t.pumpAndSettle();
    expect(find.text('carte'), findsOneWidget);
    expect(pileEcrans.pile.length, 1);
    expect(find.byTooltip('Revenir à la carte'), findsNothing);

    // juste au-dessus de la carte, pas de bouton (la flèche de retour suffit)
    await t.tap(find.text('suivant'));
    await t.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.byTooltip('Revenir à la carte'), findsNothing);
  });
}
