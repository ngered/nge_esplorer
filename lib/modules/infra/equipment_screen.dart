import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../widgets/entry_screen.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/support_bar.dart';
import 'equipment.dart';

/// Équipements d'un support (barre basse) : ajout, retrait et, pour une boîte d'épissure, ses liens fibres.
/// Travaille comme la saisie du support sur une copie de l'objet, relue dans le dépôt à l'ouverture (photos prises
/// depuis un écran de module).
class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key, required this.object});

  final GeoObject object;

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  late GeoObject _o = widget.object.copy();
  bool _changed = false;

  /// Équipements ajoutés depuis le dernier enregistrement (retirés tout à fait, sinon abandonnés).
  final Set<String> _newEquipment = {};

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _save() async {
    final app = context.read<AppProvider>();
    await app.save(_o);
    final fresh = await app.repo.object(_o.id);
    if (!mounted) return;
    setState(() {
      _o = fresh!.copy();
      _changed = false;
      _newEquipment.clear();
    });
    showSaved(context);
  }

  Future<bool> _previous() async {
    if (_changed) await _save();
    return mounted;
  }

  Future<void> _next() async {
    final fresh = await context.read<AppProvider>().repo.object(_o.id);
    if (!mounted || fresh == null || _changed) return;
    setState(() => _o = fresh.copy());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return EntryScreen(
      changed: _changed,
      child: Scaffold(
        appBar: AppBar(
          title: ScreenTitle(_o.lib ?? tr('Sans étiquette'), tr('équipements')),
          actions: [SupportMenu(object: _o, previous: _previous)],
        ),
        bottomNavigationBar: SupportBar(object: _o, inEquipment: true, previous: _previous, next: _next),
        floatingActionButton: saveButton(visible: _changed, onPressed: _save),
        body: ListView(
          padding: const EdgeInsets.only(bottom: fabMargin),
          children: [
            SupportEquipment(
              node: _o,
              referenceData: app.referenceData,
              author: app.author,
              newIds: _newEquipment,
              onChanged: () => setState(() => _changed = true),
            ),
          ],
        ),
      ),
    );
  }
}
