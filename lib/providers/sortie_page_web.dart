import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _gestionnaire;

/// Web : tant que [actif], fermer ou recharger la page demande confirmation au navigateur (les données ne sont qu'en
/// mémoire).
void avertirAvantSortie(bool actif) {
  if (actif && _gestionnaire == null) {
    _gestionnaire = ((web.BeforeUnloadEvent e) {
      e.preventDefault();
      e.returnValue = ' '; // navigateurs plus anciens
    }).toJS;
    web.window.addEventListener('beforeunload', _gestionnaire);
  } else if (!actif && _gestionnaire != null) {
    web.window.removeEventListener('beforeunload', _gestionnaire);
    _gestionnaire = null;
  }
}
