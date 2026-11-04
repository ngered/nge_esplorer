import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/geo_object.dart';
import '../data/geocoding.dart';
import '../data/reference_data.dart';
import '../lng.dart';
import '../modules/chambre/chamber_sheet.dart';
import '../modules/poteau/pole_sheet.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/support_bar.dart';
import '../widgets/comments.dart';
import '../widgets/fields.dart';
import '../widgets/back_to_map.dart';
import '../widgets/entry_screen.dart';
import '../widgets/linear_list.dart';
import '../widgets/screen_title.dart';
import 'address_screen.dart';

/// Saisie d'un support (crayon des visuels) : identification (noyau), caractéristiques et contrôles du module selon
/// le type, commentaires (journal daté et signé), linéaires rattachés, suppression. Les photos sont dans les visuels.
/// Chambre : cartes dépliables Général, Dimensions, Commentaires. Les équipements, les masques et les conduites ont
/// leurs onglets (barre basse). Poteau : cartes dépliables Général, Contrôles, Commentaires ; les portées et les
/// autres parcours sont dans l'onglet Portées.
/// La saisie travaille sur une copie, écrite dans le dépôt à l'enregistrement.
class ObjectScreen extends StatefulWidget {
  const ObjectScreen({super.key, required this.object, this.geocoder, this.linear});

  final GeoObject object;

  /// Détection de l'adresse (par défaut Géoplateforme et Photon).
  final Geocoder? geocoder;

  /// Portée ou parcours sélectionné à l'ouverture, avec son carton (autres supports : arrivée d'un parcours suivi,
  /// support rouvert par le menu ⋮).
  final String? linear;

  @override
  State<ObjectScreen> createState() => _ObjectScreenState();
}

class _ObjectScreenState extends State<ObjectScreen> {
  late GeoObject _o = widget.object.copy();
  bool _changed = false;
  Linears _linears = (linears: const [], ends: const {});

  /// Portée ou parcours sélectionné dans la liste des autres supports (façades…) : son carton « Naviguer vers ».
  late String? _selectedLinear = widget.linear;
  Route<dynamic>? _route;
  GeoObject? _address;

  /// Adresse choisie ou modifiée dans l'écran de l'adresse, enregistrée avec le support.
  GeoObject? _pendingAddress;

  @override
  void initState() {
    super.initState();
    _loadLinears();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _select(_selectedLinear);
  }

  /// Sélectionne la portée ou le parcours [id] (null : aucun), noté avec le support tel qu'il est enregistré (son
  /// intitulé à jour) pour rouvrir la saisie dans le même état (menu ⋮).
  void _select(String? id) {
    if (id != _selectedLinear) setState(() => _selectedLinear = id);
    final r = _route;
    if (r != null) screenStack.note(r, tab: 'saisie', selection: id, object: _changed ? null : _o.copy());
  }

  Future<void> _loadLinears() async {
    final repo = context.read<AppProvider>().repo;
    final l = await loadLinears(repo, _o);
    final adr = _o.props['ADR_KEY'] as String?;
    if (_pendingAddress == null) _address = adr == null ? null : await repo.object(adr);
    if (mounted) setState(() => _linears = l);
  }

  void _change() => setState(() => _changed = true);

  Future<void> _editAddress() async {
    final choice = await Navigator.push<AddressChoice>(
      context,
      MaterialPageRoute(builder: (_) => AddressScreen(node: _o, current: _address, geocoder: widget.geocoder)),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _address = _pendingAddress = choice.address;
      GeoObject.put(_o.props, 'ADR_KEY', choice.address?.id);
      _changed = true;
    });
  }

  Future<void> _save() async {
    final app = context.read<AppProvider>();
    final a = _pendingAddress;
    // l'adresse d'abord (nouvelle ou modifiée), le support la référence ; inchangée, elle n'est pas réécrite
    if (a != null) {
      final stored = await app.repo.object(a.id);
      if (stored == null || jsonEncode(stored.props) != jsonEncode(a.props)) await app.save(a);
    }
    await app.save(_o);
    final fresh = await app.repo.object(_o.id);
    if (!mounted) return;
    setState(() {
      _o = fresh!.copy();
      _changed = false;
      _pendingAddress = null;
    });
    _select(_selectedLinear);
    showSaved(context);
  }

  /// Avant d'ouvrir les portées ou d'ajouter un visuel : la saisie en cours est enregistrée.
  Future<bool> _previous() async {
    if (_changed) await _save();
    return mounted;
  }

  /// « Naviguer vers » : la saisie en cours est enregistrée, puis le support d'en face s'ouvre à la place de celui-ci,
  /// sur son écran des parcours (portées, aperçu des masques).
  Future<void> _navigate(GeoObject linear, GeoObject other) async {
    if (!await _previous() || !mounted) return;
    await follow(context, linear, other, route: true);
  }

  /// Ensuite : l'objet a pu changer (orientation, photos), les linéaires aussi.
  Future<void> _next() async {
    final fresh = await context.read<AppProvider>().repo.object(_o.id);
    if (!mounted || fresh == null) return;
    setState(() => _o = fresh.copy());
    _select(_selectedLinear);
    await _loadLinears();
  }

  /// Supprimer le support : abandon (DATE_ABD), validé au contrôle du retour ; retour à la carte.
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Supprimer le support ?')),
        content: Text(tr('{0} sera marqué supprimé. La suppression sera validée au contrôle du retour.',
            [_o.lib ?? tr('Le support')])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nge.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Supprimer')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = _o.id;
    await context.read<AppProvider>().save(_o, abandon: true);
    if (!mounted) return;
    setState(() => _changed = false);
    showSaved(context, tr('Support supprimé'));
    await WidgetsBinding.instance.endOfFrame; // l'écran ne demande plus confirmation avant de se fermer
    if (mounted) await backToMap(context);
    // le support quitté n'est plus proposé par le menu ⋮
    screenStack.forget(id);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final ref = app.referenceData;
    final family = ref.familyCode(_o.typeKey);
    final selected = family == 'CHB' || family == 'POT'
        ? null
        : _linears.linears.where((l) => l.id == _selectedLinear).firstOrNull;
    return EntryScreen(
      changed: _changed,
      child: Scaffold(
        appBar: AppBar(
          title: ScreenTitle(
            _o.lib ?? tr('Sans étiquette'),
            [tr('saisie du support'), if (_o.status == 'C') tr('créé'), if (_o.status == 'M') tr('modifié')].join(' · '),
          ),
          actions: [SupportMenu(object: _o, previous: _previous, entry: false)],
        ),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          if (selected != null)
            RouteCard(
              linear: selected,
              other: _linears.ends[selected.noe1 == _o.id ? selected.noe2 : selected.noe1],
              referenceData: ref,
              onNavigate: _navigate,
              onClose: () => _select(null),
            ),
          SupportBar(object: _o, previous: _previous, next: _next),
        ]),
        floatingActionButton: saveButton(visible: _changed, onPressed: _save),
        body: ListView(
          padding: const EdgeInsets.only(bottom: fabMargin),
          children: [
            if (family == 'CHB') ...[
              // cartes dépliables ; équipements, masques et conduites par la barre basse
              _general(ref, family, [ChamberReference(node: _o, referenceData: ref, onChanged: _change)]),
              ChamberDimensions(node: _o, referenceData: ref, onChanged: _change),
              CommentsCard(object: _o, onChanged: _change, expanded: true),
            ] else if (family == 'POT') ...[
              // cartes dépliables ; équipements et portées (avec les autres parcours) par la barre basse
              _general(ref, family, [PoleSpecs(node: _o, referenceData: ref, onChanged: _change)]),
              PoleChecks(node: _o, onChanged: _change),
              CommentsCard(object: _o, onChanged: _change, expanded: true),
            ] else ...[
              _identification(ref, family),
              CommentsCard(object: _o, onChanged: _change),
              LinearList(
                node: _o,
                data: _linears,
                referenceData: ref,
                title: tr('Portées et parcours'),
                selected: _selectedLinear,
                onSelect: (l) => _select(l.id == _selectedLinear ? null : l.id),
              ),
            ],
            if (_o.objectClass == ObjectClass.noe && !_o.outOfZone)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Nge.red,
                    side: const BorderSide(color: Color(0xFFE8B4B4)),
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr('Supprimer le support')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Adresse rattachée (numéro, voie, code postal, commune), null si absente.
  String? get _addressLabel {
    final a = _address?.props;
    if (a == null) return null;
    String joinValues(List<String> columns) =>
        [for (final c in columns) '${a[c] ?? ''}'.trim()].where((t) => t.isNotEmpty).join(' ');
    final t = [joinValues(['ADR_NUMERO', 'ADR_REP', 'ADR_VOIE']), joinValues(['ADR_CP', 'ADR_COMMUNE'])].where((t) => t.isNotEmpty);
    return t.isEmpty ? null : t.join(', ');
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String z(int n) => n.toString().padLeft(2, '0');
    return '${z(d.day)}/${z(d.month)}/${d.year}';
  }

  /// Type parmi ceux du même module (chambre, chambre FT, chambre SAT…), si le choix existe.
  Widget? _typeField(ReferenceData ref, String? family) {
    final types = [
      for (final t in ref.table('noyau', 'DEF_TYPE'))
        if (family != null && (t['ACTIF'] ?? 1) == 1 && ref.familyCode(t['TYPE_ID'] as int?) == family) t,
    ];
    if (_o.objectClass != ObjectClass.noe || types.length < 2) return null;
    return ChoiceField(
        m: _o.props, column: 'TYPE_KEY', label: tr('Type'), rows: types, colId: 'TYPE_ID', colLabel: 'TYPE_LIB',
        optional: false, onChanged: _change);
  }

  Widget _iconLine(IconData icon, String text) => Row(children: [
        Icon(icon, size: 20, color: Nge.secondaryText),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]);

  /// Adresse rattachée ; la toucher ouvre l'écran de l'adresse (sauf hors zone).
  Widget? _addressLine() {
    if (_o.objectClass != ObjectClass.noe) return null;
    final line = _iconLine(Icons.home_outlined,
        _addressLabel ?? (_o.props['ADR_KEY'] == null ? tr('Aucune adresse rattachée') : tr('Adresse non renseignée')));
    if (_o.outOfZone) return line;
    return InkWell(
      onTap: _editAddress,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: line),
          Tooltip(message: tr('Modifier l\'adresse'), child: const Icon(Icons.edit_outlined, size: 20, color: Nge.slate)),
        ]),
      ),
    );
  }

  /// Position, état particulier et identifiant ; la date de modification si [withDate].
  Widget _infoLine({bool withDate = true}) {
    final p = _o.point;
    final modifiedAt = _o.props['DATE_MODIF'] as String?;
    return Text(
      [
        if (withDate && modifiedAt != null) tr('modifié le {0}', [_date(modifiedAt)]),
        if (p != null) '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
        if (_o.props['GEOL_MOD_KEY'] == 8) tr('position à relever'),
        if (_o.outOfZone) tr('hors zone (consultation)'),
        'id ${_o.id}',
      ].join(' · '),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _identification(ReferenceData ref, String? family) =>
      Section(title: ref.typeLabel(_o.typeKey), spacing: 12, children: [
        ?_typeField(ref, family),
        StringField(m: _o.props, column: 'NOE_LIB', label: tr('Étiquette (n° d\'appui, de chambre…)'), onChanged: _change),
        ?_addressLine(),
        _infoLine(),
      ]);

  /// Carte Général d'un module à cartes dépliables : date, type, numéro, champs du module ([specs]), adresse.
  Widget _general(ReferenceData ref, String? family, List<Widget> specs) {
    final modifiedAt = _o.props['DATE_MODIF'] as String?;
    return Section(title: tr('Général'), expanded: true, spacing: 12, children: [
      _iconLine(Icons.event_outlined, modifiedAt == null ? tr('Jamais modifié') : tr('Modifié le {0}', [_date(modifiedAt)])),
      ?_typeField(ref, family),
      StringField(m: _o.props, column: 'NOE_LIB', label: tr('Numéro'), onChanged: _change),
      ...specs,
      ?_addressLine(),
      _infoLine(withDate: false),
    ]);
  }
}
