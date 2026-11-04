import 'package:flutter/material.dart';

/// Volet modal qui se déplie depuis la droite, sur toute la hauteur et sur [width] (la colonne latérale d'un écran en
/// paysage) : le reste de l'écran reste visible derrière un voile ; toucher le voile le referme. Rend la valeur passée
/// à `Navigator.pop`, comme une feuille du bas.
Future<T?> showSideSheet<T>(BuildContext context, {required double width, required WidgetBuilder builder}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Material(elevation: 8, color: Colors.white, child: builder(context)),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
