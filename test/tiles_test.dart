import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nge_esplorer/map/tile_source.dart';

/// Cache en mémoire : une tuile périmée pour l'URL connue.
class _Cache implements MapCachingProvider {
  final tiles = <String, CachedMapTile>{
    'https://tuiles.test/1/2/3.png': (
      bytes: Uint8List.fromList([1, 2, 3]),
      metadata: CachedMapTileMetadata(
          staleAt: DateTime.utc(2020), lastModified: DateTime.utc(2019, 5, 6, 7, 8, 9), etag: '"v1"'),
    ),
  };

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async => tiles[url];

  @override
  Future<void> putTile({required String url, required CachedMapTileMetadata metadata, Uint8List? bytes}) async {}
}

void main() {
  test('fonds proposés : identifiants distincts, Plan IGN sans appel à Google', () async {
    final ids = availableBaseMaps('cle').map((f) => f.$1).toList();
    expect(ids.toSet().length, ids.length);
    expect(availableBaseMaps('').map((f) => f.$2), ['Plan IGN', 'Photographies aériennes IGN', 'OpenStreetMap']);
    expect(await openBaseMap('plan', 'cle'), isA<IgnPlan>());
    expect(await openBaseMap('osm', ''), isA<Osm>());
  });

  final offline = MockClient((_) async => throw http.ClientException('réseau injoignable'));

  test('connecté : la réponse du serveur passe telle quelle', () async {
    final c = FallbackTileClient(_Cache(), MockClient((_) async => http.Response('png', 200)));
    final r = await c.get(Uri.parse('https://tuiles.test/1/2/3.png'));
    expect(r.statusCode, 200);
    expect(r.body, 'png');
  });

  test('sans connexion : tuile du cache, même périmée, déclarée non modifiée et laissée périmée', () async {
    final c = FallbackTileClient(_Cache(), offline);
    final r = await c.get(Uri.parse('https://tuiles.test/1/2/3.png'));
    expect(r.statusCode, 304);
    final m = CachedMapTileMetadata.fromHttpHeaders(r.headers);
    expect(m.isStale, isTrue, reason: 'le serveur doit être de nouveau interrogé ensuite');
    expect(m.etag, '"v1"');
    expect(m.lastModified, DateTime.utc(2019, 5, 6, 7, 8, 9));
  });

  test('fond par défaut : IGN en France, OSM ailleurs', () {
    expect(defaultBaseMap([6.18, 48.65, 6.21, 48.67]), isA<IgnPlan>()); // Heillecourt
    expect(defaultBaseMap([-7.65, 33.55, -7.55, 33.62]), isA<Osm>()); // Casablanca
    expect(defaultBaseMap(null), isA<IgnPlan>());
  });

  test('serveur saturé ou réseau coupé un instant : nouvelles tentatives avant l\'échec', () async {
    var n = 0;
    final c = tileNetworkClient(
      inner: MockClient((_) async => switch (n++) {
            0 => http.Response('', 429),
            1 => throw http.ClientException('coupure'),
            _ => http.Response('png', 200),
          }),
      delay: (_) => Duration.zero,
    );
    final r = await c.get(Uri.parse('https://tuiles.test/1/2/3.png'));
    expect([r.statusCode, n], [200, 3]);

    n = 0;
    final refused = tileNetworkClient(
      inner: MockClient((_) async {
        n++;
        return http.Response('', 404);
      }),
      delay: (_) => Duration.zero,
    );
    expect((await refused.get(Uri.parse('https://tuiles.test/0/0/0.png'))).statusCode, 404);
    expect(n, 1, reason: 'une tuile absente du serveur n\'est pas redemandée');
  });

  test('sans connexion ni cache : erreur (tuile transparente)', () async {
    final c = FallbackTileClient(_Cache(), offline);
    expect(c.get(Uri.parse('https://tuiles.test/9/9/9.png')), throwsA(isA<http.ClientException>()));
  });
}
