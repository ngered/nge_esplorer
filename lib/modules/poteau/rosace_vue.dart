import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../carte/geo.dart';
import '../../data/referentiels.dart';
import '../infra/cables.dart';
import 'rosace_edition.dart';

/// Couleurs de la légende Hirondelle (télécom vert, énergie bleu) et du poteau.
const couleurTelecom = Color(0xFF26B424);
const couleurEnergie = Color(0xFF0080CA);
const couleurInconnu = Color(0xFF8A8A8A);
const couleurPoteau = Color(0xFF0070C0);
const couleurSelection = Color(0xFFD5168B);

Color couleurReseau(Reseau r) => switch (r) {
      Reseau.telecom => couleurTelecom,
      Reseau.energie => couleurEnergie,
      Reseau.inconnu => couleurInconnu,
    };

/// Rosace des portées : rapporteur en grades orienté au nord (0 en haut, sens horaire), une aiguille par
/// portée et une flèche par câble porté. On sélectionne une aiguille en la touchant et on l'oriente en la
/// faisant glisser, comme dans Hirondelle.
class RosaceVue extends StatefulWidget {
  const RosaceVue({super.key, required this.edition, required this.referentiels});

  final RosaceEdition edition;
  final Referentiels referentiels;

  @override
  State<RosaceVue> createState() => _RosaceVueState();
}

class _RosaceVueState extends State<RosaceVue> {
  PorteeAuPoteau? _glissee;

  /// Angle (grades) et rayon relatif d'un point de l'écran par rapport au centre.
  (double, double) _polaire(Offset local, Size taille) {
    final c = taille.center(Offset.zero);
    final d = local - c;
    final angle = Geo.normaliser(math.atan2(d.dx, -d.dy) * 200 / math.pi);
    return (angle, d.distance / (taille.shortestSide / 2));
  }

  PorteeAuPoteau? _plusProche(double angle, double rayon) {
    if (rayon < 0.1) return null;
    PorteeAuPoteau? meilleure;
    var ecart = 12.0; // grades
    for (final p in widget.edition.visibles) {
      final e = (Geo.normaliser(p.angle - angle + 200) - 200).abs();
      if (e < ecart) {
        ecart = e;
        meilleure = p;
      }
    }
    return meilleure;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final taille = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          onTapUp: (d) {
            final (a, r) = _polaire(d.localPosition, taille);
            widget.edition.selectionner(_plusProche(a, r));
          },
          onPanStart: (d) {
            final (a, r) = _polaire(d.localPosition, taille);
            final p = _plusProche(a, r);
            if (p != null) {
              _glissee = p;
              widget.edition.selectionner(p);
            }
          },
          onPanUpdate: (d) {
            final p = _glissee;
            if (p == null) return;
            final (a, _) = _polaire(d.localPosition, taille);
            widget.edition.orienter(p, a);
          },
          onPanEnd: (_) => _glissee = null,
          child: ListenableBuilder(
            listenable: widget.edition,
            builder: (context, _) => CustomPaint(
              size: taille,
              painter: _RosacePeintre(
                edition: widget.edition,
                referentiels: widget.referentiels,
                theme: Theme.of(context),
                enGlissement: _glissee != null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _RosacePeintre extends CustomPainter {
  _RosacePeintre({required this.edition, required this.referentiels, required this.theme, required this.enGlissement});

  final RosaceEdition edition;
  final Referentiels referentiels;
  final ThemeData theme;
  final bool enGlissement;

  static Offset _dir(double grades) {
    final t = grades * math.pi / 200;
    return Offset(math.sin(t), -math.cos(t));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final encre = theme.colorScheme.onSurface;
    _rapporteur(canvas, c, r, encre);
    for (final p in edition.visibles) {
      _portee(canvas, c, r, p, p == edition.selection, encre);
    }
    // poteau au centre
    canvas.drawCircle(c, r * 0.07, Paint()..color = couleurPoteau);
    canvas.drawCircle(c, r * 0.07, Paint()
      ..color = encre
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    final s = edition.selection;
    if (s != null) {
      _texte(canvas, '${s.angle.toStringAsFixed(1)} gr', Offset(c.dx - r, c.dy - r + 4),
          TextStyle(color: couleurSelection, fontSize: r * 0.075, fontWeight: FontWeight.bold), aligne: false);
    }
  }

  void _rapporteur(Canvas canvas, Offset c, double r, Color encre) {
    final fin = Paint()
      ..color = encre.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    final leger = Paint()
      ..color = encre.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;
    final cercle = Paint()
      ..color = encre.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, r, cercle);
    canvas.drawCircle(c, r * 0.80, cercle);
    canvas.drawCircle(c, r * 0.12, cercle);
    final pasLibelle = r > 170 ? 10 : 20;
    for (var g = 0; g < 400; g++) {
      final d = _dir(g.toDouble());
      if (g % 10 == 0) {
        canvas.drawLine(c + d * (r * 0.12), c + d * (r * 0.80), leger);
        canvas.drawLine(c + d * (r * 0.93), c + d * r, fin);
      } else {
        canvas.drawLine(c + d * (r * (g.isEven ? 0.955 : 0.975)), c + d * r, fin);
      }
      if (g % pasLibelle == 0) {
        _texte(canvas, '$g', c + d * (r * 0.865),
            TextStyle(color: encre, fontSize: r * 0.05, fontWeight: g % 100 == 0 ? FontWeight.bold : FontWeight.normal),
            rotation: g * math.pi / 200);
      }
    }
    _texte(canvas, 'N', c + _dir(0) * (r * 0.72), TextStyle(color: encre.withValues(alpha: 0.5), fontSize: r * 0.06));
  }

  void _portee(Canvas canvas, Offset c, double r, PorteeAuPoteau p, bool selectionnee, Color encre) {
    final d = _dir(p.angle);
    final n = Offset(-d.dy, d.dx); // perpendiculaire
    final couleur = selectionnee ? couleurSelection : encre.withValues(alpha: 0.85);
    final aiguille = Paint()
      ..color = couleur
      ..strokeWidth = selectionnee ? 3 : 2
      ..strokeCap = StrokeCap.round;
    // talon contre le poteau, tige, poignée et pointe sur le bord
    canvas.drawLine(c + d * (r * 0.12) - n * (r * 0.07), c + d * (r * 0.12) + n * (r * 0.07), aiguille);
    canvas.drawLine(c + d * (r * 0.12), c + d * (r * 0.76), aiguille);
    canvas.drawCircle(c + d * (r * 0.62), selectionnee ? r * 0.035 : r * 0.025, Paint()..color = couleur);
    final pointe = c + d * (r * 0.80);
    canvas.drawPath(
        Path()
          ..moveTo(pointe.dx, pointe.dy)
          ..lineTo((pointe - d * (r * 0.05) + n * (r * 0.022)).dx, (pointe - d * (r * 0.05) + n * (r * 0.022)).dy)
          ..lineTo((pointe - d * (r * 0.05) - n * (r * 0.022)).dx, (pointe - d * (r * 0.05) - n * (r * 0.022)).dy)
          ..close(),
        Paint()..color = couleur);
    // une flèche par câble porté, côte à côte le long de l'aiguille
    final cables = [...p.cables]..sort((a, b) => (a['PCB_RANG'] as int? ?? 0).compareTo(b['PCB_RANG'] as int? ?? 0));
    final pas = r * 0.045;
    for (var i = 0; i < cables.length; i++) {
      final style = StyleCable.de(referentiels, cables[i]['MAT_KEY'] as int?);
      final decal = n * (pas * (i + 0.8)); // d'un même côté de l'aiguille, comme dans Hirondelle
      _fleche(canvas, c + d * (r * 0.17) + decal, c + d * (r * 0.52) + decal, d, n, r,
          couleurReseau(style.reseau), style.branchement);
    }
    // étiquette de destination
    final libelle = p.libelleDestination;
    final pos = c + d * (r * 0.66) + n * (r * 0.09) * (d.dx >= 0 ? -1 : 1);
    _etiquette(canvas, libelle, pos, r, selectionnee);
  }

  void _fleche(Canvas canvas, Offset a, Offset b, Offset d, Offset n, double r, Color couleur, bool tirete) {
    final trait = Paint()
      ..color = couleur
      ..strokeWidth = math.max(2, r * 0.014);
    final corps = b - d * (r * 0.04);
    if (tirete) {
      final longueur = (corps - a).distance;
      const plein = 6.0, vide = 4.0;
      for (var t = 0.0; t < longueur; t += plein + vide) {
        canvas.drawLine(a + d * t, a + d * math.min(t + plein, longueur), trait);
      }
    } else {
      canvas.drawLine(a, corps, trait);
    }
    final w = r * 0.02;
    canvas.drawPath(
        Path()
          ..moveTo(b.dx, b.dy)
          ..lineTo((corps + n * w).dx, (corps + n * w).dy)
          ..lineTo((corps - n * w).dx, (corps - n * w).dy)
          ..close(),
        Paint()..color = couleur);
  }

  void _etiquette(Canvas canvas, String texte, Offset centre, double r, bool selectionnee) {
    final tp = TextPainter(
      text: TextSpan(
          text: texte,
          style: TextStyle(
              color: selectionnee ? Colors.white : theme.colorScheme.onSurface,
              fontSize: r * 0.055,
              fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r * 0.6);
    final rect = Rect.fromCenter(center: centre, width: tp.width + 8, height: tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = selectionnee ? couleurSelection : theme.colorScheme.surface.withValues(alpha: 0.9));
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = selectionnee ? couleurSelection : theme.colorScheme.outline
          ..style = PaintingStyle.stroke);
    tp.paint(canvas, rect.topLeft + const Offset(4, 2));
  }

  void _texte(Canvas canvas, String texte, Offset pos, TextStyle style, {double rotation = 0, bool aligne = true}) {
    final tp = TextPainter(text: TextSpan(text: texte, style: style), textDirection: TextDirection.ltr)..layout();
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(rotation);
    tp.paint(canvas, aligne ? Offset(-tp.width / 2, -tp.height / 2) : Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RosacePeintre old) => true;
}
