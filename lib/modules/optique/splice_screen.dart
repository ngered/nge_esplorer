import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../providers/app_provider.dart';
import '../../theme.dart';
import '../../widgets/fields.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/support_bar.dart';
import '../immeuble/building.dart';
import '../infra/equipment.dart';
import 'equipment_screen.dart' show EquipmentScreen;
import 'fibready_chart.dart';
import 'optical.dart';
import 'route_panel.dart';

/// Écran Optique d'un équipement (boîte d'épissure, PBO, tiroir) : ses liens fibres, ouverts depuis son écran dédié
/// ([EquipmentScreen] ; onglet `liens:<EQU_CODE_EXT>` du support) : le boîtier, les câbles qui y sont raccordés, ses cassettes et
/// leurs positions (épissure, passage, attente, connecteur : fibre entrante, fibre sortante, affectation), les mesures
/// prises à l'équipement et les locaux qu'il dessert. Lecture seule : le contenu optique est préparé au BE (DOE).
/// Toucher une position déplie sous elle la route optique de sa fibre ([RoutePanel]) ; toucher une étape de la route
/// bascule aussitôt sur son boîtier, sur son connecteur ([focus]), la route toujours dépliée dessous ([route]) : dans
/// cet écran, à la place de l'onglet (autre équipement du support) ou du support affiché. Replier la route, en
/// touchant « Replier » ou à nouveau le connecteur, est une action volontaire, sans changement d'écran.
class SpliceScreen extends StatefulWidget {
  const SpliceScreen({super.key, required this.node, required this.equipment, this.focus, this.route});

  final GeoObject node;

  /// `EQU_CODE_EXT` de l'équipement (`inf.equipements` du nœud).
  final String equipment;

  /// Position à montrer à l'arrivée ([OpticalRoute.key]) : sa cassette dépliée, elle à l'écran, mise en évidence.
  final String? focus;

  /// Route dépliée sous [focus] à l'arrivée (étape touchée dans la route d'un autre boîtier).
  final List<RouteHop>? route;

  /// Onglet du support : `liens:<EQU_CODE_EXT>`.
  static String tab(String equipment) => '$tabPrefix$equipment';

  static const tabPrefix = 'liens:';

  /// Cassette dépliée d'office : la première ([cassettes] dans leur ordre), hors passages hors cassettes (cassette
  /// 0) s'il y en a une autre ; les autres sont repliées, sauf celle du connecteur à montrer ([focus]).
  static Object? firstCassette(List<Map<String, dynamic>> cassettes) =>
      (cassettes.where((c) => c['CAS_NUM'] != 0).firstOrNull ?? cassettes.firstOrNull)?['CAS_NUM'];

  @override
  State<SpliceScreen> createState() => _SpliceScreenState();
}

class _SpliceScreenState extends State<SpliceScreen> {
  /// Câbles cités par les positions et les mesures, et câbles raccordés, par code.
  final Map<String, GeoObject> _cables = {};

  /// Câbles raccordés à l'équipement (EQU1_KEY ou EQU2_KEY), avec le nœud de leur autre extrémité.
  List<(GeoObject, GeoObject?)> _connected = [];
  List<GeoObject> _served = [];
  bool _loaded = false;

  /// Position mise en évidence ([OpticalRoute.key]) et défilement jusqu'à elle à la prochaine image, l'écran chargé.
  late String? _focus = widget.focus;
  bool _scrollToFocus = true;
  final _focusKey = GlobalKey();

  /// Route dépliée : position sous laquelle elle l'est ([OpticalRoute.key]), étapes (null : en calcul), étape de ce
  /// boîtier.
  late String? _routeKey = widget.route == null ? null : widget.focus;
  late List<RouteHop>? _route = widget.route;
  late int _current = _indexIn(widget.route, widget.focus);

  /// Rang dans [route] de l'étape de cet équipement à la position [key].
  int _indexIn(List<RouteHop>? route, String? key) {
    final i = route?.indexWhere(
      (h) => h.equipment == widget.equipment && h.position != null && _key(h.position!) == key,
    );
    return i == null || i < 0 ? 0 : i;
  }

  Map<String, dynamic>? get _content => Optical.of(widget.node, widget.equipment);

  /// Devenir de la fibre de chaque position ([OpticalRoute.key]), fond de son connecteur à la charte FibReady ;
  /// calculé par la route de chaque fibre après le chargement.
  final Map<String, FibreFate> _fates = {};

  Future<void> _loadFates() async {
    final repo = context.read<AppProvider>().repo;
    final ref = context.read<AppProvider>().referenceData;
    for (final c in Optical.cassettes(_content)) {
      for (final p in Optical.positions(c)) {
        if (Optical.fibre(p, '1') == null && Optical.fibre(p, '2') == null) continue;
        final r = await OpticalRoute.trace(repo, widget.node, widget.equipment, p);
        if (!mounted) return;
        final i = _indexIn(r, _key(p));
        _fates[_key(p)] = FibReadyChart.fateOf(OpticalRoute.links(r, ref), i);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<AppProvider>().repo;
    final connected = <(GeoObject, GeoObject?)>[];
    for (final c in await repo.cablesOf(widget.node.id)) {
      final upstream = c.props['EQU2_KEY'] == widget.equipment;
      if (!upstream && c.props['EQU1_KEY'] != widget.equipment) continue;
      _cables[c.id] = c;
      // raccordement final : l'adresse desservie, à la place du nœud aval
      final other = upstream ? c.noe1 : c.noe2 ?? c.adr2;
      connected.add((c, other == null ? null : await repo.object(other)));
    }
    for (final id in Optical.citedCables(_content)) {
      if (_cables.containsKey(id)) continue;
      final c = await repo.object(id);
      if (c != null) _cables[id] = c;
    }
    final served = await repo.addressesServedBy(widget.equipment);
    if (!mounted) return;
    setState(() {
      _connected = connected
        ..sort(
          (a, b) => (a.$1.props['EQU2_KEY'] == widget.equipment ? 0 : 1).compareTo(
            b.$1.props['EQU2_KEY'] == widget.equipment ? 0 : 1,
          ),
        );
      _served = served..sort((a, b) => addressLabel(a).compareTo(addressLabel(b)));
      _loaded = true;
    });
    await _loadFates();
  }

  Map<String, dynamic>? get _infra => SupportEquipment.find(widget.node, widget.equipment);

  String _key(Map<String, dynamic> p) => OpticalRoute.key(widget.equipment, p);

  /// Toucher une position : sa route se déplie (à la place d'une autre) ; toucher celle dont la route est dépliée la
  /// replie.
  Future<void> _toggleRoute(Map<String, dynamic> p) async {
    final key = _key(p);
    if (_routeKey == key) return _fold();
    setState(() {
      _routeKey = key;
      _route = null;
      _current = 0;
    });
    final r = await OpticalRoute.trace(context.read<AppProvider>().repo, widget.node, widget.equipment, p);
    if (!mounted || _routeKey != key) return;
    setState(() {
      _route = r;
      _current = _indexIn(r, key);
    });
  }

  /// Replier la route : action volontaire, sans changement d'écran.
  void _fold() => setState(() {
    _routeKey = null;
    _route = null;
  });

  /// Étape [i] touchée dans la route : bascule aussitôt sur son boîtier, sur son connecteur, la route toujours dépliée
  /// dessous ; ici même si c'est cet équipement, sinon l'écran Optique de l'autre équipement, à la place de celui-ci
  /// (même support) ou du support affiché.
  Future<void> _goTo(int i) async {
    final r = _route;
    if (r == null || i >= r.length) return;
    final n = r[i].node, e = r[i].equipment, p = r[i].position;
    if (n == null || e == null || p == null) return;
    final focus = OpticalRoute.key(e, p);
    if (n.id == widget.node.id && e == widget.equipment) {
      setState(() {
        _routeKey = _focus = focus;
        _current = i;
        _scrollToFocus = true;
      });
    } else if (n.id == widget.node.id) {
      await openTab(
        context,
        n,
        SpliceScreen.tab(e),
        (o) => SpliceScreen(node: o, equipment: e, focus: focus, route: r),
      );
    } else {
      await openAt(
        context,
        n,
        (o) => (SpliceScreen.tab(e), SpliceScreen(node: o, equipment: e, focus: focus, route: r)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final ref = app.referenceData;
    final e = _content;
    final mat = ref.row('infra', 'MAT_EQUIP', 'MAT_ID', _infra?['MAT_KEY']);
    final label = e?['EQO_LIB'] as String? ?? (mat == null ? tr('Équipement') : SupportEquipment.label(mat));
    final cassettes = Optical.cassettes(e);
    final measures = Optical.measures(e)
      ..sort((a, b) {
        for (final k in ['MES_CABLE', 'MES_FIBRE', 'MES_LAMBDA']) {
          final c = '${a[k] ?? ''}'.padLeft(8).compareTo('${b[k] ?? ''}'.padLeft(8));
          if (c != 0) return c;
        }
        return 0;
      });
    // défilement jusqu'au connecteur une fois l'écran chargé : les câbles raccordés, lus après la première image,
    // s'insèrent au-dessus des cassettes et repousseraient le connecteur hors de l'écran (raccordements d'un PBO)
    if (_scrollToFocus && _focus != null && _loaded) {
      _scrollToFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _focusKey.currentContext;
        if (c != null && c.mounted) Scrollable.ensureVisible(c, alignment: 0.3);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: ScreenTitle(label, tr('optique')),
        // affichage des liens au choix, là où on les lit (aussi dans les Paramètres)
        actions: [
          SupportMenu(
            object: widget.node,
            actions: [
              for (final d in LinkDisplay.values)
                (
                  icon: d == app.linkDisplay ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  label: tr('Liens : {0}', [tr(d.lib)]),
                  onSelected: () => app.setLinkDisplay(d),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SupportBar(object: widget.node),
      // colonne entière (pas de liste paresseuse) : la position à montrer existe dès la première image
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Section(
              title: tr('Boîtier'),
              spacing: 4,
              children: [
                InfoLine(tr('Support'), widget.node.lib ?? tr('Sans étiquette')),
                if (e?['OTYP_KEY'] != null) InfoLine(tr('Type'), ref.equipmentType(e!['OTYP_KEY'] as int?) ?? '?'),
                if (mat != null) InfoLine(tr('Matériel'), SupportEquipment.label(mat)),
                if (e?['EQO_CAPA'] != null)
                  InfoLine(tr('Capacité'), trn(e!['EQO_CAPA'] as num, '{0} fibre', '{0} fibres')),
                if (e?['EQO_EMPLACEMENT'] != null) InfoLine(tr('Emplacement'), '${e!['EQO_EMPLACEMENT']}'),
                if (e?['EQO_PARENT_KEY'] != null)
                  InfoLine(
                    tr('Dans'),
                    Optical.of(widget.node, e!['EQO_PARENT_KEY'] as String?)?['EQO_LIB'] as String? ?? '?',
                  ),
                if (e?['AVCT_KEY'] != null) InfoLine(tr('Avancement'), ref.progress(e!['AVCT_KEY'] as int?) ?? '?'),
                if (e == null)
                  Text(
                    tr(
                      'Pas de contenu optique au paquet pour cet équipement : cassettes et positions à préparer au BE.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            if (_connected.isNotEmpty)
              Section(
                title: tr('Câbles raccordés'),
                children: [
                  for (final (c, other) in _connected)
                    _CableTile(cable: c, other: other, equipment: widget.equipment, ref: ref),
                ],
              ),
            for (final c in cassettes)
              Builder(
                builder: (context) {
                  final positions = Optical.positions(c);
                  final num = c['CAS_NUM'];
                  final focused = _focus != null && positions.any((p) => _key(p) == _focus);
                  final type = ref.cassetteType(c['CTYP_KEY'] as int?);
                  return Section(
                    title: num == 0
                        ? tr('Passages hors cassettes')
                        : [
                            tr('Cassette {0}', [num]),
                            ?type,
                          ].join(' — '),
                    // par défaut, seule la première cassette est dépliée (et celle du connecteur à montrer)
                    expanded: focused || num == SpliceScreen.firstCassette(cassettes),
                    action: Text(
                      trn(positions.length, '{0} position', '{0} positions'),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12, color: Nge.secondaryText),
                    ),
                    children: [
                      for (final (i, p) in positions.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _PositionRow(
                          key: _key(p) == _focus ? _focusKey : null,
                          position: p,
                          cables: _cables,
                          ref: ref,
                          focused: _key(p) == _focus,
                          equipmentType: ref.equipmentTypeCode(e?['OTYP_KEY'] as int?),
                          fibReady: app.fibReadyChart,
                          badges: app.linkDisplay == LinkDisplay.badges,
                          fate: _fates[_key(p)] ?? FibreFate.other,
                          // route optique de la fibre qui traverse la position, dépliée dessous (notes equipements rep3)
                          onRoute: Optical.fibre(p, '1') == null && Optical.fibre(p, '2') == null
                              ? null
                              : () => _toggleRoute(p),
                        ),
                        if (_routeKey == _key(p))
                          RoutePanel(
                            route: _route,
                            current: _current,
                            ref: ref,
                            onSelect: _goTo,
                            onFold: _fold,
                            fibReady: app.fibReadyChart,
                            badges: app.linkDisplay == LinkDisplay.badges,
                          ),
                      ],
                    ],
                  );
                },
              ),
            if (e != null && cassettes.isEmpty)
              Section(
                title: tr('Cassettes'),
                children: [
                  Text(
                    tr('Aucune cassette au paquet pour cet équipement.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            if (measures.isNotEmpty)
              Section(
                title: tr('Mesures'),
                expanded: measures.length <= 12,
                action: Text(
                  _measureSummary(measures),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12, color: Nge.secondaryText),
                ),
                children: [for (final m in measures) _MeasureTile(measure: m, cables: _cables)],
              ),
            if (_served.isNotEmpty)
              Section(
                title: tr('Locaux desservis'),
                expanded: _served.length <= 12,
                action: Text(
                  trn(_served.length, '{0} adresse', '{0} adresses'),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12, color: Nge.secondaryText),
                ),
                children: [
                  for (final a in _served)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.home_outlined),
                      title: Text(addressLabel(a)),
                      subtitle: Text(
                        premisesSummary([
                          for (final l in Building.premises(a))
                            if (l['EQU_KEY'] == widget.equipment) l,
                        ], ref),
                      ),
                    ),
                ],
              ),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  static String _measureSummary(List<Map<String, dynamic>> measures) {
    final failed = measures.where((m) => m['MES_CONFORME'] == 0).length;
    final n = trn(measures.length, '{0} mesure', '{0} mesures');
    return failed == 0 ? n : '$n · ${trn(failed, '{0} hors seuils', '{0} hors seuils')}';
  }
}

/// Câble raccordé : arrivée (amont, EQU2_KEY de l'équipement) ou départ (aval, EQU1_KEY), capacité, fonction, nœud
/// de l'autre extrémité.
class _CableTile extends StatelessWidget {
  const _CableTile({required this.cable, required this.other, required this.equipment, required this.ref});

  final GeoObject cable;
  final GeoObject? other;
  final String equipment;
  final ReferenceData ref;

  @override
  Widget build(BuildContext context) {
    final p = cable.props;
    final upstream = p['EQU2_KEY'] == equipment;
    final end =
        (other?.objectClass == ObjectClass.adr ? addressLabel(other!) : other?.lib) ??
        (upstream ? cable.noe1 : cable.noe2 ?? cable.adr2) ??
        '?';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(upstream ? Icons.call_received : Icons.call_made, color: Nge.petrolBlue),
      title: Text(cable.lib ?? cable.id),
      subtitle: Text(
        [
          if (p['CAB_CAPA'] != null) tr('{0} FO', [p['CAB_CAPA']]),
          ?ref.cableFunction(p['CFON_KEY'] as int?),
          upstream ? tr('depuis {0}', [end]) : tr('vers {0}', [end]),
        ].join(' · '),
      ),
    );
  }
}

/// Position d'une cassette : numéro, fonction (référentiel DEF_POS_FONCTION), connecteur, affectation ; fibre
/// entrante (FIB1) et fibre sortante (FIB2), une seule pour une attente ou un connecteur.
class _PositionRow extends StatelessWidget {
  const _PositionRow({
    super.key,
    required this.position,
    required this.cables,
    required this.ref,
    this.focused = false,
    this.equipmentType,
    this.fibReady = false,
    this.badges = false,
    this.fate = FibreFate.other,
    this.onRoute,
  });

  final Map<String, dynamic> position;
  final Map<String, GeoObject> cables;
  final ReferenceData ref;

  /// Position montrée à l'arrivée (repliage d'une route) : fond jaune.
  final bool focused;

  /// Fonction de l'équipement (`OTYP_CODE`) : une PTO distingue la prise abonné.
  final String? equipmentType;

  /// Route optique de la fibre de la position (null : position sans fibre).
  final VoidCallback? onRoute;

  /// Charte FibReady ([FibreRow]) : connecteur sur fond du devenir [fate] de la fibre.
  final bool fibReady;

  /// Variante en pastilles de la charte FibReady.
  final bool badges;
  final FibreFate fate;

  @override
  Widget build(BuildContext context) {
    final f1 = Optical.fibre(position, '1'), f2 = Optical.fibre(position, '2');
    Widget fibre(FibreRef f) => FibreText(fibre: f, cable: cables[f.cable], referenceData: ref);
    if (fibReady) return _fibReady(f1, f2);
    return Material(
      color: focused ? Nge.yellow.withValues(alpha: 0.35) : Colors.transparent,
      child: InkWell(
        onTap: onRoute,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Text('${position['POS_NUM'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // une seule mention du lien : attente abonné, réserve, fibre morte, fusion, passage…
                        LinkChip(position: position, ref: ref, equipmentType: equipmentType),
                        if (position['POS_CONNECTEUR'] != null)
                          Text('${position['POS_CONNECTEUR']}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    if (f1 != null) fibre(f1),
                    if (f2 != null)
                      Row(
                        children: [
                          if (f1 != null)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.subdirectory_arrow_right, size: 16, color: Nge.secondaryText),
                            ),
                          Flexible(child: fibre(f2)),
                        ],
                      ),
                  ],
                ),
              ),
              if (onRoute != null)
                Tooltip(
                  message: tr('Route optique'),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4, top: 2),
                    child: Icon(Icons.route_outlined, size: 20, color: Nge.slate),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ligne à la charte FibReady (maquette « schéma optique ») : `24Fo | T1 | F1 | -x- | F1 | T1 | 24Fo`, puis le
  /// rang de la position et l'accès à la route optique.
  Widget _fibReady(FibreRef? f1, FibreRef? f2) => Material(
    color: focused ? Nge.yellow.withValues(alpha: 0.35) : Colors.transparent,
    child: InkWell(
      onTap: onRoute,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: FibreRow(
                fibreIn: f1,
                badges: badges,
                cableIn: f1 == null ? null : cables[f1.cable],
                fibreOut: f2,
                cableOut: f2 == null ? null : cables[f2.cable],
                link: FibreLink.ofPosition(position, ref, equipmentType: equipmentType),
                fate: fate,
                ref: ref,
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${position['POS_NUM'] ?? ''}',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11, color: Nge.secondaryText),
              ),
            ),
            SizedBox(
              width: 32,
              child: onRoute == null
                  ? null
                  : Tooltip(
                      message: tr('Route optique'),
                      child: const Icon(Icons.route_outlined, size: 20, color: Nge.slate),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Mesure prise à l'équipement : fibre telle que nommée par l'appareil, longueur d'onde et sens, longueur, perte,
/// conformité aux seuils.
class _MeasureTile extends StatelessWidget {
  const _MeasureTile({required this.measure, required this.cables});

  final Map<String, dynamic> measure;
  final Map<String, GeoObject> cables;

  @override
  Widget build(BuildContext context) {
    final m = measure;
    final f = Optical.fibre(m);
    final (icon, color, status) = switch (m['MES_CONFORME']) {
      1 => (Icons.check_circle_outline, Nge.green, tr('conforme')),
      0 => (Icons.error_outline, Nge.red, tr('hors seuils')),
      _ => (Icons.help_outline, Nge.secondaryText, tr('non évaluée')),
    };
    final cable = m['MES_CABLE'] ?? (f == null ? null : cables[f.cable]?.lib ?? f.cable);
    final date = (m['MES_DATE'] as String?)?.split('T').first.split('-').reversed.join('/');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Tooltip(
        message: status,
        child: Icon(icon, color: color),
      ),
      title: Text(
        [
          ?cable,
          if ((m['MES_FIBRE'] ?? f?.num) != null) tr('fibre {0}', [m['MES_FIBRE'] ?? f?.num]),
          if (m['MES_LAMBDA'] != null) tr('{0} nm', [m['MES_LAMBDA']]),
          ?m['MES_SENS'],
        ].join(' · '),
      ),
      subtitle: Text(
        [
          if (m['MES_LNG'] != null) tr('{0} m', [decimal(m['MES_LNG'] as num)]),
          if (m['MES_PERTE'] != null) tr('{0} dB', [decimal(m['MES_PERTE'] as num, 3)]),
          if (m['MES_ORIGINE'] != null || m['MES_EXTREMITE'] != null)
            '${m['MES_ORIGINE'] ?? '?'} → ${m['MES_EXTREMITE'] ?? '?'}',
          ?date,
        ].join(' · '),
      ),
    );
  }
}
