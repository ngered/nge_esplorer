import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _handler;

/// Web : tant que [enabled], fermer ou recharger la page demande confirmation au navigateur (les données ne sont qu'en
/// mémoire).
void warnBeforeLeaving(bool enabled) {
  if (enabled && _handler == null) {
    _handler = ((web.BeforeUnloadEvent e) {
      e.preventDefault();
      e.returnValue = ' '; // navigateurs plus anciens
    }).toJS;
    web.window.addEventListener('beforeunload', _handler);
  } else if (!enabled && _handler != null) {
    web.window.removeEventListener('beforeunload', _handler);
    _handler = null;
  }
}
