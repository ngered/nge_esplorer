import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/widgets/back_to_map.dart';
import 'package:nge_esplorer/widgets/entry_screen.dart';

/// Enregistrements faits par les écrans d'essai.
final saved = <String>[];

/// Écran d'essai ; [guarded] : saisie non enregistrée, enregistrer ou abandonner avant de le quitter (comme la
/// fiche) ; l'enregistrement prend un peu de temps, comme l'écriture au dépôt.
class _Screen extends StatelessWidget {
  const _Screen(this.name, {this.next, this.guarded = false});

  final String name;
  final Widget? next;
  final bool guarded;

  @override
  Widget build(BuildContext context) => EntryScreen(
        changed: guarded,
        onSave: () async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          saved.add(name);
        },
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

    // C se ferme, B demande s'il faut enregistrer : toucher à côté du dialogue, on reste sur B
    await t.tap(find.byTooltip('Revenir à la carte'));
    await t.pumpAndSettle();
    expect(find.text('Enregistrer les modifications ?'), findsOneWidget);
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(screenStack.stack.length, 3);

    // on abandonne les modifications de B : rien d'enregistré, A se ferme aussi, retour à la carte
    await t.tap(find.byTooltip('Revenir à la carte'));
    await t.pumpAndSettle();
    await t.tap(find.text('Abandonner les modifications'));
    await t.pumpAndSettle();
    expect(find.text('carte'), findsOneWidget);
    expect(screenStack.stack.length, 1);
    expect(saved, isEmpty);
    expect(find.byTooltip('Revenir à la carte'), findsNothing);

    // on enregistre B : le retour à la carte attend la fin de l'enregistrement, puis ferme B et A
    for (var i = 0; i < 3; i++) {
      await t.tap(find.text('suivant'));
      await t.pumpAndSettle();
    }
    await t.tap(find.byTooltip('Revenir à la carte'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(saved, ['B']);
    expect(find.text('carte'), findsOneWidget);
    expect(screenStack.stack.length, 1);

    // juste au-dessus de la carte, pas de bouton (la flèche de retour suffit)
    await t.tap(find.text('suivant'));
    await t.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.byTooltip('Revenir à la carte'), findsNothing);
  });
}
