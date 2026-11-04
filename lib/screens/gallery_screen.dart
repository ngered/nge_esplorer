import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/geo_object.dart';
import '../data/visuals.dart';
import '../lng.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/support_bar.dart';
import '../widgets/photo.dart';
import '../widgets/screen_title.dart';
import 'visuals_screen.dart';
import '../widgets/messages.dart';

/// Galerie d'un visuel : ses photos dans l'ordre, la première étant la photo de référence ; réordonner (glisser
/// ou « Définir comme référence »), supprimer avec « Annuler ». Chaque geste est enregistré aussitôt, appliqué au
/// support tel qu'il est dans le dépôt : l'objet passé a pu vieillir, et d'autres écrans ont pu l'enregistrer.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.object, required this.visual});

  final GeoObject object;
  final Visual visual;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> with UndoMessage<GalleryScreen> {
  late GeoObject _o = widget.object;
  late Visual _v = widget.visual;

  /// Un geste vient de changer la galerie (suppression, déplacement) : les commandes des tuiles restent inactives un
  /// instant, le temps que les tuiles se replacent, pour qu'un double toucher n'agisse pas sur la photo voisine.
  bool _settling = false;
  Timer? _settle;

  /// Photos supprimées à la suite, et ordre d'avant la première : « Annuler » les rétablit toutes.
  final List<Map<String, dynamic>> _deleted = [];
  List<Object?> _orderBeforeDeletion = const [];

  /// Défilement de la liste quand on glisse une photo près de son bord.
  EdgeDraggingAutoScroller? _scroller;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _settle?.cancel();
    _scroller?.stopAutoScroll();
    super.dispose();
  }

  /// Commandes inactives jusqu'à un moment après la fin du geste en cours.
  Future<void> _gesture(Future<void> Function() action) async {
    if (_settling) return;
    _settle?.cancel();
    setState(() => _settling = true);
    try {
      await action();
    } finally {
      _settle = Timer(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _settling = false);
      });
    }
  }

  Future<void> _reload() async {
    final fresh = await context.read<AppProvider>().repo.object(_o.id);
    if (mounted && fresh != null) setState(() => _o = fresh);
  }

  /// Applique [change] à une copie du support relu dans le dépôt, l'affiche tout de suite, puis l'enregistre. Toute
  /// autre écriture qu'une suppression rend caduc l'« Annuler » des suppressions précédentes.
  Future<void> _save(void Function(GeoObject o) change, {bool deletion = false}) async {
    final app = context.read<AppProvider>();
    if (!deletion) {
      hideUndo();
      _deleted.clear();
    }
    final copy = (await app.repo.object(_o.id) ?? _o).copy();
    change(copy);
    if (mounted) setState(() => _o = copy);
    await app.save(copy);
    if (mounted) await _reload();
  }

  /// Ordre de la galerie : les photos [codes] (FIC_CODE_EXT) dans cet ordre, les autres ensuite.
  void _order(GeoObject o, List<Object?> codes) {
    final photos = o.photos(_v);
    final byCode = {for (final p in photos) p['FIC_CODE_EXT']: p};
    o.reorderPhotos([
      for (final c in codes) ?byCode[c],
      for (final p in photos)
        if (!codes.contains(p['FIC_CODE_EXT'])) p,
    ]);
  }

  /// Place la photo [code] (FIC_CODE_EXT) au rang qu'occupe la photo [at] (tuile déposée sur une autre, « Définir
  /// comme référence ») ; rien si l'une a disparu entre-temps.
  Future<void> _move(Object? code, Object? at) => _gesture(() async {
        final codes = [for (final p in _o.photos(_v)) p['FIC_CODE_EXT']];
        final from = codes.indexOf(code), to = codes.indexOf(at);
        if (from < 0 || to < 0 || from == to) return;
        codes.insert(to, codes.removeAt(from));
        await _save((o) => _order(o, codes));
      });

  /// Photo en plein écran, agrandie au pincement ou à la molette.
  Future<void> _view(Map<String, dynamic> f) async {
    final image = photoImage(context.read<AppProvider>(), f);
    if (image == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PhotoViewer(image: image, title: _v.lib, date: _date(f['DATE_PRISE'] ?? f['DATE_CREA']))),
    );
  }

  Future<void> _delete(Map<String, dynamic> photo) => _gesture(() async {
        final app = context.read<AppProvider>();
        // suppressions à la suite, tant que leur « Annuler » est affiché : il les rétablira toutes
        if (!undoShown) {
          _deleted.clear();
          _orderBeforeDeletion = [for (final p in _o.photos(_v)) p['FIC_CODE_EXT']];
        }
        final entry = Map<String, dynamic>.of(photo);
        _deleted.add(entry);
        final isNew = app.repo.newFiles.containsKey(photo['fichier']);
        await _save(deletion: true, (o) {
          final f = o.photos(_v).where((p) => p['FIC_CODE_EXT'] == entry['FIC_CODE_EXT']).firstOrNull;
          if (f != null) o.deletePhoto(_v, f, isNew: isNew, author: app.author);
        });
        if (!mounted) return;
        final entries = List.of(_deleted), order = _orderBeforeDeletion;
        showUndo(trn(entries.length, 'Photo supprimée', '{0} photos supprimées'), () => _restore(entries, order));
      });

  /// « Annuler » des suppressions : les seules photos [entries] reviennent, à leur place dans l'ordre d'avant
  /// ([codes]), sur le support tel qu'il est dans le dépôt.
  Future<void> _restore(List<Map<String, dynamic>> entries, List<Object?> codes) => _save((o) {
        for (final entry in entries) {
          final f = o.files.where((p) => p['FIC_CODE_EXT'] == entry['FIC_CODE_EXT']).firstOrNull;
          if (f == null) {
            o.props['fichiers'] = [...o.files, Map<String, dynamic>.of(entry)];
          } else {
            f
              ..remove('DATE_ABD')
              ..remove('SRC_ABD');
          }
        }
        _order(o, codes);
      });

  Future<void> _rename() async {
    final lib = await askTitle(context, title: tr('Renommer le visuel'), initial: _v.lib);
    if (lib == null || lib == _v.lib || !mounted) return;
    final old = _v;
    setState(() => _v = Visual.free(lib, old.code));
    await _save((o) => o.renameVisual(old, lib));
  }

  Future<void> _takePhoto() async {
    hideUndo();
    if (await takePhoto(context, _o, _v)) await _reload();
  }

  static String _date(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    String n(int v) => v.toString().padLeft(2, '0');
    return '${n(d.day)}/${n(d.month)}/${d.year} ${n(d.hour)}:${n(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final v = _v;
    final photos = _o.photos(v);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Nge.barBackground,
      appBar: AppBar(
        title: ScreenTitle(v.lib, '${_o.lib ?? tr('Sans étiquette')} · ${trn(photos.length, '{0} photo', '{0} photos')}'),
        // menu ⋮ à la place des pictos (notes rep8) : prendre une photo, renommer un visuel libre, puis les écrans
        // du support
        actions: [
          SupportMenu(
            object: _o,
            previous: () async {
              hideUndo();
              return true;
            },
            actions: [
              (icon: Icons.add_a_photo_outlined, label: tr('Prendre une photo'), onSelected: _takePhoto),
              if (v.free) (icon: Icons.drive_file_rename_outline, label: tr('Renommer le visuel'), onSelected: _rename),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SupportBar(
        object: _o,
        // un visuel ajouté ou un onglet ouvert depuis la barre : l'« Annuler » de la galerie ne vaut plus
        previous: () async {
          hideUndo();
          return true;
        },
        next: _reload,
      ),
      body: photos.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Aucune photo dans ce visuel.'), style: t.bodyMedium, textAlign: TextAlign.center),
              ),
            )
          // tuiles comme les visuels (notes rep10) : chaque photo entière, au format 4:3 ; une colonne sur un téléphone
          // en portrait, davantage sur les écrans larges
          : LayoutBuilder(builder: (context, c) {
              final columns = math.max(1, ((c.maxWidth - 12) / (VisualCard.minWidth + 12)).floor());
              return ListView(padding: const EdgeInsets.all(12), children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tr('La première photo est la photo de référence du visuel. Toucher une photo l\'affiche en grand ; '
                       'appui long pour la déplacer.'),
                    style: t.bodySmall,
                  ),
                ),
                for (var i = 0; i < photos.length; i += columns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                        for (var j = i; j < i + columns; j++)
                          Expanded(child: j < photos.length ? _tile(app, photos, j) : const SizedBox()),
                      ]),
                    ),
                  ),
              ]);
            }),
    );
  }

  /// Vignette d'une photo glissée, centrée sous le doigt.
  static const _dragSize = Size(160, 120);

  /// Tuile de la photo de rang [i] : appui long pour la déposer sur une autre tuile, qui prend sa place ; la photo
  /// glissée est désignée par son identifiant (la galerie peut changer pendant le geste) ; la liste défile quand on
  /// approche de son bord.
  Widget _tile(AppProvider app, List<Map<String, dynamic>> photos, int i) {
    final f = photos[i];
    final code = f['FIC_CODE_EXT'] as String?;
    final image = photoImage(app, f);
    return DragTarget<String>(
      key: ValueKey(code),
      onWillAcceptWithDetails: (d) => d.data != code && !_settling,
      onAcceptWithDetails: (d) => _move(d.data, code),
      builder: (context, candidates, _) {
        Widget card({bool target = false}) => _PhotoCard(
              image: image,
              reference: i == 0,
              date: _date(f['DATE_PRISE'] ?? f['DATE_CREA']),
              target: target,
              onView: () => _view(f),
              onReference: i == 0 || _settling ? null : () => _move(code, photos.first['FIC_CODE_EXT']),
              onDelete: _settling ? null : () => _delete(f),
            );
        return LongPressDraggable<String>(
          data: code,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => _scroller = EdgeDraggingAutoScroller(Scrollable.of(context), velocityScalar: 50),
          // la liste défile dès que la vignette franchit son bord
          onDragUpdate: (d) => _scroller?.startAutoScrollIfNecessary(
              Rect.fromCenter(center: d.globalPosition, width: _dragSize.width, height: _dragSize.height)),
          onDragEnd: (_) => _scroller?.stopAutoScroll(),
          feedback: Transform.translate(
            offset: Offset(-_dragSize.width / 2, -_dragSize.height / 2),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: SizedBox.fromSize(
                size: _dragSize,
                child: ColoredBox(
                  color: Nge.slateDark,
                  child: Photo(image: image, missingText: '', fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: card()),
          child: card(target: candidates.isNotEmpty),
        );
      },
    );
  }
}

/// Carte d'une photo de la galerie : la photo entière au format 4:3, sur fond sombre (une photo prise en hauteur
/// n'est pas rognée), puis référence, date et commandes ; [target] : une photo déplacée la survole.
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.image,
    required this.reference,
    required this.date,
    required this.target,
    required this.onView,
    required this.onReference,
    required this.onDelete,
  });

  final ImageProvider? image;
  final bool reference;
  final String date;
  final bool target;
  final VoidCallback onView;
  final VoidCallback? onReference;

  /// Null : inactif un instant (un geste vient de changer la galerie).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: target
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Nge.yellow, width: 3),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: image == null ? null : onView,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: Nge.slateDark,
              child: Photo(image: image, missingText: tr('Photo non embarquée'), fit: BoxFit.contain),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(children: [
            if (reference)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Nge.yellow, borderRadius: BorderRadius.circular(10)),
                child: Text(tr('Référence'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nge.slateDark)),
              ),
            Expanded(child: Text(date, style: t.bodySmall)),
            if (!reference)
              IconButton(
                tooltip: tr('Définir comme référence'),
                icon: const Icon(Icons.vertical_align_top),
                onPressed: onReference,
              ),
            IconButton(
              tooltip: tr('Supprimer la photo'),
              icon: const Icon(Icons.delete_outline, color: Nge.red),
              onPressed: onDelete,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(Icons.drag_indicator, semanticLabel: tr('Déplacer')),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Photo en plein écran sur fond noir, agrandie au pincement (molette sous Windows), déplacée au glissement.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.image, required this.title, required this.date});

  final ImageProvider image;
  final String title;
  final String date;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: ScreenTitle(title, date)),
        body: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Center(
            child: Photo(image: image, missingText: tr('Photo introuvable'), fit: BoxFit.contain),
          ),
        ),
      );
}
