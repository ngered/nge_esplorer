import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../lng.dart';
import '../providers/app_provider.dart';
import '../theme.dart';

/// Serveur de photos demandé (web, développement) par l'adresse de la page, `?photos=http://localhost:8090/` ou le
/// port seul `?photos=8090`, sinon à la compilation, `--dart-define=SERVEUR_PHOTOS=8090` (lanceurs VS Code : un `&`
/// dans l'adresse coupe la ligne de commande de flutter.bat) ; il sert le dossier du projet BE
/// (tools/essai/serveur_photos.py). Null sinon (le paramètre « Photos au serveur local » donne alors le port 8090).
String? photoServerFromUrl(Uri pageUrl,
    {bool web = kIsWeb, String compile = const String.fromEnvironment('SERVEUR_PHOTOS')}) {
  if (!web) return null;
  final v = (pageUrl.queryParameters['photos'] ?? compile).trim();
  if (v.isEmpty) return null;
  final url = int.tryParse(v) != null ? 'http://localhost:$v/' : v;
  return url.endsWith('/') ? url : '$url/';
}

/// Image d'une photo (élément de `fichiers`) : contenu embarqué dans le paquet ou pris sur le terminal, sinon lu au
/// serveur de photos par son chemin dans le projet (`FIC_CHEMIN`). Null sans source. Originaux de 12 Mpx (48 Mo
/// décodés, appareil photo du terminal, relevés de Nancy) : décodés à la largeur d'affichage, d'où qu'ils viennent.
ImageProvider? photoImage(AppProvider app, Map f) {
  ImageProvider fit(ImageProvider i) => ResizeImage(i, width: photoWidth, policy: ResizeImagePolicy.fit);
  final path = f['fichier'] as String?;
  final bytes = path == null ? null : app.repo.file(path);
  if (bytes != null) return fit(MemoryImage(bytes));
  final distant = f['FIC_CHEMIN'] as String?;
  final server = app.photoServer;
  if (server == null || distant == null) return null;
  return fit(NetworkImage(Uri.parse(server).resolve(distant).toString()));
}

/// Largeur de décodage des photos (pixels) ; une photo moins large garde la sienne (pas d'agrandissement).
const photoWidth = 1280;

/// Photo cadrée ([fit] : remplissant le cadre, ou entière dans la galerie) ; à défaut, le cadre [NoPhoto] avec
/// [missingText] (ou « Photo introuvable » si la lecture échoue).
class Photo extends StatelessWidget {
  const Photo({super.key, required this.image, required this.missingText, this.label, this.fit = BoxFit.cover});

  final ImageProvider? image;
  final String missingText;
  final String? label;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (image == null) return NoPhoto(text: missingText);
    return Image(
      image: image!,
      fit: fit,
      semanticLabel: label,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (context, error, stack) => NoPhoto(text: tr('Photo introuvable')),
    );
  }
}

class NoPhoto extends StatelessWidget {
  const NoPhoto({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Nge.border, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.photo_camera_outlined, size: 30, color: Nge.secondaryText),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontSize: 13, color: Nge.secondaryText)),
          ]),
        ),
      );
}
