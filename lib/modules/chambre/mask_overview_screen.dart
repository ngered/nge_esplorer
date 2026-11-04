import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../widgets/fields.dart';
import '../../widgets/linear_list.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/support_bar.dart';
import 'mask_editor.dart';
import 'mask_screen.dart';

/// Aperçu des masques de la chambre (bouton Masques de la barre basse) : une ligne par face, toucher une face ouvre
/// sa grille ; dessous, les conduites (parcours vers les autres supports, conduites sans destination connue).
/// L'objet et ses linéaires sont relus dans le dépôt à l'ouverture et au retour de la grille.
class MaskOverviewScreen extends StatefulWidget {
  const MaskOverviewScreen({super.key, required this.chamber});

  final GeoObject chamber;

  @override
  State<MaskOverviewScreen> createState() => _MaskOverviewScreenState();
}

class _MaskOverviewScreenState extends State<MaskOverviewScreen> {
  late GeoObject _o = widget.chamber;
  Linears _linears = (linears: const [], ends: const {});

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = context.read<AppProvider>().repo;
    final fresh = await repo.object(_o.id);
    if (fresh == null) return;
    final l = await loadLinears(repo, fresh);
    if (mounted) {
      setState(() {
        _o = fresh;
        _linears = l;
      });
    }
  }

  Future<void> _open(String face) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MaskScreen(chamber: _o, face: face)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final noDestination = MaskEditor.ductsOf(_o).length;
    return Scaffold(
      appBar: AppBar(title: ScreenTitle(_o.lib ?? tr('Sans étiquette'), tr('masques'))),
      bottomNavigationBar: SupportBar(object: _o, inModule: true, next: _reload),
      body: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
        ChamberMasks(node: _o, onOpen: _open),
        LinearList(
          node: _o,
          data: _linears,
          referenceData: context.watch<AppProvider>().referenceData,
          title: tr('Conduites'),
          extra: [
            if (noDestination > 0)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Sans destination connue')),
                subtitle: Text(trn(noDestination, '{0} conduite', '{0} conduites')),
              ),
          ],
        ),
      ]),
    );
  }
}

/// Masques de la chambre : une ligne par face (alvéoles, grille) ; toucher une face ouvre sa grille.
class ChamberMasks extends StatelessWidget {
  const ChamberMasks({super.key, required this.node, required this.onOpen});

  final GeoObject node;
  final void Function(String face) onOpen;

  @override
  Widget build(BuildContext context) {
    final faces = {
      for (final f in (node.namespace('chb')?['faces'] as List?) ?? const []) '${(f as Map)['FAC_CODE']}': f,
    };
    return Section(title: tr('Masques'), children: [
      for (final code in chamberFaces)
        Builder(builder: (context) {
          final f = faces[code];
          final n = ((f?['positions'] as List?) ?? const []).where((p) => (p as Map)['DATE_ABD'] == null).length;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, child: Text(code)),
            title: Text(n == 0 ? tr('Face non relevée') : trn(n, '{0} alvéole', '{0} alvéoles')),
            subtitle: f?['FAC_NB_COL'] == null ? null : Text(tr('Grille {0} × {1}', [f!['FAC_NB_COL'], f['FAC_NB_LIG']])),
            trailing: const Icon(Icons.grid_on_outlined),
            onTap: () => onOpen(code),
          );
        }),
    ]);
  }
}
