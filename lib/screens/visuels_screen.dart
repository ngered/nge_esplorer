import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/objet.dart';
import '../data/visuels.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/barre_support.dart';
import '../widgets/titre_ecran.dart';
import 'galerie_screen.dart';
import 'objet_screen.dart';

/// Ouvre un support sur ses visuels.
Future<void> ouvrirSupport(BuildContext context, Objet o) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => VisuelsScreen(objet: o)));

/// Prend une photo pour le visuel [v] de [o] et l'enregistre aussitôt, sur l'objet tel qu'il est dans le dépôt
/// (web : choix d'une image ; Android : appareil photo, à venir). Vrai si une photo a été ajoutée.
Future<bool> prendrePhoto(BuildContext context, Objet o, Visuel v, {String? message}) async {
  final app = context.read<AppProvider>();
  final messager = ScaffoldMessenger.of(context);
  final f = await FilePicker.pickFile(type: FileType.image, dialogTitle: v.lib);
  if (f == null) return false;
  final octets = await f.readAsBytes();
  final frais = await app.repo.objet(o.id) ?? o;
  await app.ajouterPhoto(frais.copie(), v, nom: f.name, octets: octets);
  messager.showSnackBar(SnackBar(content: Text(message ?? 'Photo ajoutée : ${v.lib}')));
  return true;
}

/// Ajoute un visuel libre à [o] : titre saisi, puis première photo (un visuel libre n'existe qu'avec ses photos).
Future<void> ajouterVisuelLibre(BuildContext context, Objet o) async {
  final lib = await demanderTitre(context, titre: 'Nouveau visuel libre');
  if (lib == null || !context.mounted) return;
  await prendrePhoto(context, o, Visuel.libre(lib), message: 'Visuel ajouté : $lib');
}

/// Titre d'un visuel libre (null : annulé ou vide).
Future<String?> demanderTitre(BuildContext context, {required String titre, String initial = ''}) async {
  var saisi = initial;
  final res = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titre),
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Titre du visuel', hintText: 'Boîte aux lettres, PBO voisin…'),
        onChanged: (t) => saisi = t,
        onFieldSubmitted: (t) => Navigator.pop(c, t),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, saisi), child: const Text('Valider')),
      ],
    ),
  );
  final t = res?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// Écran d'arrivée d'un support : une carte par visuel (photo de référence, nombre de photos ou « Manquante »,
/// prendre une photo, fonction propre du visuel) ; toucher un visuel ouvre sa galerie. Le crayon ouvre la saisie.
class VisuelsScreen extends StatefulWidget {
  const VisuelsScreen({super.key, required this.objet});

  final Objet objet;

  @override
  State<VisuelsScreen> createState() => _VisuelsScreenState();
}

class _VisuelsScreenState extends State<VisuelsScreen> {
  late Objet _o = widget.objet;

  Future<void> _recharger() async {
    final frais = await context.read<AppProvider>().repo.objet(_o.id);
    if (mounted && frais != null) setState(() => _o = frais);
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ecran));
    await _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final visuels = Visuel.de(_o, app.referentiels);
    final manquants = visuels.where((v) => v.obligatoire && _o.photos(v).isEmpty).length;
    return Scaffold(
      backgroundColor: Nge.fondBarre,
      appBar: AppBar(
        title: TitreEcran(
          _o.lib ?? 'Sans étiquette',
          manquants == 0 ? 'visuels · complets' : 'visuels · $manquants manquant${manquants > 1 ? 's' : ''}',
        ),
        actions: [
          IconButton(
            tooltip: 'Saisie du support',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _ouvrir(ObjetScreen(objet: _o)),
          ),
        ],
      ),
      bottomNavigationBar: BarreSupport(objet: _o, apres: _recharger),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (visuels.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Aucun visuel attendu pour ce type. « Ajouter » crée un visuel libre.',
                style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          ),
        for (final v in visuels)
          Builder(builder: (context) {
            final photos = _o.photos(v);
            final chemin = photos.firstOrNull?['fichier'] as String?;
            return CarteVisuel(
              visuel: v,
              nombre: photos.length,
              reference: chemin == null ? null : app.repo.fichier(chemin),
              onOuvrir: () => _ouvrir(GalerieScreen(objet: _o, visuel: v)),
              onPhoto: () async {
                if (await prendrePhoto(context, _o, v)) await _recharger();
              },
            );
          }),
      ]),
    );
  }
}

/// Carte d'un visuel : titre, état, photo de référence, prendre une photo, fonction propre (grille du masque).
class CarteVisuel extends StatelessWidget {
  const CarteVisuel({
    super.key,
    required this.visuel,
    required this.nombre,
    required this.reference,
    required this.onOuvrir,
    required this.onPhoto,
  });

  final Visuel visuel;
  final int nombre;

  /// Photo de référence (null : aucune photo, ou photo non embarquée dans le paquet).
  final Uint8List? reference;
  final VoidCallback onOuvrir;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final v = visuel;
    final t = Theme.of(context).textTheme;
    final (etat, fond, encre) = nombre > 0
        ? ('$nombre photo${nombre > 1 ? 's' : ''}', const Color(0xFFE3F1E8), Nge.vert)
        : (v.obligatoire ? ('Manquante', const Color(0xFFFFF4D1), const Color(0xFF8A6400)) : ('Aucune', Nge.survol, Nge.texteSecondaire));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOuvrir,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('${v.lib}${v.obligatoire ? ' *' : ''}', style: t.titleMedium)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
                child: Text(etat, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: encre)),
              ),
            ]),
            if (v.siMasque) Text('Obligatoire si la face porte un masque', style: t.bodySmall),
            if (v.libre) Text('Visuel libre', style: t.bodySmall),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 160,
                    child: reference != null
                        ? Image.memory(reference!, fit: BoxFit.cover, semanticLabel: 'Photo de référence')
                        : _SansPhoto(texte: nombre == 0 ? 'Aucune photo' : 'Photo non embarquée'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(children: [
                IconButton.outlined(
                  tooltip: 'Prendre une photo',
                  icon: const Icon(Icons.add_a_photo_outlined),
                  onPressed: onPhoto,
                ),
                if (v.action == 'MASQUE') ...[
                  const SizedBox(height: 8),
                  IconButton.outlined(
                    tooltip: 'Grille du masque',
                    icon: const Icon(Icons.grid_on),
                    onPressed: () => ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Grille du masque : à venir'))),
                  ),
                ],
              ]),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SansPhoto extends StatelessWidget {
  const _SansPhoto({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Nge.bordure, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.photo_camera_outlined, size: 30, color: Nge.texteSecondaire),
            const SizedBox(height: 6),
            Text(texte, style: const TextStyle(fontSize: 13, color: Nge.texteSecondaire)),
          ]),
        ),
      );
}
