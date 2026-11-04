import 'package:flutter/material.dart';

/// Couleurs de la charte NGE (Megatools/NgeCharte/ClsCharte.cs de FibReady).
abstract final class Nge {
  /// Bleu nuit : support de marque, réservé à l'écran de démarrage.
  static const navyBlue = Color(0xFF022A78);

  /// Jaune : action principale (texte [slateDark]) et filet sous les barres.
  static const yellow = Color(0xFFFAC100);
  static const yellowLight = Color(0xFFFFD240);

  /// Bleu pétrole : titres de rubriques.
  static const petrolBlue = Color(0xFF1A6D8E);
  static const turquoise = Color(0xFF34AFC1);
  static const cream = Color(0xFFF9F8F0);

  /// Rouge : suppressions et défauts seulement.
  static const red = Color(0xFFC62828);
  static const green = Color(0xFF1E7B45);
  static const amber = Color(0xFFB98600);

  static const barBackground = Color(0xFFF4F6FA);
  static const hover = Color(0xFFE6EBF4);
  static const hoverPressed = Color(0xFFD2D9E7);
  static const rule = Color(0xFFDDE2EC);
  static const border = Color(0xFFC5CDDB);

  /// Bleu d'interface : barres, accents.
  static const slate = Color(0xFF1C3C73);
  static const slateLight = Color(0xFF34528A);

  /// Texte sur fond clair.
  static const slateDark = Color(0xFF153166);
  static const listSelection = Color(0xFFCADAF0);

  static const text = Color(0xFF333A4A);
  static const secondaryText = Color(0xFF6B7280);
  static const textOnDark = Color(0xFFC8D3EA);

  /// Entrée inactive sur une barre bleue.
  static const inactiveOnDark = Color(0xFF6F86AE);

  /// Épaisseur du filet jaune sous les barres (ClsNgeRenderer.RuleThickness).
  static const ruleThickness = 3.0;
}

/// Thème clair imposé : lisible en plein soleil, pas de thème sombre automatique (docs/echanges.md §8).
/// Texte de base en 16, cibles tactiles de 48 dp et plus.
ThemeData ngeTheme() {
  const schema = ColorScheme.light(
    primary: Nge.slate,
    onPrimary: Colors.white,
    primaryContainer: Nge.listSelection,
    onPrimaryContainer: Nge.slateDark,
    secondary: Nge.yellow,
    onSecondary: Nge.slateDark,
    secondaryContainer: Nge.hover,
    onSecondaryContainer: Nge.slateDark,
    tertiary: Nge.petrolBlue,
    onTertiary: Colors.white,
    error: Nge.red,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: Nge.text,
    onSurfaceVariant: Nge.secondaryText,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Nge.barBackground,
    surfaceContainer: Nge.barBackground,
    surfaceContainerHigh: Nge.hover,
    surfaceContainerHighest: Nge.hover,
    outline: Nge.border,
    outlineVariant: Nge.rule,
  );
  final base = ThemeData(colorScheme: schema, useMaterial3: true);
  final text = base.textTheme.apply(bodyColor: Nge.text, displayColor: Nge.slateDark);
  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)));
  const minSize = Size(48, 48);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    textTheme: text.copyWith(
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 16),
      bodySmall: text.bodySmall?.copyWith(fontSize: 14, color: Nge.secondaryText),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Nge.slateDark),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Nge.slate,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      shape: Border(bottom: BorderSide(color: Nge.yellow, width: Nge.ruleThickness)),
      titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Nge.yellow,
        foregroundColor: Nge.slateDark,
        disabledBackgroundColor: Nge.rule,
        minimumSize: minSize,
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Nge.slateDark,
        side: const BorderSide(color: Nge.border),
        minimumSize: minSize,
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Nge.slateDark,
        minimumSize: minSize,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: minSize)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Nge.yellow,
      foregroundColor: Nge.slateDark,
      extendedTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Nge.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Nge.slate, width: 2),
      ),
      labelStyle: TextStyle(color: Nge.slateDark),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Nge.rule),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Nge.rule, space: 1),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Nge.text,
      contentTextStyle: TextStyle(fontSize: 15, color: Colors.white),
      actionTextColor: Nge.yellow,
      behavior: SnackBarBehavior.floating,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Nge.listSelection,
        selectedForegroundColor: Nge.slateDark,
        side: const BorderSide(color: Nge.border),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: Nge.listSelection,
      side: BorderSide(color: Nge.border),
      labelStyle: TextStyle(fontSize: 14, color: Nge.slateDark),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
  );
}
