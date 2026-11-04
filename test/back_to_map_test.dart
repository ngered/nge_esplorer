import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
import 'package:nge_esplorer/widgets/entry_screen.dart';

/// Écran d'essai ; [guarded] : saisie non enregistrée, confirmation avant de le quitter (comme la fiche).
class _Screen extends StatelessWidget {
  const _Screen(this.name, {this.next, this.guarded = false});

  final String name;
  final Widget? next;
  final bool guarded;

  @override
  Widget build(BuildContext context) => EntryScreen(
        changed: guarded,
        child: Scaffold(
          appBar: AppBar(title: Text(name), actions: const [MapButton()]),
          body: next == null
              ? null
              : TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => next!)),
                  child: const Text('suivant'),
                ),
        ),
      );
}

void main() {
  testWidgets('retour à la carte : écran par écran, arrêté si l\'utilisateur reste sur une saisie', (t) async {
    await t.pumpWidget(MaterialApp(
      navigatorObservers: [screenStack],
      home: const _Screen('carte',
          next: _Screen('A', next: _Screen('B', guarded: true, next: _Screen('C')))),
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
    expect(screenStack.stack.length, 3);

    // cette fois on quitte B : A se ferme aussi, retour à la carte
    await t.tap(find.byTooltip('Revenir à la carte'));
    await t.pumpAndSettle();
    await t.tap(find.text('Quitter'));
    await t.pumpAndSettle();
    expect(find.text('carte'), findsOneWidget);
    expect(screenStack.stack.length, 1);
    expect(find.byTooltip('Revenir à la carte'), findsNothing);

    // juste au-dessus de la carte, pas de bouton (la flèche de retour suffit)
    await t.tap(find.text('suivant'));
    await t.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.byTooltip('Revenir à la carte'), findsNothing);
  });
}
