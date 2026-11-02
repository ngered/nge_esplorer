import 'package:flutter/material.dart';

/// Couleurs de la charte NGE (Megatools/NgeCharte/ClsCharte.cs de FibReady).
abstract final class Nge {
  /// Bleu nuit : support de marque, réservé à l'écran de démarrage.
  static const bleuNuit = Color(0xFF022A78);

  /// Jaune : action principale (texte [ardoiseFoncee]) et filet sous les barres.
  static const jaune = Color(0xFFFAC100);
  static const jauneClair = Color(0xFFFFD240);

  /// Bleu pétrole : titres de rubriques.
  static const petrole = Color(0xFF1A6D8E);
  static const turquoise = Color(0xFF34AFC1);
  static const creme = Color(0xFFF9F8F0);

  /// Rouge : suppressions et défauts seulement.
  static const rouge = Color(0xFFC62828);
  static const vert = Color(0xFF1E7B45);
  static const ambre = Color(0xFFB98600);

  static const fondBarre = Color(0xFFF4F6FA);
  static const survol = Color(0xFFE6EBF4);
  static const appui = Color(0xFFD2D9E7);
  static const filet = Color(0xFFDDE2EC);
  static const bordure = Color(0xFFC5CDDB);

  /// Bleu d'interface : barres, accents.
  static const ardoise = Color(0xFF1C3C73);
  static const ardoiseClaire = Color(0xFF34528A);

  /// Texte sur fond clair.
  static const ardoiseFoncee = Color(0xFF153166);
  static const selectionListe = Color(0xFFCADAF0);

  static const texte = Color(0xFF333A4A);
  static const texteSecondaire = Color(0xFF6B7280);
  static const texteSurFonce = Color(0xFFC8D3EA);

  /// Entrée inactive sur une barre bleue.
  static const inactifSurFonce = Color(0xFF6F86AE);

  /// Épaisseur du filet jaune sous les barres (ClsNgeRenderer.RuleThickness).
  static const epaisseurFilet = 3.0;
}

/// Thème clair imposé : lisible en plein soleil, pas de thème sombre automatique (docs/echanges.md §8).
/// Texte de base en 16, cibles tactiles de 48 dp et plus.
ThemeData themeNge() {
  const schema = ColorScheme.light(
    primary: Nge.ardoise,
    onPrimary: Colors.white,
    primaryContainer: Nge.selectionListe,
    onPrimaryContainer: Nge.ardoiseFoncee,
    secondary: Nge.jaune,
    onSecondary: Nge.ardoiseFoncee,
    secondaryContainer: Nge.survol,
    onSecondaryContainer: Nge.ardoiseFoncee,
    tertiary: Nge.petrole,
    onTertiary: Colors.white,
    error: Nge.rouge,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: Nge.texte,
    onSurfaceVariant: Nge.texteSecondaire,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Nge.fondBarre,
    surfaceContainer: Nge.fondBarre,
    surfaceContainerHigh: Nge.survol,
    surfaceContainerHighest: Nge.survol,
    outline: Nge.bordure,
    outlineVariant: Nge.filet,
  );
  final base = ThemeData(colorScheme: schema, useMaterial3: true);
  final texte = base.textTheme.apply(bodyColor: Nge.texte, displayColor: Nge.ardoiseFoncee);
  const forme = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)));
  const tailleMini = Size(48, 48);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    textTheme: texte.copyWith(
      bodyMedium: texte.bodyMedium?.copyWith(fontSize: 16),
      bodySmall: texte.bodySmall?.copyWith(fontSize: 14, color: Nge.texteSecondaire),
      titleMedium: texte.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Nge.ardoiseFoncee),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Nge.ardoise,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      shape: Border(bottom: BorderSide(color: Nge.jaune, width: Nge.epaisseurFilet)),
      titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Nge.jaune,
        foregroundColor: Nge.ardoiseFoncee,
        disabledBackgroundColor: Nge.filet,
        minimumSize: tailleMini,
        shape: forme,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Nge.ardoiseFoncee,
        side: const BorderSide(color: Nge.bordure),
        minimumSize: tailleMini,
        shape: forme,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Nge.ardoiseFoncee,
        minimumSize: tailleMini,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: tailleMini)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Nge.jaune,
      foregroundColor: Nge.ardoiseFoncee,
      extendedTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Nge.bordure),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Nge.ardoise, width: 2),
      ),
      labelStyle: TextStyle(color: Nge.ardoiseFoncee),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Nge.filet),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Nge.filet, space: 1),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Nge.texte,
      contentTextStyle: TextStyle(fontSize: 15, color: Colors.white),
      actionTextColor: Nge.jaune,
      behavior: SnackBarBehavior.floating,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Nge.selectionListe,
        selectedForegroundColor: Nge.ardoiseFoncee,
        side: const BorderSide(color: Nge.bordure),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: Nge.selectionListe,
      side: BorderSide(color: Nge.bordure),
      labelStyle: TextStyle(fontSize: 14, color: Nge.ardoiseFoncee),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
  );
}
