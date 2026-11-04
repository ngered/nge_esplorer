import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/widgets/entry_screen.dart';
import 'package:nge_esplorer/widgets/messages.dart';

void main() {
  testWidgets('un nouveau message remplace les précédents, sans file de messages périmés', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showSaved(context);
              showSaved(context);
              ScaffoldMessenger.of(context).replaceSnackBar(const SnackBar(content: Text('Liens fibres')));
            },
            child: const Text('actions'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('actions'));
    await t.pumpAndSettle();
    expect(find.text('Liens fibres'), findsOneWidget);
    expect(find.text('Enregistré'), findsNothing);

    // le message se ferme : aucun « Enregistré » en attente ne prend la suite
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  group('message d\'annulation d\'un écran', () {
    late int undone;

    Future<void> open(WidgetTester t) async {
      undone = 0;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => _UndoScreen(onUndo: () => undone++))),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      await t.tap(find.text('supprimer'));
      await t.pumpAndSettle();
      expect(find.text('Photo supprimée'), findsOneWidget);
    }

    testWidgets('disparaît seul (un message à action resterait affiché)', (t) async {
      await open(t);
      await t.pump(UndoMessage.undoDuration + const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(undone, 0);
    });

    testWidgets('Annuler appelle l\'annulation', (t) async {
      await open(t);
      await t.tap(find.text('ANNULER'));
      await t.pumpAndSettle();
      expect(undone, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('se ferme avec l\'écran : il ne suit pas sur l\'écran précédent', (t) async {
      await open(t);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('ouvrir'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('une autre modification le rend caduc', (t) async {
      await open(t);
      await t.tap(find.text('modifier'));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

/// Écran d'essai : « supprimer » propose l'annulation, « modifier » la rend caduque.
class _UndoScreen extends StatefulWidget {
  const _UndoScreen({required this.onUndo});

  final VoidCallback onUndo;

  @override
  State<_UndoScreen> createState() => _UndoScreenState();
}

class _UndoScreenState extends State<_UndoScreen> with UndoMessage<_UndoScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Column(children: [
          TextButton(onPressed: () => showUndo('Photo supprimée', widget.onUndo), child: const Text('supprimer')),
          TextButton(onPressed: hideUndo, child: const Text('modifier')),
        ]),
      );
}
