import 'package:flutter/material.dart';

import '../../data/geo_object.dart';
import '../../data/reference_data.dart';
import '../../lng.dart';
import '../../theme.dart';
import 'optical.dart';

/// Charte FibReady de l'affichage des liens fibres (notes equipements rep4, maquette Figma « schéma optique » et
/// « route optique ») : une ligne par lien, en cellules : capacité du câble entrant, tube, fibre, connecteur, fibre,
/// tube et capacité du câble sortant. Tubes et fibres aux couleurs de FibReady (`param_fiber_colours.csv`), connecteur
/// par son symbole textuel (`DLINK_SYMBOL` de `connecteurs.csv` : `-x-`, `-#`, `-R`…) sur un fond qui dit où va la fibre
/// (`LinkFib.GetStatutColor` de FibReady, [FibreFate]). L'affichage simplifié précédent ([LinkChip]) reste au choix
/// dans les Paramètres.
abstract final class FibReadyChart {
  /// Couleurs des fibres et des tubes par rang dans leur contenant (1 à 12, puis de nouveau) : fond et texte,
  /// `param_fiber_colours.csv` des paramètres FibReady.
  static const fibreColors = [
    (Color(0xFFFF0000), Colors.white), // rouge
    (Color(0xFF0000FF), Colors.white), // bleu
    (Color(0xFFADFF2F), Colors.black), // vert
    (Color(0xFFFFFF00), Colors.black), // jaune
    (Color(0xFF8A2BE2), Colors.white), // violet
    (Color(0xFFFFFFFF), Colors.black), // blanc
    (Color(0xFFFFA500), Colors.black), // orange
    (Color(0xFFA9A9A9), Colors.black), // gris
    (Color(0xFF800000), Colors.white), // marron
    (Color(0xFF000000), Colors.white), // noir
    (Color(0xFF0E7EB3), Colors.black), // turquoise
    (Color(0xFFFFC0CB), Colors.black), // rose
  ];

  /// Fond et texte de la fibre ou du tube de rang [rank] (1 = rouge).
  static (Color, Color) colorOfRank(int rank) => fibreColors[(rank - 1) % 12];

  /// Symbole affiché du lien [l], règle de FibReady (`DoLinkFib` : sans câble à gauche, le symbole est retourné) :
  /// fibre seulement du côté sortant ([hasIn] faux, [hasOut] vrai), `-o` devient `o-`, `-ø` devient `ø-`, `-R`
  /// devient `R-`… ; le départ d'un connecteur est l'attente `-o` ainsi retournée (`o-`). Null : « … ».
  static String symbolOf(FibreLink? l, {required bool hasIn, required bool hasOut}) {
    if (l == null) return '…';
    final base = l == FibreLink.start ? FibreLink.wait.symbol : l.symbol;
    return !hasIn && hasOut ? String.fromCharCodes(base.runes.toList().reversed) : base;
  }

  /// Liens « prise » de FibReady (`ClsMiscLnk.StrPrises` : `-#`, `<A>`…).
  static bool isOutlet(FibreLink? l) => l == FibreLink.subscriber || l == FibreLink.subscriberWait;

  /// Liens « réserve » de FibReady (symbole terminé par `R`).
  static bool isReserve(FibreLink? l) => l == FibreLink.reserve || l == FibreLink.passageReserve;

  /// Devenir de la fibre au lien de rang [i] de la suite [links] (route optique, de l'amont à l'aval ; null : lien
  /// hors du paquet), selon `LinkFib.GetLinkerStatus` de FibReady : prise abonné repérée en amont (la fibre continue
  /// au-delà d'une prise) ; fibre terminée en réserve ; prise abonné en aval (ce lien compris) ; sinon autre.
  static FibreFate fateOf(List<FibreLink?> links, int i) {
    if (links.take(i).any(isOutlet)) return FibreFate.beyondOutlet;
    final end = links.lastWhere((l) => l != null, orElse: () => null);
    if (isReserve(end)) return FibreFate.reserve;
    if (links.skip(i).any(isOutlet)) return FibreFate.outlet;
    return FibreFate.other;
  }
}

/// Affichage des liens fibres (Paramètres) : charte FibReady en cellules ([FibreRow]), variante en pastilles
/// (notes equipements rep7 : badge du câble, gros rond du tube, petit rond de la fibre, badge du connecteur), ou
/// affichage simplifié précédent ([LinkChip]).
enum LinkDisplay {
  fibReady('Charte FibReady', 'Cellules : capacité, tube, fibre, connecteur'), // tr
  badges('Pastilles', 'Badge du câble, rond du tube, petit rond de la fibre, badge du connecteur'), // tr
  simple('Simplifié', 'Libellé du lien et fibres en texte'); // tr

  const LinkDisplay(this.lib, this.detail);
  final String lib;
  final String detail;

  /// Valeur conservée dans les Paramètres (null : charte FibReady, par défaut).
  String? get stored => this == fibReady ? null : name;

  static LinkDisplay of(String? stored) => values.where((v) => v.name == stored).firstOrNull ?? fibReady;
}

/// Devenir d'une fibre, couleur de fond de son connecteur (`LinkFib.GetStatutColor` de FibReady).
enum FibreFate {
  outlet('Vers une prise ou une attente abonné', Color(0xFF90EE90)), // tr
  beyondOutlet('Au-delà d\'une prise abonné', Color(0xFFFFA500)), // tr
  reserve('Vers une réserve', Color(0xFF9370DB)), // tr
  other('Autre destination', Color(0xFFFFFFE0)); // tr

  const FibreFate(this.lib, this.color);
  final String lib;
  final Color color;
}

/// Ligne d'un lien à la charte FibReady : `24Fo | T1 | F1 | -x- | F1 | T1 | 24Fo`, cellules vides encadrées côté
/// sans fibre. [fate] : fond du connecteur ; [link] null : connecteur inconnu ou suite hors du paquet (« … »).
class FibreRow extends StatelessWidget {
  const FibreRow({
    super.key,
    required this.fibreIn,
    required this.cableIn,
    required this.fibreOut,
    required this.cableOut,
    required this.link,
    required this.fate,
    required this.ref,
    this.badges = false,
  });

  final FibreRef? fibreIn;
  final GeoObject? cableIn;
  final FibreRef? fibreOut;
  final GeoObject? cableOut;
  final FibreLink? link;
  final FibreFate fate;
  final ReferenceData ref;

  /// Variante en pastilles ([_badgeRow]) plutôt qu'en cellules.
  final bool badges;

  static const height = 26.0;
  static const _cell = 30.0, _capa = 46.0, _link = 44.0;
  static const _widths = [_capa, _cell, _cell, _link, _cell, _cell, _capa];

  /// Trait des cellules, celui du synoptique de FibReady (gris ardoise foncé).
  static const line = Color(0xFF4F5868);

  /// Texte noir ou blanc selon la luminosité du fond, règle de FibReady (`FibGridView.GetContrastColor`).
  static Color contrastOn(Color back) {
    final luminance = 0.299 * (back.r * 255) + 0.587 * (back.g * 255) + 0.114 * (back.b * 255);
    return luminance > 140 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final tin = _tubeFibre(fibreIn, cableIn), tout = _tubeFibre(fibreOut, cableOut);
    final cells = <(Color?, String?, Color?, bool)>[
      _capaCell(cableIn, fibreIn),
      _rankCell('T', tin?.tube, fibreIn),
      _rankCell('F', tin?.fibre, fibreIn),
      (
        fate.color,
        FibReadyChart.symbolOf(link, hasIn: fibreIn != null, hasOut: fibreOut != null),
        contrastOn(fate.color),
        true,
      ),
      _rankCell('F', tout?.fibre, fibreOut),
      _rankCell('T', tout?.tube, fibreOut),
      _capaCell(cableOut, fibreOut),
    ];
    if (badges) return _badgeRow(tin, tout);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // tailles en pixels physiques entiers, réduites (sans mise à l'échelle de l'image, qui brouille traits et texte)
    // si la place manque
    return LayoutBuilder(
      builder: (context, c) {
        final natural = _widths.fold(0.0, (a, w) => a + w);
        final k = c.maxWidth.isFinite && c.maxWidth < natural ? c.maxWidth / natural : 1.0;
        double snap(double v) => (v * dpr).floor() / dpr;
        final widths = [for (final w in _widths) snap(w * k)];
        final h = snap(height * (k < 0.85 ? 0.85 : k));
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: [if (link != null) tr(link!.lib), tr(fate.lib)].join(' · '),
            child: CustomPaint(
              foregroundPainter: _GridPainter(widths, dpr),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (n, (bg, text, fg, mono)) in cells.indexed)
                    Container(
                      width: widths[n],
                      height: h,
                      alignment: Alignment.center,
                      color: bg ?? Colors.white,
                      child: text == null
                          ? null
                          : Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                fontFamily: mono ? 'monospace' : null,
                                fontSize: (mono ? 13 : 12) * (k < 0.85 ? 0.85 : k),
                                color: fg,
                                height: 1,
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Variante en pastilles (notes equipements rep7) : badge du câble (capacité), gros rond du tube et petit rond de
  /// la fibre à leurs couleurs FibReady, avec leur rang, badge du connecteur sur le fond de la destination de la
  /// fibre ; emplacements fixes pour que les lignes s'alignent, vides côté sans fibre.
  Widget _badgeRow(({int? tube, int? fibre})? tin, ({int? tube, int? fibre})? tout) => LayoutBuilder(
    builder: (context, c) {
      // largeurs réduites si la place manque (route optique sur un téléphone), sans mise à l'échelle de l'image
      const natural = 250.0;
      final k = c.maxWidth.isFinite && c.maxWidth < natural ? c.maxWidth / natural : 1.0;
      return _badges(tin, tout, k);
    },
  );

  Widget _badges(({int? tube, int? fibre})? tin, ({int? tube, int? fibre})? tout, double k) {
    Widget slot(double w, Widget? child) => SizedBox(
      width: (w * k).floorToDouble(),
      height: height,
      child: Center(child: child),
    );
    Widget badge(String text, Color bg, Color fg, {bool mono = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: line.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: 12 * (k < 0.85 ? 0.85 : k),
          height: 1,
          color: fg,
          fontFamily: mono ? 'monospace' : null,
        ),
      ),
    );
    Widget dot(int? rank, double size, FibreRef? f) {
      size = (size * (k < 0.8 ? 0.8 : k)).roundToDouble();
      if (f == null) return slot(size + 6, null);
      final (bg, fg) = rank == null ? (Colors.white, Nge.secondaryText) : FibReadyChart.colorOfRank(rank);
      return slot(
        size + 6,
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: line, width: 0.8),
          ),
          child: Text(
            '${rank ?? '?'}',
            style: TextStyle(fontSize: size > 18 ? 11 : 8, height: 1, color: fg),
          ),
        ),
      );
    }

    Widget capa(GeoObject? cable, FibreRef? f) => slot(
      52,
      f == null
          ? null
          : badge(
              switch (cable?.props['CAB_CAPA']) {
                final Object c => '${c}Fo',
                null => '?',
              },
              Nge.slateDark,
              Colors.white,
            ),
    );
    return Tooltip(
      message: [if (link != null) tr(link!.lib), tr(fate.lib)].join(' · '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          capa(cableIn, fibreIn),
          dot(tin?.tube, 22, fibreIn),
          dot(tin?.fibre, 14, fibreIn),
          slot(
            50,
            badge(
              FibReadyChart.symbolOf(link, hasIn: fibreIn != null, hasOut: fibreOut != null),
              fate.color,
              contrastOn(fate.color),
              mono: true,
            ),
          ),
          dot(tout?.fibre, 14, fibreOut),
          dot(tout?.tube, 22, fibreOut),
          capa(cableOut, fibreOut),
        ],
      ),
    );
  }

  /// Capacité du câble, sur fond sombre comme FibReady ; vide sans fibre de ce côté.
  (Color?, String?, Color?, bool) _capaCell(GeoObject? cable, FibreRef? f) {
    if (f == null) return (null, null, null, false);
    final capa = cable?.props['CAB_CAPA'];
    return (Nge.slateDark, capa == null ? '?' : '${capa}Fo', Colors.white, false);
  }

  /// Tube ou fibre de rang [rank] dans son contenant, à sa couleur FibReady ; rang inconnu (câble absent du paquet) :
  /// le rang de la fibre dans le câble, sans couleur.
  (Color?, String?, Color?, bool) _rankCell(String prefix, int? rank, FibreRef? f) {
    if (f == null) return (null, null, null, false);
    if (rank == null) return (null, prefix == 'F' ? '${f.num}' : '?', Nge.secondaryText, false);
    final (bg, fg) = FibReadyChart.colorOfRank(rank);
    return (bg, '$prefix$rank', fg, false);
  }
}

/// Traits de la ligne : cadre et séparations des cellules, d'un pixel physique entier (au moins), sans anticrénelage :
/// nets comme ceux de FibReady.
class _GridPainter extends CustomPainter {
  _GridPainter(this.widths, this.dpr);

  final List<double> widths;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FibreRow.line
      ..isAntiAlias = false;
    final t = (dpr < 1.5 ? 1 : dpr.round()) / dpr;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, t), paint);
    canvas.drawRect(Rect.fromLTWH(0, size.height - t, size.width, t), paint);
    var x = 0.0;
    for (var i = 0; i <= widths.length; i++) {
      final left = i == widths.length ? size.width - t : x;
      canvas.drawRect(Rect.fromLTWH(left, 0, t, size.height), paint);
      if (i < widths.length) x += widths[i];
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.dpr != dpr || old.widths.join() != widths.join();
}

/// Tube et rang de la fibre [f] dans son tube, lus dans le câble [cable] ; null sans fibre.
({int? tube, int? fibre})? _tubeFibre(FibreRef? f, GeoObject? cable) {
  if (f == null) return null;
  final row = cable == null ? null : Optical.fibres(cable).where((x) => x['FIB_NUM'] == f.num).firstOrNull;
  return (tube: row?['FIB_TUBE'] as int?, fibre: row?['FIB_NUM_TUBE'] as int?);
}
