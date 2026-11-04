import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/geo_object.dart';
import '../data/visuals.dart';
import '../lng.dart';
import '../modules/chambre/mask_screen.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/back_to_map.dart';
import '../widgets/support_bar.dart';
import '../widgets/photo.dart';
import '../widgets/screen_title.dart';
import 'gallery_screen.dart';
import '../widgets/messages.dart';

/// Ouvre un support sur ses visuels (route `support:<id>`, base de ses onglets, voir [openTab]), depuis la carte.
Future<void> openSupport(BuildContext context, GeoObject o) =>
    Navigator.push(context, MaterialPageRoute(settings: supportSettings(o), builder: (_) => VisualsScreen(object: o)));

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
  messenger.replaceSnackBar(SnackBar(content: Text(message ?? tr('Photo ajoutée : {0}', [v.lib]))));
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
/// prendre une photo, fonction propre du visuel) ; toucher un visuel ouvre sa galerie. Le menu ⋮ ouvre la saisie.
class VisualsScreen extends StatefulWidget {
  const VisualsScreen({super.key, required this.object});

  final GeoObject object;

  @override
  State<VisualsScreen> createState() => _VisualsScreenState();
}

class _VisualsScreenState extends State<VisualsScreen> {
  late GeoObject _o = widget.object;

  /// Écritures déjà relues ([AppProvider.revision]) : les visuels se relisent après chacune, faite ici ou dans un
  /// onglet ouvert au-dessus, que l'on revienne par le retour arrière ou par le menu ⋮ (une copie périmée, passée à
  /// la galerie, aurait effacé ce qui a été enregistré entre-temps).
  int _revision = -1;
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  /// Relit le support, et le note tel qu'il est enregistré : quitté depuis ses visuels, il garde son intitulé à jour
  /// dans les supports quittés (menu ⋮).
  Future<void> _reload() async {
    final fresh = await context.read<AppProvider>().repo.object(_o.id);
    if (!mounted || fresh == null) return;
    setState(() => _o = fresh);
    final r = _route;
    if (r != null) screenStack.note(r, tab: 'support', object: fresh.copy());
  }

  /// Écran propre des visuels (galerie ; grille d'une face, route nommée [settings] pour la retenir si l'on quitte
  /// le support) ; au retour, l'objet est relu.
  Future<void> _open(Widget screen, [RouteSettings? settings]) async {
    await Navigator.push(context, MaterialPageRoute(settings: settings, builder: (_) => screen));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    if (app.revision != _revision) {
      _revision = app.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    final visuals = Visual.of(_o, app.referenceData);
    final missing = visuals.where((v) => v.mandatory && _o.photos(v).isEmpty).length;
    return Scaffold(
      backgroundColor: Nge.barBackground,
      appBar: AppBar(
        title: ScreenTitle(
          _o.lib ?? tr('Sans étiquette'),
          missing == 0 ? tr('visuels · complets') : trn(missing, 'visuels · {0} manquant', 'visuels · {0} manquants'),
        ),
        // menu ⋮ à la place des pictos (notes rep8) : la saisie du support, les supports quittés, le repérage
        actions: [SupportMenu(object: _o, visuals: false)],
      ),
      bottomNavigationBar: SupportBar(object: _o, next: _reload),
      body: LayoutBuilder(builder: (context, c) {
        // tuiles d'au moins [VisualCard.minWidth], toutes du même style (notes rep9) : une colonne sur un téléphone en
        // portrait, deux sur une tablette en portrait ou un téléphone en paysage, trois sur une tablette en paysage,
        // davantage sur un écran très large
        final columns = math.max(1, ((c.maxWidth - 12) / (VisualCard.minWidth + 12)).floor());
        Widget card(Visual v) {
          final photos = _o.photos(v);
          return VisualCard(
            visual: v,
            count: photos.length,
            reference: photos.isEmpty ? null : photoImage(app, photos.first),
            onOpen: () => _open(GalleryScreen(object: _o, visual: v)),
            onPhoto: () async {
              if (await takePhoto(context, _o, v)) await _reload();
            },
            onMask: () => _open(MaskScreen(chamber: _o, face: v.code), tabSettings(_o, 'masques:${v.code}')),
          );
        }

        return ListView(padding: const EdgeInsets.all(12), children: [
          if (visuals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr('Aucun visuel attendu pour ce type. « Ajouter » crée un visuel libre.'),
                  style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            ),
          // rangées de tuiles de même hauteur (celle de la plus haute si une note ou un long titre l'allonge)
          for (var i = 0; i < visuals.length; i += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                  for (var j = i; j < i + columns; j++)
                    Expanded(child: j < visuals.length ? card(visuals[j]) : const SizedBox()),
                ]),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Carte d'un visuel, du même style sur tous les écrans (notes rep9) : titre et état, notes, puis la photo de
/// référence au format 4:3 des photos (ni bandeau ni photo étirée), les commandes en icônes à sa droite (prendre une
/// photo, grille du masque).
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

  /// Largeur minimale d'une tuile : en deçà de deux tuiles (téléphone en portrait), une seule colonne.
  static const minWidth = 340.0;

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
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Expanded(
                child: Text('${v.lib}${v.mandatory ? ' *' : ''}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              ),
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
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Photo(
                      image: reference,
                      missingText: count == 0 ? tr('Aucune photo') : tr('Photo non embarquée'),
                      label: tr('Photo de référence'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(spacing: 8, children: [
                IconButton.outlined(
                  tooltip: tr('Prendre une photo'),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  onPressed: onPhoto,
                ),
                if (v.action == 'MASQUE')
                  IconButton.outlined(
                    tooltip: tr('Grille du masque'),
                    icon: const Icon(Icons.grid_on),
                    onPressed: onMask,
                  ),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }
}
