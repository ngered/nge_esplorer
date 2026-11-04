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
/// serveur de photos par son chemin dans le projet (`FIC_CHEMIN`). Null sans source.
ImageProvider? photoImage(AppProvider app, Map f) {
  final path = f['fichier'] as String?;
  final bytes = path == null ? null : app.repo.file(path);
  if (bytes != null) return MemoryImage(bytes);
  final distant = f['FIC_CHEMIN'] as String?;
  final server = app.photoServer;
  if (server == null || distant == null) return null;
  // originaux de 12 Mpx (48 Mo décodés) : décodés à la largeur d'affichage
  return ResizeImage(NetworkImage(Uri.parse(server).resolve(distant).toString()),
      width: 1280, policy: ResizeImagePolicy.fit);
}

/// Photo cadrée ; à défaut, le cadre [NoPhoto] avec [missingText] (ou « Photo introuvable » si la lecture échoue).
class Photo extends StatelessWidget {
  const Photo({super.key, required this.image, required this.missingText, this.label});

  final ImageProvider? image;
  final String missingText;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (image == null) return NoPhoto(text: missingText);
    return Image(
      image: image!,
      fit: BoxFit.cover,
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
