import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/carte/pictos.dart';
import 'package:nge_esplorer/modules/renseignement.dart';

void main() {
  testWidgets('pictos FibReady : chargés et recolorés pour chaque statut, point pour un type sans picto', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Wrap(children: [
        for (final famille in ['POT', 'CHB', 'FAC'])
          for (final r in [null, ...Renseignement.values])
            PictoSupport(famille: famille, fond: r?.couleur, energie: famille == 'POT' && r == Renseignement.complet),
        const PictoSupport(famille: 'INCONNU'),
      ]),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(15));
    expect(find.byType(PointSupport), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
