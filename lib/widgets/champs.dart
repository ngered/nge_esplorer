import 'package:flutter/material.dart';

import '../data/objet.dart';

/// Champs de saisie liés à une clé d'une carte de propriétés (valeur vide = clé retirée).

class ChampTexte extends StatelessWidget {
  const ChampTexte({super.key, required this.m, required this.cle, required this.libelle, required this.onChanged, this.lignes = 1});

  final Map<String, dynamic> m;
  final String cle;
  final String libelle;
  final VoidCallback onChanged;
  final int lignes;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: m[cle] as String? ?? '',
        minLines: lignes,
        maxLines: lignes == 1 ? 1 : lignes + 3,
        decoration: InputDecoration(labelText: libelle),
        onChanged: (t) {
          Objet.poser(m, cle, t);
          onChanged();
        },
      );
}

class ChampNombre extends StatelessWidget {
  const ChampNombre(
      {super.key, required this.m, required this.cle, required this.libelle, required this.onChanged, this.entier = false});

  final Map<String, dynamic> m;
  final String cle;
  final String libelle;
  final VoidCallback onChanged;
  final bool entier;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: m[cle]?.toString().replaceAll('.', ',') ?? '',
        keyboardType: TextInputType.numberWithOptions(decimal: !entier),
        decoration: InputDecoration(labelText: libelle),
        onChanged: (t) {
          final s = t.replaceAll(',', '.').trim();
          Objet.poser(m, cle, entier ? int.tryParse(s) : double.tryParse(s));
          onChanged();
        },
      );
}

/// Liste déroulante sur un référentiel (lignes `{cleId: …, colLib: …}`).
class ChampListe extends StatelessWidget {
  const ChampListe({
    super.key,
    required this.m,
    required this.cle,
    required this.libelle,
    required this.lignes,
    required this.colId,
    required this.colLib,
    required this.onChanged,
  });

  final Map<String, dynamic> m;
  final String cle;
  final String libelle;
  final List<Map<String, dynamic>> lignes;
  final String colId;
  final String colLib;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final valeur = m[cle];
    final connue = lignes.any((l) => l[colId] == valeur);
    return DropdownButtonFormField<Object?>(
      initialValue: connue ? valeur : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: libelle),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final l in lignes) DropdownMenuItem(value: l[colId], child: Text('${l[colLib]}')),
      ],
      onChanged: (v) {
        Objet.poser(m, cle, v);
        onChanged();
      },
    );
  }
}

/// Oui / non / non vu (1, 0, absent), pour les contrôles.
class ChampOuiNon extends StatelessWidget {
  const ChampOuiNon({super.key, required this.m, required this.cle, required this.libelle, required this.onChanged});

  final Map<String, dynamic> m;
  final String cle;
  final String libelle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final v = m[cle] as int?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(libelle)),
        SegmentedButton<int>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 1, label: Text('Oui')),
            ButtonSegment(value: 0, label: Text('Non')),
          ],
          selected: {?v},
          onSelectionChanged: (s) {
            Objet.poser(m, cle, s.isEmpty ? null : s.first);
            onChanged();
          },
        ),
      ]),
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, required this.titre, required this.enfants, this.action});

  final String titre;
  final List<Widget> enfants;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(titre, style: Theme.of(context).textTheme.titleMedium)),
              ?action,
            ]),
            const SizedBox(height: 4),
            ...enfants,
          ]),
        ),
      );
}
