import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/map/symbols.dart';
import 'package:nge_esplorer/modules/completion.dart';

void main() {
  testWidgets('pictos FibReady : chargés et recolorés pour chaque statut, point pour un type sans picto', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Wrap(children: [
        for (final family in ['POT', 'CHB', 'FAC'])
          for (final r in [null, ...Completion.values])
            SupportSymbol(family: family, fill: r?.color, energy: family == 'POT' && r == Completion.complete),
        const SupportSymbol(family: 'INCONNU'),
      ]),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(15));
    expect(find.byType(SupportPoint), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
