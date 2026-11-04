import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../map/colors.dart';
import '../../map/geo.dart';
import '../../data/reference_data.dart';
import '../infra/cables.dart';
import 'rosette_editor.dart';

/// Couleurs de la rosace (télécom et énergie : celles de la carte) et du poteau.
const unknownColor = Color(0xFF8A8A8A);
const poleColor = Color(0xFF0070C0);
const selectionColor = Color(0xFFD5168B);

Color networkColor(Network r) => switch (r) {
      Network.telecom => telecomColor,
      Network.energy => energyColor,
      Network.unknown => unknownColor,
    };

/// Rosace des portées : rapporteur en grades orienté au nord (0 en haut, sens horaire), une aiguille par
/// portée et une flèche par câble porté. On sélectionne une aiguille en la touchant et on l'oriente en la
/// faisant glisser, comme dans Hirondelle.
class RosetteView extends StatefulWidget {
  const RosetteView({super.key, required this.editor, required this.referenceData});

  final RosetteEditor editor;
  final ReferenceData referenceData;

  @override
  State<RosetteView> createState() => _RosetteViewState();
}

class _RosetteViewState extends State<RosetteView> {
  PoleSpan? _dragged;

  /// Angle (grades) et rayon relatif d'un point de l'écran par rapport au centre.
  (double, double) _polar(Offset local, Size size) {
    final c = size.center(Offset.zero);
    final d = local - c;
    final angle = Geo.normalize(math.atan2(d.dx, -d.dy) * 200 / math.pi);
    return (angle, d.distance / (size.shortestSide / 2));
  }

  PoleSpan? _nearest(double angle, double radius) {
    if (radius < 0.1) return null;
    PoleSpan? best;
    var bestGap = 12.0; // grades
    for (final p in widget.editor.activeSpans) {
      final e = (Geo.normalize(p.angle - angle + 200) - 200).abs();
      if (e < bestGap) {
        bestGap = e;
        best = p;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          onTapUp: (d) {
            final (a, r) = _polar(d.localPosition, size);
            widget.editor.select(_nearest(a, r));
          },
          onPanStart: (d) {
            final (a, r) = _polar(d.localPosition, size);
            final p = _nearest(a, r);
            if (p != null) {
              _dragged = p;
              widget.editor.select(p);
            }
          },
          onPanUpdate: (d) {
            final p = _dragged;
            if (p == null) return;
            final (a, _) = _polar(d.localPosition, size);
            widget.editor.orient(p, a);
          },
          onPanEnd: (_) => _dragged = null,
          child: ListenableBuilder(
            listenable: widget.editor,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _RosettePainter(
                editor: widget.editor,
                referenceData: widget.referenceData,
                theme: Theme.of(context),
                dragging: _dragged != null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _RosettePainter extends CustomPainter {
  _RosettePainter({required this.editor, required this.referenceData, required this.theme, required this.dragging});

  final RosetteEditor editor;
  final ReferenceData referenceData;
  final ThemeData theme;
  final bool dragging;

  static Offset _dir(double grads) {
    final t = grads * math.pi / 200;
    return Offset(math.sin(t), -math.cos(t));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final ink = theme.colorScheme.onSurface;
    _protractor(canvas, c, r, ink);
    for (final p in editor.activeSpans) {
      _span(canvas, c, r, p, p == editor.selection, ink);
    }
    // poteau au centre
    canvas.drawCircle(c, r * 0.07, Paint()..color = poleColor);
    canvas.drawCircle(c, r * 0.07, Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    final s = editor.selection;
    if (s != null) {
      _drawText(canvas, '${s.angle.toStringAsFixed(1)} gr', Offset(c.dx - r, c.dy - r + 4),
          TextStyle(color: selectionColor, fontSize: r * 0.075, fontWeight: FontWeight.bold), aligned: false);
    }
  }

  void _protractor(Canvas canvas, Offset c, double r, Color ink) {
    final thinPaint = Paint()
      ..color = ink.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    final lightPaint = Paint()
      ..color = ink.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;
    final circlePaint = Paint()
      ..color = ink.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, r, circlePaint);
    canvas.drawCircle(c, r * 0.80, circlePaint);
    canvas.drawCircle(c, r * 0.12, circlePaint);
    final labelStep = r > 170 ? 10 : 20;
    for (var g = 0; g < 400; g++) {
      final d = _dir(g.toDouble());
      if (g % 10 == 0) {
        canvas.drawLine(c + d * (r * 0.12), c + d * (r * 0.80), lightPaint);
        canvas.drawLine(c + d * (r * 0.93), c + d * r, thinPaint);
      } else {
        canvas.drawLine(c + d * (r * (g.isEven ? 0.955 : 0.975)), c + d * r, thinPaint);
      }
      if (g % labelStep == 0) {
        _drawText(canvas, '$g', c + d * (r * 0.865),
            TextStyle(color: ink, fontSize: r * 0.05, fontWeight: g % 100 == 0 ? FontWeight.bold : FontWeight.normal),
            rotation: g * math.pi / 200);
      }
    }
    _drawText(canvas, 'N', c + _dir(0) * (r * 0.72), TextStyle(color: ink.withValues(alpha: 0.5), fontSize: r * 0.06));
  }

  void _span(Canvas canvas, Offset c, double r, PoleSpan p, bool selected, Color ink) {
    final d = _dir(p.angle);
    final n = Offset(-d.dy, d.dx); // perpendiculaire
    final color = selected ? selectionColor : ink.withValues(alpha: 0.85);
    final needlePaint = Paint()
      ..color = color
      ..strokeWidth = selected ? 3 : 2
      ..strokeCap = StrokeCap.round;
    // talon contre le poteau, tige, poignée et pointe sur le bord
    canvas.drawLine(c + d * (r * 0.12) - n * (r * 0.07), c + d * (r * 0.12) + n * (r * 0.07), needlePaint);
    canvas.drawLine(c + d * (r * 0.12), c + d * (r * 0.76), needlePaint);
    canvas.drawCircle(c + d * (r * 0.62), selected ? r * 0.035 : r * 0.025, Paint()..color = color);
    final tip = c + d * (r * 0.80);
    canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((tip - d * (r * 0.05) + n * (r * 0.022)).dx, (tip - d * (r * 0.05) + n * (r * 0.022)).dy)
          ..lineTo((tip - d * (r * 0.05) - n * (r * 0.022)).dx, (tip - d * (r * 0.05) - n * (r * 0.022)).dy)
          ..close(),
        Paint()..color = color);
    // une flèche par câble porté, côte à côte le long de l'aiguille
    final cables = [...p.cables]..sort((a, b) => (a['PCB_RANG'] as int? ?? 0).compareTo(b['PCB_RANG'] as int? ?? 0));
    final step = r * 0.045;
    for (var i = 0; i < cables.length; i++) {
      final style = CableStyle.of(referenceData, cables[i]['MAT_KEY'] as int?);
      final shift = n * (step * (i + 0.8)); // d'un même côté de l'aiguille, comme dans Hirondelle
      _arrow(canvas, c + d * (r * 0.17) + shift, c + d * (r * 0.52) + shift, d, n, r,
          networkColor(style.network), style.drop);
    }
    // étiquette de destination
    final label = p.destinationLabel;
    final pos = c + d * (r * 0.66) + n * (r * 0.09) * (d.dx >= 0 ? -1 : 1);
    _label(canvas, label, pos, r, selected);
  }

  void _arrow(Canvas canvas, Offset a, Offset b, Offset d, Offset n, double r, Color color, bool dashed) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = math.max(2, r * 0.014);
    final body = b - d * (r * 0.04);
    if (dashed) {
      final length = (body - a).distance;
      const dashLength = 6.0, dashGap = 4.0;
      for (var t = 0.0; t < length; t += dashLength + dashGap) {
        canvas.drawLine(a + d * t, a + d * math.min(t + dashLength, length), linePaint);
      }
    } else {
      canvas.drawLine(a, body, linePaint);
    }
    final w = r * 0.02;
    canvas.drawPath(
        Path()
          ..moveTo(b.dx, b.dy)
          ..lineTo((body + n * w).dx, (body + n * w).dy)
          ..lineTo((body - n * w).dx, (body - n * w).dy)
          ..close(),
        Paint()..color = color);
  }

  void _label(Canvas canvas, String text, Offset center, double r, bool selected) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: selected ? Colors.white : theme.colorScheme.onSurface,
              fontSize: r * 0.055,
              fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r * 0.6);
    final rect = Rect.fromCenter(center: center, width: tp.width + 8, height: tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = selected ? selectionColor : theme.colorScheme.surface.withValues(alpha: 0.9));
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = selected ? selectionColor : theme.colorScheme.outline
          ..style = PaintingStyle.stroke);
    tp.paint(canvas, rect.topLeft + const Offset(4, 2));
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style, {double rotation = 0, bool aligned = true}) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(rotation);
    tp.paint(canvas, aligned ? Offset(-tp.width / 2, -tp.height / 2) : Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RosettePainter old) => true;
}
