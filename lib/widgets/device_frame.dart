import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../lng.dart';

/// Terminal simulé sur le web (dimensions en points logiques, comme sur Android).
enum Terminal {
  smartphone('smartphone', 'Smartphone', Size(360, 800)),
  large('grand', 'Grand smartphone', Size(412, 915)), // tr
  tablet('tablette', 'Tablette', Size(800, 1280)), // tr
  landscape('paysage', 'Tablette paysage', Size(1280, 800)); // tr

  const Terminal(this.code, this.lib, this.size);

  final String code;
  final String lib;
  final Size size;

  /// Terminal demandé par l'adresse de la page (`?terminal=smartphone`, `grand`, `tablette`, `paysage`, ou
  /// dimensions libres `?terminal=390x844`) ; null hors web ou sans paramètre.
  static Size? fromUrl(Uri url, {bool web = kIsWeb}) {
    if (!web) return null;
    final v = url.queryParameters['terminal']?.toLowerCase();
    if (v == null) return null;
    final t = values.where((t) => t.code == v).firstOrNull;
    if (t != null) return t.size;
    final m = RegExp(r'^(\d{3,4})x(\d{3,4})$').firstMatch(v);
    return m == null ? Terminal.smartphone.size : Size(double.parse(m[1]!), double.parse(m[2]!));
  }
}

/// Version web dans les proportions d'un terminal : l'application dans un cadre de la taille choisie, réduit si la
/// fenêtre est trop petite, avec le choix du terminal dessous. Dialogues, feuilles et messages restent dans le cadre.
/// Plein écran : adresse sans le paramètre `terminal`.
class DeviceFrame extends StatefulWidget {
  const DeviceFrame({super.key, required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  State<DeviceFrame> createState() => _DeviceFrameState();
}

class _DeviceFrameState extends State<DeviceFrame> {
  late Size _size = widget.size;

  static const _bezel = 10.0;

  @override
  Widget build(BuildContext context) {
    final size = _size;
    final mq = MediaQuery.of(context);
    final choice = Material(
      color: Colors.transparent,
      child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final t in Terminal.values)
          ChoiceChip(
            label: Text('${tr(t.lib)} ${t.size.width.toInt()}×${t.size.height.toInt()}'),
            selected: size == t.size,
            onSelected: (_) => setState(() => _size = t.size),
          ),
      ]),
    );
    return ColoredBox(
      color: const Color(0xFF3A4150),
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.all(_bezel),
                decoration: BoxDecoration(
                  color: const Color(0xFF111418),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox.fromSize(
                    size: size,
                    child: MediaQuery(
                      data: mq.copyWith(
                        size: size,
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                        viewInsets: EdgeInsets.zero,
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: choice),
      ]),
    );
  }
}
