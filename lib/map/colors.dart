import 'dart:ui';

/// Couleurs métier de la carte et de la rosace : celles de l'application (GraceTHD, légende Hirondelle), appui
/// énergie en bleu, façade en orange.
const telecomColor = Color(0xFF26B424);
const energyColor = Color(0xFF0080CA);
const undergroundColor = Color(0xFF7B3FA0);
const facadeColor = Color(0xFFE67E22);
const addressColor = Color(0xFFF39C12);

/// Câbles optiques tirés (couche Tirage) : bande sous le linéaire qui les porte.
const cableColor = Color(0xFF00838F);

/// Parcours d'infra (linéaires entre supports : portées, façades, fourreaux) : pastille de la couche.
const infraColor = Color(0xFF5D6D7E);

/// Capacités des câbles dessinés en parallèle (couche Tirage), de la plus petite à la plus grande : fibres au plus
/// et couleur (palette proche de FibReady : 48 FO violet, 144 FO vert).
const cableCapacities = [
  (12, Color(0xFF1E88E5)),
  (24, Color(0xFF00ACC1)),
  (48, Color(0xFF8E24AA)),
  (96, Color(0xFFF4511E)),
  (144, Color(0xFF7CB342)),
  (null, Color(0xFFE53935)),
];

/// Couleur d'un câble de [capacity] fibres (inconnue : couleur du tirage).
Color cableCapacityColor(int? capacity) {
  if (capacity == null) return cableColor;
  for (final (max, color) in cableCapacities) {
    if (max == null || capacity <= max) return color;
  }
  return cableColor;
}

/// Objet modifié depuis le chargement du paquet.
const changedColor = Color(0xFFD5168B);
