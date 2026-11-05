import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../data/geo_object.dart';
import '../data/geocoding.dart';
import '../lng.dart';
import '../modules/immeuble/building.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/fields.dart';
import '../widgets/screen_title.dart';
import '../widgets/messages.dart';

/// Adresse choisie : celle du paquet (copie, éventuellement modifiée), une nouvelle, ou aucune (détachée).
typedef AddressChoice = ({GeoObject? address});

/// Adresse d'un support (fiche « Adresse édition » de FibReady) : sélection par commune, voie et adresse parmi
/// celles du paquet, ou nouvelle adresse ; détail (numéro, complément, code postal, commentaire) ; détection
/// automatique par géocodage inversé de la position du support (adresse auto de FibReady), rapprochée des adresses
/// du paquet ; immeuble, BAL et locaux de l'adresse du paquet choisie, en lecture ([BuildingSection]). Renvoie le
/// choix ([AddressChoice]) ou null (annulé) ; l'enregistrement est celui du support.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key, required this.node, this.current, this.geocoder});

  final GeoObject node;

  /// Adresse rattachée (copie de travail, éventuellement pas encore enregistrée).
  final GeoObject? current;
  final Geocoder? geocoder;

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  List<GeoObject> _all = [];
  String _commune = '';
  String _voie = '';

  /// Adresse du paquet sélectionnée ; null : nouvelle adresse.
  String? _selectedId;

  /// Détail de l'adresse en cours (colonnes ADR_*), et position d'une nouvelle adresse.
  Map<String, dynamic> _detail = {};
  LatLng? _point;

  /// Incrémenté quand les champs sont remplis par programme (sélection, détection) : ils sont reconstruits.
  int _revision = 0;
  bool _busy = false;

  static const _detailColumns = ['ADR_NUMERO', 'ADR_REP', 'ADR_CP', 'ADR_INSEE', 'ADR_BAN_ID', 'ADR_COMMENT'];

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    if (c != null) _select(c);
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<AppProvider>().repo.addresses();
    final c = widget.current;
    if (!mounted) return;
    setState(() => _all = [
          // adresse en cours, éventuellement modifiée ou nouvelle, à la place de celle du dépôt
          for (final a in list)
            if (a.id != c?.id) a,
          ?c,
        ]);
  }

  /// Comparaison des libellés : casse, accents et espaces ignorés (« RUE MARECHAL OUDINOT » = « Rue Maréchal Oudinot »).
  static String _norm(String? s) {
    const accents = {'à': 'a', 'â': 'a', 'ä': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
      'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ÿ': 'y', 'œ': 'oe', '-': ' ', '\'': ' '};
    final t = (s ?? '').toLowerCase().split('').map((c) => accents[c] ?? c).join();
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _number(GeoObject a) =>
      [a.props['ADR_NUMERO'], a.props['ADR_REP']].where((v) => v != null && '$v'.isNotEmpty).join(' ');

  List<String> get _communes => {for (final a in _all) if (a.props['ADR_COMMUNE'] != null) '${a.props['ADR_COMMUNE']}'}
      .toList()
    ..sort();

  List<String> get _voies => {
        for (final a in _all)
          if (_norm(a.props['ADR_COMMUNE'] as String?) == _norm(_commune) && a.props['ADR_VOIE'] != null)
            '${a.props['ADR_VOIE']}',
      }.toList()
    ..sort();

  /// Adresses du paquet sur la voie choisie, par numéro.
  List<GeoObject> get _onStreet => [
        for (final a in _all)
          if (_norm(a.props['ADR_COMMUNE'] as String?) == _norm(_commune) &&
              _norm(a.props['ADR_VOIE'] as String?) == _norm(_voie))
            a,
      ]..sort((a, b) {
          final c = ((a.props['ADR_NUMERO'] as num?) ?? 0).compareTo((b.props['ADR_NUMERO'] as num?) ?? 0);
          return c != 0 ? c : _number(a).compareTo(_number(b));
        });

  void _select(GeoObject a) {
    _selectedId = a.id;
    _commune = '${a.props['ADR_COMMUNE'] ?? ''}';
    _voie = '${a.props['ADR_VOIE'] ?? ''}';
    _detail = {for (final c in _detailColumns) if (a.props[c] != null) c: a.props[c]};
    _point = a.point;
    _revision++;
  }

  /// Nouvelle adresse sur la voie choisie : code postal et INSEE repris d'une adresse de la commune.
  void _newAddress({bool keepDetail = false}) {
    _selectedId = null;
    final same = _all.where((a) => _norm(a.props['ADR_COMMUNE'] as String?) == _norm(_commune)).firstOrNull;
    if (!keepDetail) _detail = {};
    for (final c in ['ADR_CP', 'ADR_INSEE']) {
      if (_detail[c] == null && same?.props[c] != null) _detail[c] = same!.props[c];
    }
    _point = null;
  }

  /// Commune ou voie changée : l'adresse sélectionnée n'y est plus, on passe à une nouvelle adresse.
  void _identityChanged() {
    final selected = _all.where((a) => a.id == _selectedId).firstOrNull;
    if (selected != null && !_onStreet.contains(selected)) _newAddress(keepDetail: true);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context)
        .replaceSnackBar(SnackBar(content: Text(text)));

  Future<void> _detect() async {
    final p = widget.node.point;
    if (p == null) return _message(tr('Position du support inconnue.'));
    setState(() => _busy = true);
    FoundAddress? a;
    try {
      a = await (widget.geocoder ?? Geocoder()).reverse(p);
    } catch (_) {
      if (mounted) _message(tr('Détection impossible : pas de connexion ou service indisponible.'));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (a == null || a.commune == null) return _message(tr('Aucune adresse trouvée à cette position.'));
    final found = a;
    final match = _all.where((x) {
      final q = x.props;
      final sameCommune = q['ADR_INSEE'] != null && found.insee != null
          ? q['ADR_INSEE'] == found.insee
          : _norm(q['ADR_COMMUNE'] as String?) == _norm(found.commune);
      return sameCommune &&
          _norm(q['ADR_VOIE'] as String?) == _norm(found.voie) &&
          q['ADR_NUMERO'] == found.numero &&
          _norm(q['ADR_REP'] as String?) == _norm(found.rep);
    }).firstOrNull;
    final label = [
      [found.numero, found.rep, found.voie].whereType<Object>().join(' '),
      [found.cp, found.commune].whereType<String>().join(' '),
    ].where((t) => t.isNotEmpty).join(', ');
    setState(() {
      if (match != null) {
        _select(match);
      } else {
        // commune et voie du paquet si elles y sont déjà, sous leur libellé du paquet
        _commune = _communes.where((c) => _norm(c) == _norm(found.commune)).firstOrNull ?? found.commune!;
        _voie = _voies.where((v) => _norm(v) == _norm(found.voie)).firstOrNull ?? found.voie ?? '';
        _newAddress();
        _detail = {
          'ADR_NUMERO': ?found.numero,
          'ADR_REP': ?found.rep,
          'ADR_CP': ?found.cp,
          'ADR_INSEE': ?found.insee,
          'ADR_BAN_ID': ?found.banId,
        };
        _point = found.point;
        _revision++;
      }
    });
    _message(match != null ? tr('Adresse du paquet : {0}', [label]) : tr('Nouvelle adresse : {0}', [label]));
  }

  void _validate() {
    if (_selectedId != null) {
      final a = _all.firstWhere((a) => a.id == _selectedId).copy();
      for (final c in _detailColumns) {
        GeoObject.put(a.props, c, _detail[c]);
      }
      Navigator.pop<AddressChoice>(context, (address: a));
      return;
    }
    if (_commune.trim().isEmpty || _voie.trim().isEmpty) {
      return _message(tr('Commune et voie à renseigner pour une nouvelle adresse.'));
    }
    final p = _point ?? widget.node.point;
    final a = GeoObject(id: const Uuid().v4(), objectClass: ObjectClass.adr, geometry: p == null ? null : GeoObject.geoPoint(p));
    GeoObject.put(a.props, 'ADR_COMMUNE', _commune.trim());
    GeoObject.put(a.props, 'ADR_VOIE', _voie.trim());
    for (final c in _detailColumns) {
      GeoObject.put(a.props, c, _detail[c]);
    }
    Navigator.pop<AddressChoice>(context, (address: a));
  }

  Widget _suggest({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) =>
      Autocomplete<String>(
        key: ValueKey('$label $_revision'),
        initialValue: TextEditingValue(text: value),
        optionsBuilder: (v) {
          final q = _norm(v.text);
          return options.where((o) => q.isEmpty || _norm(o).contains(q)).take(30);
        },
        onSelected: onChanged,
        fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
          controller: ctl,
          focusNode: focus,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label),
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final onStreet = _onStreet;
    final known = onStreet.any((a) => a.id == _selectedId);
    return Scaffold(
      appBar: AppBar(title: ScreenTitle(tr('Adresse'), widget.node.lib ?? tr('Sans étiquette'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            if (widget.current != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Nge.red),
                icon: const Icon(Icons.link_off),
                label: Text(tr('Détacher')),
                onPressed: () => Navigator.pop<AddressChoice>(context, (address: null)),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _validate, child: Text(tr('Valider'))),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 16), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.tonalIcon(
            onPressed: _busy || widget.node.point == null ? null : _detect,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: Text(tr('Détection automatique')),
          ),
        ),
        Section(title: tr('Sélection'), spacing: 12, children: [
          _suggest(
            label: tr('Commune'),
            value: _commune,
            options: _communes,
            onChanged: (v) => setState(() {
              _commune = v;
              _identityChanged();
            }),
          ),
          _suggest(
            label: tr('Voie'),
            value: _voie,
            options: _voies,
            onChanged: (v) => setState(() {
              _voie = v;
              _identityChanged();
            }),
          ),
          DropdownButtonFormField<String?>(
            key: ValueKey('adresse $_revision ${onStreet.length} $_selectedId'),
            initialValue: known ? _selectedId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Adresse')),
            items: [
              DropdownMenuItem(value: null, child: Text(tr('Nouvelle adresse'))),
              for (final a in onStreet)
                DropdownMenuItem(value: a.id, child: Text(_number(a).isEmpty ? tr('(sans numéro)') : _number(a))),
            ],
            onChanged: (id) => setState(() {
              if (id == null) {
                _newAddress();
                _revision++;
              } else {
                _select(onStreet.firstWhere((a) => a.id == id));
              }
            }),
          ),
          if (known)
            Text(tr('Le détail modifie l\'adresse du paquet, pour tous les supports qui y sont rattachés.'),
                style: Theme.of(context).textTheme.bodySmall),
        ]),
        KeyedSubtree(
          key: ValueKey('détail $_revision'),
          child: Section(title: tr('Détail'), spacing: 12, children: [
            Row(children: [
              Expanded(
                  child: NumberField(
                      m: _detail, column: 'ADR_NUMERO', label: tr('Numéro'), integer: true, onChanged: () {})),
              const SizedBox(width: 12),
              Expanded(child: StringField(m: _detail, column: 'ADR_REP', label: tr('Complément'), onChanged: () {})),
            ]),
            StringField(m: _detail, column: 'ADR_CP', label: tr('Code postal'), onChanged: () {}),
            StringField(m: _detail, column: 'ADR_COMMENT', label: tr('Commentaire'), rows: 2, onChanged: () {}),
          ]),
        ),
        // immeuble et BAL de l'adresse du paquet (module immeuble), en lecture
        if (known) BuildingSection(address: onStreet.firstWhere((a) => a.id == _selectedId)),
      ]),
    );
  }
}
