import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/geo_object.dart';
import '../data/visuals.dart';
import '../lng.dart';
import '../modules/chambre/mask_screen.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/support_bar.dart';
import '../widgets/photo.dart';
import '../widgets/screen_title.dart';
import 'gallery_screen.dart';
import 'object_screen.dart';

/// Ouvre un support sur ses visuels (route `support:<id>`, base de ses onglets, voir [openTab]).
Future<void> openSupport(BuildContext context, GeoObject o) => Navigator.push(
    context, MaterialPageRoute(settings: RouteSettings(name: supportRoute(o)), builder: (_) => VisualsScreen(object: o)));

/// Prend une photo pour le visuel [v] de [o] et l'enregistre aussitôt, sur l'objet tel qu'il est dans le dépôt
/// (web : choix d'une image ; Android : appareil photo, à venir). Vrai si une photo a été ajoutée.
Future<bool> takePhoto(BuildContext context, GeoObject o, Visual v, {String? message}) async {
  final app = context.read<AppProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final f = await FilePicker.pickFile(type: FileType.image, dialogTitle: v.lib);
  if (f == null) return false;
  final bytes = await f.readAsBytes();
  final fresh = await app.repo.object(o.id) ?? o;
  await app.addPhoto(fresh.copy(), v, name: f.name, bytes: bytes);
  messenger.showSnackBar(SnackBar(content: Text(message ?? tr('Photo ajoutée : {0}', [v.lib]))));
  return true;
}

/// Ajoute un visuel libre à [o] : titre saisi, puis première photo (un visuel libre n'existe qu'avec ses photos).
Future<void> addFreeVisual(BuildContext context, GeoObject o) async {
  final lib = await askTitle(context, title: tr('Nouveau visuel libre'));
  if (lib == null || !context.mounted) return;
  await takePhoto(context, o, Visual.free(lib), message: tr('Visuel ajouté : {0}', [lib]));
}

/// Titre d'un visuel libre (null : annulé ou vide).
Future<String?> askTitle(BuildContext context, {required String title, String initial = ''}) async {
  var entered = initial;
  final res = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('Titre du visuel'), hintText: tr('Boîte aux lettres, PBO voisin…')),
        onChanged: (t) => entered = t,
        onFieldSubmitted: (t) => Navigator.pop(c, t),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Annuler'))),
        FilledButton(onPressed: () => Navigator.pop(c, entered), child: Text(tr('Valider'))),
      ],
    ),
  );
  final t = res?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// Écran d'arrivée d'un support : une carte par visuel (photo de référence, nombre de photos ou « Manquante »,
/// prendre une photo, fonction propre du visuel) ; toucher un visuel ouvre sa galerie. Le crayon ouvre la saisie.
class VisualsScreen extends StatefulWidget {
  const VisualsScreen({super.key, required this.object});

  final GeoObject object;

  @override
  State<VisualsScreen> createState() => _VisualsScreenState();
}

class _VisualsScreenState extends State<VisualsScreen> {
  late GeoObject _o = widget.object;

  Future<void> _reload() async {
    final fresh = await context.read<AppProvider>().repo.object(_o.id);
    if (mounted && fresh != null) setState(() => _o = fresh);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final visuals = Visual.of(_o, app.referenceData);
    final missing = visuals.where((v) => v.mandatory && _o.photos(v).isEmpty).length;
    return Scaffold(
      backgroundColor: Nge.barBackground,
      appBar: AppBar(
        title: ScreenTitle(
          _o.lib ?? tr('Sans étiquette'),
          missing == 0 ? tr('visuels · complets') : trn(missing, 'visuels · {0} manquant', 'visuels · {0} manquants'),
        ),
        actions: [
          IconButton(
            tooltip: tr('Saisie du support'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await openTab(context, _o, 'saisie', (o) => ObjectScreen(object: o));
              await _reload();
            },
          ),
        ],
      ),
      bottomNavigationBar: SupportBar(object: _o, next: _reload),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (visuals.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(tr('Aucun visuel attendu pour ce type. « Ajouter » crée un visuel libre.'),
                style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          ),
        for (final v in visuals)
          Builder(builder: (context) {
            final photos = _o.photos(v);
            return VisualCard(
              visual: v,
              count: photos.length,
              reference: photos.isEmpty ? null : photoImage(app, photos.first),
              onOpen: () => _open(GalleryScreen(object: _o, visual: v)),
              onPhoto: () async {
                if (await takePhoto(context, _o, v)) await _reload();
              },
              onMask: () => _open(MaskScreen(chamber: _o, face: v.code)),
            );
          }),
      ]),
    );
  }
}

/// Carte d'un visuel : titre, état, photo de référence, prendre une photo, fonction propre (grille du masque).
class VisualCard extends StatelessWidget {
  const VisualCard({
    super.key,
    required this.visual,
    required this.count,
    required this.reference,
    required this.onOpen,
    required this.onPhoto,
    this.onMask,
  });

  final Visual visual;
  final int count;

  /// Photo de référence (null : aucune photo, ou photo non embarquée dans le paquet ni servie).
  final ImageProvider? reference;
  final VoidCallback onOpen;
  final VoidCallback onPhoto;

  /// Grille du masque de la face (visuel d'action MASQUE).
  final VoidCallback? onMask;

  @override
  Widget build(BuildContext context) {
    final v = visual;
    final t = Theme.of(context).textTheme;
    final (state, fill, ink) = count > 0
        ? (trn(count, '{0} photo', '{0} photos'), const Color(0xFFE3F1E8), Nge.green)
        : (v.mandatory ? (tr('Manquante'), const Color(0xFFFFF4D1), const Color(0xFF8A6400)) : (tr('Aucune'), Nge.hover, Nge.secondaryText));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('${v.lib}${v.mandatory ? ' *' : ''}', style: t.titleMedium)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(12)),
                child: Text(state, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
              ),
            ]),
            if (v.ifMasked) Text(tr('Obligatoire si la face porte un masque'), style: t.bodySmall),
            if (v.free) Text(tr('Visuel libre'), style: t.bodySmall),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 160,
                    child: Photo(
                      image: reference,
                      missingText: count == 0 ? tr('Aucune photo') : tr('Photo non embarquée'),
                      label: tr('Photo de référence'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(children: [
                IconButton.outlined(
                  tooltip: tr('Prendre une photo'),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  onPressed: onPhoto,
                ),
                if (v.action == 'MASQUE') ...[
                  const SizedBox(height: 8),
                  IconButton.outlined(
                    tooltip: tr('Grille du masque'),
                    icon: const Icon(Icons.grid_on),
                    onPressed: onMask,
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
