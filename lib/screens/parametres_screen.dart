import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../carte/tile_source.dart';
import '../providers/app_provider.dart';
import '../widgets/retour_carte.dart';
import '../widgets/saisie.dart';

/// Paramètres de l'application : fonds de plan (clé Google, annulation des tuiles obsolètes).
class ParametresScreen extends StatefulWidget {
  const ParametresScreen({super.key});

  @override
  State<ParametresScreen> createState() => _ParametresScreenState();
}

class _ParametresScreenState extends State<ParametresScreen> {
  late final _cle = TextEditingController(text: context.read<AppProvider>().cleGoogle);
  bool _visible = false;
  bool _test = false;
  String? _resultat;
  bool _ok = false;

  @override
  void dispose() {
    _cle.dispose();
    super.dispose();
  }

  Future<void> _tester() async {
    setState(() {
      _test = true;
      _resultat = null;
    });
    try {
      await GoogleTiles.ouvrir(TypeGoogle.plan, _cle.text.trim());
      _ok = true;
      _resultat = 'Clé acceptée par la Map Tiles API.';
    } catch (e) {
      _ok = false;
      _resultat = 'Clé refusée ou Google injoignable : $e';
    }
    if (mounted) setState(() => _test = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final modifie = _cle.text.trim() != app.cleGoogle;
    return EcranSaisie(
      modifie: modifie,
      message: 'La clé Google saisie ne sera pas enregistrée.',
      child: Scaffold(
        appBar: AppBar(title: const Text('Paramètres'), actions: const [BoutonCarte()]),
        floatingActionButton: boutonEnregistrer(
          visible: modifie,
          onPressed: () {
            app.definirCleGoogle(_cle.text);
            signalerEnregistre(context, app.cleGoogle.isEmpty ? 'Clé Google retirée' : 'Clé Google enregistrée');
          },
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, margeBoutonFlottant),
          children: [
            Text('Fonds de plan', style: t.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _cle,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Clé Google Map Tiles',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _visible ? 'Masquer' : 'Afficher',
                  icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _visible = !_visible),
                ),
              ),
              onChanged: (_) => setState(() => _resultat = null),
            ),
            const SizedBox(height: 8),
            Text(
              'Clé d\'API Google Maps Platform avec l\'API Map Tiles activée (console Google Cloud). Renseignée, les '
              'fonds Google Plan, Satellite et Hybride apparaissent dans le sélecteur. La clé, son usage et sa '
              'facturation au-delà de la franchise gratuite sont sous la responsabilité de l\'utilisateur. Les tuiles '
              'Google ne s\'affichent qu\'avec une connexion (pas d\'usage hors connexion selon les règles de Google).',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _test || _cle.text.trim().isEmpty ? null : _tester,
                icon: _test
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check),
                label: const Text('Tester la clé'),
              ),
            ),
            if (_resultat != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_resultat!, style: TextStyle(color: _ok ? Colors.green.shade700 : c.error)),
              ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Annuler les téléchargements de tuiles inutiles'),
              subtitle: const Text(
                'Abandonne les tuiles qui ne seront plus affichées après un déplacement rapide '
                '(économie de données) ; désactivé par défaut.',
              ),
              value: app.annulerTuilesObsoletes,
              onChanged: app.definirAnnulationTuiles,
            ),
          ],
        ),
      ),
    );
  }
}
