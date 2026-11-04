import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/widgets/device_frame.dart';

void main() {
  test('terminal demandé par l\'adresse de la page', () {
    Size? size(String url, {bool web = true}) => Terminal.fromUrl(Uri.parse(url), web: web);
    expect(size('http://localhost/'), isNull);
    expect(size('http://localhost/?terminal=smartphone', web: false), isNull);
    expect(size('http://localhost/?terminal=Tablette'), const Size(800, 1280));
    expect(size('http://localhost/?terminal=390x844'), const Size(390, 844));
    expect(size('http://localhost/?terminal=n_importe'), Terminal.smartphone.size);
  });

  testWidgets('l\'application occupe la taille du terminal ; changement de terminal', (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => DeviceFrame(size: Terminal.smartphone.size, child: child!),
      home: Builder(builder: (context) => Text('${MediaQuery.sizeOf(context).width.toInt()}')),
    ));
    expect(t.getSize(find.byType(Navigator)), const Size(360, 800));
    expect(find.text('360'), findsOneWidget);

    await t.tap(find.textContaining('Tablette paysage'));
    await t.pumpAndSettle();
    expect(find.text('1280'), findsOneWidget);
  });
}
