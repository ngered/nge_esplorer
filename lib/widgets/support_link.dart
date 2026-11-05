import 'package:flutter/material.dart';

import '../data/geo_object.dart';
import '../data/reference_data.dart';
import '../lng.dart';
import '../map/symbols.dart';

/// Pictogramme du support [o] comme sur la carte : famille de son type, encre bleue pour l'énergie, marque de
/// l'équipement optique porté.
Widget supportSymbolOf(GeoObject o, ReferenceData referenceData, {double size = 20}) => SupportSymbol(
      family: SupportSymbol.familyOf(o.typeKey, referenceData),
      energy: o.typeKey == 15,
      mark: OpticalMark.of(o, referenceData),
      size: size,
    );

/// Lien vers le support d'en face (« Vers … » de l'alvéole choisie, notes rep10) : bouton bien visible sur toute la
/// largeur, avec le pictogramme et le type du support, son étiquette en gras ; une touche y mène.
class SupportLink extends StatelessWidget {
  const SupportLink({super.key, required this.target, required this.referenceData, required this.onPressed});

  final GeoObject target;
  final ReferenceData referenceData;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        style: FilledButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        child: Row(children: [
          const Icon(Icons.near_me_outlined, size: 20),
          const SizedBox(width: 10),
          supportSymbolOf(target, referenceData, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: tr('Vers {0}', [target.lib ?? tr('Sans étiquette')]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' · ${referenceData.typeLabel(target.typeKey)}'),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ]),
      );
}
