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

/// Galerie d'un visuel : ses photos dans l'ordre, la première étant la photo de référence ; réordonner (glisser
/// ou « Définir comme référence »), supprimer avec « Annuler ». Chaque geste est enregistré aussitôt.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.object, required this.visual});

  final GeoObject object;
  final Visual visual;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late GeoObject _o = widget.object;
  late Visual _v = widget.visual;

  Future<void> _reload() async {
    final fresh = await context.read<AppProvider>().repo.object(_o.id);
    if (mounted && fresh != null) setState(() => _o = fresh);
  }

  /// Affiche la copie modifiée tout de suite, puis l'enregistre.
  Future<void> _save(GeoObject copy) async {
    final app = context.read<AppProvider>();
    setState(() => _o = copy);
    await app.save(copy);
    await _reload();
  }

  Future<void> _move(int from, int to) async {
    if (to > from) to--; // indice d'arrivée avant retrait (convention de ReorderableListView)
    if (to == from) return;
    final copy = _o.copy();
    final order = copy.photos(_v);
    order.insert(to, order.removeAt(from));
    copy.reorderPhotos(order);
    await _save(copy);
  }

  Future<void> _delete(Map<String, dynamic> photo) async {
    final app = context.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final previous = _o.copy();
    final copy = _o.copy();
    final f = copy.photos(_v).firstWhere((p) => p['FIC_CODE_EXT'] == photo['FIC_CODE_EXT']);
    copy.deletePhoto(_v, f, isNew: app.repo.newFiles.containsKey(f['fichier']), author: app.author);
    await _save(copy);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Photo supprimée')),
        action: SnackBarAction(
          label: 'ANNULER',
          onPressed: () async {
            await app.save(previous);
            if (mounted) await _reload();
          },
        ),
      ));
  }

  Future<void> _rename() async {
    final lib = await askTitle(context, title: tr('Renommer le visuel'), initial: _v.lib);
    if (lib == null || lib == _v.lib || !mounted) return;
    final copy = _o.copy()..renameVisual(_v, lib);
    setState(() => _v = Visual.free(lib, _v.code));
    await _save(copy);
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
        actions: [
          if (v.free)
            IconButton(
              tooltip: tr('Renommer le visuel'),
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: _rename,
            ),
          IconButton(
            tooltip: tr('Prendre une photo'),
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: () async {
              if (await takePhoto(context, _o, v)) await _reload();
            },
          ),
        ],
      ),
      bottomNavigationBar: SupportBar(object: _o, next: _reload),
      body: photos.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Aucune photo dans ce visuel.'), style: t.bodyMedium, textAlign: TextAlign.center),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              buildDefaultDragHandles: false,
              header: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('La photo du haut est la photo de référence du visuel.'), style: t.bodySmall),
              ),
              itemCount: photos.length,
              onReorder: _move,
              itemBuilder: (context, i) {
                final f = photos[i];
                return Card(
                  key: ValueKey(f['FIC_CODE_EXT']),
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      height: 220,
                      child: Photo(image: photoImage(app, f), missingText: tr('Photo non embarquée')),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      child: Row(children: [
                        if (i == 0)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Nge.yellow, borderRadius: BorderRadius.circular(10)),
                            child: Text(tr('Référence'),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nge.slateDark)),
                          ),
                        Expanded(child: Text(_date(f['DATE_PRISE'] ?? f['DATE_CREA']), style: t.bodySmall)),
                        if (i > 0)
                          IconButton(
                            tooltip: tr('Définir comme référence'),
                            icon: const Icon(Icons.vertical_align_top),
                            onPressed: () => _move(i, 0),
                          ),
                        IconButton(
                          tooltip: tr('Supprimer la photo'),
                          icon: const Icon(Icons.delete_outline, color: Nge.red),
                          onPressed: () => _delete(f),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle, semanticLabel: tr('Déplacer')),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}
