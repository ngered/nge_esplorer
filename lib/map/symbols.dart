import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/geo_object.dart';
import '../data/reference_data.dart';
import '../modules/immeuble/building.dart';
import '../modules/optique/optical.dart';
import 'colors.dart';

/// Picto d'un support, repris de FibReady (jeu par défaut des paramètres : `Pictures/noe/svg`) : fond « papier », la
/// couleur du statut de renseignement dans un carré intérieur aux bords fins ; encre bleue pour un appui énergie ;
/// équipement optique porté : marque au coin bas droit ([OpticalMark]). Type sans picto : point.
class SupportSymbol extends StatelessWidget {
  const SupportSymbol({super.key, required this.family, this.fill, this.energy = false, this.mark, this.size = 24});

  /// Famille du type (POT, CHB, FAC…).
  final String? family;

  /// Couleur du statut (null : papier, comme dans FibReady).
  final Color? fill;
  final bool energy;

  /// Équipement optique porté par le support.
  final OpticalMark? mark;
  final double size;

  static const paper = Color(0xFFFEFFF8);

  /// Famille du picto d'un support de type [typeKey] : celle du type ([ReferenceData.familyCode]), sauf le NRO,
  /// shelter plutôt qu'armoire de rue parmi les sites techniques (`SIT-NRO`).
  static String? familyOf(int? typeKey, ReferenceData ref) =>
      ref.type(typeKey)?['TYPE_CODE'] == 'SIT-NRO' ? 'SIT-NRO' : ref.familyCode(typeKey);

  /// Immeuble et armoire de rue (site technique : SRO…) : pictos des paramètres Evicom (`NOE_IMM`, `NOE_ADR`) ;
  /// shelter du NRO dessiné dans leur style (`NOE_SHELTER`, sans équivalent dans les paramètres).
  static String? assetFile(String? family) => switch (family) {
        'POT' => 'NOE_POT',
        'CHB' => 'NOE_CHB',
        'FAC' => 'NOE_FAC',
        'IMM' => 'NOE_IMM',
        'SIT' => 'NOE_ADR',
        'SIT-NRO' => 'NOE_SHELTER',
        _ => null,
      };

  /// Carré du statut dans le corps du picto (unités du viewBox 16 × 16 des SVG FibReady).
  static Rect? square(String? family) => switch (family) {
        'POT' => const Rect.fromLTWH(4.5, 7, 7, 7),
        'CHB' => const Rect.fromLTWH(4, 4, 8, 8),
        'FAC' => const Rect.fromLTWH(3.5, 4.5, 7, 7),
        'IMM' => const Rect.fromLTWH(4.5, 4, 7, 7),
        'SIT' => const Rect.fromLTWH(4.5, 4.5, 7, 7),
        'SIT-NRO' => const Rect.fromLTWH(3, 7, 6, 6),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final f = assetFile(family);
    final ink = energy ? energyColor : Colors.black;
    if (f == null) return SupportPoint(fill: fill ?? paper, ink: ink, size: size * 0.6);
    final svg = SvgPicture(
      SvgAssetLoader('assets/fibready/noe/$f.svg', colorMapper: _SymbolColors(paper, ink)),
      width: size,
      height: size,
    );
    final c = square(family);
    if ((fill == null || c == null) && mark == null) return svg;
    final u = size / 16;
    // marque centrée près du coin, débordant du picto : elle ne cache pas le carré du statut
    final side = size * 0.42;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        svg,
        if (fill != null && c != null)
          Positioned(
            left: c.left * u,
            top: c.top * u,
            child: StatusSquare(color: fill!, side: c.width * u, ink: ink),
          ),
        if (mark != null)
          Positioned(right: -side * 0.4, bottom: -side * 0.4, child: OpticalBadge(mark: mark!, side: side)),
      ]),
    );
  }
}

/// Picto d'une adresse selon son usage ([AddressUsage]), aux couleurs FibReady (jaune, violet du FTTE).
class AddressSymbol extends StatelessWidget {
  const AddressSymbol({super.key, required this.usage, this.size = 18});

  final AddressUsage usage;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/fibready/noe/${usage.picture}.svg', width: size, height: size);
}

/// Équipement optique porté par un support, marqué au coin de son picto aux formes des pictos FibReady : losange du
/// PBO, carré du BPE ; rond pour un autre équipement (DTI, PTO, baie, tiroir).
enum OpticalMark {
  bpe('BPE'), // tr
  pbo('PBO'), // tr
  other('Autre équipement optique'); // tr

  const OpticalMark(this.lib);
  final String lib;

  /// Marque du support [node] : l'équipement le plus structurant qu'il porte (BPE, puis PBO, puis autre) ; null sans
  /// équipement optique présent.
  static OpticalMark? of(GeoObject node, ReferenceData ref) {
    final f = Optical.functions(node, ref);
    if (f.isEmpty) return null;
    return f.contains('BPE') ? bpe : (f.contains('PBO') ? pbo : other);
  }
}

/// Marque d'un équipement optique : forme noire bordée de blanc, lisible sur le picto comme sur le fond de plan.
class OpticalBadge extends StatelessWidget {
  const OpticalBadge({super.key, required this.mark, this.side = 10});

  final OpticalMark mark;
  final double side;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(side), painter: _BadgePainter(mark));
}

class _BadgePainter extends CustomPainter {
  _BadgePainter(this.mark);

  final OpticalMark mark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final shape = switch (mark) {
      OpticalMark.pbo => Path()
        ..moveTo(r.center.dx, r.top)
        ..lineTo(r.right, r.center.dy)
        ..lineTo(r.center.dx, r.bottom)
        ..lineTo(r.left, r.center.dy)
        ..close(),
      OpticalMark.bpe => Path()..addRect(r.deflate(size.width * 0.12)),
      OpticalMark.other => Path()..addOval(r.deflate(size.width * 0.1)),
    };
    final edge = size.width * 0.16;
    canvas.drawPath(shape, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * edge
      ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(shape, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.mark != mark;
}

/// Couleur d'un statut de renseignement : carré aux bords fins (picto, étiquette).
class StatusSquare extends StatelessWidget {
  const StatusSquare({super.key, required this.color, required this.side, this.ink = Colors.black});

  final Color color;
  final double side;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
        width: side,
        height: side,
        decoration: BoxDecoration(color: color, border: Border.all(color: ink, width: 0.75)),
      );
}

/// Support aux petites échelles (FibReady : point au-delà du 1/10 000).
class SupportPoint extends StatelessWidget {
  const SupportPoint({super.key, required this.fill, required this.ink, this.size = 10});

  final Color fill;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: Border.all(color: ink, width: 1)),
      );
}

/// Papier → statut, noir → encre (clé du cache des SVG : égalité par valeur).
class _SymbolColors extends ColorMapper {
  const _SymbolColors(this.fill, this.ink);

  final Color fill;
  final Color ink;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) => switch (color.toARGB32()) {
        0xFFFEFFF8 => fill,
        0xFF000000 => ink,
        _ => color,
      };

  @override
  bool operator ==(Object other) => other is _SymbolColors && other.fill == fill && other.ink == ink;

  @override
  int get hashCode => Object.hash(fill, ink);
}
