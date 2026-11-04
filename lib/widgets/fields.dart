import 'package:flutter/material.dart';

import '../data/geo_object.dart';
import '../lng.dart';
import '../theme.dart';

/// Champs de saisie liés à une clé d'une carte de propriétés (valeur vide = clé retirée).

class StringField extends StatelessWidget {
  const StringField({super.key, required this.m, required this.column, required this.label, required this.onChanged, this.rows = 1});

  final Map<String, dynamic> m;
  final String column;
  final String label;
  final VoidCallback onChanged;
  final int rows;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: m[column] as String? ?? '',
        minLines: rows,
        maxLines: rows == 1 ? 1 : rows + 3,
        decoration: InputDecoration(labelText: label),
        onChanged: (t) {
          GeoObject.put(m, column, t);
          onChanged();
        },
      );
}

class NumberField extends StatelessWidget {
  const NumberField(
      {super.key,
      required this.m,
      required this.column,
      this.label,
      required this.onChanged,
      this.integer = false,
      this.unit,
      this.note});

  final Map<String, dynamic> m;
  final String column;
  final String? label;
  final VoidCallback onChanged;
  final bool integer;

  /// Unité affichée après la valeur (m, mm…).
  final String? unit;

  /// Indication en petit et en gris dans le cadre du champ, en bas à gauche sous la valeur (valeur de référence…).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      initialValue: m[column]?.toString().replaceAll('.', ',') ?? '',
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      // avec une indication : valeur en haut du cadre, indication dessous ; libellé toujours sur la bordure (au
      // repos, centré dans le cadre, il chevaucherait l'indication)
      textAlignVertical: note == null ? null : TextAlignVertical.top,
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        floatingLabelBehavior: note == null ? null : FloatingLabelBehavior.always,
        contentPadding: note == null ? null : const EdgeInsets.fromLTRB(12, 12, 12, 28),
      ),
      onChanged: (t) {
        final s = t.replaceAll(',', '.').trim();
        GeoObject.put(m, column, integer ? int.tryParse(s) : double.tryParse(s));
        onChanged();
      },
    );
    if (note == null) return field;
    return Stack(children: [
      field,
      Positioned(
        // aligné sur la valeur, à 16 du bord du cadre
        left: 16,
        right: 16,
        bottom: 8,
        // le toucher passe au champ
        child: IgnorePointer(
          child: Text(note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2, color: Nge.secondaryText)),
        ),
      ),
    ]);
  }
}

/// Liste déroulante sur un référentiel (lignes `{cleId: …, colLib: …}`).
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.m,
    required this.column,
    required this.label,
    required this.rows,
    required this.colId,
    required this.colLabel,
    required this.onChanged,
    this.optional = true,
  });

  final Map<String, dynamic> m;
  final String column;
  final String label;
  final List<Map<String, dynamic>> rows;
  final String colId;
  final String colLabel;
  final VoidCallback onChanged;

  /// Valeur « — » proposée (clé retirée) ; faux pour une colonne obligatoire (type du nœud).
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final value = m[column];
    final known = rows.any((l) => l[colId] == value);
    return DropdownButtonFormField<Object?>(
      initialValue: known ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (optional || !known) const DropdownMenuItem(value: null, child: Text('—')),
        for (final l in rows) DropdownMenuItem(value: l[colId], child: Text('${l[colLabel]}')),
      ],
      onChanged: (v) {
        if (v == null && !optional) return;
        GeoObject.put(m, column, v);
        onChanged();
      },
    );
  }
}

/// Oui / non / non vu (1, 0, absent), pour les contrôles.
class YesNoField extends StatelessWidget {
  const YesNoField({super.key, required this.m, required this.column, required this.label, required this.onChanged});

  final Map<String, dynamic> m;
  final String column;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final v = m[column] as int?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label)),
        SegmentedButton<int>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(value: 1, label: Text(tr('Oui'))),
            ButtonSegment(value: 0, label: Text(tr('Non'))),
          ],
          selected: {?v},
          onSelectionChanged: (s) {
            GeoObject.put(m, column, s.isEmpty ? null : s.first);
            onChanged();
          },
        ),
      ]),
    );
  }
}

/// Carte titrée d'un écran de saisie ; dépliable si [expanded] est donné (ouverte au départ s'il est vrai).
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.children, this.action, this.expanded, this.spacing = 0});

  final String title;
  final List<Widget> children;
  final Widget? action;

  /// Null : toujours ouverte ; sinon dépliable, ouverte au départ si vrai.
  final bool? expanded;

  /// Écart entre les champs (12 pour que l'étiquette d'un champ ne chevauche pas le cadre du précédent).
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final head = Row(children: [
      Expanded(
        child: Text(title.toUpperCase(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Nge.petrolBlue)),
      ),
      ?action,
    ]);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: spacing, children: children);
    if (expanded == null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const SizedBox(height: 4), body]),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('section $title'),
        initiallyExpanded: expanded!,
        title: head,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        // clé propre au contenu : sans elle, le défilement d'un champ de texte se range dans la même entrée du
        // PageStorage que l'état ouvert de la carte (un booléen relu comme position au dépliage)
        children: [KeyedSubtree(key: PageStorageKey('section $title body'), child: body)],
      ),
    );
  }
}
