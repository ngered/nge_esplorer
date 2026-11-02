import '../../data/referentiels.dart';

/// Réseau d'un câble, déduit du catalogue (`MAT_CABLE.CAB_TYPE`).
enum Reseau { telecom, energie, inconnu }

/// Style d'une flèche de la rosace (légende Hirondelle) : couleur = réseau, tireté = branchement.
class StyleCable {
  const StyleCable(this.reseau, {required this.branchement});

  final Reseau reseau;
  final bool branchement;

  static StyleCable de(Referentiels ref, int? matKey) {
    final c = ref.cable(matKey);
    final type = c?['CAB_TYPE'] as String?;
    final reseau = switch (type) {
      'N' || 'I' => Reseau.energie,
      'Telecom' || 'FO' || 'Fibre' => Reseau.telecom,
      _ => Reseau.inconnu,
    };
    return StyleCable(reseau, branchement: c?['CAB_USAGE'] == 'BRANCHEMENT');
  }
}

/// Tensions de pose des câbles portés (`INF_PORTEE_CABLE.PCB_TENSION`).
const tensions = {
  'STD_AGGLO': 'Standard agglomération',
  'STD_ECART': 'Standard écart',
  'RELEVE': 'Flèche relevée',
};
