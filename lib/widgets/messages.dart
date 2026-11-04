import 'package:flutter/material.dart';

import '../lng.dart';

/// Messages en bas d'écran : un nouveau message remplace ceux qui sont affichés ou en attente. Sur le terrain, une
/// file de confirmations périmées (« Enregistré » après « Enregistré ») cacherait le message utile ; un « Annuler »
/// reste offert tant qu'aucune autre action n'a suivi.
extension ReplaceSnackBar on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> replaceSnackBar(SnackBar bar) {
    clearSnackBars();
    return showSnackBar(bar);
  }
}

/// Message « … · ANNULER » d'un écran. Il disparaît seul au bout de [undoDuration] : un SnackBar porteur d'une action
/// reste sinon affiché jusqu'à ce qu'on la touche, d'écran en écran. Il se ferme avec l'écran ([dispose]) et dès qu'une
/// autre modification le rend caduc ([hideUndo]) : son annulation reprend l'état d'avant, elle effacerait sinon ce qui
/// a été fait depuis.
mixin UndoMessage<T extends StatefulWidget> on State<T> {
  static const undoDuration = Duration(seconds: 6);

  ScaffoldMessengerState? _undoMessenger;

  /// Jeton du message affiché, null une fois fermé.
  Object? _undoShown;

  void showUndo(String text, VoidCallback onUndo) {
    final messenger = _undoMessenger = ScaffoldMessenger.of(context);
    final shown = _undoShown = Object();
    messenger
        .replaceSnackBar(SnackBar(
          content: Text(text),
          persist: false,
          duration: undoDuration,
          action: SnackBarAction(label: tr('Annuler').toUpperCase(), onPressed: onUndo),
        ))
        .closed
        .then((_) {
      if (identical(_undoShown, shown)) _undoShown = null;
    });
  }

  /// Le message d'annulation est encore affiché (rien ne l'a rendu caduc).
  bool get undoShown => _undoShown != null;

  /// Ferme le message d'annulation s'il est encore affiché.
  void hideUndo() {
    if (_undoShown != null) _undoMessenger?.hideCurrentSnackBar();
    _undoShown = null;
  }

  @override
  void dispose() {
    hideUndo();
    super.dispose();
  }
}
