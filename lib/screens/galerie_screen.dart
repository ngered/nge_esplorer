import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/objet.dart';
import '../data/visuels.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/barre_support.dart';
import '../widgets/titre_ecran.dart';
import 'visuels_screen.dart';

/// Galerie d'un visuel : ses photos dans l'ordre, la première étant la photo de référence ; réordonner (glisser
/// ou « Définir comme référence »), supprimer avec « Annuler ». Chaque geste est enregistré aussitôt.
class GalerieScreen extends StatefulWidget {
  const GalerieScreen({super.key, required this.objet, required this.visuel});

  final Objet objet;
  final Visuel visuel;

  @override
  State<GalerieScreen> createState() => _GalerieScreenState();
}

class _GalerieScreenState extends State<GalerieScreen> {
  late Objet _o = widget.objet;
  late Visuel _v = widget.visuel;

  Future<void> _recharger() async {
    final frais = await context.read<AppProvider>().repo.objet(_o.id);
    if (mounted && frais != null) setState(() => _o = frais);
  }

  /// Affiche la copie modifiée tout de suite, puis l'enregistre.
  Future<void> _enregistrer(Objet copie) async {
    final app = context.read<AppProvider>();
    setState(() => _o = copie);
    await app.enregistrer(copie);
    await _recharger();
  }

  Future<void> _deplacer(int de, int vers) async {
    if (vers > de) vers--; // indice d'arrivée avant retrait (convention de ReorderableListView)
    if (vers == de) return;
    final copie = _o.copie();
    final ordre = copie.photos(_v);
    ordre.insert(vers, ordre.removeAt(de));
    copie.ordonnerPhotos(ordre);
    await _enregistrer(copie);
  }

  Future<void> _supprimer(Map<String, dynamic> photo) async {
    final app = context.read<AppProvider>();
    final messager = ScaffoldMessenger.of(context);
    final avant = _o.copie();
    final copie = _o.copie();
    final f = copie.photos(_v).firstWhere((p) => p['FIC_CODE_EXT'] == photo['FIC_CODE_EXT']);
    copie.supprimerPhoto(_v, f, nouvelle: app.repo.fichiersNouveaux.containsKey(f['fichier']), auteur: app.auteur);
    await _enregistrer(copie);
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Photo supprimée'),
        action: SnackBarAction(
          label: 'ANNULER',
          onPressed: () async {
            await app.enregistrer(avant);
            if (mounted) await _recharger();
          },
        ),
      ));
  }

  Future<void> _renommer() async {
    final lib = await demanderTitre(context, titre: 'Renommer le visuel', initial: _v.lib);
    if (lib == null || lib == _v.lib || !mounted) return;
    final copie = _o.copie()..renommerVisuel(_v, lib);
    setState(() => _v = Visuel.libre(lib, _v.code));
    await _enregistrer(copie);
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
      backgroundColor: Nge.fondBarre,
      appBar: AppBar(
        title: TitreEcran(v.lib, '${_o.lib ?? 'Sans étiquette'} · ${photos.length} photo${photos.length > 1 ? 's' : ''}'),
        actions: [
          if (v.libre)
            IconButton(
              tooltip: 'Renommer le visuel',
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: _renommer,
            ),
          IconButton(
            tooltip: 'Prendre une photo',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: () async {
              if (await prendrePhoto(context, _o, v)) await _recharger();
            },
          ),
        ],
      ),
      bottomNavigationBar: BarreSupport(objet: _o, apres: _recharger),
      body: photos.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Aucune photo dans ce visuel.', style: t.bodyMedium, textAlign: TextAlign.center),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              buildDefaultDragHandles: false,
              header: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('La photo du haut est la photo de référence du visuel.', style: t.bodySmall),
              ),
              itemCount: photos.length,
              onReorder: _deplacer,
              itemBuilder: (context, i) {
                final f = photos[i];
                final chemin = f['fichier'] as String?;
                final octets = chemin == null ? null : app.repo.fichier(chemin);
                return Card(
                  key: ValueKey(f['FIC_CODE_EXT']),
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      height: 220,
                      child: octets != null
                          ? Image.memory(octets, fit: BoxFit.cover)
                          : const ColoredBox(
                              color: Nge.survol,
                              child: Center(
                                child: Text('Photo non embarquée', style: TextStyle(color: Nge.texteSecondaire)),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      child: Row(children: [
                        if (i == 0)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Nge.jaune, borderRadius: BorderRadius.circular(10)),
                            child: const Text('Référence',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nge.ardoiseFoncee)),
                          ),
                        Expanded(child: Text(_date(f['DATE_PRISE'] ?? f['DATE_CREA']), style: t.bodySmall)),
                        if (i > 0)
                          IconButton(
                            tooltip: 'Définir comme référence',
                            icon: const Icon(Icons.vertical_align_top),
                            onPressed: () => _deplacer(i, 0),
                          ),
                        IconButton(
                          tooltip: 'Supprimer la photo',
                          icon: const Icon(Icons.delete_outline, color: Nge.rouge),
                          onPressed: () => _supprimer(f),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle, semanticLabel: 'Déplacer'),
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
