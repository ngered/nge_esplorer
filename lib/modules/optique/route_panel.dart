import 'package:flutter/material.dart';

import '../../data/data_repository.dart';
import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../map/colors.dart';
import '../../theme.dart';
import '../infra/equipment.dart';
import 'optical.dart';

/// Étape d'une route optique : la position [position] de l'équipement [equipment] du nœud [node], avec la fibre qui y
/// entre ([fibreIn], par le câble [cableIn]) et celle qui en sort ([fibreOut], [cableOut]). [position] null : la fibre
/// arrive à un équipement absent du paquet ou sans contenu optique (hors zone), où la route s'arrête.
typedef RouteHop = ({
  GeoObject? node,
  String? equipment,
  Map<String, dynamic>? position,
  FibreRef? fibreIn,
  GeoObject? cableIn,
  FibreRef? fibreOut,
  GeoObject? cableOut,
});

/// Route optique d'une fibre (comme celle de FibReady) : suite des positions qu'elle traverse, du connecteur de
/// départ (tiroir) jusqu'à l'attente (PBO), retrouvée de proche en proche par les positions des équipements (les
/// routes `OPT_ROUTE` restent au BE, docs/paquet.md). Une position mène vers l'amont par sa fibre entrante (`FIB1`,
/// câble arrivant, dont l'équipement de départ `EQU1_KEY` a la même fibre en sortie `FIB2`) et vers l'aval par sa
/// fibre sortante (`FIB2`, câble partant, vers `EQU2_KEY`).
abstract final class OpticalRoute {
  /// Garde-fou contre une boucle dans des données incohérentes.
  static const maxHops = 64;

  /// Identité d'une position de l'équipement [equipment] (les cartes lues sont des vues, pas toujours les mêmes).
  static String key(String? equipment, Map<String, dynamic> p) =>
      '$equipment|${p['POS_NUM']}|${Optical.fibre(p, '1')}|${Optical.fibre(p, '2')}';

  /// Cassette de la position [p] dans le contenu optique [content].
  static Map<String, dynamic>? cassetteOf(Map<String, dynamic>? content, Map<String, dynamic> p) {
    final k = key(null, p);
    for (final c in Optical.cassettes(content)) {
      if (Optical.positions(c).any((x) => key(null, x) == k)) return c;
    }
    return null;
  }

  /// Route passant par la position [position] de l'équipement [equipment] du nœud [node], de l'amont à l'aval.
  static Future<List<RouteHop>> trace(
    DataRepository repo,
    GeoObject node,
    String equipment,
    Map<String, dynamic> position,
  ) async {
    final cables = <String, GeoObject?>{};
    Future<GeoObject?> cable(String id) async =>
        cables.containsKey(id) ? cables[id] : cables[id] = await repo.object(id);

    Future<RouteHop> hop(
      GeoObject? n,
      String? e,
      Map<String, dynamic>? p, {
      FibreRef? fibreIn,
      FibreRef? fibreOut,
    }) async {
      final fin = p == null ? fibreIn : Optical.fibre(p, '1');
      final fout = p == null ? fibreOut : Optical.fibre(p, '2');
      return (
        node: n,
        equipment: e,
        position: p,
        fibreIn: fin,
        cableIn: fin == null ? null : await cable(fin.cable),
        fibreOut: fout,
        cableOut: fout == null ? null : await cable(fout.cable),
      );
    }

    /// Étape à l'autre extrémité du câble de la fibre [f] : équipement amont ([upstream]) ou aval.
    Future<RouteHop?> next(FibreRef f, {required bool upstream}) async {
      final c = await cable(f.cable);
      final e = c?.props[upstream ? 'EQU1_KEY' : 'EQU2_KEY'] as String?;
      final n = e == null ? null : await repo.nodeOfEquipment(e);
      // le câble arrive à l'équipement ou à son contenant (baie du SRO) : la fibre est dans l'un de ses tiroirs
      final found = n == null
          ? null
          : [
              for (final x in [e!, ...Optical.descendants(n, e)])
                for (final k in Optical.cassettes(Optical.of(n, x)))
                  for (final p in Optical.positions(k))
                    if (Optical.fibre(p, upstream ? '2' : '1') == f) (x, p),
            ].firstOrNull;
      final p = found?.$2;
      if (p == null) {
        // suite hors du paquet : la fibre, son câble et l'extrémité connue
        return hop(
          n ?? (c == null ? null : await repo.object((upstream ? c.noe1 : c.noe2) ?? '')),
          e,
          null,
          fibreIn: upstream ? null : f,
          fibreOut: upstream ? f : null,
        );
      }
      return hop(n, found!.$1, p);
    }

    final route = [await hop(node, equipment, position)];
    final seen = {key(equipment, position)};
    for (final upstream in [true, false]) {
      var f = upstream ? route.first.fibreIn : route.last.fibreOut;
      while (f != null && route.length < maxHops) {
        final h = await next(f, upstream: upstream);
        if (h == null) break;
        if (h.position != null && !seen.add(key(h.equipment, h.position!))) break;
        upstream ? route.insert(0, h) : route.add(h);
        if (h.position == null) break;
        f = upstream ? h.fibreIn : h.fibreOut;
      }
    }
    return route;
  }
}

/// Route optique dépliée sous le connecteur touché dans l'écran Optique d'un équipement (notes equipements rep3) :
/// une ligne par équipement traversé, de l'amont à l'aval, à la manière de FibReady : rang, fonction et étiquette de
/// l'équipement, support, cassette et position, câble entrant (capacité, couleur de sa capacité) et couleurs du tube et
/// de la fibre, lien nommé comme dans FibReady ([LinkChip] : départ, fusion, passage lové, attente abonné, réserve,
/// attente, fibre morte ; prise abonné si la route s'achève à la PTO du logement), câble sortant. L'étape du boîtier affiché est mise en
/// évidence ([current]) ; toucher une autre étape bascule aussitôt sur son boîtier, sur son connecteur, la route
/// restant dépliée ([onSelect]) ; la replier est une action volontaire ([onFold]), qui ne change pas d'écran.
/// [route] null : en cours de calcul.
class RoutePanel extends StatelessWidget {
  const RoutePanel({
    super.key,
    required this.route,
    required this.current,
    required this.ref,
    required this.onSelect,
    required this.onFold,
  });

  final List<RouteHop>? route;

  /// Rang de l'étape du boîtier affiché (connecteur touché, ou atteint depuis la route).
  final int current;
  final ReferenceData ref;
  final ValueChanged<int> onSelect;
  final VoidCallback onFold;

  @override
  Widget build(BuildContext context) {
    final r = route;
    final links = r == null ? 0 : r.where((h) => h.position != null).length;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: Nge.barBackground,
        border: Border.all(color: Nge.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                const Icon(Icons.route_outlined, size: 20, color: Nge.petrolBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [tr('Route optique'), if (r != null) trn(links, '{0} lien', '{0} liens')].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Nge.petrolBlue),
                  ),
                ),
                TextButton.icon(onPressed: onFold, icon: const Icon(Icons.unfold_less), label: Text(tr('Replier'))),
              ],
            ),
          ),
          if (r == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final (i, h) in r.indexed)
              _HopTile(
                rank: i + 1,
                hop: h,
                ref: ref,
                current: i == current,
                onTap: h.position == null || i == current ? null : () => onSelect(i),
              ),
        ],
      ),
    );
  }
}

/// Étiquette de l'équipement d'une étape : celle du contenu optique, sinon l'intitulé de l'équipement, sinon le
/// support.
String hopLabel(RouteHop h, ReferenceData ref) {
  final content = h.node == null || h.equipment == null ? null : Optical.of(h.node!, h.equipment);
  final infra = h.node == null || h.equipment == null ? null : SupportEquipment.find(h.node!, h.equipment!);
  return content?['EQO_LIB'] as String? ??
      (infra != null ? SupportEquipment.title(h.node!, infra, ref) : h.node?.lib ?? tr('Hors du paquet'));
}

class _HopTile extends StatelessWidget {
  const _HopTile({required this.rank, required this.hop, required this.ref, required this.current, this.onTap});

  final int rank;
  final RouteHop hop;
  final ReferenceData ref;

  /// Étape du boîtier affiché : fond jaune et filet à gauche.
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final h = hop;
    final content = h.node == null || h.equipment == null ? null : Optical.of(h.node!, h.equipment);
    final code = ref.equipmentTypeCode(content?['OTYP_KEY'] as int?);
    final label = hopLabel(h, ref);
    final p = h.position;
    final where = [
      ?h.node?.lib,
      if (p != null)
        ?switch (OpticalRoute.cassetteOf(content, p)?['CAS_NUM']) {
          final Object n => tr('K{0}', [n]),
          null => null,
        },
      if (p?['POS_NUM'] != null) tr('P{0}', [p!['POS_NUM']]),
      if (p == null) tr('suite hors du paquet'),
    ].join(' · ');
    return Material(
      color: current ? Nge.yellow.withValues(alpha: 0.35) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: current ? Nge.petrolBlue : Colors.transparent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Container(
                width: 40,
                margin: const EdgeInsets.only(right: 8, top: 1),
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Nge.slateDark),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  code ?? '?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(where, style: const TextStyle(fontSize: 12, color: Nge.secondaryText)),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (h.fibreIn != null) _Fibre(fibre: h.fibreIn!, cable: h.cableIn, ref: ref, incoming: true),
                        if (p != null)
                          LinkChip(position: p, ref: ref, equipmentType: code)
                        else
                          const Text('…', style: TextStyle(fontWeight: FontWeight.w700)),
                        if (h.fibreOut != null)
                          _Fibre(fibre: h.fibreOut!, cable: h.cableOut, ref: ref, incoming: false),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fibre d'une étape : capacité du câble et trait à la couleur de sa capacité, côté extérieur ; couleurs du tube et
/// de la fibre côté opération ; étiquette du câble en infobulle.
class _Fibre extends StatelessWidget {
  const _Fibre({required this.fibre, required this.cable, required this.ref, required this.incoming});

  final FibreRef fibre;
  final GeoObject? cable;
  final ReferenceData ref;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final capa = cable?.props['CAB_CAPA'] as int?;
    final f = cable == null ? null : Optical.fibres(cable!).where((x) => x['FIB_NUM'] == fibre.num).firstOrNull;
    final tube = f?['FIB_TUBE'] as int?;
    final cableSide = [
      Text(capa == null ? '?' : tr('{0}fo', [capa]), style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 4),
      Container(width: 16, height: 3, color: cableCapacityColor(capa)),
      const SizedBox(width: 4),
    ];
    final dots = [
      ColorDot(
        color: colorOf(ref.fibreColor(f?['TUBE_COUL_KEY'] as int?)?['COUL_RGB']),
        rings: tube == null ? 0 : (tube - 1) ~/ 12,
        tooltip: tube == null ? null : tr('Tube {0}', [tube]),
      ),
      ColorDot(
        color: colorOf(ref.fibreColor(f?['COUL_KEY'] as int?)?['COUL_RGB']),
        tooltip: tr('Fibre {0}', [f?['FIB_NUM_TUBE'] ?? fibre.num]),
      ),
    ];
    return Tooltip(
      message: [
        cable?.lib ?? fibre.cable,
        tr('fibre {0}', [fibre.num]),
      ].join(' · '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: incoming ? [...cableSide, ...dots] : [...dots, const SizedBox(width: 1), ...cableSide.reversed],
      ),
    );
  }
}
