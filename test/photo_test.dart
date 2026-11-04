import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nge_esplorer/data/memory_repository.dart';
import 'package:nge_esplorer/providers/app_provider.dart';
import 'package:nge_esplorer/widgets/photo.dart';

String? _url(ImageProvider? i) => switch (i) {
      ResizeImage(:final NetworkImage imageProvider) => imageProvider.url,
      NetworkImage(:final url) => url,
      _ => null,
    };

void main() {
  test('serveur de photos demandé par l\'adresse', () {
    String? s(String q) => photoServerFromUrl(Uri.parse('http://localhost:8080/?$q'), web: true);
    expect(s('photos=8090'), 'http://localhost:8090/');
    expect(s('terminal=smartphone&photos=http://poste:9000/nancy'), 'http://poste:9000/nancy/');
    expect(s('terminal=smartphone'), isNull);
    expect(photoServerFromUrl(Uri.parse('http://x/?photos=8090'), web: false), isNull);
    // lanceurs VS Code : à la compilation (--dart-define), l'adresse restant prioritaire
    expect(photoServerFromUrl(Uri.parse('http://x/?terminal=smartphone'), web: true, compile: '8090'),
        'http://localhost:8090/');
    expect(photoServerFromUrl(Uri.parse('http://x/?photos=9000'), web: true, compile: '8090'),
        'http://localhost:9000/');
  });

  test('photo embarquée, sinon lue au serveur par son chemin dans le projet', () async {
    final app = AppProvider(MemoryRepository());
    const path = 'photos/NCY/C17480/1453709173_CHA_7348_DESSUS_1.jpg';
    expect(photoImage(app, {'FIC_CHEMIN': path}), isNull);
    app.setUseLocalPhotoServer(true);
    expect(_url(photoImage(app, {'FIC_CHEMIN': path})), 'http://localhost:8090/$path');
    app.urlPhotoServer = 'http://poste:9000/';
    expect(_url(photoImage(app, {'FIC_CHEMIN': path})), 'http://poste:9000/$path');
    await app.repo.addFile('fichiers/F1.jpg', Uint8List.fromList([1, 2, 3]));
    expect(photoImage(app, {'fichier': 'fichiers/F1.jpg', 'FIC_CHEMIN': path}), isA<MemoryImage>());
  });
}
