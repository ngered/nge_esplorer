import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/geo_object.dart';
import '../lng.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import 'fields.dart';

/// Carte « Commentaires » d'un support : journal daté et signé de l'objet (PRJ_COMMENTAIRE), du plus ancien au plus
/// récent ; chaque entrée porte la pastille de son type, son auteur, sa date et son texte. Seuls les commentaires du
/// compte saisis pendant l'intervention en cours et pas encore exportés se modifient ou se retirent, après
/// confirmation ([AppProvider.canEditComment]) ; les autres, dont ceux venus du BE, sont en lecture seule. Comme le
/// reste de la saisie, les commentaires s'écrivent dans la copie de travail [object] et s'enregistrent avec elle
/// ([onChanged]).
class CommentsCard extends StatefulWidget {
  const CommentsCard({super.key, required this.object, required this.onChanged, this.expanded});

  final GeoObject object;
  final VoidCallback onChanged;

  /// Carte dépliable (voir [Section.expanded]).
  final bool? expanded;

  @override
  State<CommentsCard> createState() => _CommentsCardState();
}

class _CommentsCardState extends State<CommentsCard> {
  Future<(CommentType, String)?> _ask([Map<String, dynamic>? comment]) =>
      showDialog<(CommentType, String)>(context: context, builder: (_) => _CommentDialog(comment: comment));

  Future<void> _add() async {
    final r = await _ask();
    if (r == null || !mounted) return;
    final app = context.read<AppProvider>();
    widget.object.addComment(type: r.$1, text: r.$2, author: app.author, intervention: app.intervention);
    widget.onChanged();
  }

  Future<void> _edit(Map<String, dynamic> c) async {
    final r = await _ask(c);
    if (r == null || !mounted || (r.$1 == CommentType.of(c) && r.$2 == c['COM_TEXTE'])) return;
    widget.object.editComment(c, type: r.$1, text: r.$2, author: context.read<AppProvider>().author);
    widget.onChanged();
  }

  /// Retire le commentaire [c] après confirmation, son texte rappelé. Pas d'« Annuler » dans un message : la carte,
  /// sortie de la liste au défilement d'une longue saisie, ne pourrait plus l'honorer, et le message survivrait à
  /// « Abandonner les modifications ».
  Future<void> _remove(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        scrollable: true,
        title: Text(tr('Retirer ce commentaire ?')),
        content: Text('${c['COM_TEXTE'] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Annuler'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nge.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Retirer')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.object.removeComment(c);
    widget.onChanged();
  }

  static String _date(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    String n(int v) => v.toString().padLeft(2, '0');
    return '${n(d.day)}/${n(d.month)}/${d.year} ${n(d.hour)}:${n(d.minute)}';
  }

  Widget _entry(Map<String, dynamic> c, {required bool editable}) {
    final type = CommentType.of(c);
    final date = _date(c['DATE_CREA']);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        // centrée sur la ligne de l'auteur
        padding: const EdgeInsets.only(top: 4),
        child: Tooltip(message: tr(type.lib), child: CommentTypeDot(type)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '${c['COM_AUTEUR'] ?? '?'}',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Nge.slateDark)),
              if (date.isNotEmpty) TextSpan(text: ' · $date'),
            ]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text('${c['COM_TEXTE'] ?? ''}'),
        ]),
      ),
      if (editable) ...[
        IconButton(
          tooltip: tr('Modifier le commentaire'),
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _edit(c),
        ),
        IconButton(
          tooltip: tr('Retirer le commentaire'),
          color: Nge.red,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _remove(c),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final comments = widget.object.comments;
    return Section(title: tr('Commentaires'), expanded: widget.expanded, spacing: 12, children: [
      if (comments.isEmpty) Text(tr('Aucun commentaire'), style: Theme.of(context).textTheme.bodySmall),
      for (final c in comments) _entry(c, editable: app.canEditComment(c)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add_comment_outlined),
          label: Text(tr('Ajouter un commentaire')),
        ),
      ),
    ]);
  }
}

/// Pastille de la couleur d'un type de commentaire.
class CommentTypeDot extends StatelessWidget {
  const CommentTypeDot(this.type, {super.key, this.size = 12});

  final CommentType type;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: type.color, shape: BoxShape.circle),
      );
}

/// Saisie d'un commentaire, nouveau ou modifié ([comment]) : type par puces de couleur (Standard par défaut), texte
/// sur plusieurs lignes ; la validation reste inactive tant que le texte est vide. Rend le type et le texte.
class _CommentDialog extends StatefulWidget {
  const _CommentDialog({this.comment});

  final Map<String, dynamic>? comment;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late CommentType _type = widget.comment == null ? CommentType.standard : CommentType.of(widget.comment!);
  late final _text = TextEditingController(text: widget.comment?['COM_TEXTE'] as String? ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text.text.trim();
    final isNew = widget.comment == null;
    return AlertDialog(
      scrollable: true,
      title: Text(isNew ? tr('Nouveau commentaire') : tr('Modifier le commentaire')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in CommentType.values)
            ChoiceChip(
              avatar: Center(child: CommentTypeDot(t)),
              label: Text(tr(t.lib)),
              showCheckmark: false,
              selected: _type == t,
              selectedColor: t.color.withValues(alpha: 0.2),
              side: BorderSide(color: _type == t ? t.color : Nge.border, width: _type == t ? 2 : 1),
              onSelected: (_) => setState(() => _type = t),
            ),
        ]),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Commentaire')),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(
          onPressed: text.isEmpty ? null : () => Navigator.pop(context, (_type, text)),
          child: Text(isNew ? tr('Ajouter') : tr('Valider')),
        ),
      ],
    );
  }
}
