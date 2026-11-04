import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../lng.dart';
import '../map/tile_source.dart';
import '../providers/app_provider.dart';
import '../widgets/back_to_map.dart';
import '../widgets/entry_screen.dart';

/// Paramètres de l'application : langue, fonds de plan (clé Google, annulation des tuiles obsolètes) ; sur le web, photos
/// au serveur local.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _txtGoogleKey = TextEditingController(text: context.read<AppProvider>().googleKey);
  bool _visible = false;
  bool _test = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _txtGoogleKey.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    setState(() {
      _test = true;
      _result = null;
    });
    try {
      await GoogleTiles.open(GoogleMapType.roadmap, _txtGoogleKey.text.trim());
      _ok = true;
      _result = tr('Clé acceptée par la Map Tiles API.');
    } catch (e) {
      _ok = false;
      _result = tr('Clé refusée ou Google injoignable : {0}', [e]);
    }
    if (mounted) setState(() => _test = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final changed = _txtGoogleKey.text.trim() != app.googleKey;
    return EntryScreen(
      changed: changed,
      message: tr('La clé Google saisie ne sera pas enregistrée.'),
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Paramètres')), actions: const [MapButton()]),
        floatingActionButton: saveButton(
          visible: changed,
          onPressed: () {
            app.setGoogleKey(_txtGoogleKey.text);
            showSaved(context, app.googleKey.isEmpty ? tr('Clé Google retirée') : tr('Clé Google enregistrée'));
          },
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, fabMargin),
          children: [
            Text(tr('Langue'), style: t.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: app.language,
              decoration: InputDecoration(labelText: tr('Langue de l\'interface'), border: const OutlineInputBorder()),
              items: [
                for (final e in Lng.languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (code) {
                if (code != null) app.setLanguage(code);
              },
            ),
            const SizedBox(height: 8),
            Text(tr('Les données du paquet (libellés des référentiels, commentaires) restent dans leur langue.'),
                style: t.bodySmall),
            const Divider(height: 32),
            Text(tr('Fonds de plan'), style: t.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _txtGoogleKey,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: tr('Clé Google Map Tiles'),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _visible ? tr('Masquer') : tr('Afficher'),
                  icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _visible = !_visible),
                ),
              ),
              onChanged: (_) => setState(() => _result = null),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Clé d\'API Google Maps Platform avec l\'API Map Tiles activée (console Google Cloud). Renseignée, les '
                 'fonds Google Plan, Satellite et Hybride apparaissent dans le sélecteur. La clé, son usage et sa '
                 'facturation au-delà de la franchise gratuite sont sous la responsabilité de l\'utilisateur. Les tuiles '
                 'Google ne s\'affichent qu\'avec une connexion (pas d\'usage hors connexion selon les règles de Google).'),
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _test || _txtGoogleKey.text.trim().isEmpty ? null : _runTest,
                icon: _test
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check),
                label: Text(tr('Tester la clé')),
              ),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_result!, style: TextStyle(color: _ok ? Colors.green.shade700 : c.error)),
              ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Annuler les téléchargements de tuiles inutiles')),
              subtitle: Text(
                tr('Abandonne les tuiles qui ne seront plus affichées après un déplacement rapide '
                   '(économie de données) ; désactivé par défaut.'),
              ),
              value: app.cancelStaleTiles,
              onChanged: app.setCancelStaleTiles,
            ),
            if (kIsWeb) ...[
              const Divider(height: 32),
              Text(tr('Photos (version web de développement)'), style: t.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Photos au serveur local')),
                subtitle: Text(
                  tr('Affiche les photos non embarquées dans le paquet en les lisant au serveur {0} '
                     '(tools/essai/serveur_photos.py <projet>).', [AppProvider.localPhotoServer]) +
                      (app.urlPhotoServer == null
                          ? ''
                          : ' ${tr('Serveur imposé par l\'adresse de la page : {0}.', [app.urlPhotoServer])}'),
                ),
                value: app.urlPhotoServer != null || app.useLocalPhotoServer,
                onChanged: app.urlPhotoServer != null ? null : app.setUseLocalPhotoServer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
